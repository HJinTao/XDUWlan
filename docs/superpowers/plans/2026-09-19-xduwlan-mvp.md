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
- 自动化测试由指导者编写和维护；学习者聚焦生产代码实现，但必须理解测试意图、测试数据、断言和失败原因。每个小步骤按“指导者先写失败测试 → 学习者实现 → 指导者运行并解释结果”的节奏推进。
- 每个小步骤开始实现前，指导者必须说明具体文件、函数/类/Protocol、职责、输入输出、依赖方向、调用流程和贴近代码的伪代码，并与学习者对齐后再进入实现。
- 指导者只实现本步所需的结构骨架：文件、目录、空符号、类型签名、边界和占位异常；具体业务逻辑由学习者实现。除非学习者明确要求接管，不得代写任务实现。
- 实施采用纵向切片，顺序为 `status`、`configure`、`login`、`watch`、`account`；每个切片穿插所需模型、配置、服务、适配器、CLI、测试与文档，不提前完成未来切片的底层模块。
- 学习者按 Python 初学者对待；每一步先解释本步实际出现的语法，再由学习者实现一个数分钟内可完成的小单元。
- 学习者同时按计算机网络初学者对待；首次出现网络概念时，先解释它解决的问题、通信参与方、网络层次、输入输出、正常数据流和当前相关失败，再映射到具体 API、项目符号与测试。概念模型、操作系统或库接口、本项目抽象应分别说明，知识只随当前小步渐进展开。
- 未来切片的空骨架可保留作结构地图，但对应逻辑和测试延后；常规测试集合不得长期保留与当前切片无关的预期失败。
- 代码注释和 docstring 使用中文；代码标识符、命令、协议字段、库名和 API 名称保留原文。
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
- `tests/portal/test_client.py`
- `tests/credentials/test_store.py`
- `tests/watcher/test_state_machine.py`
- `tests/monitor/test_parser.py`
- `tests/monitor/test_client.py`
- `tests/monitor/fixtures/home.html`
- `tests/monitor/fixtures/login.html`
- `tests/test_formatting.py`
- `tests/test_logging.py`
- `tests/test_cli.py`

### 将更新的文档

- `docs/learning/01-models-and-config.md` 至 `docs/learning/09-packaging.md`：按纵向切片顺序记录原理、Python 语法、API 检索问题、实验和复盘。
- `docs/protocol/connectivity-detection.md`、`srun-authentication.md`、`self-service.md`：只记录脱敏且标记证据类型的协议事实。
- `docs/progress.md`、`docs/session-handoff.md`：每个任务完成时更新。
- `README.md`：在命令可用后补充安装和使用示例。

## 纵向切片顺序

1. **切片一 `status`（任务 2 至 4）**：只实现网络探测模型、探测所需配置、DNS/TCP/HTTP 适配器和 `status` CLI，完成后用户可以看到真实或本地模拟的网络状态。
2. **切片二 `configure` 与 `login`（任务 5 至 6）**：在切片开始时再实现认证模型、凭据错误和协议错误；先让 `configure` 可保存凭据，再贯通 Portal 纯逻辑、HTTP 客户端和 `login`。
3. **切片三 `watch`（任务 7）**：复用已通过测试的探测和登录，不在状态机中重写网络或协议逻辑。
4. **切片四 `account`（任务 8 至 9）**：在切片开始时再实现账户模型，随后贯通 HTML 解析、人工验证码、会话和展示。
5. **切片五交付（任务 10）**：统一完成日志脱敏、跨平台测试、打包和真实验收。

每个切片都重复“语法与原理讲解 → 指导者写当前失败测试和骨架 → 学习者实现 → 指导者审查与 GREEN 验证 → CLI 运行 → 文档与提交”。

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

## 任务 2：定义 `status` 所需的网络模型、错误和配置

**Files:**
- Create: `src/xduwlan/models.py`
- Create: `src/xduwlan/errors.py`
- Create: `src/xduwlan/config.py`
- Create: `tests/test_models.py`
- Create: `tests/test_config.py`
- Modify: `docs/architecture.md`

