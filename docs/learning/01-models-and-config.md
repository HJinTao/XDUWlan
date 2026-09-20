# 01. 网络模型与非敏感配置

## 本节问题

`status` 命令还没有执行真实网络请求时，怎样先建立稳定、不可变、可测试的数据结构和配置入口？

## 本节目标

- 使用 `Enum` 定义稳定的网络状态和探测阶段；
- 使用 `@dataclass(frozen=True)` 定义不可变探测结果和配置对象；
- 使用 `tuple` 保存不可修改的阶段观察集合；
- 使用 `@classmethod` 提供完整默认配置；
- 使用 `Path` 和 `tomllib` 读取非敏感 TOML 配置；
- 合并默认值、忽略未知字段并校验数值；
- 使用 `ConfigurationError` 隔离底层解析异常。

本节不执行 DNS、TCP 或 HTTP 请求，也不读取密码、Cookie、验证码或会话凭据。

## 文件与符号

- `src/xduwlan/models.py`：
  - `NetworkState`：一次完整探测的最终分类；
  - `ProbeStage`：DNS、TCP、HTTP 三个探测阶段；
  - `ProbeObservation`：一个阶段的成功状态、耗时和说明；
  - `NetworkProbeResult`：汇总最终状态、观察集合和可选 Portal 地址。
- `src/xduwlan/config.py`：
  - `AppConfig`：六个非敏感运行配置字段；
  - `AppConfig.defaults()`：创建完整默认配置；
  - `AppConfig.load(path)`：读取、合并和校验 TOML。
- `src/xduwlan/errors.py`：
  - `XDUWlanError`：项目可预期异常的共同父类；
  - `ConfigurationError`：配置内容或格式不合法。
- `tests/test_models.py`：验证枚举契约和不可变模型。
- `tests/test_config.py`：验证默认值、TOML 合并、错误类型、正数约束和异常链。

## 调用流程

```text
配置文件路径
  → Path.read_text(encoding="utf-8")
  → tomllib.loads(text)
  → 已知字段覆盖 AppConfig.defaults()
  → 校验周期和超时
  → AppConfig

任务三 DNS/TCP/HTTP 探测器
  → 创建 ProbeObservation
  → 汇总为 NetworkProbeResult
  → 任务四 status CLI 读取并展示
```

模型只保存数据，不依赖 CLI、操作系统或具体网络库。配置只保存非敏感值，密码将在后续切片通过系统凭据库管理。

## 关键 Python 语法

### Enum

```python
class ProbeStage(Enum):
    DNS = "dns"
```

`ProbeStage.DNS.name` 是 `"DNS"`，`ProbeStage.DNS.value` 是 `"dns"`。成员名称和值共同构成稳定契约，因此测试同时检查二者。

### 不可变数据类

```python
@dataclass(frozen=True)
class ProbeObservation:
    stage: ProbeStage
    succeeded: bool
```

`dataclass` 根据字段生成初始化和比较方法；`frozen=True` 阻止对象创建后重新赋值。

### tuple 与可选类型

```python
observations: tuple[ProbeObservation, ...]
portal_url: str | None = None
```

`tuple[T, ...]` 表示任意数量的 `T`；`str | None` 表示字符串或空值；`= None` 提供默认值。

### 类方法

```python
@classmethod
def defaults(cls) -> AppConfig:
    return cls(...)
```

调用 `AppConfig.defaults()` 时，`cls` 代表 `AppConfig` 类。使用 `cls(...)` 创建对象，避免在方法内部重复写死类名。

### TOML 与默认值合并

`tomllib.loads(text)` 把 TOML 字符串解析为字典。`data.get(key, default)` 在字段缺失时返回默认值。程序只读取六个已知字段，因此未知字段会被忽略。

### 类型边界

```python
if isinstance(value, bool) or not isinstance(value, (int, float)):
    raise ConfigurationError(...)
```

Python 中 `bool` 是 `int` 的子类，所以 `isinstance(True, int)` 为真。秒数不能接受 TOML 布尔值，因此需要先显式排除 `bool`，再检查 `int` 或 `float`。

类型检查必须先于 `value <= 0`。否则字符串与数字比较会泄漏普通 `TypeError`。

### 异常链

```python
try:
    data = tomllib.loads(text)
except tomllib.TOMLDecodeError as exc:
    raise ConfigurationError("配置文件不是有效的 TOML") from exc
```

上层只需要处理项目统一的 `ConfigurationError`，调试时仍可通过 `__cause__` 查看原始 `TOMLDecodeError`。

## API 检索问题

- `enum.Enum` 的成员 `.name` 和 `.value` 分别是什么？
- `dataclasses.dataclass(frozen=True)` 会生成哪些方法和异常？
- `pathlib.Path.read_text()` 如何指定编码？
- `tomllib.loads()` 接收什么输入并抛出什么异常？
- `dict.get(key, default)` 在键存在和不存在时分别返回什么？
- `isinstance(True, int)` 为什么返回 `True`？
- `raise NewError(...) from exc` 如何保存异常链？

## 测试条件和结果

任务二包含 18 个测试：

- 4 个模型测试：两个枚举、两个不可变数据类；
- 14 个配置测试：默认值、不可变性、三条正常加载路径、畸形 TOML、四组非正数和四组错误类型。

运行：

```bash
conda run -n xduwlan python -m pytest tests/test_models.py tests/test_config.py -q
```

已验证：18 个测试全部通过。全仓库当前 25 个测试全部通过。

## 易错点与复盘

- 只检查枚举 `.value` 会漏掉成员名称拼写错误，因此测试改为同时检查名称和值；
- `dataclass` 已自动生成 `__init__`，保留手写占位 `__init__` 会阻止它工作；
- 单元素元组必须写成 `(observation,)`；
- `bool` 是 `int` 的子类，数值配置必须显式排除布尔值；
- 类型校验必须在大小比较之前；
- 捕获解析异常时只包围可能失败的解析语句，避免掩盖其他编程错误；
- 代码功能通过后仍需整理导入顺序、顶层空行和尾随空格。

## 当前边界

模型和配置已经可供后续模块调用，但程序仍未执行真实网络探测。下一步将进入 `status` 切片的任务三，逐步实现 DNS、TCP 和 HTTP 探测。
