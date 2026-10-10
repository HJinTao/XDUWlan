# XDUWlan

XDUWlan 是面向西安电子科技大学校园网的 Flutter 跨平台认证应用，目标平台为 Windows、macOS、Linux、Android 和 iOS/iPadOS。

## 产品目标

- 图形界面优先，提供账号配置、网络状态、一键认证、可选自动恢复和清晰的失败提示。
- 自动恢复默认关闭，只在应用处于前台时检测和认证，进入后台或退出后停止自动操作。
- 下载安装即可使用，不要求用户另行安装 Python、Dart 或其他语言运行环境。
- 账号密码只保存到系统安全凭据存储；存储不可用时明确报错，不回退到明文文件。

Wi-Fi 连接和重连由操作系统负责。本项目专注校园网认证与恢复，不包含流量或余额查询、账户管理、设备管理。

## 开发

需要 Flutter 3.47.7 / Dart 3.13.5 或兼容版本。进入 Flutter 工程目录后执行：

```bash
cd app
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

桌面发布构建：

```bash
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

GitHub Actions 的桌面构建任务会在构建成功后上传对应平台的 Release 产物，
可在 workflow 运行详情页的 Artifacts 区域下载。产物保留 30 天，Windows、
macOS 和 Linux 分别提供独立归档。推送 `v*` 标签时，workflow 还会把三种平台
的压缩包发布到对应的 GitHub Release 页面；重复推送同一标签会覆盖同名附件。

各平台的工具链、最低系统版本、签名和真机验收要求见[维护状态](docs/current.md)。当前测试只使用虚构账号、本地服务和测试证书，不连接真实校园网，也不读取旧实现的凭据。

## 文档

- [维护约定](AGENTS.md)
- [当前实现与验证](docs/current.md)
- [协议与验证记录](docs/protocol.md)
