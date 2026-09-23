# 当前工作记忆

## 当前切片

`status` 和 `configure` 已完成。下一切片是 `login`：仅在确认需要认证时读取凭据，执行一次 Portal 认证，并重新探测以验证联网结果。

当前还没有 `login` 的模块、测试或脱敏协议向量。修改认证协议前必须先取得满足 `docs/security.md` 的脱敏证据；不能根据未验证的字段或响应猜测实现。

## 已完成能力

- Python 3.11+ 可安装 CLI，注册 `status`、`configure`、`login`、`watch`、`account`；后三个命令仍是占位。
- `AppConfig` 提供非敏感默认配置、TOML 合并、数值校验和解析异常转换。
- `DefaultNetworkProbe` 使用独立 DNS、TCP、HTTP 适配器完成安全的网络状态探测。
- `status` 支持 `--config`、`--json` 和 `--debug`，不会输出 Portal URL、HTTP 正文或底层异常。
- `Credentials` 隐藏账号和密码的 `repr`；`CredentialStore` 提供与平台无关的保存和读取端口。
- `KeyringCredentialStore` 通过固定查询键把账号与密码作为单条 JSON 保存到系统凭据库；后端和损坏记录错误统一转换为安全项目错误。
- `DefaultCredentialConfigurator` 负责账号整理、空字段校验和保存编排；CLI 使用 `input()` 读取账号、`getpass.getpass()` 隐藏读取密码。
- `configure` 在终端不能关闭密码回显时明确失败，不提供明文回退；成功、校验失败、存储失败和取消输入使用稳定输出与退出码。

## 已实现调用关系

```text
xduwlan configure
  → _handle_configure()
      → input() / getpass.getpass()
      → CredentialConfigurator.configure()
          → CredentialStore.save()
          ← KeyringCredentialStore
              → keyring.set_password()
              → 操作系统凭据库
```

CLI 只处理终端交互和结果展示；应用服务处理输入规则与保存编排；系统适配器处理 JSON、第三方异常和平台凭据库。

## 当前验证

- `conda run -n xduwlan python -m pytest -q tests/test_credential_service.py tests/test_cli.py tests/test_credentials.py`：`40 passed`。
- `conda run -n xduwlan python -m pytest -q`：`88 passed`。
- `git diff --check` 与两份 HTML 可视化脚本校验通过。
- 生产代码和项目文档未发现测试用账号、密码或私密错误标记；自动化测试没有访问真实终端、校园网或系统凭据记录。

## 后续事项

- 配置字符串字段类型、非有限数值和结果模型运行时容器类型暂未加强；不阻断 `login`。
- 西电 Portal 的真实字段、编码顺序和响应必须通过脱敏证据确认。
- `configure` 尚未进行真实系统凭据库的受控人工验证；真实实验只能由学习者明确执行并记录脱敏结果。
- 自服务平台验证码继续坚持人工输入，不实现识别或绕过。

## 下一责任人和动作

指导者先为 `login` 的协议证据收集与脱敏测试向量设计子任务；若仓库没有足够外部事实，由学习者明确执行受控实验。取得证据前不建立认证实现 RED。

## 本任务索引

开始 `login` 前按需读取：

- `docs/security.md`
- `docs/architecture.md`
- `docs/roadmap.md`
- `docs/protocol/README.md`
- `src/xduwlan/cli.py`
- `src/xduwlan/config.py`
- `src/xduwlan/credentials.py`
- `src/xduwlan/probe/interfaces.py`
- `src/xduwlan/probe/service.py`
- `tests/test_cli.py`
- `tests/probe/test_service.py`