**Interfaces:**
- Produces `NetworkState`、`ProbeStage`、`ProbeObservation`、`NetworkProbeResult`。
- Produces `ConfigurationError`；其他异常在使用它们的切片中再进入验收范围。
- Produces `AppConfig.load(path: Path) -> AppConfig` 和 `AppConfig.defaults() -> AppConfig`。
- 配置只包含 `portal_url`、`probe_url`、`probe_interval_seconds`、`request_timeout_seconds`、`operator_suffix` 和 `log_level`。
- `AuthenticationState`、`AuthenticationResult`、`OnlineSession`、`ProductUsage`、`AccountSnapshot` 即使已有空骨架，本任务也不实现、不验收。

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
首次创建前预期因模块缺失而导入失败；当前仓库已有空骨架，预期改为枚举成员为空或 `NotImplementedError` 导致的行为失败。

- [ ] **Step 3: 学习者写当前切片的最小实现**

使用 `Enum` 和 `@dataclass(frozen=True)` 定义模型；使用 `tomllib.loads` 读取 TOML，缺少字段时使用明确默认值，数值字段校验为正数，非法值抛出 `ConfigurationError`。

- [ ] **Step 4: 增加边界测试并运行**

测试空 TOML、未知字段忽略、非正周期与超时拒绝，以及网络探测结果使用不可变 `tuple` 观察集合。认证和账户模型测试从当前测试集合移除，到对应切片再按 TDD 写入。运行：`python -m pytest tests/test_models.py tests/test_config.py -q`。

- [ ] **Step 5: 更新中文学习记录并提交**

创建 `docs/learning/01-models-and-config.md`，只解释本切片用到的 `Enum`、`dataclass(frozen=True)`、`tuple` 和 `tomllib`；`Decimal` 留到 `account` 切片。更新架构、进度和交接文档；提交 `feat: 定义 status 模型与配置`。

## 任务 3：实现 DNS、TCP、HTTP 的基础探测

本任务的每个小步都先完成网络原理讲解再写测试：DNS 解释主机名、解析器、IP 地址及地址候选；TCP 解释端点、连接建立、超时及其与 DNS 结果的关系；HTTP 解释请求与响应、状态码、重定向和 Captive Portal。每次讲解都要把网络数据流映射到本任务的类型、函数、参数、返回值和测试替身，不把标准库调用当作黑盒。

**Files:**
- Create: `src/xduwlan/probe/__init__.py`
- Create: `src/xduwlan/probe/interfaces.py`
- Create: `src/xduwlan/probe/dns.py`
- Create: `src/xduwlan/probe/tcp.py`
- Create: `src/xduwlan/probe/http.py`
- Create: `src/xduwlan/probe/classifier.py`
- Create: `tests/probe/test_dns.py`
- Create: `tests/probe/test_tcp.py`
- Create: `tests/probe/test_http.py`
- Create: `tests/probe/test_classifier.py`
- Create: `tests/probe/test_integration_server.py`

**Interfaces:**
- `DnsResolver.resolve(host: str, port: int) -> tuple[ResolvedAddress, ...]`。
- `TcpConnector.connect(address: ResolvedAddress, timeout: float) -> TcpObservation`。
- `HttpConnectivityChecker.request(url: str, timeout: float) -> HttpObservation`。
- `NetworkProbe.probe() -> NetworkProbeResult`。
- `classify_http_observation(observation: HttpObservation, portal_hosts: frozenset[str]) -> NetworkState`。

- [x] **Step 1: 对齐 DNS 文件、符号和调用关系，创建第一个失败测试与骨架**

先建立 `URL → 主机名 → DNS 地址候选 → IP 地址与端口 → TCP → HTTP` 的完整路径，再把当前小步收窄到：

```text
SystemDnsResolver.resolve(host, port)
  → socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
  → 逐条转换系统地址记录
  → tuple[ResolvedAddress, ...]
```

