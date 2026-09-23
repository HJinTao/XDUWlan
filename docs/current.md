# 当前工作记忆

## 当前切片

`status` 已完成，下一切片是 `configure`。它的目标是安全收集校园网账号与密码，并通过系统凭据库保存密码。

当前尚未为 `configure` 创建测试、模块或实现。第一个凭据存储子任务已经完成设计，等待学习者阅读规格后进入实施计划与 RED。

## 已完成能力

- Python 3.11+ 可安装 CLI，注册 `status`、`configure`、`login`、`watch`、`account`；除 `status` 外仍是占位命令。
- `AppConfig` 提供非敏感默认配置、TOML 合并、数值校验和解析异常转换。
- 网络探测模型使用稳定枚举和不可变数据类。
- 系统适配器完成 DNS 地址解析、TCP 连接观察、禁止自动重定向的 HTTP 请求和有限正文读取。
- `DefaultNetworkProbe` 编排 DNS、TCP 多候选和 HTTP 分类，阶段失败返回安全结果。
- `status` 支持 `--config`、`--json` 和 `--debug`，不会在 JSON 中输出 Portal URL、HTTP 正文或底层异常。

## 下一子任务

实现 `configure` 的凭据存储边界。已确认账号与密码作为一条记录进入系统凭据库，普通 TOML 不保存学号；具体接口、数据流、错误边界和测试范围以设计规格为准：

- [`2026-09-23-credential-store-design.md`](superpowers/specs/2026-09-23-credential-store-design.md)

本子任务不接入 Portal 登录，不实现协议编码，不把密码写入 TOML，也不提供明文文件回退。

## 候选调用关系

```text
configure CLI
  → 收集账号与密码
  → CredentialStore
  → keyring 适配器
  → 操作系统凭据库
```

调用关系已经确认；设计规格经学习者阅读后，指导者先编写实施计划，再建立完整 RED 和符号骨架。

## 学习上下文

学习者已经接触 `Enum`、不可变 `dataclass`、类型标注、TOML、异常链、`Protocol`、依赖注入，以及 DNS → TCP → HTTP 的基本路径。

`configure` 预计新增或加深：端口接口与适配器的区别、系统凭据库、`getpass.getpass()`、第三方库异常边界。讲解只覆盖第一个凭据子任务需要的内容。

## 当前验证

- 最近记录的完整基线：提交 `e987129` 上执行 `conda run -n xduwlan python -m pytest -q`，结果为 `66 passed`。
- 2026-09-22 的文档重构没有修改生产代码或测试；按已批准范围未重复运行 Python 测试。
- Markdown 入口、长期文档和两份 HTML 可视化已经与当前仓库结构同步。

## 后续事项

- 配置字符串字段类型、非有限数值和结果模型运行时容器类型暂未加强；不阻断 `configure`。
- 西电 Portal 的真实字段和响应必须在 `login` 切片通过脱敏证据确认。
- 自服务平台验证码继续坚持人工输入，不实现识别或绕过。

## 下一责任人和动作

学习者先阅读凭据存储设计规格；确认后由指导者编写实施计划，并按计划建立测试与骨架。

## 本任务索引

开始 `configure` 前按需读取：

- `docs/security.md`
- `docs/architecture.md`
- `docs/roadmap.md`
- `docs/decisions/0003-system-keyring.md`
- `docs/superpowers/specs/2026-09-23-credential-store-design.md`
- `src/xduwlan/cli.py`
- `src/xduwlan/config.py`
- `src/xduwlan/errors.py`
- `tests/test_cli.py`
- `pyproject.toml`
