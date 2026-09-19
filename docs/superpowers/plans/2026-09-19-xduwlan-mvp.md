# XDUWlan MVP 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Python 构建一个可学习、可测试、可跨平台迁移的西电校园网自动认证与自服务监测命令行程序。

**Architecture:** 采用“核心领域模型 + 端口接口 + 基础设施适配器”的模块化结构。CLI 只解析命令和展示结果；网络探测、Portal 认证、自动重连和自服务监测分别由独立应用服务编排。真实网络访问、系统凭据库和页面解析均通过接口隔离，以便单元测试和未来跨语言重写。

**Tech Stack:** Python 3.11+；网络基础阶段使用标准库；真实认证使用 `httpx`；HTML 解析使用 `beautifulsoup4`；系统凭据使用 `keyring`；测试使用 `pytest`；打包使用 PyInstaller；所有项目文档使用中文。

**Spec:** `docs/superpowers/specs/2026-09-19-xduwlan-design.md`

## Global Constraints

- 第一版使用 Python 3.11+ 和命令行界面。
- 网络基础阶段优先使用 Python 标准库。
- 进入真实认证和 HTML 采集后，再按规格引入 `httpx`、`BeautifulSoup`、`keyring` 等依赖。
- 核心模型和状态机不依赖 CLI、操作系统、`httpx` 或 `keyring`。
- Portal 认证与自服务监测保持独立；自服务验证码由用户人工输入，不实现绕过。
- 密码只从系统凭据库或当前交互输入获取，不进入普通配置文件、环境变量长期存储或日志。
- 测试和协议向量只使用虚构数据；不得提交真实密码、验证码、Cookie、CSRF Token、challenge、完整认证 URL 或原始自服务 HTML。
- 所有项目文档正文使用中文；代码标识符、命令、协议字段、库名和 API 名称保留原文。
- 第一版 `watch` 以前台命令运行，不实现后台服务、系统托盘或开机自启。
- 真实网络实验手动执行，不放入自动化测试。
- 每个任务完成后运行该任务的测试，更新 `docs/progress.md` 和 `docs/session-handoff.md`，再创建一个小步 Git 提交。

---

## 文件结构总览

### 将创建的代码文件

- `pyproject.toml`：项目元数据、依赖、测试和 CLI 入口。
- `src/xduwlan/__init__.py`：包版本和公共导出。
- `src/xduwlan/models.py`：不可变领域模型、枚举和结果类型。
- `src/xduwlan/errors.py`：项目异常层次。
- `src/xduwlan/config.py`：非敏感 TOML 配置和默认值。
- `src/xduwlan/probe/`：DNS、TCP、HTTP、Portal 识别和探测分类。
- `src/xduwlan/portal/`：深澜 challenge、编码、请求和响应解析。
- `src/xduwlan/credentials/`：`keyring` 和内存测试凭据库。
- `src/xduwlan/watcher/`：探测、认证、验证、退避和停止状态机。
- `src/xduwlan/monitor/`：自服务会话、验证码流程和 HTML 解析。
- `src/xduwlan/cli.py`：`configure`、`status`、`login`、`watch`、`account` 命令。
- `src/xduwlan/formatting.py`：字节数、金额、状态和脱敏展示。

### 将创建的测试文件

- `tests/test_models.py`
- `tests/test_config.py`
- `tests/probe/test_classifier.py`
- `tests/probe/test_http.py`
- `tests/probe/test_integration_server.py`
- `tests/portal/test_encoding.py`
- `tests/portal/test_parser.py`
- `tests/credentials/test_store.py`
- `tests/watcher/test_state_machine.py`
- `tests/monitor/test_parser.py`
- `tests/monitor/fixtures/home.html`
- `tests/monitor/fixtures/login.html`
- `tests/test_cli.py`

### 将更新的文档

- `docs/learning/01-dns.md` 至 `docs/learning/08-packaging.md`：每个主题记录原理、API 检索问题、实验和复盘。
- `docs/protocol/connectivity-detection.md`、`srun-authentication.md`、`self-service.md`：只记录脱敏且标记证据类型的协议事实。
- `docs/progress.md`、`docs/session-handoff.md`：每个任务完成时更新。
- `README.md`：在命令可用后补充安装和使用示例。

