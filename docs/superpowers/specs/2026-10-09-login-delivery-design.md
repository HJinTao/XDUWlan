# 第一版认证恢复设计

产品范围以 [路线图](../../roadmap.md) 为唯一依据；本设计只确定剩余实现。学习者已授权指导者全部接管。

## 调用与边界

`CLI → DefaultLoginService → NetworkProbe / CredentialStore / PortalClient`。新增 `auth/protocol.py` 保存 HMAC-MD5、XEncode、自定义 Base64、checksum 与 JSONP 纯函数；`auth/pages.py` 解析可信空表单、meta refresh 和页面 CONFIG；`auth/client.py` 沿入口链获取认证上下文并完成一次 challenge/login；`auth/transport.py` 使用标准库发送有超时、正文大小上限、禁止自动重定向与代理的请求。核心模型和接口位于 `auth/interfaces.py` 与 `login_service.py`，不依赖系统和具体 HTTP 库。

`PortalClient.prepare() -> PortalContext` 不接收凭据；`PortalClient.authenticate(context, credentials) -> None` 成功返回，失败抛出安全项目异常。`LoginService.login() -> LoginResult` 编排并生成固定结果，不输出原始错误或业务消息。

```text
探测网络
若 ONLINE：返回 ALREADY_ONLINE
若不是 PORTAL_REQUIRED：安全结束
取得并校验 PortalContext
读取系统凭据；缺失时提示 configure
认证一次；拒绝、网络故障和格式变化分别映射
再次探测；只有 ONLINE 才返回 RESTORED
```

## 探测与请求安全

主探测默认使用 HTTPS；失败或未知时才用同一端点的 HTTP 地址获取 Portal 线索。HTTP 回退只用于确认需要认证，不能以其 204 覆盖 HTTPS 失败。入口中的表单、重定向和刷新必须指向配置中的精确 Portal 主机及默认端口；允许将该主机的 HTTP 入口提升到 HTTPS，不执行页面脚本。跟随次数有上限。账号、密码及派生值只发送至可信 HTTPS 同源固定端点；证书验证保持开启。配置 URL 禁止内嵌账号与密码。

空 POST 必须确认为无输入字段的 Portal 入口，不重放未知表单数据。CONFIG 的 IP 使用 IPv4 校验，acid 必须为正整数字符串；IPv6、双栈和不同校区不因离线测试而宣称已实测。协议支持 JavaScript UTF-16 单元装包，使用独立 JavaScript 参考生成虚构向量核对非 ASCII 输入。

成功响应采用已观察的 code=0 或旧格式 error=ok；其他明确业务拒绝归类为认证拒绝，不猜测未知错误码就是密码错误。缺少业务状态、challenge、上下文，回调不匹配或格式错误归类为协议变化。原始响应、challenge、IP、URL 和错误正文不进入用户输出。

## CLI 与交付

保留 `status`、`configure`、`login`，移除已取消或未实现的 `watch`、`account` 成功占位。无子命令继续显示帮助；`xduwlan login` 执行一次恢复，支持 `--config`、`--json`、`--debug`。所有认证失败都有固定中文建议与非零退出码；取消返回 130。

安装产物采用 wheel 与 sdist，提供 Python 3.11+ 的可复现安装、配置、运行和系统凭据库说明。三平台 CI 使用虚构输入和本地服务器，禁止真实校园网请求与真实凭据记录。更新架构、能力状态、协议证据、README 与两份 HTML；真实 macOS 校园网验收和远端 CI 状态如未执行，明确保留为待验证。

## 官方 API 与验证依据

Python 官方接口：[urllib.request](https://docs.python.org/3.11/library/urllib.request.html)、[HTMLParser](https://docs.python.org/3.11/library/html.parser.html)、[hmac](https://docs.python.org/3.11/library/hmac.html)、[hashlib](https://docs.python.org/3.11/library/hashlib.html)。协议事实来自 [脱敏观察](../../protocol/srun-authentication.md)，不执行参考脚本的 main。

测试以虚构编码向量、恶意 URL/HTML、替代传输及注入的服务端口验证。核心断言包括编码结果、请求方法与字段顺序、可信目标、读取凭据时机、仅一次认证、认证后再探测、错误分类及全部输出的敏感标记缺失。
