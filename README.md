# XDUWlan

XDUWlan 是面向西安电子科技大学校园网的轻量常驻连接管家，优先支持 Linux 和 macOS。Windows 保持构建兼容，本期不作为桌面交互验收平台。

## 产品目标

- 图形界面优先，提供账号配置、网络状态、一键认证、自动恢复和清晰的失败提示。
- 自动恢复默认开启，关闭窗口隐藏到托盘后继续检测和认证；使用主界面或托盘的“退出”才终止进程。托盘不可用时，关闭窗口直接退出。
- 登录系统后启动默认关闭，开启后以 `--background` 隐藏模式运行。Linux 再次启动会激活已有实例。
- 首屏立即显示，设置、托盘、通知和启动项在首帧后初始化；准备中的功能局部禁用，账号配置与界面浏览仍可操作。
- 在线时每 60 秒检查一次；临时失败按 30 秒、60 秒、5 分钟退避。缺少账号或认证被拒绝时暂停自动认证，每 5 分钟只检查网络，保存账号或手动认证后恢复尝试。系统恢复后立即检查，不补跑休眠期间的任务。
- 下载安装即可使用，不要求用户另行安装 Python、Dart 或其他语言运行环境。

Wi-Fi 连接和重连由操作系统负责。本项目专注校园网认证与恢复，不包含流量或余额查询、账户管理、设备管理。启动、检查、认证和保存账号均不访问查询门户 `https://zfw.xidian.edu.cn/login`。未来相关查询功能将使用独立适配器，只在用户主动进入时交互获取图片验证码及可能的短信验证码，使用基础账号和同一密码。

## 使用与隐私

在“配置账号”中填写账号和密码，选择“校园网（空后缀）”或“自定义”后缀，然后保存。只保存一组账号，再次保存会覆盖原记录；不提供“保存并测试”，也不预设未经实测的运营商映射。密码输入默认隐藏，可按需显示。

账号密码以明文保存在应用支持目录的 `credentials.json` 中，不增加加密或系统凭据存储。现有文件格式不变；macOS 既有容器目录存在时继续使用原目录，无需迁移。仅在确认需要认证并校验可信上下文后，凭据及派生值才发送到受信任的 HTTPS 校园网端点，保留证书验证。文件读写失败会给出配置错误提示。

`settings.json` 只保存自动恢复和登录启动开关。`diagnostics.json` 最多保存 50 条时间、操作来源、动作、网络状态、安全结果、失败类别和耗时，不记录账号、密码、Cookie、验证码、认证参数或原始响应。诊断文件损坏时保留一个隔离文件并重新记录；诊断页“清空”同时删除当前和隔离记录。系统通知仅用于自动认证成功或失败，同类连续失败只提示一次。

Linux 的托盘依赖桌面提供 StatusNotifierItem 宿主；GNOME 缺少宿主时会提示启用 AppIndicator，主程序继续运行。macOS 使用用户 LaunchAgent 注册登录启动，直接发行构建不启用 App Store sandbox；修改安装位置前应先关闭原位置的登录启动。

## 开发

需要 Flutter 3.47.7 / Dart 3.13.5 或兼容版本。进入 Flutter 工程目录后执行：

```bash
cd app
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Linux 构建需要 GTK 3、X11、Xi 和 libnotify 开发文件：

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libx11-dev libxi-dev libnotify-dev
```

桌面发布构建：

```bash
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

GitHub Actions 对三个桌面平台执行静态分析、离线测试和 Release 构建，成功后上传对应产物，保留 30 天。推送 `v*` 标签时，workflow 将三种平台压缩包发布到对应 GitHub Release；重复发布同一标签会覆盖同名附件。

平台验收证据和未验证项见[维护状态](docs/current.md)。自动测试只使用虚构账号、本地服务和测试证书，不连接真实校园网。

## 文档

- [维护约定](AGENTS.md)
- [当前实现与验证](docs/current.md)
- [协议与验证记录](docs/protocol.md)
