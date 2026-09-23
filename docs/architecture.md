# 架构说明

## 架构目标

XDUWlan 使用“CLI → 应用服务 → 端口接口 ← 基础设施适配器”的依赖方向。核心数据、状态机和协议纯逻辑不依赖 CLI、操作系统、`httpx` 或 `keyring`，便于单元测试和未来跨语言实现。

```text
CLI
  → 应用服务
    → 核心模型与端口接口
      ← DNS、TCP、HTTP、凭据库和文件适配器
```

CLI 负责解析输入、装配依赖、调用服务和格式化结果；应用服务负责编排流程；端口接口描述调用方需要的能力；适配器连接 Python 标准库、第三方库或操作系统。

## 当前实现

```text
src/xduwlan/
├── cli.py
├── config.py
├── credential_service.py
├── credentials.py
├── errors.py
├── keyring_store.py
├── models.py
└── probe/
    ├── interfaces.py
    ├── dns.py
    ├── tcp.py
    ├── http.py
    ├── classifier.py
    └── service.py
```

- `models.py`：网络状态、探测阶段和不可变结果；
- `config.py`：非敏感配置的默认值、TOML 合并与校验；
- `credential_service.py`：`configure` 应用服务契约、输入校验与保存编排；
- `credentials.py`：不可变凭据模型与 `CredentialStore` 端口；
- `keyring_store.py`：使用固定查询键读写单条 JSON 凭据记录的 `keyring` 适配器，并转换后端与损坏记录错误；
- `probe/interfaces.py`：DNS、TCP、HTTP 和完整探测的端口契约；
- `probe/dns.py`、`tcp.py`、`http.py`：系统网络适配器；
- `probe/classifier.py`：把 HTTP 证据分类为稳定网络状态；
- `probe/service.py`：编排阶段并生成 `NetworkProbeResult`；
- `cli.py`：装配系统能力并提供 `status` 与 `configure` 用户界面。

## `status` 调用链

```text
xduwlan status
  → main()
  → _handle_status()
  → AppConfig.defaults() / AppConfig.load()
  → build_network_probe()
  → DefaultNetworkProbe.probe()
      → DnsResolver.resolve()
      → TcpConnector.connect()
      → HttpConnectivityChecker.request()
      → classify_http_observation()
  → NetworkProbeResult
  → 中文 / JSON / debug 输出
```

`DefaultNetworkProbe` 依赖 `Protocol`，不知道系统适配器如何完成网络操作。测试可以注入替代对象，不访问外部网络。

## `configure` 调用链

```text
xduwlan configure
  → main()
  → _handle_configure()
      → input() / getpass.getpass()
      → CredentialConfigurator.configure()
          → CredentialStore.save()
          ← KeyringCredentialStore
              → keyring.set_password()
              → 操作系统凭据库
```

CLI 不校验凭据内容，也不直接依赖存储端口。`DefaultCredentialConfigurator` 负责输入规则和保存编排，`KeyringCredentialStore` 负责第三方库与操作系统边界。

## 切片边界

已完成切片记录实际职责；其余切片只记录计划边界，具体接口在对应子任务开始前对齐：

| 切片 | 计划职责 |
| --- | --- |
| `configure` | 已完成交互输入、应用服务、系统凭据存储和安全错误输出 |
| `login` | 深澜 challenge、参数编码、响应解析和认证编排 |
| `watch` | 周期探测、认证、验证、退避和停止 |
| `account` | 自服务会话、人工验证码、HTTP 客户端和 HTML 解析 |

Portal 认证与自服务监测必须保持独立：前者负责让设备联网，后者负责读取账户数据。验证码或自服务页面变化不得直接破坏 Portal 登录。

## 稳定边界

未来跨语言实现优先复用网络与认证状态值、协议测试向量、错误分类、状态机转换和 CLI 输入输出约定。平台差异集中在适配器，不进入核心模型。

## 可视化

- [命令分层与数据流](visualizations/xduwlan-architecture.html)
- [文件、符号与依赖关系](visualizations/xduwlan-file-architecture.html)
