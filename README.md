# XDUWlan

XDUWlan 是面向西安电子科技大学校园网的连接管家，当前优先支持 Linux、macOS 和移动端。Windows 保持构建兼容，本阶段暂停新增桌面功能。

## 产品目标

- 图形界面优先，提供账号配置、网络状态、一键认证、自动恢复和清晰的失败提示。
- 自动恢复默认开启，关闭窗口隐藏到托盘后继续检测和认证；使用主界面或托盘的“退出”才终止进程。托盘不可用时，关闭窗口直接退出。
- 登录系统后启动默认关闭，开启后以 `--background` 隐藏模式运行。Linux 再次启动会激活已有实例。
- 移动端支持 iOS 18+ 和 Android 8+（API 26+）。前台实时检查；后台由系统尽力安排，不保证固定周期。
- iOS 区分蜂窝、普通 Wi-Fi 和校园网认证状态；蜂窝、未确认 Wi-Fi 或其他网络上禁止自动认证和手动认证，只允许检查并提示。只有 Wi-Fi 且取得可信校园 Portal 证据时才允许认证。
- 首屏立即显示，设置、托盘、通知和启动项在首帧后初始化；准备中的功能局部禁用，账号配置与界面浏览仍可操作。
- 在线时每 60 秒检查一次；临时失败按 30 秒、60 秒、5 分钟退避。缺少账号或认证被拒绝时暂停自动认证，每 5 分钟只检查网络，保存账号或手动认证后恢复尝试。系统恢复后立即检查，不补跑休眠期间的任务。
- 下载安装即可使用，不要求用户另行安装 Python、Dart 或其他语言运行环境。

Wi-Fi 连接和重连由操作系统负责。本项目专注校园网认证与恢复，不包含流量或余额查询、账户管理、设备管理。启动、检查、认证和保存账号均不访问查询门户 `https://zfw.xidian.edu.cn/login`。未来相关查询功能将使用独立适配器，只在用户主动进入时交互获取图片验证码及可能的短信验证码，使用基础账号和同一密码。

## 使用与隐私

在“配置账号”中填写账号和密码，选择“校园网（空后缀）”或“自定义”后缀，然后保存。只保存一组账号，再次保存会覆盖原记录；不提供“保存并测试”，也不预设未经实测的运营商映射。密码输入默认隐藏，可按需显示。

账号密码以明文保存在应用支持目录的 `credentials.json` 中，不增加加密或系统凭据存储。现有文件格式不变；macOS 既有容器目录存在时继续使用原目录，无需迁移。仅在确认需要认证并校验可信上下文后，凭据及派生值才发送到受信任的 HTTPS 校园网端点，保留证书验证。文件读写失败会给出配置错误提示。

`settings.json` 只保存自动恢复和登录启动开关。`diagnostics.json` 最多保存 50 条时间、操作来源、动作、网络状态、安全结果、失败类别和耗时，不记录账号、密码、Cookie、验证码、认证参数或原始响应。诊断文件损坏时保留一个隔离文件并重新记录；诊断页“清空”同时删除当前和隔离记录。系统通知仅用于自动认证成功或失败，同类连续失败只提示一次。

移动端继续使用同一 `credentials.json` 明文格式，但文件仅保存在 iOS/Android 应用沙盒中，不迁移桌面配置；移动端后台任务受系统调度、权限和电量策略影响。

移动端通知使用本地通知。iOS 首次前台进入时请求通知权限，启动、回到前台和发送前重新查询授权状态；用户拒绝后不重复弹出授权框，首页显示当前授权状态。认证成功、认证失败和校园网络状态变化按安全状态去重后通知。

Linux 的托盘依赖桌面提供 StatusNotifierItem 宿主；GNOME 缺少宿主时会提示启用 AppIndicator，主程序继续运行。

