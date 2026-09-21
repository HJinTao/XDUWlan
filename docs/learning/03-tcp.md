# 03. TCP 连接、超时与资源关闭

## 本节问题

DNS 得到地址候选后，怎样判断目标 IP 地址和端口是否能建立 TCP 连接，并把成功或失败转换成稳定观察？

## 目标与非目标

本节实现一次 TCP 连接尝试，记录目标、成功状态和毫秒耗时，并区分超时与其他系统错误。

本节不发送 HTTP 数据，不重试多个地址，不细分每一种 `errno`，也不根据单次 TCP 结果直接判断最终网络状态。

## 网络位置与参与方

```text
DNS 地址候选 → TCP 连接 → TLS（HTTPS）→ HTTP 请求
```

TCP 连接的服务端目标由 IP 地址和端口组成。客户端操作系统还会选择本地 IP 和临时端口，所以一条连接由双方的 IP 与端口共同标识。

连接建立概念上经历三次握手：

```text
客户端 -- SYN --> 服务端
客户端 <-- SYN + ACK -- 服务端
客户端 -- ACK --> 服务端
```

Python 不手工构造这些报文；`socket.create_connection()` 调用操作系统套接字接口完成连接。成功只证明目标端口接受了 TCP 连接，不证明 TLS、HTTP 或互联网状态正常。

常见失败包括：

- 超时：限定时间内没有完成连接，原因可能是丢包、防火墙静默丢弃或目标无响应；
- 连接拒绝：目标明确拒绝，通常表现为 `OSError`；
- 网络不可达：操作系统没有可用路由，同样表现为 `OSError`。

## 文件与符号

- `src/xduwlan/probe/interfaces.py`：
  - `TcpObservation`：保存地址、成功状态、耗时和安全说明；
  - `TcpConnector.connect()`：声明连接探测能力。
- `src/xduwlan/probe/tcp.py`：
  - `SystemTcpConnector.connect()`：调用系统连接接口并转换结果。
- `tests/probe/test_tcp.py`：覆盖成功、超时和一般系统错误。

## 调用与状态流

```text
ResolvedAddress + timeout
→ perf_counter() 记录开始
→ socket.create_connection((host, port), timeout=timeout)
├── 成功：with 退出时关闭 socket → succeeded=True
├── socket.timeout：记录耗时 → “TCP 连接超时”
└── OSError：记录耗时 → “TCP 连接失败”
→ TcpObservation
```

`socket.timeout` 是 `OSError` 的子类，因此必须先捕获具体的 `socket.timeout`，再捕获一般 `OSError`，否则超时会被错误归入普通失败。

## Python 与标准库

- `try` / `except` 把底层异常转换成项目观察，而不是让异常直接泄漏到 CLI；
- `with socket.create_connection(...)` 使用上下文管理协议，成功返回或异常离开代码块时都会关闭 socket；
- `time.perf_counter()` 是单调计时器，适合测量持续时间，不表示墙上日期时间；
- 秒差乘以 `1000` 得到毫秒；
- 参数化测试用同一契约验证不同异常分类。

## API 检索问题

- `socket.create_connection()` 接收什么地址结构，何时抛出 `TimeoutError` 或 `OSError`？
- TCP 连接超时与连接拒绝在网络现象上有什么区别？
- 上下文管理器的 `__enter__()`、`__exit__()` 如何保证资源关闭？
- `perf_counter()` 为什么比 `time.time()` 更适合测量耗时？

## 测试与结果

测试替换外部连接和时钟，不访问真实网络：

- 成功用例验证目标、超时参数、500 毫秒耗时和连接关闭；
- 超时用例返回 `succeeded=False` 与稳定中文分类；
- 一般 `OSError` 用例返回普通失败；
- 两类错误正文都不得进入 `detail`。

运行：

```bash
conda run -n xduwlan python -m pytest tests/probe/test_tcp.py -q
```

已验证：3 个测试通过。

## 易错点与当前边界

- `socket.timeout` 必须写在 `OSError` 之前；
- 底层异常正文可能包含平台细节或地址，不应直接进入用户输出；
- 成功连接后即使在 `with` 内 `return`，Python 也会先执行 `__exit__()`；
- 当前一次只连接一个地址候选，多地址尝试与最终故障分类留给完整探测服务。
