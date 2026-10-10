"""用虚构桌面目录验证压缩包的权限、链接和内容核对。"""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys

spec = importlib.util.spec_from_file_location(
    "package_desktop", Path(__file__).with_name("package_desktop.py"))
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageTests(unittest.TestCase):
    def test_cli_pack_uses_utf8_with_windows_console_codepage(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Release"
            (source / "data/flutter_assets").mkdir(parents=True)
            (source / "xduwlan_app.exe").write_bytes(b"test-only-executable")
            (source / "flutter_windows.dll").write_bytes(b"test-only-runtime")
            (source / "data/icudtl.dat").write_bytes(b"test-only-icu")
            script = str(Path(__file__).with_name("package_desktop.py"))
            arguments = [sys.executable, script, "pack", "--platform", "windows",
                         "--version", "test-codepage", "--source", str(source),
                         "--output", str(root / "out")]
            environment = {**os.environ, "PYTHONIOENCODING": "cp1252"}
            result = subprocess.run(arguments, env=environment, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8"))
            self.assertIn("桌面包封装", result.stdout.decode("utf-8"))
            package.verify(root / "out/xduwlan-test-codepage-windows.zip", source)
            # 失败仍须退出非零，中文安全提示也不能依赖 Windows 本地编码。
            (source / "flutter_windows.dll").unlink()
            rejected = subprocess.run(arguments, env=environment, capture_output=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("桌面包缺少运行文件", rejected.stderr.decode("utf-8"))
            self.assertNotIn(str(source), rejected.stderr.decode("utf-8"))

    def test_safe_error_status_never_includes_exception_text(self):
        private = "test-only-private-path-and-input"
        cases = [
            (PermissionError(13, private, private), "category=io", "error=PermissionError"),
            (UnicodeEncodeError("ascii", private + "中", len(private), len(private) + 1,
                                private), "category=encoding", "error=UnicodeEncodeError"),
            (ValueError(private), "category=value", "error=ValueError"),
        ]
        for failure, category, error in cases:
            status = package.safe_error_status(failure)
            self.assertIn(category, status)
            self.assertIn(error, status)
            self.assertNotIn(private, status)
        self.assertIn("errno=13", package.safe_error_status(cases[0][0]))
        self.assertNotIn("errno=9999", package.safe_error_status(OSError(9999, private)))

    def test_cli_failure_reports_safe_stage_and_keeps_nonzero_exit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "test-only-private-source"
            source.mkdir()
            blocked = root / "test-only-private-output"
            blocked.write_bytes(b"test-only-blocked-output")
            result = subprocess.run([
                sys.executable, str(Path(__file__).with_name("package_desktop.py")),
                "pack", "--platform", "windows", "--version", "test-commit",
                "--source", str(source), "--output", str(blocked),
            ], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stage=output_prepare category=io", result.stderr)
            self.assertNotIn("test-only-private", result.stderr)
            self.assertEqual(blocked.read_bytes(), b"test-only-blocked-output")

    @unittest.skipIf(os.name == "nt", "Unix 权限与符号链接由 Linux/macOS 验证")
    def test_linux_roundtrip_rejects_changed_content_and_preserves_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "bundle"
            (source / "lib").mkdir(parents=True)
            (source / "data/flutter_assets").mkdir(parents=True)
            (source / "data/icudtl.dat").write_bytes(b"test-icu")
            executable = source / "xduwlan_app"
            executable.write_bytes(b"test-only-executable")
            executable.chmod(0o755)
            library = source / "lib/libflutter_linux_gtk.so"
            library.write_bytes(b"test-only-library")
            # CMake install(FILES) 的共享库为 644，动态加载不要求执行位。
            library.chmod(0o644)
            (source / "lib/versioned.so").symlink_to(library.name)
            archive = package.pack("linux", "test-commit", source, root / "out")
            package.verify(archive)
            manifest = package.load_manifest(archive)
            self.assertEqual(manifest["entries"]["xduwlan_app"]["mode"], 0o755)
            self.assertEqual(manifest["entries"]["lib/libflutter_linux_gtk.so"]["mode"], 0o644)
            self.assertEqual(manifest["entries"]["lib/versioned.so"]["target"], library.name)
            executable.write_bytes(b"altered")
            with self.assertRaises(package.PackageError):
                package.verify(archive, source)
            # 模拟先上传目录造成权限丢失，再打包；即使校验和匹配也要拒绝。
            executable.write_bytes(b"test-only-executable")
            executable.chmod(0o644)
            subprocess.run(["tar", "-czf", str(archive), "-C", str(source), "."], check=True)
            archive.with_name("SHA256SUMS-linux").write_text("".join(
                f"{package.digest(path)}  {path.name}\n"
                for path in [archive, package.manifest_path(archive)]))
            with self.assertRaises(package.PackageError):
                package.verify(archive)

    def test_windows_requires_runtime_data_and_dll(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Release"
            (source / "data/flutter_assets").mkdir(parents=True)
            (source / "xduwlan_app.exe").write_bytes(b"test-only-executable")
            with self.assertRaises(package.PackageError):
                package.pack("windows", "test-commit", source, root / "out")
            (source / "flutter_windows.dll").write_bytes(b"test-runtime")
            (source / "window_manager_plugin.dll").write_bytes(b"test-plugin")
            (source / "data/icudtl.dat").write_bytes(b"test-icu")
            archive = package.pack("windows", "test-commit", source, root / "out")
            package.verify(archive, source)
            self.assertIn("window_manager_plugin.dll", package.load_manifest(archive)["entries"])
            # Release 只发布汇总校验文件，下载后使用同一验证入口。
            archive.with_name("SHA256SUMS-windows").rename(archive.with_name("SHA256SUMS"))
            package.verify(archive, source)

    def test_checksum_detects_changed_download(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "xduwlan-test-linux.tar.gz"
            archive.write_bytes(b"damaged-download")
            archive.with_name("SHA256SUMS-linux").write_text(
                "0" * 64 + "  " + archive.name + "\n")
            with self.assertRaises(package.PackageError):
                package.verify(archive)


if __name__ == "__main__":
    unittest.main()