## 任务 1：建立可运行的 Python 项目骨架

**Files:**
- Create: `pyproject.toml`
- Create: `src/xduwlan/__init__.py`
- Create: `src/xduwlan/cli.py`
- Create: `tests/test_cli.py`
- Modify: `README.md`
- Modify: `docs/progress.md`
- Modify: `docs/session-handoff.md`

**Interfaces:**
- Produces `xduwlan.cli.main(argv: list[str] | None = None) -> int`。
- Produces console entry point `xduwlan = xduwlan.cli:main`。
- `main([])` 输出帮助并返回 `0`；未知命令由 `argparse` 返回 `2`，但测试通过捕获 `SystemExit` 验证。

- [ ] **Step 1: 写失败测试**

```python
from xduwlan.cli import main


def test_main_without_command_prints_help(capsys):
    assert main([]) == 0
    assert "status" in capsys.readouterr().out
```

- [ ] **Step 2: 运行测试确认失败**

运行：`python -m pytest tests/test_cli.py::test_main_without_command_prints_help -q`
预期：因 `xduwlan` 包或 `main` 尚不存在而失败。

- [ ] **Step 3: 写最小实现**

在 `cli.py` 中创建 `ArgumentParser`，注册五个命令名但先让命令处理器只返回 `0`；在 `pyproject.toml` 中声明 `requires-python = ">=3.11"`、测试依赖 `pytest` 和 console script。

- [ ] **Step 4: 运行测试确认通过**

运行：`python -m pytest tests/test_cli.py -q`
预期：帮助测试通过。

- [ ] **Step 5: 写中文学习记录**

创建 `docs/learning/00-python-cli.md`，记录 `argparse.ArgumentParser`、`add_subparsers`、`add_argument` 和退出码的检索问题，并在 `README.md` 中说明开发安装命令 `python -m pip install -e ".[test]"`。

- [ ] **Step 6: 更新状态并提交**

更新进度和交接文档，将当前阶段写为“项目骨架已运行”，运行 `git add pyproject.toml src tests docs README.md && git commit -m "feat: 建立 Python 项目骨架"`。

## 任务 2：定义核心模型、错误和配置

**Files:**
- Create: `src/xduwlan/models.py`
- Create: `src/xduwlan/errors.py`
- Create: `src/xduwlan/config.py`
- Create: `tests/test_models.py`
- Create: `tests/test_config.py`
- Modify: `docs/architecture.md`

**Interfaces:**
- Produces `NetworkState`、`ProbeStage`、`ProbeObservation`、`NetworkProbeResult`。
- Produces `AuthenticationState`、`AuthenticationResult`、`OnlineSession`、`ProductUsage`、`AccountSnapshot`。
- Produces `AppConfig.load(path: Path) -> AppConfig` 和 `AppConfig.defaults() -> AppConfig`。
- 配置只包含 `portal_url`、`probe_url`、`probe_interval_seconds`、`request_timeout_seconds`、`operator_suffix` 和 `log_level`。

- [ ] **Step 1: 写失败测试**

```python
from xduwlan.models import NetworkState, NetworkProbeResult
from xduwlan.config import AppConfig


def test_probe_result_is_immutable():
    result = NetworkProbeResult(NetworkState.ONLINE, ())
    try:
        result.state = NetworkState.UNKNOWN
    except AttributeError:
        pass
    else:
        raise AssertionError("探测结果必须不可变")


def test_default_config_has_bounded_timeout():
    config = AppConfig.defaults()
    assert 1 <= config.request_timeout_seconds <= 30
```

- [ ] **Step 2: 运行测试确认失败**

运行：`python -m pytest tests/test_models.py tests/test_config.py -q`
预期：导入失败。

- [ ] **Step 3: 写最小实现**

使用 `Enum` 和 `@dataclass(frozen=True)` 定义模型；使用 `tomllib.loads` 读取 TOML，缺少字段时使用明确默认值，数值字段校验为正数，非法值抛出 `ConfigurationError`。

- [ ] **Step 4: 增加边界测试并运行**

测试空 TOML、未知字段忽略、负超时拒绝、`Decimal` 余额和 `tuple` 会话集合。运行：`python -m pytest tests/test_models.py tests/test_config.py -q`。

