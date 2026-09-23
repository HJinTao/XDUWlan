# `configure` 凭据存储边界 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立可测试的 `CredentialStore` 端口和基于 `keyring` 的生产适配器，让账号与密码作为一条安全记录保存和读取。

**Architecture:** 核心层用不可变 `Credentials` 和 `CredentialStore` `Protocol` 描述调用方需要的能力，不依赖 `keyring`。基础设施适配器用固定查询键把两项凭据编码为一个 JSON 字符串，通过一次系统凭据库调用完成保存，并把后端故障或损坏记录转换为安全的项目异常。

**Tech Stack:** Python 3.11+、`dataclasses`、`typing.Protocol`、标准库 `json`、`keyring>=25,<26`、pytest 8+

**Spec:** `docs/superpowers/specs/2026-09-23-credential-store-design.md`

## Global Constraints

- 指导者负责编写自动化测试、测试替身、目录与符号骨架、验证、审查和解释；学习者负责 JSON 编解码、状态分支和异常转换业务逻辑。
- 账号和密码都只进入系统凭据库，不进入 TOML、命令参数、日志、错误文本或明文回退文件。
- 固定 `service_name` 为 `XDUWlan`，固定内部记录名为 `campus-network-credentials`。
- 存储 JSON 只写出 `account` 和 `password`；读取允许额外字段，但要求顶层为对象且两个必需字段均为字符串。
- 未配置返回 `None`；读取失败、写入失败和记录损坏分别使用固定安全消息。
- 本子任务不接入 `configure` CLI、`getpass`、Portal 协议、删除、多账号或真实凭据库。
- 自动化测试只使用虚构标记，并替换全部 `keyring` 系统调用。
- RED 与对应 GREEN 属于同一职责阶段，不为二者分别提交。

## File Structure

- Create `src/xduwlan/credentials.py`：不可变凭据模型与存储端口。
- Create `src/xduwlan/keyring_store.py`：JSON 记录格式与 `keyring` 生产适配器。
- Modify `src/xduwlan/errors.py`：增加凭据存储项目异常。
- Modify `pyproject.toml`：增加 `keyring` 运行时依赖。
- Create `tests/__init__.py`：让共享测试替身使用稳定包路径。
- Create `tests/fakes.py`：测试用内存凭据存储。
- Create `tests/test_credentials.py`：保护对象表示和内存替身语义。
- Create `tests/test_keyring_store.py`：保护单记录写入、读取、缺失状态、损坏记录和异常脱敏。
- Modify `docs/architecture.md`：记录已实现的凭据端口与适配器。
- Modify `docs/current.md`：记录 RED/GREEN、验证证据和下一责任人。
- Modify `docs/visualizations/xduwlan-architecture.html`：更新 `configure` 调用链完成状态。
- Modify `docs/visualizations/xduwlan-file-architecture.html`：加入新文件、符号、依赖和测试职责。

---

### Task 1: 指导者建立完整 RED 与符号骨架

**Files:**
- Create: `src/xduwlan/credentials.py`
- Create: `src/xduwlan/keyring_store.py`
- Modify: `src/xduwlan/errors.py`
- Modify: `pyproject.toml`
- Create: `tests/__init__.py`
- Create: `tests/fakes.py`
- Create: `tests/test_credentials.py`
- Create: `tests/test_keyring_store.py`
- Modify: `docs/current.md`

**Interfaces:**
- Consumes: `XDUWlanError`；`keyring.get_password()`、`keyring.set_password()` 和 `keyring.errors.KeyringError`。
- Produces: `Credentials(account: str, password: str)`、`CredentialStore.save(credentials) -> None`、`CredentialStore.load() -> Credentials | None`、`CredentialStoreError`、`KeyringCredentialStore` 和 `MemoryCredentialStore`。

- [ ] **Step 1: Add and install the runtime dependency**

将 `pyproject.toml` 的运行时依赖改为：

```toml
dependencies = ["keyring>=25,<26"]
```

运行：

```bash
conda run -n xduwlan python -m pip install -e '.[test]'
conda run -n xduwlan python -c "from importlib.metadata import version; print(version('keyring'))"
```

Expected: 输出 `25.x` 版本号，安装过程不访问系统凭据记录。

