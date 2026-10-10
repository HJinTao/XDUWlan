"""在构建平台封装桌面包，校验下载后内容、权限与符号链接。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tarfile
import tempfile
import zipfile


class PackageError(Exception):
    pass


_stage = "arguments"
_safe_stages = {
    "arguments", "source_prepare", "output_prepare", "source_layout",
    "source_inventory", "archive_write", "manifest_write", "checksum_write",
    "verify_checksum", "verify_manifest", "verify_members", "verify_extract",
    "verify_layout", "verify_inventory", "verify_source", "completion",
}
_safe_error_types = {
    "PackageError", "OSError", "FileNotFoundError", "FileExistsError",
    "PermissionError", "IsADirectoryError", "NotADirectoryError",
    "UnicodeDecodeError", "UnicodeEncodeError", "UnicodeError", "ValueError",
    "BadZipFile", "LargeZipFile", "TarError", "ReadError", "CompressionError",
    "CalledProcessError", "RuntimeError", "OverflowError", "KeyError",
    "TypeError",
}
_safe_errnos = {1, 2, 5, 13, 17, 22, 28, 30, 36, 39, 95}


def set_stage(value):
    global _stage
    _stage = value if value in _safe_stages else "unknown"


def safe_error_status(failure):
    """仅公开固定阶段、异常类别和白名单 errno，不读取异常正文或路径。"""
    if isinstance(failure, PackageError):
        category = "validation"
    elif isinstance(failure, UnicodeError):
        category = "encoding"
    elif isinstance(failure, (zipfile.BadZipFile, zipfile.LargeZipFile, tarfile.TarError)):
        category = "archive"
    elif isinstance(failure, OSError):
        category = "io"
    elif isinstance(failure, ValueError):
        category = "value"
    elif isinstance(failure, subprocess.CalledProcessError):
        category = "process"
    else:
        category = "unknown"
    error = type(failure).__name__
    if error not in _safe_error_types:
        error = "UnknownError"
    stage = _stage if _stage in _safe_stages else "unknown"
    status = f"desktop_package_failed stage={stage} category={category} error={error}"
    if isinstance(failure, OSError) and failure.errno in _safe_errnos:
        status += f" errno={failure.errno}"
    return status


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def inventory(root, unix):
    entries = {}
    for path in sorted(root.rglob("*")):
        key = path.relative_to(root).as_posix()
        info = path.lstat()
        value = {"mode": stat.S_IMODE(info.st_mode)} if unix else {}
        if path.is_symlink():
            if not path.resolve().is_relative_to(root.resolve()):
                raise PackageError("包内链接超出应用目录")
            value.update(type="link", target=os.readlink(path))
        elif path.is_dir():
            value.update(type="directory")
        elif path.is_file():
            value.update(type="file", sha256=digest(path), size=info.st_size)
        else:
            raise PackageError("包内存在不支持的文件类型")
        entries[key] = value
    return entries


def check_layout(platform, root):
    if platform == "macos":
        app = root / "XDUWlan.app"
        required = [app / "Contents/MacOS/XDUWlan", app / "Contents/Info.plist",
                    app / "Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS",
                    app / "Contents/Frameworks/App.framework/Resources/flutter_assets"]
        executables = required[:1] + required[2:3]
    elif platform == "linux":
        required = [root / "xduwlan_app", root / "lib/libflutter_linux_gtk.so",
                    root / "data/icudtl.dat", root / "data/flutter_assets"]
        executables = required[:1]
    elif platform == "windows":
        required = [root / "xduwlan_app.exe", root / "flutter_windows.dll",
                    root / "data/icudtl.dat", root / "data/flutter_assets"]
        executables = []
    else:
        raise PackageError("不支持的平台")
    if any(not path.is_file() for path in required[:-1]) or not required[-1].is_dir():
        raise PackageError("桌面包缺少运行文件")
    if any(not path.is_file() or not (path.stat().st_mode & 0o111)
           for path in executables):
        raise PackageError("桌面包执行权限不完整")


def manifest_path(archive):
    return archive.with_name(archive.name + ".manifest.json")


def load_manifest(archive):
    return json.loads(manifest_path(archive).read_text(encoding="utf-8"))


def source_inventory(platform, source):
    if platform != "macos":
        return inventory(source, platform != "windows")
    result = {"XDUWlan.app/" + key: value for key, value in inventory(source, True).items()}
    result["XDUWlan.app"] = {"type": "directory", "mode": stat.S_IMODE(source.stat().st_mode)}
    return result


def safe_members(archive, platform):
    if platform == "linux":
        with tarfile.open(archive) as stream:
            members = [(m.name, m.linkname if m.issym() else None) for m in stream]
            if any(m.islnk() or not (m.isfile() or m.isdir() or m.issym())
                   for m in stream.getmembers()):
                raise PackageError("压缩包文件类型不可用")
    else:
        with zipfile.ZipFile(archive) as stream:
            members = [(m.filename, stream.read(m).decode("utf-8")
                        if stat.S_ISLNK(m.external_attr >> 16) else None)
                       for m in stream.infolist()]
    for name, link in members:
        path = Path(name)
        if path.is_absolute() or ".." in path.parts:
            raise PackageError("压缩包路径不可用")
        if link is not None:
            target = Path(link)
            normalized = os.path.normpath(str(path.parent / target))
            if target.is_absolute() or normalized == ".." or normalized.startswith("../"):
                raise PackageError("压缩包链接超出应用目录")


def verify(archive, source=None):
    set_stage("verify_checksum")
    archive = Path(archive).resolve()
    checksum = archive.with_name("SHA256SUMS-" +
                                 archive.name.split("-")[-1].split(".")[0])
    if not checksum.exists():
        checksum = archive.with_name("SHA256SUMS")
    expected = {}
    for line in checksum.read_text(encoding="utf-8").splitlines():
        value, name = line.split("  ", 1)
        expected[name] = value
    for path in [archive, manifest_path(archive)]:
        if expected.get(path.name) != digest(path):
            raise PackageError("下载包 SHA-256 不一致")
    set_stage("verify_manifest")
    manifest = load_manifest(archive)
    platform = manifest["platform"]
    set_stage("verify_members")
    safe_members(archive, platform)
    with tempfile.TemporaryDirectory(prefix="xduwlan-package-check-") as temporary:
        root = Path(temporary)
        set_stage("verify_extract")
        if platform == "macos":
            subprocess.run(["ditto", "-x", "-k", str(archive), str(root)], check=True)
        elif platform == "linux":
            subprocess.run(["tar", "-xzf", str(archive), "-C", str(root)], check=True)
        else:
            with zipfile.ZipFile(archive) as stream:
                stream.extractall(root)
        set_stage("verify_layout")
        check_layout(platform, root)
        set_stage("verify_inventory")
        if inventory(root, platform != "windows") != manifest["entries"]:
            raise PackageError("解包后的内容、权限或链接不一致")
    if source is not None:
        set_stage("verify_source")
        source = Path(source)
        if source_inventory(platform, source) != manifest["entries"]:
            raise PackageError("下载包与当前构建目录不一致")


def pack(platform, version, source, output):
    set_stage("arguments")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", version):
        raise PackageError("产物标识不可用")
    set_stage("source_prepare")
    source, output = Path(source).resolve(), Path(output).resolve()
    set_stage("output_prepare")
    output.mkdir(parents=True, exist_ok=True)
    suffix = "tar.gz" if platform == "linux" else "zip"
    archive = output / f"xduwlan-{version}-{platform}.{suffix}"
    # macOS 仅暂存当前 app，防止 Products 中其他构建入口混入发行包。
    with tempfile.TemporaryDirectory(prefix="xduwlan-package-input-") as temporary:
        basis = source
        if platform == "macos":
            set_stage("source_prepare")
            basis = Path(temporary)
            subprocess.run(["ditto", str(source), str(basis / "XDUWlan.app")], check=True)
        set_stage("source_layout")
        check_layout(platform, basis)
        set_stage("source_inventory")
        entries = inventory(basis, platform != "windows")
        set_stage("archive_write")
        if platform == "macos":
            subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
                            str(basis / "XDUWlan.app"), str(archive)], check=True)
        elif platform == "linux":
            subprocess.run(["tar", "-czf", str(archive), "-C", str(basis), "."], check=True)
        else:
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as stream:
                for path in sorted(basis.rglob("*")):
                    stream.write(path, path.relative_to(basis).as_posix())
    set_stage("manifest_write")
    manifest_path(archive).write_text(json.dumps(
        {"platform": platform, "entries": entries}, ensure_ascii=False,
        sort_keys=True) + "\n", encoding="utf-8")
    set_stage("checksum_write")
    archive.with_name("SHA256SUMS-" + platform).write_text("".join(
        f"{digest(path)}  {path.name}\n" for path in [archive, manifest_path(archive)]),
        encoding="utf-8")
    verify(archive)
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["pack", "verify"])
    parser.add_argument("--platform", choices=["linux", "macos", "windows"])
    parser.add_argument("--version")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "pack":
            if not all([args.platform, args.version, args.source, args.output]):
                parser.error("pack 需要平台、标识、源目录和输出目录")
            result = pack(args.platform, args.version, args.source, args.output)
            set_stage("completion")
            print("桌面包封装与解包核对通过：" + result.name)
        else:
            if not args.archive:
                parser.error("verify 需要压缩包")
            verify(args.archive, args.source)
            set_stage("completion")
            print("下载包内容、权限、链接与 SHA-256 核对通过")
    except PackageError as failure:
        # 本类只由上面的固定安全检查文案构造，不带输入或底层异常。
        raise SystemExit(safe_error_status(failure) + " " + str(failure)) from None
    except Exception as failure:
        # 异常仍以失败退出，不把底层路径、归档内容或异常正文送入日志。
        raise SystemExit(safe_error_status(failure)) from None


if __name__ == "__main__":
    main()