- [ ] **Step 5: 更新中文学习记录并提交**

创建 `docs/learning/01-models-and-config.md`，解释 `Enum`、`dataclass(frozen=True)`、`Decimal`、`tomllib`；更新架构、进度和交接文档；提交 `feat: 定义核心模型与配置`。

## 任务 3：实现 DNS、TCP、HTTP 的基础探测

**Files:**
- Create: `src/xduwlan/probe/interfaces.py`
- Create: `src/xduwlan/probe/dns.py`
- Create: `src/xduwlan/probe/tcp.py`
- Create: `src/xduwlan/probe/http.py`
- Create: `src/xduwlan/probe/classifier.py`
- Create: `tests/probe/test_http.py`
- Create: `tests/probe/test_classifier.py`
- Create: `tests/probe/test_integration_server.py`

**Interfaces:**
- `DnsResolver.resolve(host: str, port: int) -> tuple[ResolvedAddress, ...]`。
- `TcpConnector.connect(address: ResolvedAddress, timeout: float) -> TcpObservation`。
- `HttpConnectivityChecker.request(url: str, timeout: float) -> HttpObservation`。
- `NetworkProbe.probe() -> NetworkProbeResult`。
- `classify_http_observation(observation: HttpObservation, portal_hosts: frozenset[str]) -> NetworkState`。

- [ ] **Step 1: 写分类失败测试**

```python
def test_expected_204_is_online():
    observation = HttpObservation(status_code=204, location=None, body="", elapsed_ms=2.0)
    assert classify_http_observation(observation, frozenset()) is NetworkState.ONLINE


def test_redirect_to_portal_requires_authentication():
    observation = HttpObservation(
        status_code=302,
        location="https://w.xidian.edu.cn/srun_portal",
        body="",
        elapsed_ms=3.0,
    )
    assert classify_http_observation(observation, frozenset({"w.xidian.edu.cn"})) is NetworkState.PORTAL_REQUIRED
```

- [ ] **Step 2: 运行指定测试确认失败**

运行：`python -m pytest tests/probe/test_classifier.py -q`
预期：模型或分类函数尚不存在而失败。

- [ ] **Step 3: 实现最小纯分类逻辑**

先实现 `204 -> ONLINE`、已知 Portal 主机的 `3xx -> PORTAL_REQUIRED`、正文含深澜登录特征的 `200 -> PORTAL_REQUIRED`，其他响应返回 `UNKNOWN`。URL 使用 `urllib.parse.urlparse` 分解，不用字符串包含替代结构化解析。

- [ ] **Step 4: 实现标准库网络适配器**

使用 `socket.getaddrinfo` 解析地址，使用 `socket.create_connection` 建立 TCP，使用 `urllib.request.Request` 和自定义 `HTTPRedirectHandler` 禁止自动跟随重定向。捕获 `socket.timeout`、`OSError`、`urllib.error.URLError`，转成观察结果而不是泄漏堆栈。

- [ ] **Step 5: 用本地 HTTP 服务器写集成测试**

使用 `http.server.ThreadingHTTPServer` 在测试线程启动三个路径：`/online` 返回 204、`/portal` 返回 302、`/login` 返回 200 深澜特征；验证请求器不跟随 302，并在测试结束关闭服务器。

- [ ] **Step 6: 更新学习和协议文档并提交**

创建 `docs/learning/02-dns.md`、`03-tcp.md`、`04-http.md` 和 `docs/protocol/connectivity-detection.md`，记录 `getaddrinfo`、`create_connection`、`Request`、重定向处理器和异常边界；运行全部探测测试；提交 `feat: 实现基础网络探测`。

## 任务 4：接入 `status` 命令

**Files:**
- Create: `src/xduwlan/probe/service.py`
- Modify: `src/xduwlan/cli.py`
- Modify: `tests/test_cli.py`
- Create: `tests/probe/test_service.py`
- Modify: `README.md`

**Interfaces:**
- `DefaultNetworkProbe(config: AppConfig).probe() -> NetworkProbeResult`。
- CLI `status` 接受 `--config PATH`、`--json` 和 `--debug`，默认输出中文摘要；`--json` 输出不含敏感字段的 JSON。