- [ ] **Step 2: Create importable production skeletons**

在 `src/xduwlan/errors.py` 增加：

```python
class CredentialStoreError(XDUWlanError):
    """系统凭据库不可用或其中的记录无效。"""
```

创建 `src/xduwlan/credentials.py`；先保留默认 `repr`，让安全表示测试准确失败：

```python
"""校园网凭据模型与存储端口。"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class Credentials:
    """保存一组校园网账号和密码。"""

    account: str
    password: str


class CredentialStore(Protocol):
    """声明调用方需要的凭据持久化能力。"""

    def save(self, credentials: Credentials) -> None:
        """保存或覆盖当前凭据。"""
        ...

    def load(self) -> Credentials | None:
        """读取当前凭据；尚未配置时返回 ``None``。"""
        ...
```

创建 `src/xduwlan/keyring_store.py`，只提供固定兼容键和待实现方法：

```python
"""通过 keyring 连接操作系统凭据库。"""

from __future__ import annotations

import keyring

from xduwlan.credentials import Credentials


_SERVICE_NAME = "XDUWlan"
_RECORD_NAME = "campus-network-credentials"


class KeyringCredentialStore:
    """把校园网凭据作为一条系统凭据记录保存。"""

    def save(self, credentials: Credentials) -> None:
        """保存或覆盖当前凭据。"""
        raise NotImplementedError

    def load(self) -> Credentials | None:
        """读取当前凭据；尚未配置时返回 ``None``。"""
        raise NotImplementedError
```

- [ ] **Step 3: Create the reusable in-memory test store**

创建空的 `tests/__init__.py`，再创建 `tests/fakes.py`：

```python
from xduwlan.credentials import Credentials


class MemoryCredentialStore:
    """只在测试进程内保存最近一组凭据。"""

    def __init__(self) -> None:
        self._credentials: Credentials | None = None

    def save(self, credentials: Credentials) -> None:
        self._credentials = credentials

    def load(self) -> Credentials | None:
        return self._credentials
```

- [ ] **Step 4: Write model and fake tests**

创建 `tests/test_credentials.py`：

```python
from tests.fakes import MemoryCredentialStore
from xduwlan.credentials import Credentials


def test_credentials_repr_hides_account_and_password():
    """对象表示不得泄漏账号或密码。"""
    account = "student-example"
    password = "password-example-only"

    representation = repr(Credentials(account=account, password=password))

    assert account not in representation
    assert password not in representation


def test_memory_credential_store_round_trip():
    """内存替身应表达未配置和覆盖保存语义。"""
    store = MemoryCredentialStore()
    credentials = Credentials(
        account="student-example",
        password="password-example-only",
    )

    assert store.load() is None
    store.save(credentials)
    assert store.load() == credentials
```

- [ ] **Step 5: Write the complete adapter tests**

创建 `tests/test_keyring_store.py`：

