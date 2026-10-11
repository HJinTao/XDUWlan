# 当前实现与维护状态

## 当前能力

`app/` 是唯一产品实现，使用 Flutter 3.47.7 / Dart 3.13.5。当前实现覆盖 Linux/macOS 桌面连接管家与 iOS 18+/Android API 26+ 移动端前台流程；移动端后台使用 Workmanager 的系统尽力调度，不承诺桌面端的 60 秒周期。默认行为、用法和隐私要求以 [README](../README.md#产品目标) 为准。Windows 保持源码、插件注册和 CI 构建兼容，本阶段暂停新增桌面功能。

首帧前只同步创建对象并调用 `runApp()`。首帧后 `AppRuntimeController` 并行初始化设置、通知和对应平台能力；桌面端额外初始化窗口、托盘与登录启动状态，移动端注册后台任务，诊断文件独立读写。初始化状态局部展示，不阻塞账号配置和浏览。

`RecoveryController` 是检查与认证的唯一入口，所有来源共享串行门闩，返回同一安全 `OperationReport`。交互请求合并为一个待执行意图，当前操作完成后优先执行；自动检查确认需要认证时在同一轮中认证并复查，不重复初始探测。运行时消费报告，安排唯一的一次性调度计时器，并更新托盘、通知和诊断。关闭隐藏不取消操作；退出停止调度、取消网络作用域并释放桌面资源。睡眠信号取消调度，唤醒立即检查。

移动端通过 `RuntimeHost` 与桌面窗口/托盘能力隔离；前台生命周期恢复时立即检查，后台回调创建独立恢复实例执行一轮检查/认证，并把白名单报告写入移动端诊断文件。iOS 使用 `BGTaskScheduler`，Android 使用唯一的 WorkManager 周期任务，最小周期为 15 分钟；移动端界面不显示托盘、登录启动和退出控制。

设置和诊断采用有界 JSON 文件与同目录原子替换。诊断保留最近 50 条白名单记录，文件损坏整体隔离为单个 `.corrupt` 文件，清空删除当前及隔离记录。账号文件格式不变；macOS 解除 sandbox 后，惰性目录解析器继续使用存在的旧容器支持目录，新安装使用平台常规目录，不读取或迁移真实配置。

Linux runner 使用 `GtkApplication` 唯一实例和 StatusNotifierItem 宿主检测，监听 logind 睡眠信号。macOS runner 保持关闭隐藏与 Dock 恢复，监听系统睡眠/唤醒；登录启动由 `launch_at_startup` 调用本应用的 LaunchAgent 桥，仅操作内容与路径均匹配的启动项。macOS 直接发行构建已关闭 App Store sandbox，旧安装移动位置前应先关闭登录启动。

Linux 登录启动已替换插件的文件操作。`PluginDesktopHost` 经专用 MethodChannel 把文件工作交给 `GTask` 线程，完成回主线程后只传布尔状态或固定错误分类。独立的 `AutostartFile` 核对目录与文件元数据、完整内容和当前可执行路径；启用以同目录 `O_TMPFILE` 和持有的描述符原子无覆盖发布。禁用先移入私有暂存目录再复核，竞争中的未知内容以无覆盖重命名恢复，恢复受阻时保留捕获内容。文件系统不支持所需原子机制时安全失败；用户可见行为见 [README](../README.md#使用与隐私)。

`tool/recovery_validation.dart` 是手动 Linux 开发入口，独立构建与标识，正常产品入口不调用。工具使用生产 `IoNetworkProbe`、`SrunPortalClient`、凭据接口、`RecoveryController` 与 `AppRuntimeController`；计数包装不建立另一套认证或调度。固定命令经原子捕获后调用生产运行时，设置、诊断和安全报告写入新建私有会话目录，不访问真实登录启动项；用法见 [README](../README.md#手动-linux-恢复验证)。

协议观察场景 `--scenario=protocol-observe` 已加入该入口。它只接受 Linux/ThinkPad、本次私有会话目录中的一次性候选文件，读取现有凭据并在内存中完成一轮 challenge/login 与独立 HTTPS 复查；输出为固定脱敏布尔值、计数、耗时和失败类别。候选、凭据、认证派生字段和响应内容不会写入输出。规则提升仍需两次独立成功且至少一次经过固定无线 `down/up`，当前没有真实校园网观察结论，产品默认映射未改变。

移动端真实环境验证固定使用授权的 ThinkPad Ubuntu 实验机。Mac 与 ThinkPad 通过网线 SSH 相连；ThinkPad 的无线接口使用 NetworkManager 连接 `xduwlan-lab-b` 和随机 MAC，网络上下线只通过固定的 `nmcli connection down/up xduwlan-lab-b` 操作。ThinkPad 现有用户信息文件只由授权 Linux 验证入口惰性读取；不复制账号、密码、SSID、IP、MAC、认证参数或原始响应。

ThinkPad 负责真实网络控制、NetworkManager 状态、Linux 认证结果和主机侧脱敏证据；其 `down/up` 只改变 ThinkPad 自身无线连接，不控制 iPhone 的网络路径。iOS 真机独立负责观察当时的链路显示、认证按钮是否禁用、前后台状态和本地通知；iOS 应用不提供上下线控制，需要另一种路径时只能使用 iOS 系统控制或现有网络条件。两端证据按时间和测试批次关联，离线测试、模拟器测试或单侧记录不能替代对应的真实设备证据。

新增 `app/tool/thinkpad_lab.dart` 固定动作控制器，接受 `status`、`down`、`up`、`observe` 和受限时长/批次参数。它只构造固定的 NetworkManager 命令，输出固定类别的脱敏 JSON；证据目录必须新建且为空。当前仅完成离线测试，未在真实 ThinkPad 执行 `down/up`。

iOS Simulator 的补充测试不修改 macOS 系统代理。Mac 只建立到 ThinkPad 测试 HTTP CONNECT 代理的 SSH 本地端口转发，XDUWlan Debug/测试构造显式注入回环代理端口；当前生产传输默认 `DIRECT`，Release 和后台任务不启用代理。ThinkPad 侧必须看到代理命中和安全计数，才能证明 XDUWlan 请求经过该观察链路；该证据只用于 Portal/协议观察，不用于蜂窝路径或真实 iOS 通知结论。

`IoPortalTransport` 的 `testProxy` 只接受回环主机和数字端口，代理地址仅保留在内存中；默认、Release 和后台构造都返回 `DIRECT`。`app/test/tool/simulator_proxy_smoke.sh` 仅用于授权环境的手动烟测，限制 RFC1918 SSH 目标、数字端口、固定本地转发和一次无凭据探测；当前未执行真实 SSH 或 ThinkPad 代理验证。

## 已验证事实

2026-10-10 至 2026-10-11 的本地验证只使用虚构输入、临时目录、内存传输或本地 HTTP/TLS 服务，未使用真实账号、访问校园网、注册用户登录项或改变系统网络设置。

- 当前候选的 `dart format --output=none --set-exit-if-changed lib test tool` 与 `flutter analyze` 通过；完整 `flutter test --no-pub` 的 252 项测试通过。
- 自动测试覆盖首帧后初始化与挂起时交互、统一操作报告、串行排队、单计时器和 60 秒周期、退避重置、账号错误暂停及保存后恢复、隐藏与退出、睡眠与唤醒调度、通知去重、设置和诊断错误恢复、旧目录兼容及查询门户零请求。
- 回归测试覆盖初始化顺序竞争、账号拒绝后排队恢复、设置保存与启动项状态竞争，以及启动项操作与读回均失败时禁用开关、不把旧值描述为已确认状态。开发工具测试覆盖命令捕获竞争、私有会话目录、白名单输出和生产运行时调用；同步截止时间测试不依赖冷启动延迟。
- macOS 原生登录启动文件测试在临时目录验证后台参数、权限、启用/禁用、未知内容及符号链接的拒绝行为。此证据不等同于真实登录启动验收。
- Linux 原生文件逻辑的 14 组临时目录测试覆盖重复操作、旧格式、特殊字符、类型、所有权、权限、损坏内容、写入失败，以及发布、捕获、恢复和临时清理竞争；macOS 本地离线子集与此前候选的 Linux CI 均通过。测试未注册真实用户启动项。
- macOS 原生离线 Release 入口 `test/native_smoke.dart` 使用独立临时记录和虚构账号，分别以正常模式、`--background` 和系统再激活运行。已验证菜单栏托盘创建、正常模式可见、后台首次启动保持隐藏但完成首帧初始化、关闭隐藏、恢复窗口、通知送达、诊断与显式退出（进程退出码 0）。系统再激活通过 Launch Services 触发，与 Dock 再激活共用原生回调；未模拟鼠标点击 Dock。
- 当前产品入口的 `flutter build macos --release -t lib/main.dart` 已在本机构建成功，产物为 `app/build/macos/Build/Products/Release/XDUWlan.app`；构建成功不代表已签名发行或真实网络验收。
- 当前产品入口的 `flutter build ios --no-codesign` 已在本机构建成功，产物为 `app/build/ios/iphoneos/Runner.app`；工程配置为 iOS 18、移动包标识 `cn.xduwlan.mobile`。
- 本轮 iOS 离线实现已加入 `NWPathMonitor` 脱敏链路事实、认证安全门、本地通知授权状态与连续事件去重；iOS Simulator/Flutter 测试覆盖畸形路径回退、不可用/蜂窝零请求、Wi-Fi Portal 矩阵、通知拒绝状态和移动认证按钮门控。`flutter build ios --no-codesign` 与 iOS Simulator Debug 构建通过。
- iOS Simulator Debug 产物已安装并启动于 iPhone 16 Pro 模拟器；首帧启动日志未出现 Flutter 未处理异常。模拟器只作为启动/插件回归证据，不作为蜂窝路径、系统通知授权或真实校园网证据。
- iOS 18.7.1 真机 `Hhhjt的iPhone` 已完成 Release 签名、安装和启动，使用虚构数据启动验证；尚未进行真实校园网认证。
- iOS 启动白屏/闪退回归已定位并修复：Workmanager 在首轮初始化时先提交 `BGAppRefreshTask`，但 iOS launch handler 尚未注册，系统抛出 `No launch handler registered for task with identifier cn.xduwlan.mobile.recovery`；`AppDelegate` 现于应用启动阶段提前注册任务标识。iOS 18.6 模拟器已重新安装、启动并显示完整首页，日志无该异常。
- Flutter 分析、完整 Dart 测试和移动运行时测试通过；`flutter build apk --debug` 已构建成功。Android 模拟器启动后未保持 ADB 连接，尚未完成 Android 安装/启动验收。
- GitHub Actions 已加入 Linux/macOS 原生启动项检查、平台内封装及 artifact 下载后核对，并单独构建和上传 Linux 开发工具。此前候选的 [CI](https://github.com/HJinTao/XDUWlan/actions/runs/38071076914) 中，Linux 的 Dart/原生检查与产品 Release 构建通过；封装因错误要求共享库具有执行位而失败。当前修复保留构建权限、只要求 Linux 主程序可执行，虚构的 `0644` 共享库回归已先失败后通过。
- 最终候选提交 `d9059dd` 的 push [三平台 CI](https://github.com/HJinTao/XDUWlan/actions/runs/38073853102) 与 PR [三平台 CI](https://github.com/HJinTao/XDUWlan/actions/runs/38073856520) 均通过；每个平台的 Release 构建、封装、artifact 下载后核对均通过，Windows 还验证了 UTF-8 安全失败输出。审查入口为[草稿 PR #1](https://github.com/HJinTao/XDUWlan/pull/1)。
- 授权 ThinkPad 的最终应用代码 bundle 已在 Wayland 会话启动；该 bundle 与 d9059dd 的产品源码相同，d9059dd 之后只变更桌面封装脚本与其测试。应用 IPv4/IPv6 默认路由均走目标无线连接，SSH 控制仍走有线。产品入口运行期间诊断记录保持白名单且每 60 秒检查，SNI 宿主注册了托盘菜单；隐藏窗口、托盘恢复、单实例再次启动和托盘退出均得到安全退出证据。开发工具在线检查与认证跳过场景均未读取凭据或提交认证；1 轮受控断线记录为 `unavailable`，重新连接后的下一轮检查报告 `restored`，之后回到 60 秒检查节奏，最大并发请求为 1。
- 最终 d9059dd 包已在 ThinkPad 完成下载、远端完整性核对和解包；启动验证时 Wayland 用户会话进入 `closing` 状态，应用进程静默退出，未形成可依赖的持续运行计时。因此两小时持续运行仍未完成，不能把此前等价源码 bundle 的短时运行证据替代为最终包证据。真实登录启动和系统休眠恢复也仍未验收。

## 平台验收边界与遗留问题

| 平台 | 本轮证据 | 仍需验收 |
| --- | --- | --- |
| macOS | Dart 自动测试、插件边界测试、原生临时目录测试、本机产品 Release 构建；最终 d9059dd CI 原生检查、Release 构建和包核对 | 真实登录启动、鼠标点击 Dock、真实系统休眠/恢复、安装签名与授权校园网环境 |
| Linux | 调度与平台接口离线测试；启动项原生边界测试；最终 d9059dd CI 原生检查、Release 构建、包核对；Wayland 产品启动、SNI 托盘、隐藏/恢复、单实例和退出；1 轮授权断线恢复 | 两小时持续运行；真实登录启动与休眠恢复；GNOME 无宿主降级和通知送达的完整桌面验收 |
| Windows | 共享 Dart 分析/测试、插件注册、后台启动与电源事件源码兼容；最终 d9059dd 测试、Release 构建、包核对和 UTF-8 安全错误回归 | 桌面交互不作为本期要求 |
| iOS | iOS 18 工程、后台任务声明、无签名 Release 构建、共享 Dart 测试、iOS 18.6 模拟器首帧、路径/通知离线测试与 iOS Simulator Debug 构建 | 当前无物理 iOS 机：真机链路类型、系统通知授权变化、前后台本地通知闭环和授权校园网环境仍待验收。ThinkPad 只验证独立的校园网协议链 |
| Android | API 26 工程、WorkManager 配置、共享 Dart 测试、`flutter build apk --debug` | API 26+ 模拟器/真机前台流程、Android 13+ 通知权限实测和后台任务触发 |

`local_notifier` 0.1.6 的 macOS 实现仍使用已弃用的 `NSUserNotification` API，并依赖 CocoaPods；当前能构建与运行，但 Flutter 提示未来版本可能要求 Swift Package Manager。后续 SDK/插件升级需复核通知与构建兼容性。

离线测试不证明所有校区、运营商、账户、IPv6/双栈或平台的实际认证行为。协议事实见 [协议记录](protocol.md)，真实设备操作与数据处理边界见 [维护约定](../AGENTS.md)。
