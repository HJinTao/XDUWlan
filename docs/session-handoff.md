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
- 已创建任务 2 的 `tests/test_models.py` 和 `tests/test_config.py`，覆盖不可变模型、稳定枚举值、`Decimal`、`tuple`、默认配置、部分覆盖、未知字段和非法数值。
- 已创建 `src/xduwlan/models.py`、`src/xduwlan/errors.py` 和 `src/xduwlan/config.py` 骨架，包含类型签名、中文 docstring、`TODO` 和 `NotImplementedError`，未实现业务逻辑。
- 已验证骨架可以正常导入和编译；任务 2 的 15 个测试因待实现行为而按预期失败，任务 1 的 7 个 CLI 测试继续通过。
- 已将五个命令的交互式分层架构图保存到 `docs/visualizations/xduwlan-architecture.html`，入口位于 `docs/architecture.md`。
- 已根据学习者要求把实施路线改为纵向切片：`status`、`configure`、`login`、`watch`、`account`；不再要求先完成所有底层模型。
- 已明确按 Python 初学者教学：每个小步先解释语法，再由学习者实现数分钟规模的单元。

## 当前代码状态

仓库已有任务 1 的 Python CLI 骨架，以及任务 2 的全局模型、错误和配置空骨架。五个命令仍是占位实现。当前只把 `NetworkState`、`ProbeStage`、`ProbeObservation`、`NetworkProbeResult` 和探测配置视为待实现范围；认证与账户符号留待未来切片。

## 下一步任务

1. 指导者从 `tests/test_models.py` 移出认证结果和账户快照测试，未来在 `login`、`account` 切片按 TDD 重新加入。
2. 指导者讲解 `from enum import Enum`、`class`、继承、缩进、赋值和字符串；学习者只实现 `NetworkState` 与 `ProbeStage`。
3. 指导者运行两个枚举测试并解释结果；GREEN 后再讲解和实现 `ProbeObservation`、`NetworkProbeResult`。

## 必须先阅读

- `AGENTS.md`
- `docs/progress.md`
- `docs/superpowers/specs/2026-09-19-xduwlan-design.md`
- `docs/superpowers/plans/2026-09-19-xduwlan-mvp.md`

## 已知风险

- 西电 Portal 的真实请求参数和协议版本必须通过脱敏观察与测试向量逐步确认。
- 自服务平台使用图片验证码，不能承诺无人值守的首次登录。
- 校园网环境、运营商后缀、认证地址和页面结构可能变化，必须把可变值放入配置和适配器。
