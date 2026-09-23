# 当前工作记忆

## 当前切片

`status` 已完成，下一切片是 `configure`。它的目标是安全收集校园网账号与密码，并通过系统凭据库保存密码。

当前尚未为 `configure` 创建测试、模块或实现。第一个凭据存储子任务的技术边界已经由指导者决定，并压缩保存在本文件；下一步先向学习者讲解已定设计，再建立 RED。

## 已完成能力

- Python 3.11+ 可安装 CLI，注册 `status`、`configure`、`login`、`watch`、`account`；除 `status` 外仍是占位命令。
- `AppConfig` 提供非敏感默认配置、TOML 合并、数值校验和解析异常转换。
- 网络探测模型使用稳定枚举和不可变数据类。
- 系统适配器完成 DNS 地址解析、TCP 连接观察、禁止自动重定向的 HTTP 请求和有限正文读取。
- `DefaultNetworkProbe` 编排 DNS、TCP 多候选和 HTTP 分类，阶段失败返回安全结果。
- `status` 支持 `--config`、`--json` 和 `--debug`，不会在 JSON 中输出 Portal URL、HTTP 正文或底层异常。

## 下一子任务

实现 `configure` 的凭据存储边界。已定设计为：

- `Credentials` 使用不可变数据类保存账号和密码，并在 `repr` 中隐藏两个字段；
- `CredentialStore` 只声明 `save(credentials)` 和 `load()`；尚未配置时返回 `None`；
- `KeyringCredentialStore` 使用固定查询键，把账号与密码编码为一条 JSON 记录后一次写入系统凭据库；
- 凭据库错误或损坏记录统一转换为不泄漏内容的 `CredentialStoreError`；
- 自动化测试使用内存替身和虚构凭据，不访问真实系统凭据库。

本子任务不接入 Portal 登录，不实现协议编码，不把密码写入 TOML，也不提供明文文件回退。

## 已定调用关系

```text
configure CLI
  → 收集账号与密码
  → CredentialStore
  → keyring 适配器
  → 操作系统凭据库
```

下一步向学习者讲解本子任务的文件、符号、数据流和测试，随后由指导者一次建立完整 RED 和符号骨架。

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

指导者先向学习者讲解已定设计，再建立完整 RED 与符号骨架；确认失败准确后，由学习者一次实现凭据存储行为到 GREEN。

## 本任务索引

开始 `configure` 前按需读取：

- `docs/security.md`
- `docs/architecture.md`
- `docs/roadmap.md`
- `docs/decisions/0003-system-keyring.md`
- `src/xduwlan/cli.py`
- `src/xduwlan/config.py`
- `src/xduwlan/errors.py`
- `tests/test_cli.py`
- `pyproject.toml`