- [ ] **Step 1: 写失败测试**

```python
def test_status_online_returns_zero_and_prints_state(monkeypatch, capsys):
    monkeypatch.setattr("xduwlan.cli.build_network_probe", lambda config: FakeOnlineProbe())
    assert main(["status"]) == 0
    assert "已联网" in capsys.readouterr().out
```

- [ ] **Step 2: 运行测试确认失败**

运行：`python -m pytest tests/test_cli.py::test_status_online_returns_zero_and_prints_state -q`。
预期：命令尚未连接应用服务而失败。

- [ ] **Step 3: 实现应用服务和输出**

让 CLI 读取配置、创建探测器、调用 `probe()`，根据 `NetworkState` 映射中文说明和退出码；`--json` 使用 `json.dumps`，只输出状态、阶段成功与耗时。

- [ ] **Step 4: 增加状态分支测试**

覆盖 `ONLINE` 返回 0、`PORTAL_REQUIRED` 返回 4、网络不可用返回 5、配置错误返回 2。运行：`python -m pytest tests/test_cli.py tests/probe/test_service.py -q`。

- [ ] **Step 5: 完成 M1 文档和提交**

README 增加 `python -m xduwlan status` 示例；更新 M1 进度和交接；提交 `feat: 增加 status 命令`。

## 任务 5：实现深澜协议纯逻辑和响应解析

**Files:**
- Create: `src/xduwlan/portal/models.py`
- Create: `src/xduwlan/portal/encoding.py`
- Create: `src/xduwlan/portal/parser.py`
- Create: `tests/portal/test_encoding.py`
- Create: `tests/portal/test_parser.py`
- Create: `tests/fixtures/srun_vectors.json`
- Modify: `docs/protocol/srun-authentication.md`
- Create: `docs/learning/05-cryptographic-fields.md`

**Interfaces:**
- `parse_challenge_response(text: str) -> Challenge`。
- `hmac_md5_hex(password: str, challenge: str) -> str`。
- `xencode(message: str, key: str) -> str`。
- `build_info(username: str, password: str, challenge: Challenge, config: PortalConfig) -> str`。
- `build_checksum(parameters: LoginParameters) -> str`。
- `parse_portal_response(text: str) -> AuthenticationResult`。

- [ ] **Step 1: 写固定向量失败测试**

测试从 `tests/fixtures/srun_vectors.json` 读取虚构用户名、密码、challenge、客户端 IP 和期望输出；分别断言 HMAC、`info` 和 checksum。禁止把真实请求值放入 fixture。

- [ ] **Step 2: 运行测试确认失败**

运行：`python -m pytest tests/portal -q`。
预期：编码器和解析器尚不存在而失败。

- [ ] **Step 3: 实现纯函数**

按已验证的 Portal 脚本顺序实现 URL-safe 参数编码、HMAC-MD5、深澜 `xencode` 变体和 checksum；函数只接受显式参数，不读取配置文件、凭据库或网络。

- [ ] **Step 4: 实现 JSONP/JSON 响应解析**

解析成功、已在线、密码错误、认证间隔过短、服务器拒绝和未知响应；无法解析的正文抛出 `ProtocolError`，不把原始正文写入异常消息。

- [ ] **Step 5: 运行向量和性质测试**

运行：`python -m pytest tests/portal -q`。额外验证同一输入纯函数输出稳定、空 challenge 和非法编码会明确失败。

- [ ] **Step 6: 更新协议和学习文档并提交**

记录每个字段的证据类型（已观察、已验证或推断），说明 `hashlib`、`hmac`、`base64`、`urllib.parse.urlencode` 的检索入口；提交 `feat: 实现深澜协议编码与解析`。

## 任务 6：接入凭据、安全配置和 Portal 登录

**Files:**
- Create: `src/xduwlan/credentials/store.py`
- Create: `src/xduwlan/credentials/keyring_store.py`
- Create: `src/xduwlan/portal/client.py`
- Modify: `src/xduwlan/config.py`
- Modify: `src/xduwlan/cli.py`
- Create: `tests/credentials/test_store.py`
- Create: `tests/portal/test_client.py`
- Create: `docs/learning/06-credentials-and-http-client.md`

