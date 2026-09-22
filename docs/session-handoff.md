# 会话交接

## 当前目标

任务 4 已完成：探测服务、`status` CLI、配置读取、脱敏 JSON、debug 输出和系统适配器装配均已验证。下一步进入任务五 `configure`。

## 已完成

- 项目目标、范围和学习方式已经确认。
- 选定 Python CLI 作为第一版。
- 选定模块化 CLI + 核心领域模型架构。
- 确定 Portal 认证与自服务监测分离。
- 确定 `status`、`login`、`watch`、`account`、`configure` 五个 MVP 命令。
- 确定前台运行、系统凭据库、人工验证码和中文文档规则。
- 已创建正式规格及基础项目文档。
- 已创建逐任务实施计划：`docs/superpowers/plans/2026-09-19-xduwlan-mvp.md`。
- 已约定测试分工：指导者编写、运行和解释自动化测试；学习者负责生产代码实现并理解测试逻辑。
- 已约定架构讲解粒度：每个小步骤开始前必须对齐具体文件、函数/类/Protocol、职责、输入输出、依赖方向和调用流程，不能只描述抽象模块。
- 已约定实现分工：指导者只搭建文件、符号、类型签名和占位边界；学习者实现具体逻辑。除非明确要求接管，指导者不代写任务实现。
- 已约定代码注释和 docstring 使用中文。
- 已约定学习者完成业务逻辑后，指导者默认承担不改变行为的格式整理；可能改变控制流、数据或外部行为的修改仍需先说明并由学习者实现或明确授权。
- 已约定实现单元按连贯概念、函数或紧密相关状态划分，同一函数内相关分支可合并推进，不按固定时长机械拆分，同时保留清晰的 RED/GREEN 信号。
- 已约定任务完成时按配置、生产代码与测试、文档等职责分批提交，逐批检查暂存差异；最后只有在 `git status --porcelain` 为空时才称工作区干净，学习者修改或来源不明的改动必须保留并报告。
- 已创建任务 1 的 CLI 测试文件 `tests/test_cli.py`，并完成过预期的 RED 验证。
- 已创建 Conda 环境 `xduwlan`，Python 版本为 3.11.16，pytest 版本为 9.1.1。
- 已完成任务 1：`pyproject.toml`、`src/xduwlan/__init__.py` 和 `src/xduwlan/cli.py` 已实现，7 个 CLI 测试通过。
- 已创建 `docs/learning/00-python-cli.md` 并更新 README 的开发安装说明。
- 已创建任务 2 的 `tests/test_models.py` 和 `tests/test_config.py`，当前覆盖网络枚举、不可变探测结果、`tuple` 观察集合、默认配置、部分覆盖、未知字段和非法数值。
- 已创建 `src/xduwlan/models.py`、`src/xduwlan/errors.py` 和 `src/xduwlan/config.py` 骨架，包含类型签名、中文 docstring、`TODO` 和 `NotImplementedError`，未实现业务逻辑。
- 已验证初始骨架可以正常导入和编译，并完成过预期 RED 验证。
- 已将五个命令的交互式分层架构图保存到 `docs/visualizations/xduwlan-architecture.html`，入口位于 `docs/architecture.md`。
- 已将当前仓库 25 个有效文件的交互式框架图保存到 `docs/visualizations/xduwlan-file-architecture.html`，可从文件树查看每个文件的输入、内部结构、输出、状态和边界。
- 已约定当前文件框架图作为活文档维护：文件结构、主要符号、调用关系或完成状态实际变化时更新；单纯讲解不要求重绘。
- 已约定教学节奏按理解难度和逻辑内聚性调整：新主题完整对齐，熟悉且紧密相关的逻辑可以合并推进；当前目标测试通过后不自动扩展非阻断边界，必要的安全与功能阻断仍及时处理。
- 已根据学习者要求把实施路线改为纵向切片：`status`、`configure`、`login`、`watch`、`account`；不再要求先完成所有底层模型。
- 已明确按 Python 初学者教学：每轮先解释当前实际出现的语法，再由学习者实现边界清晰、规模适当的连贯单元。
- 已从 `models.py`、`errors.py` 和 `tests/test_models.py` 移除认证、凭据和账户相关符号；这些内容将在对应切片重新按 TDD 引入。
- 任务 2 的 18 个模型与配置测试全部通过；全仓库 25 个测试全部通过。
- 学习者已完成 `NetworkState` 五个枚举成员；指导者因拼写错误未被原测试捕获而补强测试，使成员名称和值都进入稳定契约，当前该测试已通过。
- 学习者已完成 `ProbeStage` 的 `DNS`、`TCP` 和 `HTTP`，小步 2A 的两个枚举测试全部通过。
- 指导者已把原先合并的结果测试拆成 `ProbeObservation` 与 `NetworkProbeResult` 两个独立测试，使小步 2B 可以逐类获得 RED/GREEN 反馈。
- 学习者已使用 `@dataclass(frozen=True)` 完成 `ProbeObservation`，四个字段和不可变行为测试通过；进入 `NetworkProbeResult` 前先做一次纯格式整理。
- 学习者已完成 `NetworkProbeResult`，`models.py` 的 4 个测试全部通过；指导者按学习者授权整理了该文件的导入顺序、顶层空行和尾随空格，行为未改变。
- 学习者已把 `AppConfig` 改为 `@dataclass(frozen=True)` 并实现 `defaults()`；默认值和不可变性测试通过，指导者按授权整理了该文件格式。
- 学习者已完成 `AppConfig.load()` 的 TOML 读取、默认值合并和未知字段忽略；三个正常加载测试通过，指导者按授权整理了导入与 docstring 格式。
- 指导者已将错误数值类型测试参数化，`probe_interval_seconds` 和 `request_timeout_seconds` 都必须拒绝字符串值。
- 字符串类型测试已通过；指导者补充 TOML `true` 用例，揭示 `isinstance(True, int)` 为真的 Python 边界，等待学习者显式排除 `bool`。
- 学习者已显式排除 `bool`，两个数值字段的字符串和布尔类型测试全部通过。
- 学习者已完成大于零校验，原定 17 个任务二测试通过；指导者复核 `load()` docstring 后新增畸形 TOML 异常链测试，当前该测试准确 RED。
- 学习者已用 `raise ... from exc` 完成 TOML 解析异常转换，异常链测试通过；任务 2 已完成。
- 已创建 `docs/learning/01-models-and-config.md`，记录任务二原理、语法、调用流程、测试和实际易错点。
- 已明确把学习者同时按计算机网络初学者对待：每个网络小步先解释其在完整通信路径中的位置、参与方、分层、输入输出、正常数据流和当前失败现象，再映射到 API、代码符号与测试；该要求已写入协作规则、规格、计划和学习文档模板。
- 已明确 Superpowers 等工作技能按任务复杂度、风险和实际适用范围选择，不在每次对话中机械调用；简单 Git 操作、只读检查、状态汇报和已经完成需求对齐后的执行应直接进行。
- 已开始任务 3，并完成 URL → 主机名 → DNS → IP 地址与端口 → TCP → HTTP 的路径说明。
- 已创建 `src/xduwlan/probe/__init__.py`、`interfaces.py` 和 `dns.py`；`ResolvedAddress`、`DnsResolver` 与 `SystemDnsResolver.resolve()` 的最小实现均已就位。
- 已创建 `tests/probe/test_dns.py`，第一个测试要求调用 `socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)`，并把系统记录转换为不可变的 `ResolvedAddress` 元组。
- 已在实现前验证既有 25 个回归测试通过，新 DNS 测试因占位实现按预期 RED；随后由学习者实现并转为 GREEN。
- 已把当前文件框架图更新为 29 个文件，纳入任务 3 新增的 `probe` 文件、符号和依赖方向。
- 学习者已完成 `SystemDnsResolver.resolve()`：调用 `socket.getaddrinfo(..., type=socket.SOCK_STREAM)`，逐条解包系统五元组并返回不可变的 `ResolvedAddress` 元组。
- 指导者已审查地址转换逻辑并按学习者授权整理 docstring、尾随空格和括号缩进，未改变业务行为。
- 已验证 DNS 目标测试 `1 passed`，全仓库 `26 passed`，源码和测试可编译。
- 已把进度、计划和文件架构图从 DNS RED 更新为 GREEN。
- 已讲解 TCP 在 DNS 与 HTTP 之间的位置、连接端点、三次握手、超时和常见失败，并确认 TCP 小步设计。
- 已在 `interfaces.py` 新增不可变 `TcpObservation` 和 `TcpConnector` Protocol。
- 已创建 `src/xduwlan/probe/tcp.py` 的 `SystemTcpConnector.connect()` 骨架，以及 `tests/probe/test_tcp.py` 的成功连接测试。
- TCP 测试使用替代连接和可控时钟，不访问真实网络；已验证它因 `NotImplementedError` 准确 RED，既有 26 个测试保持 GREEN。
- 当前文件框架图已更新为 31 个文件，纳入 TCP 新文件、符号、依赖方向和 RED 状态。
- 学习者已完成 `SystemTcpConnector.connect()` 成功路径：使用 `perf_counter()` 计时，通过 `with socket.create_connection(...)` 建立并关闭连接，返回成功 `TcpObservation`。
- 指导者已审查连接目标、超时传递、资源关闭、毫秒换算和结果构造，并按授权整理标准库导入、中文 docstring 与尾随逗号，业务行为未改变。
- 已验证 TCP 目标测试 `1 passed`，全仓库 `27 passed`，源码和测试可编译。
- 已把进度、计划和文件架构图从 TCP 成功路径 RED 更新为 GREEN。
- 已在 `tests/probe/test_tcp.py` 增加参数化失败测试，同时覆盖 `socket.timeout` 和一般 `OSError` 的分类、耗时与说明脱敏。
- 当前 TCP 测试为成功路径 `1 GREEN`、失败路径 `2 RED`；既有 26 个回归测试保持 GREEN。
- 学习者已在同一轮实现 `socket.timeout` 与其他 `OSError` 的失败观察，保持成功连接行为不变，并且没有泄漏底层错误正文。
- 指导者已审查异常捕获顺序、失败耗时、说明脱敏和成功回归，按授权整理 docstring、未使用变量与空白格式。
- 已验证 TCP 测试 `3 passed`，全仓库 `29 passed`，源码和测试可编译，差异与空白检查通过。
- TCP 小步已完成并在进度、计划和文件架构图中统一标记为 GREEN。
- 已讲解 HTTP 在 TCP/TLS 之后的位置、请求与响应结构、状态码、Header、正文、重定向和 Captive Portal 拦截。
- 已确认以较完整单元实现普通响应、字符集与 64 KiB 读取上限、原始 302、默认禁止重定向 opener 和三类网络错误观察。
- 已在 `interfaces.py` 新增不可变 `HttpObservation` 与 `HttpConnectivityChecker` Protocol。
- 已创建 `src/xduwlan/probe/http.py` 的 `NoRedirectHandler`、`SystemHttpConnectivityChecker` 骨架及 `MAX_BODY_BYTES` 边界。
- 已创建 `tests/probe/test_http.py`，8 个用例全部因目标行为尚未实现而准确 RED；既有 29 个测试保持 GREEN。
- 当前文件框架图已更新为 33 个文件，纳入 HTTP 新文件、符号、依赖方向和 RED 状态。
- 学习者已完成 `NoRedirectHandler`、默认 opener、普通响应与 `HTTPError` 转换、正文限量与字符集解码，以及三类网络错误观察。
- 指导者已审查 GET 与 timeout 参数、资源关闭、异常顺序、原始 302 与 `Location` 保留、64 KiB 上限和底层错误正文脱敏。
- 指导者按授权整理 `http.py` 的导入顺序、长行、空白、尾随逗号和中文 docstring，业务行为未改变。
- 已验证 HTTP 测试 `8 passed`，全仓库 `37 passed`，源码和测试可编译，差异与空白检查通过。
- HTTP 观察单元已在进度、计划和文件架构图中统一标记为 GREEN。
- 已讲解 Captive Portal 如何用 302 或登录页替代正常连通性响应，以及为什么需要组合状态码、`Location` hostname 和正文特征。
- 已确认分类优先级为 204 在线、已知 Portal 主机 3xx、200 深澜正文、其余未知；未知或畸形信号不直接推断本地网络状态。
- 已创建 `src/xduwlan/probe/classifier.py` 的 `classify_http_observation()` 骨架和 `tests/probe/test_classifier.py` 的 8 个行为测试。
- 分类测试覆盖结构化 hostname 精确匹配，防止查询参数中的 Portal 文本冒充主机；畸形 `Location` 必须安全回退到 UNKNOWN。
- 已验证分类器 8 个测试因 `NotImplementedError` 准确 RED，既有 37 个测试保持 GREEN。
- 当前文件框架图已更新为 35 个文件；分类器实现前的 RED 已记录，当前状态已同步为 GREEN。
- 学习者已完成 `classify_http_observation()`：204 返回 ONLINE，已知 Portal hostname 的 3xx 与 200 深澜正文返回 PORTAL_REQUIRED，其余返回 UNKNOWN。
- 分类器使用 `urlparse(...).hostname` 精确匹配主机名，查询参数中的 Portal 文本不能冒充主机，畸形 URL 局部捕获 `ValueError` 后安全回退。
- 指导者已审查分类优先级与 UNKNOWN 边界，并按授权整理标准库导入和尾部空白，业务行为未改变。
- 已验证分类器测试 `8 passed`，全仓库 `45 passed`，源码和测试可编译，差异与空白检查通过。
- 分类器已在进度、计划和文件架构图中统一标记为 GREEN。
- 已创建 `tests/probe/test_integration_server.py`，在 `127.0.0.1` 的系统分配端口启动 `ThreadingHTTPServer`，使用真实 `urllib` 请求三条路径。
- `/online` 的 204 分类为 ONLINE；`/portal` 的原始 302 被保留并分类为 PORTAL_REQUIRED；`/login` 的 200 深澜特征页面分类为 PORTAL_REQUIRED。
- `/portal` 测试确认服务器只收到一次 `/portal`，未收到 `/login`，证明真实客户端没有自动跟随重定向。
- fixture 在 `finally` 中调用 `shutdown()`、`server_close()` 和 `thread.join()`，测试后无服务器线程或监听端口泄漏。
- 已创建 DNS、TCP、HTTP 三份学习文档和连通性协议记录，真实校园网结论均明确标记为待脱敏实测。
- 已验证本地集成测试 `3 passed`，任务 3 探测测试 `23 passed`，全仓库 `48 passed`。
- 当前文件框架图已更新为 40 个文件；任务 3 的代码、测试和文档状态均为 GREEN。
- 任务 4 已对齐服务、端口契约与 CLI 的具体文件、符号、调用关系和失败分类边界；第一轮仅实现 HTTPS 成功路径。
- 已新增 `NetworkProbe` Protocol、`DefaultNetworkProbe` 的依赖注入骨架和 `tests/probe/test_service.py`；测试因 `probe()` 抛出 `NotImplementedError` 准确 RED。
- 新测试使用虚构 HTTPS URL、保留示例地址和三个替代对象，断言默认 443 端口、DNS → TCP → HTTP 顺序、超时传递、原始 URL、ONLINE 和三条成功观察。
- 当前文件框架图已更新为 42 个节点；本轮无网络回归 `45 passed`。全量回归在沙箱中因 loopback 监听权限产生 3 个 fixture 错误，提权自动审批服务出错，未能重试集成测试。
- 学习者实现 HTTPS 成功路径后，首个服务测试通过；权限变化后全量回归 `49 passed`，包含本地 loopback 集成测试。
- 指导者只整理 `service.py` 导入、空白、长行、引号与尾随逗号，未改变控制流。
- 新增 DNS 失败组的 2 个参数化测试：空地址复现 `AttributeError`，`socket.gaierror` 原样外泄；成功路径 `1 passed`，旧测试 `48 passed`。
- 学习者已处理 DNS 无候选和 `socket.gaierror`，服务层 3 个测试与全仓库 51 个测试通过。
- 新增 TCP 多候选与全失败测试：先失败后成功路径 GREEN；全部失败时仍请求 HTTP，服务层当前 `4 passed, 1 failed`；旧测试 48 个通过。
- 学习者完成 TCP 全失败提前返回，服务测试 5 个与全仓库 53 个通过。
- 指导者增加服务层 Portal 重定向和 HTTP 失败的参数化测试：自定义 Portal 主机得到 `PORTAL_REQUIRED`，原始 `Location` 不进入结果，请求失败为 `UNKNOWN`；服务测试 7 个，全量 55 个通过。
- CLI 为 `status` 注册三个选项与两个空符号；首个在线输出测试在 `_handle_status()` 占位处准确 RED，未访问真实网络。
- 学习者完成默认配置、探测器调用和 ONLINE 输出；全仓库 55 个测试通过。
- 指导者新增四个非在线状态映射用例：Portal 返回 4，两类网络不可用返回 5，UNKNOWN 返回 1；当前因实际返回 `None` 而 4 RED，CLI 其余 7 个测试 GREEN。
- 根据学习者希望后续加快节奏的反馈，指导者把配置路径与错误、JSON 脱敏、debug 阶段信息和系统适配器装配测试合并到当前单元；CLI 当前 7 GREEN、11 RED，服务测试仍 7 GREEN。
- 学习者新增 `_STATUS_RESULTS` 字典并用 tuple 解包统一输出与退出码，五类状态全部 GREEN；指导者仅清理一处尾随空格，CLI 当前 11 GREEN、7 RED。
- 学习者完成 `status` 的配置路径、配置错误、JSON 脱敏、debug 阶段信息和真实适配器装配；CLI 18 个、服务 7 个、全仓库 66 个测试通过。
- 已创建 `docs/learning/05-status-cli.md`，并更新 README、实施计划和文件框架图；任务四文档状态已从 RED 更新为 GREEN。

## 当前代码状态

仓库已有任务 1 至任务 4 的完整 `status` 切片；`login`、`watch`、`account`、`configure` 仍为占位命令。任务四相关生产代码与测试、学习与项目文档已按职责分两批提交。

## 下一步任务

1. 下一次会话先阅读本交接、`docs/progress.md` 和 `docs/learning/05-status-cli.md`。
2. 进入任务五 `configure`，先对齐凭据输入、`CredentialStore` Protocol 和系统凭据库边界。

## 必须先阅读

- `AGENTS.md`
- `docs/progress.md`
- `docs/superpowers/specs/2026-09-19-xduwlan-design.md`
- `docs/superpowers/plans/2026-09-19-xduwlan-mvp.md`

## 已知风险

- 西电 Portal 的真实请求参数和协议版本必须通过脱敏观察与测试向量逐步确认。
- 自服务平台使用图片验证码，不能承诺无人值守的首次登录。
- 校园网环境、运营商后缀、认证地址和页面结构可能变化，必须把可变值放入配置和适配器。