```python
import json

import pytest
from keyring.errors import KeyringError

from xduwlan.credentials import Credentials
from xduwlan.errors import CredentialStoreError
from xduwlan.keyring_store import KeyringCredentialStore


ACCOUNT = "student-example"
PASSWORD = "password-example-only"
SERVICE_NAME = "XDUWlan"
RECORD_NAME = "campus-network-credentials"


def test_save_writes_one_fixed_keyring_record(monkeypatch):
    """保存应通过一次调用写入固定键和完整 JSON 载荷。"""
    calls = []

    def fake_set_password(service_name, record_name, payload):
        calls.append((service_name, record_name, payload))

    monkeypatch.setattr(
        "xduwlan.keyring_store.keyring.set_password",
        fake_set_password,
    )
    store = KeyringCredentialStore()
    store.save(Credentials(account=ACCOUNT, password=PASSWORD))

    assert len(calls) == 1
    service_name, record_name, payload = calls[0]
    assert (service_name, record_name) == (SERVICE_NAME, RECORD_NAME)
    assert json.loads(payload) == {
        "account": ACCOUNT,
        "password": PASSWORD,
    }


def test_load_returns_credentials_from_valid_record(monkeypatch):
    """读取应恢复两个必需字段并忽略未来扩展字段。"""
    payload = json.dumps(
        {
            "account": ACCOUNT,
            "password": PASSWORD,
            "future": "ignored",
        }
    )
    calls = []

    def fake_get_password(service_name, record_name):
        calls.append((service_name, record_name))
        return payload

    monkeypatch.setattr(
        "xduwlan.keyring_store.keyring.get_password",
        fake_get_password,
    )
    result = KeyringCredentialStore().load()

    assert calls == [(SERVICE_NAME, RECORD_NAME)]
    assert result == Credentials(account=ACCOUNT, password=PASSWORD)


def test_load_returns_none_when_record_does_not_exist(monkeypatch):
    """缺少记录是正常的未配置状态。"""
    monkeypatch.setattr(
        "xduwlan.keyring_store.keyring.get_password",
        lambda service_name, record_name: None,
    )

    assert KeyringCredentialStore().load() is None


@pytest.mark.parametrize(
    ("operation", "expected_message"),
    [
        ("save", "系统凭据库写入失败"),
        ("load", "系统凭据库读取失败"),
    ],
)
def test_keyring_errors_are_converted_without_leaking_details(
    operation,
    expected_message,
    monkeypatch,
):
    """第三方后端错误应保留异常链，但公开固定安全消息。"""
    private_marker = "private-backend-marker"
    backend_error = KeyringError(private_marker)

    def fail(*args):
        raise backend_error

    function_name = "set_password" if operation == "save" else "get_password"
    monkeypatch.setattr(
        f"xduwlan.keyring_store.keyring.{function_name}",
        fail,
    )
    store = KeyringCredentialStore()

    with pytest.raises(CredentialStoreError) as caught:
        if operation == "save":
            store.save(Credentials(account=ACCOUNT, password=PASSWORD))
        else:
            store.load()

    assert str(caught.value) == expected_message
    assert private_marker not in str(caught.value)
    assert caught.value.__cause__ is backend_error


@pytest.mark.parametrize(
    "payload",
    [
        "private-record-marker",
        json.dumps(["private-record-marker"]),
        json.dumps({"password": "private-record-marker"}),
        json.dumps({"account": 1, "password": "private-record-marker"}),
        json.dumps({"account": "private-record-marker", "password": None}),
    ],
)
def test_load_rejects_malformed_records_without_leaking_payload(
    payload,
    monkeypatch,
):
    """损坏记录的内容不得出现在项目错误文本中。"""
    monkeypatch.setattr(
        "xduwlan.keyring_store.keyring.get_password",
        lambda service_name, record_name: payload,
    )

    with pytest.raises(CredentialStoreError) as caught:
        KeyringCredentialStore().load()

    assert str(caught.value) == "系统凭据记录损坏"
    assert "private-record-marker" not in str(caught.value)
    assert caught.value.__cause__ is not None
```

- [ ] **Step 6: Run the focused suite and record RED**

Run:

```bash
conda run -n xduwlan python -m pytest -q \
  tests/test_credentials.py tests/test_keyring_store.py
```

Expected: `11 failed, 1 passed`。失败来自默认 `repr` 和 `NotImplementedError`；不得出现导入错误、依赖缺失、系统凭据库弹窗或真实后端访问。

- [ ] **Step 7: Update work memory and hand implementation to the learner**

在 `docs/current.md` 记录：

```markdown
- 凭据存储子任务已经建立完整 RED：目标测试 `11 failed, 1 passed`。
- 失败覆盖安全对象表示、单记录保存、读取、未配置状态、后端异常转换和损坏记录转换。
- 下一责任人是学习者；一次完成 `Credentials` 安全表示和 `KeyringCredentialStore` 全部业务分支到 GREEN。
```

不要在此处提交；RED、学习者实现和 GREEN 共同构成一个可独立说明的功能阶段。

---

### Task 2: 学习者实现凭据存储行为并达到 GREEN

**Files:**
- Modify: `src/xduwlan/credentials.py`
- Modify: `src/xduwlan/keyring_store.py`
- Review: `tests/test_credentials.py`
- Review: `tests/test_keyring_store.py`