**Interfaces:**
- `MemoryCredentialStore`：仅测试使用，内存中保存账号到密码的映射。
- `KeyringCredentialStore(service_name: str)`：调用 `keyring.set_password/get_password/delete_password`。
- `PortalClient.authenticate(username: str, password: str) -> AuthenticationResult`。
- `configure` 交互输入账号和密码，密码通过 `getpass.getpass` 获取。

- [ ] **Step 1: 写凭据适配器失败测试**

断言内存实现能保存、读取、删除；通过 `unittest.mock` 断言生产实现只调用 `keyring`，不写文件。

- [ ] **Step 2: 运行测试确认失败**

运行：`python -m pytest tests/credentials -q`。
预期：凭据模块尚不存在而失败。

- [ ] **Step 3: 实现凭据存储和 `configure`**

账号允许作为服务内的用户名标识；密码只传递给 `set_password`，不写入配置对象或日志。配置文件只写非敏感设置。系统凭据后端不可用时抛出 `CredentialError` 并提示用户，不回退到明文。

- [ ] **Step 4: 写 Portal 客户端失败测试**

使用 `httpx.MockTransport` 模拟 challenge 响应和登录响应，断言请求顺序、参数存在性和错误分类；断言日志记录不包含密码、challenge 或完整 URL。

- [ ] **Step 5: 实现 Portal HTTP 客户端**

用 `httpx.Client` 管理超时和连接复用；先请求 challenge，再调用纯编码函数构造参数，发送认证请求，交给响应解析器；发生超时转换为 `NETWORK_ERROR`，服务器字段错误转换为对应不可重试状态。

- [ ] **Step 6: 接入 `login` 和安全文档**

`login` 先调用探测器；`ONLINE` 返回 `ALREADY_ONLINE`，不是 `PORTAL_REQUIRED` 时不读取密码；认证成功后再次探测。运行 `python -m pytest tests/credentials tests/portal -q`，更新 M2、`docs/security.md` 和交接文档；提交 `feat: 增加凭据管理与 Portal 登录`。

## 任务 7：实现前台 `watch` 状态机

**Files:**
- Create: `src/xduwlan/watcher/policy.py`
- Create: `src/xduwlan/watcher/service.py`
- Modify: `src/xduwlan/cli.py`
- Create: `tests/watcher/test_state_machine.py`
- Create: `docs/learning/07-state-machine-and-retry.md`

**Interfaces:**
- `RetryPolicy.next_delay(failure_count: int, random_source: Callable[[], float]) -> float`。
- `WatchService.run(stop_event: threading.Event) -> None`。
- `Sleeper.wait(stop_event: threading.Event, seconds: float) -> bool`，返回是否因停止事件提前结束。

- [ ] **Step 1: 写状态转换失败测试**

使用 FakeProbe、FakePortalClient、FakeSleeper 和 `threading.Event`；验证在线时等待正常间隔、Portal 时认证并验证、临时错误退避、凭据错误停止、停止事件结束循环。

- [ ] **Step 2: 运行测试确认失败**

运行：`python -m pytest tests/watcher/test_state_machine.py -q`。
预期：服务和策略尚不存在而失败。

- [ ] **Step 3: 实现退避策略**

基础延迟序列固定为 2、4、8、16、30、60 秒，上限 60 秒；抖动范围使用可注入随机源，测试传入固定值；成功认证或重新进入在线状态时失败计数归零。

- [ ] **Step 4: 实现状态机**

按 `CHECKING`、`HEALTHY`、`AUTHENTICATING`、`VERIFYING`、`BACKING_OFF`、`STOPPED` 编排依赖；不在 watcher 内实现 Portal 加密或 HTTP 细节。

- [ ] **Step 5: 接入 `watch` 命令并测试 Ctrl+C**

命令创建真实依赖并捕获 `KeyboardInterrupt`，输出“已停止”而不打印堆栈；测试使用 FakeSleeper，不真实等待一分钟。

- [ ] **Step 6: 更新文档并提交**

记录 `threading.Event.wait`、`KeyboardInterrupt`、指数退避和 jitter；完成 M3 验收测试；提交 `feat: 增加前台自动重连状态机`。

