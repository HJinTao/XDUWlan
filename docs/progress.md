# 项目进度

## 当前阶段

设计规格已获用户批准，实施路线已调整为纵向切片。任务 1 至任务 3 已完成；切片一 `status` 已具备 DNS、TCP、HTTP 基础探测、状态分类和本地服务器集成证据，下一步进入任务 4 的完整探测服务与 CLI 接入。

## 已完成

- [x] 明确项目首要目标为学习。
- [x] 确定结对学习模式。
- [x] 确定先用 Python CLI 验证，再考虑其他语言和桌面界面。
- [x] 确定模块化 CLI + 核心领域模型架构。
- [x] 确定前台 `watch`，暂不做后台服务。
- [x] 确定 `keyring` 凭据流程。
- [x] 确定自服务验证码由用户人工输入。
- [x] 确定所有项目文档使用中文。
- [x] 写入正式设计规格。
- [x] 完成逐任务实施计划。
- [x] 确定测试分工：指导者编写和维护测试，学习者实现生产代码并理解测试逻辑。
- [x] 确定架构讲解粒度：实现前对齐具体文件、函数/类/Protocol、职责、输入输出、依赖方向和调用流程。
- [x] 确定实现分工：指导者搭建骨架和测试，学习者实现具体逻辑；代码注释和 docstring 使用中文。
- [x] 创建任务 1 的 CLI 测试并确认其因生产包缺失而失败。
- [x] 完成任务 1 的可安装 Python CLI 骨架和五个占位命令。
- [x] 通过任务 1 的 7 个 CLI 测试。
- [x] 创建任务 2 的模型与配置测试，并确认测试在实现前按预期失败。
- [x] 创建 `models.py`、`errors.py` 和 `config.py` 的类型签名、中文注释与占位异常。
- [x] 将交互式项目架构图保存到 `docs/visualizations/xduwlan-architecture.html`，并从架构文档提供入口。
- [x] 将实施方式调整为 `status` → `configure` → `login` → `watch` → `account` 的纵向切片，并写入协作规则、设计规格、架构和实施计划。
- [x] 按 `status` 切片重整任务 2 代码骨架和测试，移除当前不需要的认证、凭据与账户符号。
- [x] 创建当前仓库文件框架图，随新增学习文档更新至 25 个文件。
- [x] 完成 `NetworkState` 五个成员名称与稳定字符串值，并补强测试以同时保护名称和值的对应关系。
- [x] 完成 `ProbeStage` 的 `DNS`、`TCP`、`HTTP` 成员，小步 2A 的两个枚举测试全部通过。
- [x] 使用 `@dataclass(frozen=True)` 完成 `ProbeObservation`，字段保存与不可变性测试通过。
- [x] 完成 `NetworkProbeResult` 的状态、`tuple` 观察集合、可选 Portal 地址和不可变性；`models.py` 的 4 个测试全部通过。
- [x] 整理 `models.py` 的标准库导入、顶层空行和尾随空格，回归测试保持通过。
- [x] 将 `AppConfig` 改为不可变数据类并实现 `defaults()`；默认字段与不可变性测试通过。
- [x] 完成 TOML 读取、默认值合并和未知字段忽略，三个正常加载测试通过。
- [x] 完成两个数值字段的字符串类型校验；补充 TOML 布尔值边界测试并确认其因 `bool` 是 `int` 子类而正确 RED。
- [x] 显式排除两个数值字段的布尔值，字符串和布尔类型的四个测试全部通过。
- [x] 完成两个数值字段的大于零校验，原定 17 个任务二测试全部通过。
- [x] 契约复核发现 TOML 解析异常尚未转换，新增异常链测试并确认其准确 RED。
- [x] 使用 `raise ... from exc` 将 `TOMLDecodeError` 转换为 `ConfigurationError` 并保留异常链。
- [x] 完成任务 2 的 18 个模型与配置测试，并创建 `docs/learning/01-models-and-config.md` 学习记录。
- [x] 明确学习者同时按计算机网络初学者对待；网络小步必须先讲通信路径、参与方、分层、数据流和失败现象，再映射到 API、代码符号与测试，并将这一要求同步到协作规则、规格、计划和学习文档模板。
- [x] 明确工作技能按任务复杂度、风险和适用范围选择，不在每次对话中机械调用；简单 Git 操作、只读检查和已对齐需求后的执行直接完成。
- [x] 启动任务 3，完成 DNS 小步的文件、符号和调用关系对齐。
- [x] 创建 `probe` 包、`ResolvedAddress`、`DnsResolver` 与 `SystemDnsResolver.resolve()` 骨架。
- [x] 创建第一个 DNS 地址转换测试，并确认它因 `NotImplementedError` 按预期进入 RED。
- [x] 将当前文件框架图更新为 29 个文件，纳入任务 3 新增的 `probe` 源码与测试。
- [x] 学习者完成 `SystemDnsResolver.resolve()`：使用 `socket.getaddrinfo(..., type=socket.SOCK_STREAM)`，把系统五元组转换为不可变的 `ResolvedAddress` 元组。
- [x] 指导者完成逻辑审查与格式整理；DNS 目标测试和全量回归均为 GREEN。
- [x] 完成 TCP 网络原理、文件、符号、调用流程和测试设计对齐。
- [x] 新增 `TcpObservation`、`TcpConnector`、`SystemTcpConnector` 骨架和第一个 TCP 成功连接测试。
- [x] 验证 TCP 目标测试因 `NotImplementedError` 准确 RED，既有 26 个测试保持 GREEN。
- [x] 将当前文件框架图更新为 31 个文件，纳入 TCP 适配器、测试和共享契约。
- [x] 学习者完成 `SystemTcpConnector.connect()` 成功路径：单调计时、带超时建立连接、自动关闭 socket 并返回成功观察。
- [x] 指导者完成逻辑审查与格式整理；TCP 目标测试和全量回归均为 GREEN。
- [x] 根据学习者希望适当增大单元长度的反馈，把 TCP 超时与其他 `OSError` 合并为同一轮实现。
- [x] 新增参数化 TCP 失败测试，确认成功路径 `1 GREEN`、失败路径 `2 RED`，既有 26 个回归测试保持 GREEN。
- [x] 学习者一次完成 `socket.timeout` 与其他 `OSError` 的异常分类、失败耗时和安全说明，TCP 3 个用例全部 GREEN。
- [x] 指导者审查异常顺序、成功回归和脱敏行为，并按授权整理 docstring、未使用变量和空白格式。
- [x] 完成 HTTP 网络原理、文件、符号、调用流程、异常边界和测试范围对齐。
- [x] 新增 `HttpObservation`、`HttpConnectivityChecker`、`NoRedirectHandler` 和 `SystemHttpConnectivityChecker` 骨架。
- [x] 一次建立普通响应、字符集与限量读取、原始 302、禁止自动重定向和三类网络错误测试。
- [x] 验证 HTTP 目标测试 `8 failed`，失败均指向尚未实现的 handler、默认 opener 或请求转换逻辑；既有 29 个测试保持 GREEN。
- [x] 将当前文件框架图更新为 33 个文件，纳入 HTTP 适配器、测试与共享契约。
- [x] 学习者一次完成禁止自动重定向、默认 opener、普通响应、原始 `HTTPError`、有限正文解码和三类网络错误观察。
- [x] 指导者审查请求参数、资源关闭、异常顺序、302 保留、字符集、64 KiB 上限和说明脱敏，并按授权整理格式与 docstring。
- [x] HTTP 8 个目标测试全部 GREEN，全仓库 37 个测试全部通过。
- [x] 完成 Captive Portal 组合信号、分类优先级、结构化 `Location` 解析和纯函数边界对齐。
- [x] 新增 `classify_http_observation()` 骨架和 8 个分类测试，覆盖 204、已知与未知重定向主机、查询参数伪装、深澜正文、普通 200、网络失败和畸形 `Location`。
- [x] 验证分类器 8 个测试因 `NotImplementedError` 准确 RED，既有 37 个测试保持 GREEN。
- [x] 将当前文件框架图更新为 35 个文件，纳入分类器源码与测试。
- [x] 学习者完成 `classify_http_observation()` 的完整分类优先级、结构化 hostname 匹配、大小写无关正文特征与畸形 URL 回退。
- [x] 指导者审查精确主机匹配和 UNKNOWN 边界，并按授权整理导入顺序与空白格式。
- [x] 分类器 8 个目标测试全部 GREEN，全仓库 45 个测试全部通过。
- [x] 使用本地 `ThreadingHTTPServer` 验证真实 loopback TCP/HTTP 路径中的 204、未跟随 302 和 200 深澜正文，3 个集成测试全部通过。
- [x] 验证服务器只收到 `/portal` 而未收到 `/login`，证明真实 `urllib` 没有自动跟随重定向；测试结束完整关闭服务循环、监听 socket 和线程。
- [x] 创建 `docs/learning/02-dns.md`、`03-tcp.md`、`04-http.md` 和 `docs/protocol/connectivity-detection.md`，记录实际实现、测试证据、网络原理和待实测假设。
- [x] 完成任务 3 的 23 个探测测试；全仓库 48 个测试全部通过。
- [x] 将当前文件框架图更新为 40 个文件，纳入本地集成测试和任务三学习/协议文档。

## 当前阻塞

- 无。任务 3 的 23 个探测测试和全仓库 48 个测试全部通过；任务 3 功能与文档已分批提交。

## 后续按需处理

- 配置文件缺失、字符串字段类型、非有限数值，以及数据类传入非元组观察集合等边界，留到相关功能接入或实际遇到问题时再补测修复；不阻断当前教学进度。

## 下一步

1. 进入任务 4，先对齐 `DefaultNetworkProbe` 如何从配置 URL 提取主机名和端口，并编排 DNS、TCP、HTTP 与最终 `NetworkProbeResult`。
2. 指导者建立应用服务和 `status` CLI 的失败测试与骨架，学习者实现完整纵向调用链。

## 最近验证

已在 `xduwlan` Conda 环境中验证：`tests/probe/test_integration_server.py` 的 3 个用例全部通过；任务 3 的 23 个探测测试和全仓库 48 个测试全部通过；源码和测试可编译；差异与空白检查通过。
