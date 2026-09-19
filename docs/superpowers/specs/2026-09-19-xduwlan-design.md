# XDUWlan 项目设计规格

## 文档状态

状态：待用户审阅。

本规格汇总已经在对话中确认的项目目标、边界、架构、学习方式和验收标准。它只描述设计，不包含功能实现。

## 1. 项目目标

项目的首要目的不是尽快得到一个黑盒工具，而是通过亲手实现校园网自动认证和监测，学习计算机网络、HTTP、Captive Portal、深澜认证协议、会话管理、凭据保护和跨平台软件设计。

第一版使用 Python 3.11+ 和命令行界面。未来可使用 Java、Go、Rust 或其他语言重新实现核心协议，并通过相同的数据模型、状态机和协议测试向量进行对照验证。

## 2. 第一版范围

### 2.1 必须包含

1. `status`：判断 `ONLINE`、`PORTAL_REQUIRED`、网络不可用或 `UNKNOWN`。
2. `login`：执行一次西电深澜 Portal 认证。
3. `watch`：前台定时探测，掉线后自动认证，使用指数退避和随机抖动。
4. `account`：读取自服务平台首页中的在线会话、设备数量、套餐流量、余额和结算日期。
5. `configure`：交互式输入账号和密码，密码保存到操作系统凭据库。
6. 自动化测试：不依赖真实校园网即可测试核心逻辑、协议字段、HTML 解析和状态机。
7. 中文学习文档、架构文档、协议记录、进度记录和跨会话交接记录。

### 2.2 明确不包含

- 图形界面、系统托盘和移动端；
- 后台系统服务、开机自启和平台专属服务注册；
- 自动识别或绕过图片验证码；
- 多账号并行、云端同步和远程数据上传；
- 自动下线、删除设备或修改自服务资料；
- 长期流量图表、通知和运营分析。

## 3. 总体架构

采用“领域核心 + 端口/适配器”的模块化 CLI 结构：

```text
CLI
  ↓
应用服务
  ├── NetworkProbe
  ├── PortalClient
  ├── WatchService
  └── AccountService
  ↓
端口接口
  ├── DNS / TCP / HTTP
  ├── CredentialStore
  ├── SessionStore
  └── 日志与持久化
  ↓
具体适配器
```

核心模型和状态机不依赖 CLI、操作系统、`httpx` 或 `keyring`。CLI 只解析参数、调用应用服务和格式化结果。

推荐目录：

```text
src/xduwlan/
├── cli.py
├── models.py
├── config.py
├── probe/
├── portal/
├── monitor/
├── watcher/
├── credentials/
└── storage/
tests/
docs/
```

## 4. 核心数据模型

### 4.1 网络状态

```python
class NetworkState(Enum):
    ONLINE = "online"
    PORTAL_REQUIRED = "portal_required"
    LOCAL_NETWORK_DOWN = "local_network_down"
    INTERNET_UNREACHABLE = "internet_unreachable"
    UNKNOWN = "unknown"
```

### 4.2 探测结果

```python
@dataclass(frozen=True)
class ProbeObservation:
    stage: ProbeStage
    succeeded: bool
    elapsed_ms: float
    detail: str


@dataclass(frozen=True)
class NetworkProbeResult:
    state: NetworkState
    observations: tuple[ProbeObservation, ...]
    portal_url: str | None = None
```

### 4.3 认证结果

```python
class AuthenticationState(Enum):
    SUCCESS = "success"
    ALREADY_ONLINE = "already_online"
    INVALID_CREDENTIALS = "invalid_credentials"
    RATE_LIMITED = "rate_limited"
    SERVER_REJECTED = "server_rejected"
    NETWORK_ERROR = "network_error"
    PROTOCOL_ERROR = "protocol_error"


@dataclass(frozen=True)
class AuthenticationResult:
    state: AuthenticationState
    message: str
    retryable: bool
```

### 4.4 监测数据

```python
@dataclass(frozen=True)
class OnlineSession:
    ip_address: str
    mac_address: str | None
    login_time: datetime
    inbound_bytes: int | None
    product_name: str


@dataclass(frozen=True)
class ProductUsage:
    product_name: str
    used_bytes: int | None
    balance: Decimal | None
    settlement_date: date | None


@dataclass(frozen=True)
class AccountSnapshot:
    collected_at: datetime
    sessions: tuple[OnlineSession, ...]
    products: tuple[ProductUsage, ...]
```

业务层使用字节数和 `Decimal`，展示层再转换为人类可读格式。

## 5. 模块职责和接口

### 5.1 CLI

命令：`configure`、`status`、`login`、`watch`、`account`。

入口为 `main() -> int`。退出码约定：`0` 成功，`1` 普通失败，`2` 配置错误，`3` 凭据缺失，`4` 需要认证，`5` 网络不可用。

使用标准库 `argparse`，第一版不引入 CLI 框架。

### 5.2 网络探测

```python
class NetworkProbe(Protocol):
    def probe(self) -> NetworkProbeResult:
        ...
```

内部包括 `DnsResolver`、`TcpConnector`、`HttpConnectivityChecker`、`PortalDetector` 和 `ProbeClassifier`。HTTP 探测默认禁止自动跟随重定向，以便识别 Portal。

### 5.3 Portal 认证

```python
class PortalClient(Protocol):
    def authenticate(self, username: str, password: str) -> AuthenticationResult:
        ...
```

