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
        executables = required[:2]
    elif platform == "windows":
        required = [root / "xduwlan_app.exe", root / "flutter_windows.dll",
                    root / "data/icudtl.dat", root / "data/flutter_assets"]
        executables = []
    else:
        raise PackageError("不支持的平台")
    if any(not path.exists() for path in required):
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
    archive = Path(archive).resolve()
    checksum = archive.with_name("SHA256SUMS-" +
                                 archive.name.split("-")[-1].split(".")[0])
    expected = {}
    for line in checksum.read_text(encoding="utf-8").splitlines():
        value, name = line.split("  ", 1)
        expected[name] = value
    for path in [archive, manifest_path(archive)]:
        if expected.get(path.name) != digest(path):
            raise PackageError("下载包 SHA-256 不一致")
    manifest = load_manifest(archive)
    platform = manifest["platform"]
    safe_members(archive, platform)
    with tempfile.TemporaryDirectory(prefix="xduwlan-package-check-") as temporary:
        root = Path(temporary)
        if platform == "macos":
            subprocess.run(["ditto", "-x", "-k", str(archive), str(root)], check=True)
        elif platform == "linux":
            subprocess.run(["tar", "-xzf", str(archive), "-C", str(root)], check=True)
        else:
            with zipfile.ZipFile(archive) as stream:
                stream.extractall(root)
        check_layout(platform, root)
        if inventory(root, platform != "windows") != manifest["entries"]:
            raise PackageError("解包后的内容、权限或链接不一致")
    if source is not None:
        source = Path(source)
        if source_inventory(platform, source) != manifest["entries"]:
            raise PackageError("下载包与当前构建目录不一致")


def pack(platform, version, source, output):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", version):
        raise PackageError("产物标识不可用")
    source, output = Path(source).resolve(), Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    suffix = "tar.gz" if platform == "linux" else "zip"
    archive = output / f"xduwlan-{version}-{platform}.{suffix}"
    # macOS 仅暂存当前 app，防止 Products 中其他构建入口混入发行包。
    with tempfile.TemporaryDirectory(prefix="xduwlan-package-input-") as temporary:
        basis = source
        if platform == "macos":
            basis = Path(temporary)
            subprocess.run(["ditto", str(source), str(basis / "XDUWlan.app")], check=True)
        check_layout(platform, basis)
        entries = inventory(basis, platform != "windows")
        if platform == "macos":
            subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
                            str(basis / "XDUWlan.app"), str(archive)], check=True)
        elif platform == "linux":
            subprocess.run(["tar", "-czf", str(archive), "-C", str(basis), "."], check=True)
        else:
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as stream:
                for path in sorted(basis.rglob("*")):
                    stream.write(path, path.relative_to(basis).as_posix())
    manifest_path(archive).write_text(json.dumps(
        {"platform": platform, "entries": entries}, ensure_ascii=False,
        sort_keys=True) + "\n", encoding="utf-8")
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
            print("桌面包封装与解包核对通过：" + result.name)
        else:
            if not args.archive:
                parser.error("verify 需要压缩包")
            verify(args.archive, args.source)
            print("下载包内容、权限、链接与 SHA-256 核对通过")
    except (PackageError, OSError, ValueError, subprocess.CalledProcessError):
        raise SystemExit("桌面包检查失败，请核对构建目录和完整性") from None


if __name__ == "__main__":
    main()
