# `configure` 凭据存储边界设计

## 状态

设计已完成，等待学习者阅读确认。确认后再编写实施计划、建立 RED 和生产代码骨架。

## 背景

`configure` 切片需要收集校园网账号和密码，并让后续 `login`、`watch` 在程序重启后读取。账号属于个人信息，密码属于敏感凭据；两者都不进入普通 TOML、命令参数、日志或明文回退文件。

`keyring` 的稳定核心接口以 `(service_name, username)` 定位一条字符串密码。项目需要在不知道真实校园网账号的前提下找回整组凭据，因此不能把真实账号直接用作必须预先知道的查询键。

## 目标与非目标

本子任务建立与系统凭据库之间的稳定端口和生产适配器：

- 用项目模型表达一组校园网账号和密码；
- 用 `Protocol` 隔离上层代码与第三方 `keyring`；
- 将账号和密码作为一条记录保存到操作系统凭据库；
- 区分“尚未配置”与“凭据库故障或内容损坏”；
- 所有项目错误和对象表示都不泄漏账号、密码或底层异常文本。

本子任务不接入 `configure` CLI，不调用 `getpass`，不校验交互输入是否为空，不实现删除或多账号，不写 TOML，不实现 Portal 协议，也不访问真实系统凭据库。

## 方案选择

采用单条记录方案。适配器使用固定 `service_name` 和固定内部记录名，把 `account` 与 `password` 编码成一个 JSON 字符串，再调用一次 `keyring.set_password()`。

没有采用两条记录，因为连续两次写入没有跨平台事务保证，第二次失败会留下半配置状态。没有采用“账号写 TOML、密码按账号查询”，因为这会把学号留在明文配置中。

## 组件与依赖方向

### `src/xduwlan/credentials.py`

- `Credentials`：不可变数据类，字段为 `account: str` 和 `password: str`。两个字段都从 `repr` 隐藏，避免个人信息或密码因调试输出泄漏。
- `CredentialStore`：调用方需要的端口接口，只声明：
  - `save(credentials: Credentials) -> None`
  - `load() -> Credentials | None`

`None` 是正常的“尚未配置”状态，不是异常。

### `src/xduwlan/keyring_store.py`

- `KeyringCredentialStore`：调用 `keyring` 的生产适配器。
- 固定 service 为 `XDUWlan`，固定内部记录名为 `campus-network-credentials`。
- 存储 JSON 只包含 `account` 和 `password` 两个字段。
- 读取时验证顶层是对象，并验证两个字段均为字符串；额外字段不影响当前版本读取。

固定查询键是持久化兼容约定。真实账号只存在于系统凭据记录的值中，不作为查询键，也不进入普通配置。

### `src/xduwlan/errors.py`

- `CredentialStoreError(XDUWlanError)`：表示凭据库读取失败、写入失败或已存记录损坏。

### `tests/fakes.py`

- `MemoryCredentialStore`：只供测试注入的内存实现，遵守同一端口；不进入生产装配，不提供持久化保证。

### `pyproject.toml`

- 运行时依赖增加 `keyring>=25,<26`。第一版固定在已核对 API 的主版本内，避免未来主版本破坏接口。

依赖方向保持为：

```text
未来的 configure/login 应用服务
  → Credentials + CredentialStore
    ← MemoryCredentialStore（测试）
    ← KeyringCredentialStore（生产）
      → keyring
        → 操作系统凭据库
```

核心模型和端口不导入 `keyring`，平台差异只存在于适配器中。

## 数据流

保存流程：

```text
Credentials
  → JSON 编码
  → keyring.set_password("XDUWlan", "campus-network-credentials", payload)
  → 成功返回 None
```

保存只调用一次系统凭据库，因此不会产生项目层面的半配置状态。重新执行保存覆盖同一条记录，这是 `configure` 更新凭据所需的语义。

读取流程：

```text
keyring.get_password("XDUWlan", "campus-network-credentials")
  → None：返回 None
  → str：JSON 解码和结构校验
      → 合法：返回 Credentials
      → 非法：抛出 CredentialStoreError
```