实现分为 challenge 请求、认证参数构造、深澜编码器和响应解析器。加密算法尽量设计为纯函数，并使用虚构测试向量。

### 5.4 自动重连

`WatchService.run(stop_event)` 只编排探测、认证、验证和等待，不知道 Portal 参数如何加密。等待和退避策略通过 `Sleeper`、`RetryPolicy` 注入，以便测试不真实等待。

### 5.5 自服务监测

`AccountService` 独立于 Portal。首次登录获取验证码，用户人工输入后提交表单；成功后保存会话，后续请求首页并解析结构化数据。解析器只接收 HTML，不直接发请求。

### 5.6 凭据和会话

```python
class CredentialStore(Protocol):
    def save(self, account: str, password: str) -> None: ...
    def load(self, account: str) -> str | None: ...
    def delete(self, account: str) -> None: ...
```

生产实现使用 `keyring`。Portal 和自服务凭据使用不同服务名，即使当前账号密码相同，也不在架构中假定二者永远相同。

## 6. 关键数据流

### 6.1 `status`

```text
读取配置 → DNS → TCP → 禁止重定向的 HTTP → 检查状态码、Location 和页面特征 → 分类 → 输出
```

不能只依赖一个信号：DNS 失败可能是 DNS 服务异常，HTTP `200` 也可能是认证页面。后续可使用多个探测目标降低误判。

### 6.2 `login`

先探测网络。已联网时返回 `ALREADY_ONLINE`；只有确认需要认证时才读取凭据并发送认证请求。收到服务器成功响应后，再次进行独立互联网探测确认真正联网。完整认证 URL 和密码不得进入日志。

### 6.3 `watch`

状态机为：`CHECKING → HEALTHY / AUTHENTICATING / BACKING_OFF`，认证成功后进入 `VERIFYING`，验证成功后回到 `HEALTHY`。正常检测间隔默认 30 秒，请求超时默认 5 秒；退避为 2、4、8、16、30、60 秒并加入随机抖动。凭据错误和协议错误不无限重试。

### 6.4 `account`

读取已有会话并请求 `/home`。若跳转到 `/login`，则获取登录页、CSRF 和验证码，等待用户输入，提交后保存新会话，再请求首页。验证码失败时重新获取并提示用户，不复用无法确认有效的旧验证码。

## 7. 错误处理

定义 `ConfigurationError`、`CredentialError`、`NetworkOperationError`、`ProtocolError` 和 `ParseError`，底层保留异常链，CLI 默认输出可行动的中文错误和建议。`--debug` 才显示堆栈，但仍然必须脱敏。

## 8. 测试策略

- 单元测试：状态分类、地址识别、JSONP 解析、协议字段、流量转换、HTML 解析、退避和脱敏。
- 集成测试：使用本地临时 HTTP 服务器或 `httpx.MockTransport` 模拟 `204`、`302`、认证页面、超时和非法响应。
- 协议测试向量：使用虚构输入，未来其他语言必须通过同一批 JSON 向量。
- 真实实验：手动执行，不放入自动测试；只记录脱敏结果和结论。

## 9. 安全规则

密码只从系统凭据库或当前交互输入获取，不进入普通配置文件、环境变量长期存储或日志。Cookie、CSRF、challenge 和会话文件按敏感凭据处理。测试数据和文档不得出现真实账号、手机号、MAC、IP、验证码或原始 HTML。

## 10. 文档和跨会话规则

所有文档使用中文。每次会话结束更新 `docs/progress.md` 和 `docs/session-handoff.md`。新会话先读 `AGENTS.md`、交接文档、进度文档，再读当前学习和协议文档。Git 提交记录代码变化，决策文档记录原因，进度文档记录当前位置。

### 10.1 教学实施顺序

实现采用纵向切片，以尽早形成学习者可以运行和观察的完整命令。顺序为 `status`、`configure`、`login`、`watch`、`account`。每个切片按“解释当前语法和网络概念 → 指导者写失败测试与骨架 → 学习者实现最小逻辑 → 指导者审查并运行测试 → 接入 CLI → 实际运行 → 更新中文文档”的循环推进。

领域模型按需定义：`status` 阶段只实现网络探测模型，认证模型在 `login` 阶段实现，账户模型在 `account` 阶段实现。未来模型可以有空骨架，但不提前实现；未来测试在对应切片开始前不进入当前验收集合。这样每一轮 RED 都只指向学习者当前正在实现的行为，GREEN 后立即获得可见的功能增量。

## 11. 里程碑验收

### M1：项目基础与网络探测

`status` 可运行，能区分正常联网、Portal 和网络故障；核心分类有自动测试；完成一次 macOS 真实实验；学习文档已更新。

### M2：Portal 认证与凭据安全

`configure` 使用系统凭据库；`login` 可完成一次认证；协议字段通过虚构向量；认证错误可分类；成功后再次探测；日志无敏感数据。

### M3：自动侦测和重连

`watch` 前台运行；掉线自动认证；临时失败退避；不可重试错误停止；`Ctrl+C` 优雅退出；状态机测试不真实等待。

### M4：自服务监测

首次登录可人工输入验证码；会话可恢复和重新登录；`account` 输出在线设备、会话和套餐信息；解析器有脱敏 fixture；页面变化返回明确的 `ParseError`。

### M5：跨平台交付

macOS 完整实测；Windows 和 Linux 至少完成自动测试与 CLI 验证；有打包说明；新会话只读规定文档即可恢复工作。
