# 02. DNS 与地址解析

## 本节问题

程序从 URL 中取得主机名后，怎样把它转换成 TCP 可以使用的 IP 地址与端口候选？

## 目标与非目标

本节使用操作系统名称解析能力，把 `host` 和 `port` 转换成不可变的 `ResolvedAddress` 元组，并通过测试隔离真实网络。

本节不手工构造 DNS 报文，不指定公共 DNS 服务器，也不处理缓存、DNSSEC、地址排序或重试策略。

## 网络位置与参与方

完整路径为：

```text
URL → 主机名 → 名称解析 → IP 地址和端口 → TCP 连接 → HTTP
```

主机名是便于人和应用使用的名称；IP 地址是网络层转发数据时使用的地址；端口标识目标主机上的具体服务。一个主机名可以对应多个 IPv4 或 IPv6 地址，因此解析结果是候选集合，不是单个字符串。

本节区分三个层次：

- 概念模型：DNS 解决“主机名对应哪些地址”的问题；
- 操作系统接口：Python 的 `socket.getaddrinfo()` 调用系统名称解析器，系统可能继续使用本地配置、缓存或 DNS 服务；
- 项目抽象：`DnsResolver` 和 `ResolvedAddress` 隔离 `getaddrinfo()` 的五元组格式。

## 文件与符号

- `src/xduwlan/probe/interfaces.py`：
  - `ResolvedAddress`：保存数值 `host`、`port` 和地址族 `family`；
  - `DnsResolver.resolve()`：声明名称解析能力。
- `src/xduwlan/probe/dns.py`：
  - `SystemDnsResolver.resolve()`：调用 `socket.getaddrinfo()` 并转换结果。
- `tests/probe/test_dns.py`：使用 `monkeypatch` 替换系统解析函数，不访问真实 DNS。

依赖方向为：

```text
后续探测服务 → DnsResolver ← SystemDnsResolver → 操作系统名称解析器
                         ↓
                tuple[ResolvedAddress, ...]
```

## 数据流

```text
host + port
→ socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
→ (family, type, proto, canonname, sockaddr) 五元组列表
→ 提取 family、sockaddr[0] 和 sockaddr[1]
→ ResolvedAddress
→ 不可变 tuple
```

指定 `SOCK_STREAM` 表示只请求适合流式套接字的候选，后续用于 TCP。当前实现不使用 `type`、`proto` 和 `canonname`，解包变量以下划线开头表示本步骤有意忽略。

## Python 与标准库

- `for` 循环逐条转换地址记录；
- 五元组解包把系统结构拆成有名称的局部变量；
- `list.append()` 暂存结果，最后用 `tuple()` 转成不可变集合；
- `@dataclass(frozen=True)` 让地址记录可以稳定比较且不能被修改；
- `Protocol` 让测试或其他平台实现只需提供兼容的 `resolve()` 方法。

## API 检索问题

- `socket.getaddrinfo()` 的六个参数和五元组返回值分别是什么？
- `family=0`、`type=SOCK_STREAM` 对候选范围有什么影响？
- IPv4 与 IPv6 的 `sockaddr` 结构有什么差异？
- 操作系统名称解析与直接发送 DNS 报文有什么区别？

## 测试与结果

测试传入虚构主机名和保留示例地址，断言：

- `getaddrinfo()` 收到正确的主机名、端口和 `SOCK_STREAM`；
- 系统五元组被转换成 `ResolvedAddress`；
- 返回值是不可变 `tuple`。

运行：

```bash
conda run -n xduwlan python -m pytest tests/probe/test_dns.py -q
```

已验证：1 个测试通过。

## 易错点与当前边界

- DNS 成功只说明获得了地址候选，不代表 TCP 可以连接；
- 一个名称可能返回多个候选，完整探测服务以后需要决定尝试顺序；
- 当前没有把解析失败转换成阶段观察，也没有去重；这些行为留给完整探测服务接入时处理；
- 自动化测试不依赖外部 DNS，真实校园网解析只在手动实验中验证。
