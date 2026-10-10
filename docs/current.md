# 维护状态

## 当前版本

`0.1.0` 已实现 `status`、`configure` 和 `login`。Linux 环境中的一次认证恢复流程已完成受控验收，当前没有已知功能阻塞。功能范围与运行方式见 [README](../README.md)。

当前维护重点是认证逻辑和 Linux CLI 的可靠性。跨平台运行验收、后台任务、图形界面与自服务功能不属于当前维护范围。

## 验证记录

2026-10-09 验证结果：

- Python 3.10.22 与 Python 3.11 环境的自动化测试均为 `203 passed`。
- wheel/sdist 构建与安装成功，发行包要求 Python 3.10+。
- 真实校园网认证恢复及已联网时跳过认证已验证，详见 [协议记录](protocol.md#真实验收)。

2026-10-10：两处协议向量读取已显式指定 UTF-8，修复 Windows 默认 cp1252 导致的 UnicodeDecodeError。本地模拟 cp1252 的受影响测试 `14 passed`、完整回归 `203 passed`；[Windows Python 3.10 与 3.14 的测试、CLI 入口和构建均已通过](https://github.com/HJinTao/XDUWlan/actions/runs/38037614608)。

## 后续事项

- 不同运营商、校区、IPv6/双栈及具体业务失败响应仍待实测，见协议记录。
- 结果模型的运行时容器类型校验可以在相关接口变更时加强，当前不阻断功能。

## 维护索引

- 产品与命令：[README](../README.md)。
- 模块与边界：[架构](architecture.md)、[安全](security.md)、[协议](protocol.md)。
- CLI 与编排：`src/xduwlan/cli.py`、`config.py`、`login_service.py`。
- 网络与凭据：`src/xduwlan/auth/`、`probe/`、`keyring_store.py`。
- 测试：`tests/auth/`、`tests/probe/`、`tests/test_login_*.py`、`tests/test_python_compatibility.py`。
- 构建：`pyproject.toml`、`MANIFEST.in`。