Linux 登录启动使用 `$XDG_CONFIG_HOME/autostart/XDUWlan.desktop`；变量未设置、为空或为相对路径时，使用 `$HOME/.config/autostart/XDUWlan.desktop`。应用只管理内容与当前可执行路径匹配的普通文件，兼容既有插件格式；同名未知内容、符号链接或异常权限会安全拒绝，不覆盖或删除。操作失败会重新查询，仍无法确认状态时禁用开关；请检查同名启动项内容或目录权限后重新打开应用。更改安装位置前，应先用原位置应用关闭登录启动。

macOS 使用用户 LaunchAgent 注册登录启动，直接发行构建不启用 App Store sandbox；修改安装位置前应先关闭原位置的登录启动。

## 开发

需要 Flutter 3.47.7 / Dart 3.13.5 或兼容版本。进入 Flutter 工程目录后执行：

```bash
cd app
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
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
flutter build ios --no-codesign
flutter build apk --debug
```

移动端开发目标为 iOS Deployment Target 18.0、Android `minSdk = 26`；Android `compileSdk` 和 `targetSdk` 使用 Flutter SDK 默认值（当前为 36）。本地真机安装需要 Xcode 签名与 iOS Developer Mode；Android 需要 Android SDK Platform 36、对应 Build Tools 和已授权设备。首版只做本地真机安装，不包含商店发布。

GitHub Actions 对三个桌面平台执行静态分析、离线测试和 Release 构建，并单独执行移动端静态测试和 Android 调试构建；Linux runner 固定为 Ubuntu 24.04。各平台先生成完整压缩包，再上传、下载并解包核对内容、权限、符号链接和 SHA-256；产物保留 30 天。

| 平台 | 压缩包名称 | 包内结构 |
| --- | --- | --- |
| macOS | `xduwlan-<标识>-macos.zip` | 完整 `XDUWlan.app`，用 `ditto` 保留包内权限与链接 |
| Linux | `xduwlan-<标识>-linux.tar.gz` | `xduwlan_app`、`lib/`、`data/`，保留构建权限与链接 |
| Windows | `xduwlan-<标识>-windows.zip` | 完整 Release 目录，包括程序、所需 DLL 和 `data/` |

普通分支的标识为完整提交 SHA，标签构建使用标签名。每个产物包含 `<压缩包名>.manifest.json` 和 `SHA256SUMS-<平台>`；前者记录文件摘要及 Unix 权限与链接，后者校验压缩包和清单。Linux 主程序必须具有执行权限，共享库保留构建时的权限，不强制增加执行位。推送 `v*` 标签时，workflow 发布已核对的三种压缩包、清单与汇总 `SHA256SUMS`；重复发布同一标签会覆盖同名附件。

### 手动 Linux 恢复验证

