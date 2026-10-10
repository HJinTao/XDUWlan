# 协议与实测证据

本文保存影响实现的脱敏协议事实，不包含真实凭据、网络标识、页面或请求内容。安全边界见 [安全规则](security.md)。

## 证据等级

- **项目验证**：离线向量或本地服务证明项目契约。
- **真实观察/验收**：受控校园网实验的脱敏结果，限于实际测试环境。
- **推断/待验证**：尚不足以作为已实测行为。

项目测试通过不等于其他网络、校区或账户行为已验证。

## 探测契约（项目验证）

DNS 提供 TCP 候选；全部候选失败则停止，不发送 HTTP。HTTP 不自动重定向，正文最多读取 65,536 字节，网络和解码异常转为安全失败观察。

| HTTP 证据 | 分类 |
| --- | --- |
| 204 | ONLINE |
| 3xx，Location 主机匹配已知 Portal | PORTAL_REQUIRED |
| 200，包含 srun_portal 特征 | PORTAL_REQUIRED |
| 200，唯一空 POST 或 meta refresh 指向可信 Portal | PORTAL_REQUIRED |
| 普通 200、未知重定向、缺少或畸形证据 | UNKNOWN |

默认先探测 HTTPS，失败或未知时通过 HTTP 发现 Portal。回退只接受 PORTAL_REQUIRED；HTTP 204 不覆盖 HTTPS 失败。真正认证之前仍由 Portal 客户端校验上下文。

依据：`tests/probe/` 与 `tests/test_login_socket_integration.py`。

## 未认证入口（真实观察）

```text
HTTP 连通性请求
  → 200 空 POST 表单与自动提交脚本
  → POST Portal /index_8.html
  → 200 meta refresh
  → GET /srun_portal_pc?ac_id=...&theme=...
  → JavaScript 登录页及 CONFIG
```

首个响应没有 Location 或 srun_portal 特征。未认证时 HTTP 可达，HTTPS 探测超时；认证后两者恢复无重定向 204。

页面提供客户端 IP 和 acid；空认证主机配置使用当前 Portal 主机。生产实现不执行页面脚本，只解析已确认结构，并把可信 HTTP 导航提升为 HTTPS。IPv4/acid 校验失败时安全结束。

## 认证字段与编码（真实观察及项目验证）

challenge 使用 HTTPS GET JSONP：

```text
/cgi-bin/get_challenge
参数顺序：callback, username, ip, _
```

成功响应包含字符串 challenge/client_ip 和业务状态。项目要求回调匹配、JSON 对象、非空 challenge、client_ip 与上下文一致，随后才构造登录。

固定编码规则：

- `n = 200`、`type = 1`、`enc_ver = "srun_bx1"`。
- hmd5 为 challenge 作密钥、密码作消息的 HMAC-MD5；password 参数为 `{MD5}` 加十六进制结果。页面 md5 v2.10.0 的双参数调用已用虚构字符串对照确认。
- info 明文为按 `username, password, ip, acid, enc_ver` 排序的紧凑 JSON；执行以 challenge 为密钥的 XEncode，再用 Portal 自定义 Base64 编码，前缀 `{SRBX1}`。
- checksum 为 `challenge + username + challenge + hmd5 + challenge + acid + challenge + ip + challenge + n + challenge + type + challenge + info` 的 SHA-1。
- XEncode 按 JavaScript charCodeAt 的 UTF-16 单元装包。独立 JavaScript 向量验证 ASCII、中文和 emoji；这不代表非 ASCII 密码已在线实测。

登录使用 HTTPS GET JSONP：

```text
/cgi-bin/srun_portal
参数顺序：callback, action, username, password, os, name,
          double_stack, chksum, info, ac_id, ip, n, type, _
```

页面把数字 code=0 或旧格式 error=ok 视为成功。项目拒绝布尔 code 和缺失业务状态；明确拒绝归为认证失败，不猜测未经观察的错误码含义。原始业务消息不向外展示。

向量与解析依据：`tests/auth/reference_vectors.js`、`vectors.json`、`test_protocol.py`、`test_pages.py`、`test_client.py`。真实 HTTP/TLS、CLI 和状态转换分别由集成测试与 `test_login_service.py` 覆盖。

## 真实验收

2026-10-09，在授权的 Linux / Python 3.10.22 校园网环境中执行生产 CLI。凭据通过隐藏输入保存至 Secret Service；原始字段值与响应未进入记录。

| 场景 | 观察结果 |
| --- | --- |
| 使用新 MAC 重新接入 | 确认网络标识已变化，测试流量通过校园 Wi-Fi |
| 新 MAC 的 status | PORTAL_REQUIRED，退出码 4；不读取凭据或认证 |
| 新 MAC 的 login | RESTORED / ONLINE，退出码 0；凭据读取、prepare、authenticate 各一次，Portal 请求共五次 |
| 认证后独立检查 | 无代理、禁止重定向的 HTTP/HTTPS 请求均返回 204 |
| 再次 login | ALREADY_ONLINE，退出码 0；凭据读取和 Portal 请求均为零 |

一次恢复耗时约 10.6 秒，主要等待未认证 HTTPS 探测失败。测试通过重新接入获得未认证状态，没有执行自动下线或后台设备删除。独立实验还观察到同 MAC 重连无需再次认证。

## 待验证范围

- 真实凭据错误、账户限制和临时业务错误的具体响应。
- 不同校区、运营商、IPv6 与双栈。
- challenge 生命周期、重复使用与后台 MAC 列表容量。
- 新页面结构、脚本版本或响应字段变化。

失败分支已有虚构响应测试；上述范围不据此宣称已在线验证。