伪代码：

```python
def save(credentials):
    payload = encode(account=credentials.account, password=credentials.password)
    try:
        keyring.set_password(SERVICE, RECORD, payload)
    except KeyringError as cause:
        raise CredentialStoreError("系统凭据库写入失败") from cause


def load():
    try:
        payload = keyring.get_password(SERVICE, RECORD)
    except KeyringError as cause:
        raise CredentialStoreError("系统凭据库读取失败") from cause

    if payload is None:
        return None

    try:
        data = decode_and_validate(payload)
    except malformed_record_errors as cause:
        raise CredentialStoreError("系统凭据记录损坏") from cause

    return Credentials(account=data["account"], password=data["password"])
```

## 错误与安全边界

- 适配器只转换 `keyring.errors.KeyringError` 及其子类；不使用裸 `except`，避免吞掉项目编程错误。
- JSON 语法错误、非对象顶层、字段缺失和字段类型错误统一转换为 `CredentialStoreError`。
- 项目错误使用固定中文消息，不拼接底层异常、原始 JSON、账号或密码。
- 使用异常链保留根因，但未来 CLI 和日志只能显示项目错误的固定摘要，不能遍历或输出 `__cause__`。
- `Credentials` 的 `repr` 不显示账号和密码。
- 自动化测试只使用明显虚构的账号和密码，并替换 `keyring` 调用，不接触用户真实凭据库。
- 不提供明文文件回退；没有可用后端时明确失败。

## 一次性 RED 设计

指导者先增加依赖、测试、异常类型和可导入的符号骨架。骨架方法可以抛出 `NotImplementedError`，不包含编码、状态转换或异常转换业务逻辑。随后一次运行目标测试，形成覆盖完整职责的 RED，再交给学习者一次实现到 GREEN。

### `tests/test_credentials.py`

1. 构造虚构凭据后，`repr(credentials)` 不包含账号或密码标记。

### `tests/test_keyring_store.py`

2. 保存只调用一次 `set_password`，使用固定 service、固定记录名；解析传入 JSON 后能恢复原账号和密码。
3. 读取已保存的合法 JSON，返回相等的 `Credentials`。
4. `get_password` 返回 `None` 时，`load()` 返回 `None`。
5. 写入时抛出的 `KeyringError` 转换为 `CredentialStoreError`，项目错误文本不包含底层私密标记。
6. 读取时抛出的 `KeyringError` 做同样的安全转换。
7. 对非法 JSON、非对象顶层、字段缺失和字段类型错误进行参数化测试，均得到固定的损坏错误，错误文本不回显原始内容。

### `tests/fakes.py`

8. 提供最小 `MemoryCredentialStore`，初始读取为 `None`，保存后返回最近一组凭据。它是后续应用服务测试的复用测试替身，不形成新的生产能力。

目标 RED 命令：

```bash
conda run -n xduwlan python -m pytest -q \
  tests/test_credentials.py tests/test_keyring_store.py
```

预期失败来自未实现的安全 `repr`、JSON 编解码、记录校验和异常转换，而不是导入错误、缺少第三方依赖或访问真实系统凭据库。

## 完成条件

- 目标测试全部通过；
- 运行完整回归，现有 `status` 行为不变；
- `git diff --check` 通过；
- 测试、错误、日志和文档中没有真实账号、密码或凭据库内容；
- `docs/current.md`、`docs/architecture.md` 和两份 HTML 可视化在实现事实变化后同步；
- `configure` CLI 仍保持占位，下一子任务再对齐交互输入与应用服务。

## 官方 API 依据

- [`keyring` 核心 API 源码](https://github.com/jaraco/keyring/blob/main/keyring/core.py)：`get_password`、`set_password` 与后端选择入口；
- [`keyring` 异常层次源码](https://github.com/jaraco/keyring/blob/main/keyring/errors.py)：`KeyringError` 及其子类；
- [`keyring` PyPI 项目页](https://pypi.org/project/keyring/)：当前发布版本和 Python 版本要求。