`tool/recovery_validation.dart` 是独立开发入口，须显式构建和运行；产品默认入口与自动测试不会启动实网验证。它复用生产探测、认证、串行控制和调度，惰性读取已有产品账号，不接受凭据命令参数，也不写入账号或系统登录启动项。真实操作边界见[维护约定](AGENTS.md#安全底线)。

在 `app/` 中构建并运行：

```bash
flutter build linux --release -t tool/recovery_validation.dart
./build/linux/x64/release/bundle/xduwlan_app \
  --scenario=observe --duration-seconds=7200 --directory=/tmp/xduwlan-validation-new
```

场景支持 `check`、`authenticate`、`observe`、`manual-during-auto`、`exit-during-operation`；可选 `--background`、`--without-tray`。工具窗口和安全输出带开发验证标识，CI 单独上传 `<标识>-validation` 的 Linux 工具包。工具与产品使用相同实例 ID，须顺序运行；产品入口与工具分别验收。

指定根目录须为空或尚不存在，不能使用产品支持目录。工具在其下新建随机私有会话子目录，把独立设置、诊断、`reports.jsonl` 与控制命令保存在子目录中；省略 `--directory` 时新建临时会话目录。标准输出只提供安全报告、状态和计数，不公开会话路径或底层异常。

控制方从根目录找到本次会话子目录后，在其中以同目录临时文件和原子重命名发布单行 `command`，每条命令消费后删除。命令支持 `check`、`authenticate`、`hide`、`show`、`status`、`automatic-on`、`automatic-off`、`authenticate-when-busy`、`exit-when-busy`、`exit`。并发新发布的命令留给下一轮，未知内容不执行。

平台验收证据和未验证项见[维护状态](docs/current.md)。自动测试只使用虚构账号、本地服务和测试证书，不连接真实校园网。

### 移动端真实环境验证（ThinkPad Ubuntu）

真实校园网验证固定在授权的 ThinkPad Ubuntu 实验机完成。Mac 与 ThinkPad 通过网线 SSH 相连；ThinkPad 通过无线连接校园网，使用 NetworkManager 中已配置的 `xduwlan-lab-b` 连接和随机 MAC。上下线只允许在 ThinkPad 上执行 `nmcli connection down/up xduwlan-lab-b`，不从 iOS 或 Mac 修改校园网连接。

ThinkPad 是真实网络状态、NetworkManager 结果、Linux 认证过程和主机侧脱敏证据的记录位置。ThinkPad 现有用户信息文件仅由授权的 Linux 验证入口惰性读取，不复制到 Mac、iOS、Git、命令参数或日志。iOS 仍需在真机上独立观察界面、通知和前后台行为；iOS 证据保留在受保护的设备/测试记录中，再以脱敏批次结论与 ThinkPad 记录关联，原始截图、账号、地址和网络标识不进入仓库。

ThinkPad 也用于授权协议观察，例如确认运营商后缀的拼接位置、Unicode/URL 编码和 Srun 派生字段的一致性。每次只验证一个明确候选，不自动枚举或重试；观察工具只输出固定成功类别、失败类别、请求计数和耗时。真实后缀和认证参数不写入命令、日志、普通配置、Git 或证据文件。只有同一候选在两次独立认证并完成联网复查后，维护者才把通用编码结论转换成虚构测试向量并修改产品规则。

iOS Simulator 可通过 Mac 的 SSH 本地端口转发连接 ThinkPad 上的测试 HTTP CONNECT 代理，从而观察 XDUWlan 自己发出的 Portal/HTTPS 请求是否到达 ThinkPad。此方案不修改 macOS 系统代理：代理主机和端口只注入 XDUWlan 的 Debug/测试构造，生产构建和后台任务保持直连。Simulator 复用 Mac 网络栈，没有独立蜂窝路径；该链路只验证请求路由和协议结果，不能替代 iPhone 的蜂窝分类或通知验收。

真实验收分两条独立证据链。ThinkPad 按 `status` 基线、`down`、观察主机状态、`up`、等待 Portal、使用既有用户信息完成授权认证的顺序验证真实校园网协议；iOS 只在真机上观察当时的蜂窝/Wi-Fi 路径、认证门、通知和前后台行为。iOS 应用不负责上下线，ThinkPad 的 `down/up` 不会被记录为 iPhone 路径切换；需要另一种 iOS 路径时只能由测试人员使用系统控制或现有网络条件切换。两端记录按时间和测试批次关联，缺少任一侧时只保留对应一侧的结论。后台任务是否触发按系统实际调度记录，不作为固定周期承诺。

ThinkPad 固定动作控制器可由授权主机上的独立工具运行：`flutter run -d linux -t tool/thinkpad_lab.dart -- --action=status --evidence-directory=/private/path --batch-id=redacted-01`，动作仅允许 `status`、`down`、`up`、`observe`，连接名固定为 `xduwlan-lab-b`。证据目录必须是新建空目录，工具只写入脱敏 JSONL；不接受 shell 命令、连接名、密码或其他凭据参数。`down/up` 只应在授权 ThinkPad 上执行。

## 文档

- [维护约定](AGENTS.md)
- [当前实现与验证](docs/current.md)
- [协议与验证记录](docs/protocol.md)