指导者创建 `ResolvedAddress`、`DnsResolver`、`SystemDnsResolver.resolve()` 骨架和 `tests/probe/test_dns.py`；测试使用 `monkeypatch` 替换 `socket.getaddrinfo`，不访问真实网络。

- [x] **Step 2: 运行 DNS 指定测试确认失败**

运行：`python -m pytest tests/probe/test_dns.py -q`
预期且已验证：`SystemDnsResolver.resolve()` 抛出 `NotImplementedError`，1 个测试失败，既有 25 个回归测试仍通过。

- [x] **Step 3: 学习者实现最小 DNS 地址转换逻辑**

调用 `socket.getaddrinfo`，只请求 `SOCK_STREAM` 地址；从每条系统记录中读取 `family` 和 `sockaddr`，构造 `ResolvedAddress(host, port, family)`，最终返回不可变 `tuple`。本小步暂不加入真实网络实验、失败分类、去重或额外边界。

- [x] **Step 4: 完成 TCP 小步**

DNS 实现已经审查并通过目标测试。TCP 端点、连接建立、超时和 DNS 多候选地址之间的关系已经讲解；`TcpObservation`、`TcpConnector` 和 `SystemTcpConnector` 已建立。成功连接先完成 RED → GREEN；随后根据学习者希望适当增大实现单元的反馈，把 `socket.timeout` 与其他 `OSError` 合并为同一参数化测试轮次。学习者一次完成两类失败观察，最终 TCP 3 个用例全部 GREEN，且底层错误正文未泄漏。

- [x] **Step 5: 完成 HTTP 请求与响应观察**

HTTP 请求、响应、状态码、Header、正文、重定向和 Captive Portal 已完成讲解。`HttpObservation`、`HttpConnectivityChecker`、`NoRedirectHandler` 和 `SystemHttpConnectivityChecker` 已实现。测试覆盖默认禁止重定向 opener、204、按字符集解码与 64 KiB 上限、原始 302 `HTTPError`、`socket.timeout`、`URLError` 和一般 `OSError`；8 个目标测试已完成 RED → GREEN，底层错误正文未泄漏。

- [x] **Step 6: 完成纯分类逻辑**

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

分类器 8 个目标测试已完成 RED → GREEN。实现覆盖 `204 -> ONLINE`、已知 Portal 主机的 `3xx -> PORTAL_REQUIRED`、正文含大小写不同深澜特征的 `200 -> PORTAL_REQUIRED`，其他响应返回 `UNKNOWN`。URL 使用 `urllib.parse.urlparse` 分解并精确匹配 hostname，查询参数伪装与畸形 `Location` 均安全回退。

- [x] **Step 7: 用本地 HTTP 服务器写集成测试**

使用 `http.server.ThreadingHTTPServer` 在 loopback 临时端口启动三个路径：`/online` 返回 204、`/portal` 返回 302、`/login` 返回 200 深澜特征。3 个集成测试已验证真实 `urllib` 与分类器协作、请求器不跟随 302，以及服务循环、监听 socket 和线程在测试后关闭。

- [x] **Step 8: 更新学习和协议文档**

已创建 `docs/learning/02-dns.md`、`03-tcp.md`、`04-http.md` 和 `docs/protocol/connectivity-detection.md`，记录 `getaddrinfo`、`create_connection`、`Request`、重定向处理器、分类规则、异常边界与待实测假设。任务 3 的 23 个探测测试和全仓库 48 个测试全部通过。

- [x] **Step 9: 提交任务 3**

生产代码与测试已提交为 `8f1af1b feat: 实现基础网络探测`；学习、协议、进度和架构文档由随后的文档提交记录。

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

## 任务 5：贯通 `configure` 凭据保存切片