## 任务 8：实现自服务 HTML 解析和会话登录

**Files:**
- Create: `src/xduwlan/monitor/models.py`
- Create: `src/xduwlan/monitor/parser.py`
- Create: `src/xduwlan/monitor/client.py`
- Create: `src/xduwlan/monitor/session_store.py`
- Create: `tests/monitor/fixtures/home.html`
- Create: `tests/monitor/fixtures/login.html`
- Create: `tests/monitor/test_parser.py`
- Create: `tests/monitor/test_client.py`
- Create: `docs/learning/08-session-cookie-csrf.md`
- Create: `docs/protocol/self-service.md`

**Interfaces:**
- `parse_account_home(html: str, collected_at: datetime) -> AccountSnapshot`。
- `SelfServiceClient.begin_login() -> CaptchaChallenge`。
- `SelfServiceClient.complete_login(username: str, password: str, captcha_text: str) -> LoginResult`。
- `SelfServiceClient.get_snapshot() -> AccountSnapshot`。
- `SessionStore.save(session: SessionData) -> None`、`load() -> SessionData | None`、`delete() -> None`。

- [ ] **Step 1: 准备脱敏 fixture 和失败解析测试**

从页面结构制作虚构的 `home.html` 与 `login.html`，将姓名、账号、手机号、IP、MAC、CSRF 和验证码全部替换为占位测试值；断言首页能解析在线会话和套餐信息。

- [ ] **Step 2: 运行测试确认失败**

运行：`python -m pytest tests/monitor/test_parser.py -q`。
预期：解析器尚不存在而失败。

- [ ] **Step 3: 实现 HTML 解析器**

使用 `bs4.BeautifulSoup` 按表头和语义文本定位表格，不依赖易变的 CSS 类名；把流量文本转换为字节，把金额转换为 `Decimal`，缺失字段返回 `None`，关键表头缺失抛出 `ParseError`。

- [ ] **Step 4: 写客户端模拟测试**

用 `httpx.MockTransport` 模拟 `/login`、验证码图片、登录成功、登录失败和 `/home` 会话失效；验证客户端保留 Cookie、提交 CSRF、不会在日志中输出响应正文或会话值。

- [ ] **Step 5: 实现人工验证码流程**

`begin_login` 返回图片字节和 MIME 类型；CLI 再把图片写入受 `.gitignore` 保护的临时路径并提示用户输入。客户端不尝试 OCR、不猜验证码、不复用旧验证码。

- [ ] **Step 6: 实现会话存储并更新文档**

优先使用系统凭据库保存序列化会话；若当前后端不支持会话存储，明确返回错误而不写明文文件。记录 Cookie、CSRF、会话过期和登录状态码；提交 `feat: 增加自服务登录与数据解析`。

## 任务 9：接入 `account` 命令和数据展示

**Files:**
- Create: `src/xduwlan/formatting.py`
- Modify: `src/xduwlan/cli.py`
- Create: `tests/test_formatting.py`
- Modify: `tests/test_cli.py`
- Modify: `README.md`
- Modify: `docs/progress.md`
- Modify: `docs/session-handoff.md`

**Interfaces:**
- `format_bytes(value: int | None) -> str`。
- `format_account_snapshot(snapshot: AccountSnapshot) -> str`。
- `account` 支持 `--json` 和 `--config PATH`；首次无会话时执行验证码交互。

- [ ] **Step 1: 写格式化失败测试**

覆盖 0 字节、`None`、千字节/兆字节/吉字节转换、`Decimal("0.00")` 和多个在线设备展示；断言默认输出不包含 Cookie、CSRF 或密码。

- [ ] **Step 2: 实现展示层**

展示当前在线会话数量、IP（按规则脱敏）、上线时间、流量、产品名称、套餐总用量、余额和结算日期；JSON 输出使用模型字段，不把原始 HTML 透传。

- [ ] **Step 3: 接入 `account` 应用流程**

先尝试已有会话，失效时调用验证码流程；认证成功后保存会话并获取首页。捕获 `CredentialError`、`ParseError` 和网络错误，分别返回明确中文建议和退出码。

- [ ] **Step 4: 运行 CLI 和监测测试**