**Interfaces:**
- Consumes: Task 1 的完整失败测试、`CredentialStoreError`、固定 service 和记录名。
- Produces: 不泄漏字段的 `Credentials`；可保存、读取、识别未配置并安全转换错误的 `KeyringCredentialStore`。

- [ ] **Step 1: Explain the new concepts before coding**

指导者只讲本轮需要的三个知识点：

1. `dataclasses.field(repr=False)` 控制对象的调试表示，不改变字段读取或相等比较；账号是个人信息，密码是敏感凭据，所以两个字段都隐藏。
2. `keyring` 实际接口只能保存字符串；项目把一组凭据编码为 JSON，是为了通过一次写入得到项目层面的原子更新。
3. 适配器是安全边界：第三方 `KeyringError` 和不可信存储内容必须变成稳定项目错误，但编程错误不应被裸 `except` 吞掉。

- [ ] **Step 2: Implement the safe credential representation**

学习者在 `credentials.py` 中从 `dataclasses` 导入 `field`，并让两个字段使用 `field(repr=False)`。保持 `frozen=True`、字段名称、类型和 `Protocol` 签名不变。

目标结构：

```text
Credentials
├── account: str，参与比较，不进入 repr
└── password: str，参与比较，不进入 repr
```

- [ ] **Step 3: Implement all adapter branches as one responsibility**

学习者在 `keyring_store.py` 中导入 `json`、`keyring`、`KeyringError` 和 `CredentialStoreError`，并按以下伪代码一次完成成功路径与相关失败路径：

```text
save(credentials):
    payload = JSON({account: credentials.account, password: credentials.password})
    try:
        keyring.set_password(SERVICE, RECORD, payload)
    except KeyringError as cause:
        raise CredentialStoreError("系统凭据库写入失败") from cause

load():
    try:
        payload = keyring.get_password(SERVICE, RECORD)
    except KeyringError as cause:
        raise CredentialStoreError("系统凭据库读取失败") from cause

    if payload is None:
        return None

    try:
        data = JSON_DECODE(payload)
        if not isinstance(data, dict): raise TypeError
        account = data["account"]
        password = data["password"]
        if not isinstance(account, str) or not isinstance(password, str):
            raise TypeError
    except (json.JSONDecodeError, KeyError, TypeError) as cause:
        raise CredentialStoreError("系统凭据记录损坏") from cause

    return Credentials(account=account, password=password)
```

约束：保存 JSON 不得加入真实值或日志；读取允许额外键；异常消息不得拼接 `cause` 或 `payload`；不得捕获所有 `Exception`。

- [ ] **Step 4: Run the focused suite and reach GREEN**

Run:

```bash
conda run -n xduwlan python -m pytest -q \
  tests/test_credentials.py tests/test_keyring_store.py
```

Expected: `12 passed`。

若失败，指导者只审查实际失败对应的行为；涉及控制流或数据的修正继续由学习者完成。

- [ ] **Step 5: Run affected and full regression checks**

Run:

```bash
conda run -n xduwlan python -m pytest -q
git diff --check
```

Expected: 完整测试通过；总数应为原基线 66 加本轮 12，即 `78 passed`；`git diff --check` 无输出。

- [ ] **Step 6: Review the security-sensitive diff**

Run:

```bash
git diff -- src/xduwlan/credentials.py src/xduwlan/keyring_store.py \
  src/xduwlan/errors.py tests/test_credentials.py \
  tests/test_keyring_store.py tests/fakes.py pyproject.toml
rg -n "student-example|password-example-only|private-(backend|record)-marker" \
  src docs --glob '!docs/superpowers/**'
```

Expected: 虚构标记只存在于测试文件，不出现在生产代码、普通文档或输出逻辑；差异中没有打印、日志、TOML 回退或真实后端调用。

- [ ] **Step 7: Commit the tested feature stage**

```bash
git add pyproject.toml src/xduwlan/credentials.py \
  src/xduwlan/keyring_store.py src/xduwlan/errors.py \
  tests/__init__.py tests/fakes.py tests/test_credentials.py \
  tests/test_keyring_store.py
git diff --cached --check
git commit -m "feat: 添加系统凭据存储边界"
```

---