**Files:**
- Create: `src/xduwlan/credentials/store.py`
- Create: `src/xduwlan/credentials/keyring_store.py`
- Create: `tests/credentials/test_store.py`
- Modify: `src/xduwlan/errors.py`
- Modify: `src/xduwlan/config.py`
- Modify: `src/xduwlan/cli.py`
- Modify: `tests/test_cli.py`
- Modify: `pyproject.toml`
- Create: `docs/learning/05-credentials.md`

**Interfaces:**
- Produces `CredentialError`，从本任务开始进入实现和测试范围。
- Produces `CredentialStore` Protocol：`save(account: str, password: str) -> None`、`load(account: str) -> str | None`、`delete(account: str) -> None`。
- Produces `MemoryCredentialStore` 供测试使用。
- Produces `KeyringCredentialStore(service_name: str)`，生产环境调用系统凭据库。
- `configure` 使用 `input` 获取账号、使用 `getpass.getpass` 获取密码，不把密码写入 `AppConfig`。

- [ ] **Step 1: 讲解 Protocol、凭据边界和失败测试**

指导者先解释接口与实现的区别、为什么测试使用内存实现、为什么密码不能进入 TOML；再编写保存、读取、删除和缺失返回 `None` 的测试。

- [ ] **Step 2: 运行内存存储测试确认失败**

运行：`python -m pytest tests/credentials/test_store.py -q`。
预期：凭据模块或 `MemoryCredentialStore` 尚不存在而失败。

- [ ] **Step 3: 学习者实现 Protocol 和内存存储**

指导者只提供类和方法签名；学习者用 `dict[str, str]` 实现保存、读取和删除。运行同一测试，预期内存存储用例通过。

- [ ] **Step 4: 指导者增加 keyring 边界测试，学习者实现适配器**

测试替换 `keyring.set_password/get_password/delete_password`，验证参数和异常转换；学习者实现最小调用逻辑，后端异常使用 `raise CredentialError(...) from exc` 保留异常链，禁止明文文件回退。

- [ ] **Step 5: 接入并运行 `configure`**

指导者在 `tests/test_cli.py` 增加虚构账号和输入函数测试；学习者让 `configure` 收集账号、密码和非敏感设置，调用 `CredentialStore.save`，成功返回 0，凭据后端失败返回 3。运行：`python -m pytest tests/credentials tests/test_cli.py -q`。

- [ ] **Step 6: 更新文档并提交**

记录 `typing.Protocol`、`getpass.getpass` 和 keyring 的官方 API 检索问题；更新安全、进度和交接文档；提交 `feat: 增加安全配置与凭据保存`。

## 任务 6：贯通 `login` Portal 认证切片

**Files:**
- Modify: `src/xduwlan/models.py`
- Modify: `src/xduwlan/errors.py`
- Modify: `tests/test_models.py`
- Create: `src/xduwlan/portal/models.py`
- Create: `src/xduwlan/portal/encoding.py`
- Create: `src/xduwlan/portal/parser.py`
- Create: `src/xduwlan/portal/client.py`
- Create: `tests/portal/test_encoding.py`
- Create: `tests/portal/test_parser.py`
- Create: `tests/portal/test_client.py`
- Create: `tests/fixtures/srun_vectors.json`
- Modify: `src/xduwlan/cli.py`
- Modify: `tests/test_cli.py`
- Create: `docs/protocol/srun-authentication.md`
- Create: `docs/learning/06-portal-authentication.md`

**Interfaces:**
- Produces `AuthenticationState`、`AuthenticationResult`、`NetworkOperationError` 和 `ProtocolError`，这些符号从本任务开始进入实现和测试范围。
- `parse_challenge_response(text: str) -> Challenge`。
- `hmac_md5_hex(password: str, challenge: str) -> str`。
- `xencode(message: str, key: str) -> str`。
- `build_info(username: str, password: str, challenge: Challenge, config: PortalConfig) -> str`。
- `build_checksum(parameters: LoginParameters) -> str`。
- `parse_portal_response(text: str) -> AuthenticationResult`。
- `PortalClient.authenticate(username: str, password: str) -> AuthenticationResult`。

- [ ] **Step 1: 定义认证结果的当前测试和模型**

