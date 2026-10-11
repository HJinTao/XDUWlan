# 协议与验证记录

本文记录实现所需的脱敏协议事实，不包含真实凭据、网络标识、页面或请求内容。产品范围见 [README](../README.md)，维护原则见 [AGENTS.md](../AGENTS.md)。

## 证据等级

- **项目验证**：固定虚构向量或本地服务证明项目契约。
- **真实观察/验收**：在授权环境中得到的脱敏结果，只适用于记录的设备和网络条件。
- **待验证**：推断或尚未在目标平台确认的行为。

## 探测与认证契约

Flutter 实现位于 `app/lib/core/`、`app/lib/application/` 和 `app/lib/platform/`，对应验证位于 `app/test/`。

认证流程为：

```text
联网探测
  -> ONLINE：跳过认证
  -> PORTAL_REQUIRED：获取并校验 Portal 上下文
      -> 加载凭据 -> challenge -> 构造参数 -> login
      -> 独立联网复查，仅 ONLINE 才报告恢复成功
  -> 其他状态：结束本次恢复
```

已联网或未确认需要认证时不读取凭据，也不发起 Portal 认证请求。Portal 业务响应成功不足以证明网络已恢复，必须通过独立复查确认。

主 HTTPS 探测返回 204 才作为在线证据；确认在线或需要认证后不再执行回退。主探测未取得上述结论时，HTTP 回退只用于发现认证入口，只有需要认证的分类可以替代主结果；HTTP 204 不覆盖主 HTTPS 的 TLS/传输失败或未知状态。此边界由 [`IoNetworkProbe`](../app/lib/platform/network_probe.dart) 与[虚构响应测试](../app/test/platform/network_probe_test.dart)验证，属于项目契约。

移动端还必须合并系统链路事实。iOS 通过 `NWPathMonitor` 只提供脱敏的接口类别和可用性；蜂窝、无网络、其他接口和未知接口永远不允许认证。Wi-Fi 加普通互联网 204 只能表示“Wi-Fi 在线，校园网未确认”，不能替代可信 Portal 证据。只有 Wi-Fi 且 Portal 重定向或 srun 特征通过既有可信校验时，才进入“需要校园网认证”并允许认证；认证门在读取凭据前执行。

可信 Portal 重定向、srun 特征页面或唯一空 POST 入口表示需要认证；普通 200、未知重定向、缺少证据、超时和畸形响应均不能直接判定为在线。请求禁止自动跟随重定向，并限制正文大小、请求次数和单次超时。