### Task 3: 指导者同步架构、工作记忆与可视化

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/current.md`
- Modify: `docs/superpowers/specs/2026-09-23-credential-store-design.md`
- Modify: `docs/visualizations/xduwlan-architecture.html`
- Modify: `docs/visualizations/xduwlan-file-architecture.html`

**Interfaces:**
- Consumes: Task 2 已验证的源码、测试结果和提交。
- Produces: 与仓库结构、主要符号、调用关系、完成状态和下一子任务一致的唯一工作记忆与可视化。

- [ ] **Step 1: Update long-lived architecture facts**

在 `docs/architecture.md` 的当前文件树加入 `credentials.py` 和 `keyring_store.py`，并加入职责说明：

```text
credentials.py：不可变凭据模型与 CredentialStore 端口；不依赖 keyring。
keyring_store.py：把账号和密码作为一条 JSON 记录连接系统凭据库。
errors.py：除配置错误外，提供安全的凭据存储错误。
```

增加已实现调用链：

```text
未来的 configure/login 服务
  → CredentialStore.save()/load()
  ← KeyringCredentialStore
    → keyring.set_password()/get_password()
      → 操作系统凭据库
```

在计划边界中把 `configure` 描述更新为“凭据端口与 `keyring` 适配器已实现，交互输入待实现”。不要把整个 `configure` 切片标成完成。

- [ ] **Step 2: Compress work memory to verified facts**

在 `docs/current.md`：

- 把凭据存储边界加入“已完成能力”；
- 记录目标测试 `12 passed` 和完整回归 `78 passed`；
- 把下一子任务改为 `configure` 交互输入与应用服务；
- 下一责任人改为指导者先对齐该新子任务；
- 保留设计规格和实施计划链接，移除已结束的逐轮 RED 叙述。

- [ ] **Step 3: Update both HTML visualizations**

在 `docs/visualizations/xduwlan-architecture.html` 的 `configure` 数据中：

- 状态改为“进行中 · 凭据存储已实现”；
- 明确 `Credentials`、`CredentialStore`、`KeyringCredentialStore` 已存在；
- 明确 CLI 输入与应用服务仍待下一子任务；
- 保留“无明文回退”和操作系统凭据库边界。

在 `docs/visualizations/xduwlan-file-architecture.html`：

- 文件树加入 `src/xduwlan/credentials.py`、`src/xduwlan/keyring_store.py`、`tests/__init__.py`、`tests/fakes.py`、`tests/test_credentials.py` 和 `tests/test_keyring_store.py`；
- 为每个新文件加入职责、依赖、使用方和边界；
- 更新 `pyproject.toml` 的 `keyring>=25,<26` 事实；
- 更新 `errors.py` 的 `CredentialStoreError`；
- 移除“keyring 尚未接入”和“凭据异常以后再定义”等过时文字。

- [ ] **Step 4: Verify docs, visualizations, tests, and diff**

Run:

```bash
rg -n "keyring 尚未接入|凭据.*以后.*定义|开始前对齐" \
  docs/architecture.md docs/current.md docs/visualizations
conda run -n xduwlan python -m pytest -q
git diff --check
git status --short
```

Expected: 第一条检索无过时命中；测试仍为 `78 passed`；`git diff --check` 无输出；状态只包含本任务预期文档与可视化改动。

用浏览器分别打开两份 HTML：在命令图中切换到 `configure`，在文件图中依次选择两个生产文件和两个测试文件，确认无空白详情、脚本错误或与源码不符的状态。

- [ ] **Step 5: Commit synchronized documentation**

```bash
git add docs/architecture.md docs/current.md \
  docs/superpowers/specs/2026-09-23-credential-store-design.md \
  docs/visualizations/xduwlan-architecture.html \
  docs/visualizations/xduwlan-file-architecture.html
git diff --cached --check
git commit -m "docs: 记录凭据存储边界完成"
git status --porcelain
```

Expected: 提交成功，最终 `git status --porcelain` 无输出。

## Execution Handoff

本项目按 `AGENTS.md` 采用指导者与学习者结对执行，不使用子代理代写学习者负责的业务逻辑。因此执行方式固定为当前会话内的 `superpowers:executing-plans`：指导者先讲解 Task 1 的已定设计并建立 RED，然后停止在明确的学习者实现检查点。