运行：`python -m pytest tests/monitor tests/test_formatting.py tests/test_cli.py -q`；用 MockTransport 运行一次完整的 `account` 流程，不访问真实账号。

- [ ] **Step 5: 完成 M4 文档和提交**

README 增加 `account` 首次使用说明和验证码边界；更新 M4 进度和交接；提交 `feat: 增加 account 命令`。

## 任务 10：日志脱敏、全量验收和跨平台打包

**Files:**
- Create: `src/xduwlan/logging.py`
- Create: `tests/test_logging.py`
- Create: `requirements-dev.txt` 或更新 `pyproject.toml` 可选依赖组
- Create: `docs/development.md`
- Create: `docs/learning/09-packaging.md`
- Modify: `README.md`
- Modify: `docs/security.md`
- Modify: `docs/progress.md`
- Modify: `docs/session-handoff.md`

**Interfaces:**
- `redact_sensitive(text: str) -> str`。
- `configure_logging(level: str, debug: bool) -> None`。
- PyInstaller 构建入口为 `python -m PyInstaller --onefile --name xduwlan src/xduwlan/cli.py`，最终根据实际导入修正为可运行的包入口。

- [ ] **Step 1: 写脱敏失败测试**

输入包含密码、Cookie、CSRF、challenge、完整认证 URL、账号、MAC 和 IP 的日志文本，断言输出只保留 `[REDACTED]` 或规则化掩码；普通中文错误不能被清空。

- [ ] **Step 2: 实现日志适配器**

统一通过 `logging` 输出；默认 INFO，`--debug` 才输出脱敏 DEBUG；禁止把异常原文中的请求 URL直接写入日志。

- [ ] **Step 3: 全量测试和敏感信息扫描**

运行：`python -m pytest -q`、`git diff --check`、`rg -n "password|Cookie|CSRF|challenge|Set-Cookie" --glob '!*.pyc' .`。扫描命中只能是安全规则、接口签名、测试占位值或文档说明，不得是真实凭据。

- [ ] **Step 4: 完成开发和打包文档**

记录 macOS 实测步骤、Windows/Linux 的自动测试步骤、PyInstaller 依赖、系统凭据库前置条件和常见错误；所有说明使用中文。

- [ ] **Step 5: 进行 macOS 真实验收**

手动执行 `status`、`configure`、`login`、`watch` 和 `account`。真实账号只在本地交互输入；验收记录只保存状态、错误类别和脱敏耗时，不保存请求、Cookie、验证码或页面原文。

- [ ] **Step 6: 完成 M5 并提交**

更新 README、进度、交接和安全文档；运行全量测试和 `python -m build`（若添加构建依赖）；提交 `docs: 完成跨平台开发与验收说明`。

## 计划自审

### 规格覆盖

- 项目目标、Python 首版和跨语言迁移：任务 1、2、10。
- `status` 和网络状态分类：任务 3、4。
- 深澜 Portal 认证、测试向量和错误分类：任务 5、6。
- 前台 `watch`、退避、停止和状态机：任务 7。
- `account`、人工验证码、会话和 HTML 解析：任务 8、9。
- `keyring`、日志脱敏和安全边界：任务 6、8、10。
- 中文文档、进度和跨会话恢复：每个任务的文档步骤及任务 10。
- 跨平台测试和打包：任务 10。

### 一致性检查

- 任务 2 先定义 `NetworkProbeResult`、`AuthenticationResult` 和账户模型；后续任务只消费这些类型。
- 任务 3 的 `HttpObservation`、`ResolvedAddress`、`TcpObservation` 需在 `probe/interfaces.py` 中统一定义，任务 4 只依赖 `NetworkProbe`。
- 任务 5 的纯编码函数由任务 6 的 `PortalClient` 调用，任务 7 只依赖 `PortalClient` 接口，不依赖编码实现。
- 任务 8 的 `AccountSnapshot` 与任务 2 的模型字段保持一致，任务 9 只依赖解析器和展示接口。
- 任务 10 的打包和真实验收在全部功能测试通过后进行，不改变核心接口。

### 完整性检查

本计划没有未定义步骤或模糊的后续承诺。每个任务均包含文件、接口、失败测试、实现动作、验证命令和提交点。
