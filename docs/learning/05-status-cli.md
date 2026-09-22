# 05. 完整探测服务与 `status` CLI

## 本节问题

前面的 DNS、TCP、HTTP 适配器已经可以分别工作，怎样把它们编排成一次完整探测，并让命令行安全地展示结果？

## 目标与非目标

本节完成 `status` 的可运行链路：读取非敏感配置、执行 DNS → TCP → HTTP、分类网络状态，并输出中文摘要、脱敏 JSON 或调试阶段信息。

本节不实现 Portal 登录、凭据读取、自动重连，也不把完整重定向 URL 或 HTTP 正文输出到 JSON。

## 通信路径与模块边界

```text
用户输入 status
→ argparse 解析参数
→ _handle_status()
→ DefaultNetworkProbe
→ URL 主机名和端口
→ DNS → TCP → HTTP
→ NetworkProbeResult
→ 中文摘要或脱敏 JSON
```

`DefaultNetworkProbe` 负责网络阶段编排；CLI 不直接调用 `socket` 或 `urllib`，只负责配置、装配、展示和退出码。这样以后 `login`、`watch` 可以复用同一个 `NetworkProbe` Protocol。

## 文件与符号

- `src/xduwlan/probe/interfaces.py`：`NetworkProbe.probe()` 声明完整探测端口。
- `src/xduwlan/probe/service.py`：`DefaultNetworkProbe` 注入 `DnsResolver`、`TcpConnector`、`HttpConnectivityChecker`，将阶段观察汇总为 `NetworkProbeResult`。
- `src/xduwlan/cli.py`：`build_network_probe()` 装配系统适配器；`_handle_status()` 读取配置、调用服务、格式化输出和返回退出码。
- `tests/probe/test_service.py`：使用替代适配器验证默认端口、多地址、阶段失败和 HTTP 分类。
- `tests/test_cli.py`：验证状态映射、配置错误、JSON 脱敏、debug 和系统适配器装配。

## 结果与退出码

| `NetworkState` | 中文摘要 | 退出码 |
| --- | --- | ---: |
| `ONLINE` | 已联网 | 0 |
| `PORTAL_REQUIRED` | 需要认证 | 4 |
| `LOCAL_NETWORK_DOWN` | 本地网络不可用 | 5 |
| `INTERNET_UNREACHABLE` | 互联网不可达 | 5 |
| `UNKNOWN` | 无法确定网络状态 | 1 |

DNS 解析失败返回 `UNKNOWN`，TCP 全部候选失败返回 `INTERNET_UNREACHABLE`。一次阶段失败不会把底层异常正文直接传给用户。

## Python 与标准库

- `argparse.Namespace` 保存 `--config`、`--json` 和 `--debug` 的解析结果；
- `pathlib.Path` 把命令行路径交给 `AppConfig.load()`；
- `try` / `except (ConfigurationError, OSError)` 将配置失败转换为稳定的退出码 2；
- 字典 `_STATUS_RESULTS` 将枚举状态映射为 `(message, exit_code)`，tuple 解包同时取得两项；
- `json.dumps(..., ensure_ascii=False)` 将只含状态、阶段、成功标记和耗时的字典转换为 JSON；
- 条件表达式选择“成功”或“失败”的调试文字。

## 安全输出边界

文本 debug 可以显示阶段、成功标记、耗时和已经由适配器整理过的 `detail`。JSON 只包含：

```json
{
  "state": "online",
  "observations": [
    {"stage": "http", "succeeded": true, "elapsed_ms": 3.25}
  ]
}
```

`portal_url`、HTTP `Location`、正文和底层异常正文不进入 JSON。配置错误只显示通用的“配置读取失败”。

## 测试与结果

自动化测试使用虚构 URL、保留示例地址和替代网络依赖，不访问真实校园网。任务四服务测试 7 个、CLI 测试 18 个；全仓库验证为 66 个测试通过。

受控手动实验可以运行：

```bash
xduwlan status
xduwlan status --json
xduwlan status --debug
```

记录实验时只保留状态、阶段、耗时和脱敏错误类别，不保存完整 URL、Cookie、验证码或页面正文。

## 易错点与当前边界

- `--json --debug` 必须仍只输出一份合法 JSON，不能在 JSON 后追加 debug 文本；
- CLI 的 `build_network_probe()` 是装配边界，不应把网络实现复制到命令处理器；
- `NetworkProbeResult` 中的 `portal_url` 目前由服务保留为 `None`，Portal 认证尚未开始；
- 配置中的字符串字段和非有限数值等边界留到实际接入或出现问题时再扩展测试。

## 后续连接点

`login` 将先复用 `NetworkProbe` 判断是否已联网或需要 Portal，再把认证请求放入独立的 `PortalClient`；`watch` 将复用同一探测服务做周期检测。