指导者把认证状态稳定值、不可变结果和 `retryable` 行为测试加入 `tests/test_models.py`；学习者实现 `AuthenticationState` 与 `AuthenticationResult`，运行对应测试直到 GREEN。

- [ ] **Step 2: 写脱敏固定向量和解析失败测试**

`tests/fixtures/srun_vectors.json` 只使用虚构用户名、密码、challenge 和客户端 IP；测试分别断言 HMAC、`info`、checksum，以及成功、密码错误、限流和未知响应分类。

- [ ] **Step 3: 运行 Portal 纯逻辑测试确认失败**

运行：`python -m pytest tests/portal/test_encoding.py tests/portal/test_parser.py -q`。
预期：编码器和解析器尚不存在而失败。

- [ ] **Step 4: 学习者实现纯函数和响应解析**

按脱敏证据实现 URL-safe 参数编码、HMAC-MD5、深澜 `xencode`、checksum 和 JSONP/JSON 解析；纯函数不读取配置、凭据或网络。非法响应抛出 `ProtocolError`，异常消息不得包含原始正文。

- [ ] **Step 5: 指导者写客户端测试，学习者实现 PortalClient**

使用 `httpx.MockTransport` 模拟 challenge 和登录响应，断言请求顺序、必要参数和错误分类；学习者用 `httpx.Client` 完成请求编排，超时转换为 `NETWORK_ERROR`，日志不包含密码、challenge 或完整 URL。

- [ ] **Step 6: 接入并运行 `login`**

`login` 先调用探测器；`ONLINE` 返回 `ALREADY_ONLINE`，不是 `PORTAL_REQUIRED` 时不读取密码；需要认证时从任务 5 的 `CredentialStore` 读取密码，认证成功后再次探测。运行：`python -m pytest tests/credentials tests/portal tests/test_cli.py -q`。

- [ ] **Step 7: 更新协议、学习和安全文档并提交**

按已观察、已验证或推断记录协议字段；记录 `hashlib`、`hmac`、`base64`、`urllib.parse.urlencode` 和 `httpx.MockTransport` 的检索问题；更新 M2 和交接文档；提交 `feat: 增加 Portal 登录`。

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
- Modify: `src/xduwlan/models.py`
- Modify: `src/xduwlan/errors.py`
- Modify: `tests/test_models.py`

**Interfaces:**
- Produces `OnlineSession`、`ProductUsage`、`AccountSnapshot` 和 `ParseError`，这些符号从本切片开始进入测试与实现范围。
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
- `configure`、keyring 和凭据安全：任务 5。
- 深澜 Portal 认证、测试向量和错误分类：任务 6。
- 前台 `watch`、退避、停止和状态机：任务 7。
- `account`、人工验证码、会话和 HTML 解析：任务 8、9。
- `keyring`、日志脱敏和安全边界：任务 5、8、10。
- 中文文档、进度和跨会话恢复：每个任务的文档步骤及任务 10。
- 跨平台测试和打包：任务 10。

### 一致性检查

- 任务 2 只定义 `status` 使用的 `NetworkProbeResult` 等网络模型；任务 6 才定义认证模型，任务 8 才定义账户模型。
- 任务 3 的 `HttpObservation`、`ResolvedAddress`、`TcpObservation` 需在 `probe/interfaces.py` 中统一定义，任务 4 只依赖 `NetworkProbe`。
- 任务 5 的 `CredentialStore` 由任务 6 的登录服务复用；任务 6 的纯编码函数只由 `PortalClient` 调用，任务 7 只依赖 `PortalClient` 接口。
- 任务 8 在实现解析器前先定义 `AccountSnapshot` 等账户模型，任务 9 只依赖解析器和展示接口。
- 任务 10 的打包和真实验收在全部功能测试通过后进行，不改变核心接口。

### 完整性检查

本计划没有未定义步骤或模糊的后续承诺。每个任务均包含文件、接口、失败测试、实现动作、验证命令和提交点。
