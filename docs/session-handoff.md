# 会话交接

## 当前目标

根据已批准的中文设计规格开始任务 2；任务 1 已完成，继续采用“指导者编写测试、学习者实现生产代码”的结对学习方式，并保持先测试后实现。

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
- 已创建任务 1 的 CLI 测试文件 `tests/test_cli.py`，并完成过预期的 RED 验证。
- 已创建 Conda 环境 `xduwlan`，Python 版本为 3.11.16，pytest 版本为 9.1.1。
- 已完成任务 1：`pyproject.toml`、`src/xduwlan/__init__.py` 和 `src/xduwlan/cli.py` 已实现，7 个 CLI 测试通过。
- 已创建 `docs/learning/00-python-cli.md` 并更新 README 的开发安装说明。

## 当前代码状态

仓库已有任务 1 的 Python CLI 骨架和自动测试。五个命令仍是占位实现，不执行网络、认证或凭据操作。

## 下一步任务

1. 开始任务 2：指导者编写 `tests/test_models.py` 和 `tests/test_config.py` 的失败测试。
2. 学习者实现 `src/xduwlan/models.py`、`src/xduwlan/errors.py` 和 `src/xduwlan/config.py`。
3. 指导者运行测试、解释结果并更新文档。

## 必须先阅读

- `AGENTS.md`
- `docs/progress.md`
- `docs/superpowers/specs/2026-09-19-xduwlan-design.md`
- `docs/superpowers/plans/2026-09-19-xduwlan-mvp.md`

## 已知风险

- 西电 Portal 的真实请求参数和协议版本必须通过脱敏观察与测试向量逐步确认。
- 自服务平台使用图片验证码，不能承诺无人值守的首次登录。
- 校园网环境、运营商后缀、认证地址和页面结构可能变化，必须把可变值放入配置和适配器。
