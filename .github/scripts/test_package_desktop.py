"""用虚构桌面目录验证压缩包的权限、链接和内容核对。"""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
import subprocess

spec = importlib.util.spec_from_file_location(
    "package_desktop", Path(__file__).with_name("package_desktop.py"))
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageTests(unittest.TestCase):
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
            library.chmod(0o755)
            (source / "lib/versioned.so").symlink_to(library.name)
            archive = package.pack("linux", "test-commit", source, root / "out")
            package.verify(archive)
            manifest = package.load_manifest(archive)
            self.assertEqual(manifest["entries"]["xduwlan_app"]["mode"], 0o755)
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
