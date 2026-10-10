# 架构

## 依赖方向与设计理由

```text
CLI → 应用服务 → 核心模型与端口 ← 基础设施适配器
```

CLI 负责交互与装配，服务负责编排，适配器连接网络和凭据库。核心不依赖平台和具体 HTTP 库，使协议逻辑和失败分支可离线验证。

- 使用 Python 与标准库网络接口，减少额外依赖；Python 3.10 的 TOML 解析由条件依赖 tomli 补足。
- 长期凭据交给 keyring，平台后端不可用时明确失败，避免明文回退。
- 入口发现与认证分开：`prepare()` 不接收凭据，未知目标不会触发读取或提交。
- 不自动跟随认证重定向，逐步校验目标；成功响应之后仍做独立联网复查。

产品范围和命令契约见 [README](../README.md)，凭据边界见 [安全](security.md)，编码依据见 [协议](protocol.md)。

## 模块与接口

| 文件 | 职责与主要符号 |
| --- | --- |
| `cli.py` | `main`、参数解析、`build_network_probe`、`build_login_service`、安全结果输出 |
| `config.py` | `AppConfig`、TOML 默认值、合并与校验 |
| `models.py` | `NetworkState`、`ProbeObservation`、`NetworkProbeResult` |
| `credential_service.py` | `DefaultCredentialConfigurator`、整理输入与保存编排 |
| `credentials.py` | `Credentials`、`CredentialStore` |
| `keyring_store.py` | `KeyringCredentialStore`、固定键单条 JSON 与后端错误转换 |
| `errors.py` | 配置、凭据、Portal 网络/协议和认证拒绝异常 |
| `probe/interfaces.py` | DNS、TCP、HTTP 与 `NetworkProbe` 端口 |
| `probe/dns.py`、`tcp.py`、`http.py` | 系统网络适配器 |
| `probe/classifier.py` | `classify_http_observation`、HTTP 证据分类 |
| `probe/service.py` | `DefaultNetworkProbe`、主探测与 HTTP 入口回退 |
| `auth/interfaces.py` | `PortalContext`、`PortalResponse`、`PortalTransport`、`PortalClient` |
| `auth/pages.py` | 可信 URL、空 POST/meta refresh 和 CONFIG 解析 |
| `auth/protocol.py` | HMAC-MD5、UTF-16/XEncode、自定义 Base64、checksum、严格 JSONP |
| `auth/transport.py` | `SystemPortalTransport`、超时、正文上限、TLS 校验、禁止代理和重定向 |
| `auth/client.py` | `SrunPortalClient.prepare()` 与 `authenticate()` |
| `login_service.py` | `LoginState`、`LoginResult`、`DefaultLoginService` |

## 调用链

```text
configure → 隐藏输入 → DefaultCredentialConfigurator
          → CredentialStore.save ← KeyringCredentialStore → 系统凭据库

status → AppConfig → DefaultNetworkProbe
       → DNS → TCP → HTTP → classify_http_observation
       → 主探测失败或未知：HTTP 回退，仅接受可信 Portal 结果
       → NetworkProbeResult → 安全输出

login → AppConfig → DefaultLoginService
      → NetworkProbe.probe
      → 已联网或未确认需要认证：结束
      → PortalClient.prepare
          → HTTP 入口 → 同源 HTTPS 导航 → PortalContext
      → CredentialStore.load → 凭据校验与显式后缀
      → PortalClient.authenticate
          → HTTPS challenge → build_login_params → HTTPS login
      → NetworkProbe.probe → 仅 ONLINE 为恢复成功
      → LoginResult → 安全输出
```

导航最多六次，challenge/login 各一次，认证失败不重试。HTTP 204 不覆盖主 HTTPS 探测失败。原始响应与业务消息不进入 CLI。

## 验证边界

固定虚构 JavaScript 向量验证纯函数；本地服务器验证 HTTP 与 TLS；注入的外部边界验证状态转换和凭据访问时机。真实校园网结果独立记录在协议文档，不混入自动测试。

辅助视图：[命令职责](visualizations/xduwlan-architecture.html)、[文件职责](visualizations/xduwlan-file-architecture.html)。
