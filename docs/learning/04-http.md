# 04. HTTP 响应、重定向与 Captive Portal

## 本节问题

TCP 可以连接后，怎样发送连通性请求、保留原始重定向和有限正文，并据此识别正常联网或 Captive Portal？

## 目标与非目标

本节使用 `urllib` 发送 GET 请求，禁止自动跟随重定向，把响应或网络错误转换为 `HttpObservation`，再用纯函数分类 HTTP 证据。

本节不访问真实校园网，不实现 TLS 细节，不完成 DNS/TCP/HTTP 的整体编排，也不执行 Portal 认证。

## 网络位置与协议结构

```text
URL → DNS → TCP → TLS（HTTPS）→ HTTP 请求/响应 → 状态分类
```

HTTP 请求包含方法、路径、Header 和可选正文；响应包含状态码、Header 和可选正文。当前关键状态为：

- `204`：成功但无正文，作为连通性端点的明确在线信号；
- `200`：成功并可能含正文，既可能是普通页面，也可能是 Portal 登录页；
- `302`：临时重定向，目标位于 `Location` Header；
- 网络失败：没有收到可分类的 HTTP 状态码。

Captive Portal 可以拦截原本发往连通性端点的请求，返回指向登录页的 302，或直接返回带登录特征的 200 页面。浏览器通常自动跟随 302，但网络探测必须保留原始状态和 `Location`，否则会丢失拦截证据。

## 文件与符号

- `src/xduwlan/probe/interfaces.py`：
  - `HttpObservation`：保存状态码、`Location`、正文、耗时与说明；
  - `HttpConnectivityChecker.request()`：声明 HTTP 探测能力。
- `src/xduwlan/probe/http.py`：
  - `MAX_BODY_BYTES`：正文读取上限 65,536 字节；
  - `NoRedirectHandler`：拒绝创建重定向后续请求；
  - `SystemHttpConnectivityChecker`：执行请求并转换响应或异常。
- `src/xduwlan/probe/classifier.py`：
  - `classify_http_observation()`：组合状态码、主机名和正文特征返回网络状态。
- `tests/probe/test_http.py`：标准库边界的可控单元测试；
- `tests/probe/test_classifier.py`：纯分类测试；
- `tests/probe/test_integration_server.py`：真实 loopback TCP/HTTP 集成测试。

## 请求与响应数据流

```text
url + timeout
→ Request(method="GET")
→ build_opener(NoRedirectHandler())
→ opener.open(...)
├── 普通响应：读取状态、Location、有限正文、字符集和耗时
├── HTTPError：作为带状态码和正文的 HTTP 响应读取
├── socket.timeout：返回“HTTP 请求超时”
├── URLError：返回“HTTP 请求失败”
└── OSError：返回“HTTP 请求失败”
→ HttpObservation
→ classify_http_observation()
→ ONLINE / PORTAL_REQUIRED / UNKNOWN
```

`HTTPError` 同时是异常和响应对象。禁止跟随 302 后，`urllib` 通过它暴露原始状态码、Header 和正文，因此它必须先于 `URLError` 捕获并按响应处理。

## 分类规则

当前纯分类顺序为：

1. `204` 返回 `ONLINE`；
2. `3xx` 且 `Location` 的真实 hostname 精确位于允许集合时返回 `PORTAL_REQUIRED`；
3. `200` 正文大小写无关地包含 `srun_portal` 时返回 `PORTAL_REQUIRED`；
4. 其余返回 `UNKNOWN`。

使用 `urlparse(location).hostname`，不能使用字符串包含。否则查询参数中的 Portal 文本可能冒充真正的重定向主机。畸形 URL 只在解析位置捕获 `ValueError` 并回退到 `UNKNOWN`。

## Python 与标准库

- `HTTPRedirectHandler.redirect_request()` 返回 `None`，阻止创建后续请求；
- `OpenerDirector` 可通过构造参数注入，单元测试不访问网络；
- `Message.get_content_charset()` 读取 `Content-Type` 中声明的字符集；缺失时使用 UTF-8；
- `bytes.decode(..., errors="replace")` 避免非法页面字节让探测崩溃；
- `response.read(MAX_BODY_BYTES)` 限制内存和意外下载；
- `urllib.parse.urlparse()` 结构化解析 URL；
- 本地集成测试使用 `ThreadingHTTPServer`、loopback 地址和系统分配的临时端口。

## 本地集成测试

测试服务器绑定 `127.0.0.1` 和端口 `0`。端口 `0` 让操作系统选择可用临时端口，数据不会离开本机。

```text
/online → 204 → ONLINE
/portal → 302 + 本地 Location → PORTAL_REQUIRED
/login  → 200 + srun_portal 正文 → PORTAL_REQUIRED
```

`/portal` 测试断言服务器只收到一次 `/portal`，证明真实 `urllib` 没有继续访问 `/login`。fixture 在 `finally` 中调用 `shutdown()`、`server_close()` 和 `thread.join()`，分别停止服务循环、释放监听端口并等待线程结束。

## API 检索问题

- `urllib.request.build_opener()` 如何选择和排列 Handler？
- `HTTPRedirectHandler.redirect_request()` 返回 `None` 后 302 如何表现？
- `HTTPError` 为什么既属于 `URLError` 又能像响应一样读取？
- `Content-Type` 的 `charset` 如何决定字节到字符串的解码？
- `ThreadingHTTPServer`、loopback 和端口 `0` 分别解决什么测试问题？

## 测试与结果

运行：

```bash
conda run -n xduwlan python -m pytest tests/probe -q
```

已验证：任务三共有 23 个探测测试通过，其中 DNS 1 个、TCP 3 个、HTTP 观察 8 个、分类器 8 个、本地服务器集成 3 个。全仓库共有 48 个测试通过。

## 易错点与当前边界

- `HTTPError` 必须在 `URLError` 之前捕获；
- 自动跟随重定向会隐藏 Portal 证据；
- 普通 `200` 不能直接判定在线；
- 响应正文必须限量读取并容忍编码错误；
- 本地测试验证标准库交互，不证明西电当前 Portal 行为；真实地址、状态码和页面特征仍需脱敏校园网实验确认；
- 下一步由完整探测服务编排 DNS、TCP、HTTP 阶段并生成 `NetworkProbeResult`。
