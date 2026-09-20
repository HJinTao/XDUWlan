# 会话交接

## 当前目标

开始纵向切片一 `status`：先把当前测试收窄到网络探测模型，再由指导者逐行讲解 Python 语法、学习者实现最小逻辑，随后穿插配置、DNS/TCP/HTTP、应用服务和 CLI，直到 `status` 可运行。

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
- 已约定教学节奏有长有短：新主题完整对齐，熟悉的小步简短推进；当前目标测试通过后不自动扩展非阻断边界，必要的安全与功能阻断仍及时处理。
- 已根据学习者要求把实施路线改为纵向切片：`status`、`configure`、`login`、`watch`、`account`；不再要求先完成所有底层模型。
- 已明确按 Python 初学者教学：每个小步先解释语法，再由学习者实现数分钟规模的单元。
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

## 当前代码状态

仓库已有任务 1 的 Python CLI 骨架，以及任务 2 已完成的 `status` 网络模型、`ConfigurationError` 和 `AppConfig`。五个命令仍是占位实现，尚未执行真实网络探测。

## 下一步任务

1. 进入任务 3：先对齐 DNS/TCP/HTTP 探测将新增的文件、类、函数、输入输出和调用关系。
2. 指导者为第一个 DNS 解析小步搭建测试与骨架，学习者实现最小逻辑。

## 必须先阅读

- `AGENTS.md`
- `docs/progress.md`
- `docs/superpowers/specs/2026-09-19-xduwlan-design.md`
- `docs/superpowers/plans/2026-09-19-xduwlan-mvp.md`

## 已知风险

- 西电 Portal 的真实请求参数和协议版本必须通过脱敏观察与测试向量逐步确认。
- 自服务平台使用图片验证码，不能承诺无人值守的首次登录。
- 校园网环境、运营商后缀、认证地址和页面结构可能变化，必须把可变值放入配置和适配器。
