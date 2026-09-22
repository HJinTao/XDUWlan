# 连通性检测与 Portal 识别

## 范围

本文记录当前网络探测实现所依据的脱敏证据。现有证据来自自动化测试和本地 loopback 服务器，只验证项目契约，不证明西电真实校园网的当前行为。

## 已验证（项目）：通信路径

```text
URL 主机名
  → 操作系统名称解析
  → 一个或多个 IP 地址与端口
  → TCP 连接候选
  → 禁止自动重定向的 HTTP GET
  → 状态码、Location 和有限正文
  → NetworkState
```

- `socket.getaddrinfo(..., type=SOCK_STREAM)` 的结果可以转换为 TCP 地址候选；
- TCP 成功、超时和其他 `OSError` 可以转换为不含底层错误正文的观察；
- HTTP 客户端可以保留原始重定向，不自动访问 `Location`；
- 响应正文按声明字符集解码，最多读取 65,536 字节；
- DNS 无候选时停止后续阶段；TCP 会按顺序尝试候选，全部失败时不发送 HTTP 请求。

## 已验证（项目）：分类契约

- `204` 分类为 `ONLINE`；
- `3xx` 且 `Location` 的 hostname 精确匹配已知 Portal 主机时分类为 `PORTAL_REQUIRED`；
- `200` 正文大小写无关地包含 `srun_portal` 时分类为 `PORTAL_REQUIRED`；
- 普通 `200`、未知主机重定向、网络失败、缺失或畸形 `Location` 分类为 `UNKNOWN`；
- hostname 使用结构化 URL 解析，查询参数中的 Portal 字符串不能冒充重定向主机。

本地服务器验证了以下数据流：

```text
/online → 204 → ONLINE
/portal → 302 → 不跟随 → PORTAL_REQUIRED
/login  → 200 + srun_portal → PORTAL_REQUIRED
```

## 真实校园网证据

目前没有提交到项目的“已观察（真实）”结论。默认探测地址、Portal 主机和分类特征仍属于待实测配置与实现假设。

## 待验证

1. 已认证网络下，默认连通性端点是否稳定返回 `204`；
2. 未认证网络下，第一跳是否稳定返回指向配置 Portal 主机的 `3xx`；
3. 当前深澜登录页是否仍包含 `srun_portal` 特征；
4. IPv4、IPv6、运营商出口和校区差异是否影响分类；
5. 是否需要多个探测目标降低单点故障造成的误判；
6. DNS、TCP 和 HTTP 的真实失败样本能否支持更细的网络状态分类。

## 安全记录边界

真实实验只记录脱敏状态码、主机类别、耗时和结论。不得保存完整重定向 URL、查询参数、认证页面正文、Cookie、个人地址或设备标识。详细规则见 [安全与隐私规则](../security.md)。