Portal 入口只接受校验后的可信主机和默认端口；认证提交只允许发往配置的 HTTPS 同源目标。入口阶段不携带凭据，单轮 challenge 和 login 各最多请求一次，不在轮内重试；跨轮调度与账号错误暂停策略见 [产品行为](../README.md#产品目标)。凭据、认证派生值、Portal 上下文和原始响应不写入日志或普通配置。

## ThinkPad 协议观察规则

ThinkPad Ubuntu 是真实校园网协议观察主机。运营商后缀、用户名拼接和 Srun 字段编码只能在授权 ThinkPad 上以单候选、单认证流程观察：候选由测试人员通过受保护的本地输入提供，工具不得从命令参数读取账号/密码或候选值，不得自动枚举和重试。观察工具在内存中检查后缀是否只追加一次、有效用户名的 Unicode/URL 编码、摘要字段的输入一致性以及独立联网复查；输出只保留固定布尔值、失败类别、请求计数和耗时。

观察结果不能直接成为产品默认映射。相同候选须在两个独立实验中成功完成 login 和独立 HTTPS 复查，且至少一次发生在 ThinkPad 固定 `down/up` 重新建立 Portal 状态之后；维护者再把结论转换为虚构协议向量和离线回归测试。真实后缀、用户名、密码、challenge、认证参数、完整 URL、原始响应和个人网络信息不进入 Git、普通配置、日志或证据文件。

验证入口通过 `--scenario=protocol-observe` 启用该观察流程，仅接受 Linux 主机、已创建的私有会话目录和目录内一次性 `candidate` 文件。候选文件在内存中消费并立即删除；命令行不接受候选、账号或密码参数，也不接受候选列表、循环或重试。入口输出的 `protocolObservation` 只包含 `candidateAccepted`、`encodingRulePassed`、`verificationState`、请求/提交/凭据读取计数、耗时和固定失败类别。观察 sink 只检查有效用户名、摘要密码字段、`info`/`chksum` 同一输入及同源上下文，不保存请求值。

观察器在 login 完成后执行独立联网复查；只有 login 提交、编码规则和复查均成功才标记 `verified`/`candidateAccepted`。`ProtocolPromotionGate` 还要求同一候选的两次相互独立成功，并至少一次位于 ThinkPad 固定 `down/up` 之后。离线测试只使用虚构候选和本地 fake，不提升任何真实运营商规则。

## 测试资产

- `app/test/fixtures/srun_vectors.json`：固定虚构协议向量，覆盖 ASCII、中文和 emoji 输入。
- `app/test/fixtures/tls/`：仅用于本地测试的 TLS 证书和私钥，不对应真实服务。
- `app/test/platform/` 与 `app/test/application/`：本地传输、Portal 导航和一次恢复流程验证。

## ThinkPad Ubuntu 真实验证记录规则

真实校园网验证使用授权 ThinkPad Ubuntu：Mac 通过网线 SSH 管理 ThinkPad，ThinkPad 通过无线的 NetworkManager 连接 `xduwlan-lab-b` 访问校园网。连接切换只允许使用固定的 `nmcli connection down/up xduwlan-lab-b`；控制入口不得接受任意 shell 字符串或任意连接名。ThinkPad 的现有用户信息文件只在授权 Linux 验证入口惰性读取，凭据不离开 ThinkPad。

固定控制器 `app/tool/thinkpad_lab.dart` 只接受 `status`、`down`、`up`、`observe`，并将结果写入调用者提供的新建空私有目录。JSONL 只包含时间、动作、固定结果类别、主机链路类别、协议计数和脱敏批次标识；命令参数、连接名、密码和其他凭据不会从 CLI 读取。离线测试不构成真实主机的网络验收。

ThinkPad 私有证据目录记录时间、固定动作、NetworkManager 结果类别、主机链路类别、协议观察计数和验证批次标识。iOS 真机单独记录界面、通知授权和生命周期观察，再以脱敏批次标识与 ThinkPad 记录关联；ThinkPad 不控制或伪造 iPhone 网络路径。两侧均不记录账号、密码、Cookie、challenge、认证参数、SSID、IP、MAC、完整 URL、原始响应、截图或底层异常。仓库只保留脱敏结论、设备/系统版本、授权环境和未验证项。

真实验收分开覆盖两条证据链：ThinkPad 基线、无线 down/up、可信 Portal 状态和 ThinkPad 侧授权认证；iOS 真机当前链路类型、认证阻止/允许、通知授权、前后台行为和去重通知。ThinkPad 的无线 down/up 不控制 iPhone，不能作为 iPhone 蜂窝/Wi-Fi 切换证据；iOS 路径变化只能来自系统控制或独立网络条件。两端只有在时间和测试批次可对应时才建立关联；只完成离线测试、模拟器测试或单侧观测时，对应证据等级仍为“待验证”。

Simulator 的网络观察不修改 macOS 系统代理。Mac 只建立到 ThinkPad HTTP CONNECT 代理的 SSH 本地端口转发，XDUWlan Debug/测试构造显式注入回环 `PROXY host:port`；生产和 Release 构建保持 `DIRECT`。ThinkPad 只记录代理命中、目标类别、请求/字节计数和结果类别。Simulator 共享 Mac 网络栈，没有独立蜂窝接口；代理链路不能作为 `NWPathMonitor` 蜂窝证据，也不能替代真实 iPhone 通知验收。

离线烟测脚本 [`app/test/tool/simulator_proxy_smoke.sh`](../app/test/tool/simulator_proxy_smoke.sh) 只接受 `user@RFC1918-IPv4` SSH 目标和 1--65535 的本地/ThinkPad 端口，固定建立 `ssh -N -L local:127.0.0.1:thinkpad-port` 转发，再以 Debug dart-define 注入回环代理并执行一次无凭据 HTTPS 探测。脚本不接受远端 shell 命令、账号参数或密码；本仓库不执行真实 SSH。

测试通过不代表所有校区、运营商、IPv6/双栈环境或移动端网络通路已经验收；未经授权不得连接真实校园网或使用真实凭据进行自动化测试。
