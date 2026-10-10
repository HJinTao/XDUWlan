# XDUWlan

西安电子科技大学校园网认证恢复命令行工具。连接校园网后，程序检查网络状态，按需执行 Portal 认证，验证联网结果并退出。

当前提供 `status`、`configure` 和 `login` 三个命令，支持 Python 3.10+。Linux 环境中的认证恢复流程已完成受控实测，验证范围见[协议与验证记录](docs/protocol.md#真实验收)。

## 安装

在项目目录中创建 Python 虚拟环境并安装：

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install .
```

也可以安装到已有 Python 3.10+ 环境。Python 3.10 使用条件依赖 `tomli` 解析 TOML，3.11+ 使用标准库 `tomllib`。

Linux 需要可用且已解锁的 Secret Service 等安全凭据后端。当前以 Linux 为主要验证环境，其他平台尚未完成运行验收。

## 快速开始

首次使用时配置账号密码：

```bash
xduwlan configure
```

密码使用隐藏输入并保存至系统凭据库。需要恢复认证时运行：

```bash
xduwlan login
```

已联网时直接结束，不读取凭据。确认需要认证后，程序校验 Portal 上下文、读取凭据并认证一次；只有联网复查通过才报告恢复成功。

Wi-Fi 的连接和重连由操作系统负责。程序不提供后台常驻、自动连接 Wi-Fi、图形界面、自服务账户查询或设备管理。

## 命令

| 命令 | 作用 |
| --- | --- |
| `xduwlan status` | 检查网络状态 |
| `xduwlan configure` | 交互配置凭据 |
| `xduwlan login` | 按需认证并验证联网结果 |

`status` 和 `login` 支持 `--config PATH`、`--json` 和 `--debug`：

```bash
xduwlan status --json
xduwlan login --debug
xduwlan login --config config.toml
```

JSON 输出固定状态、探测阶段结果与耗时；debug 输出安全的阶段信息。无子命令时显示帮助。

## 配置

未指定 `--config` 时使用默认值。TOML 配置示例：

```toml
portal_url = "https://w.xidian.edu.cn"
probe_url = "https://connect.rom.miui.com/generate_204"
request_timeout_seconds = 5
operator_suffix = ""
```

Portal 必须使用可信 HTTPS 主机、默认端口和有效证书。HTTPS 探测失败时，HTTP 回退用于发现 Portal；HTTP 返回 204 不会覆盖 HTTPS 验证失败。

`operator_suffix` 仅在显式配置时追加一次。兼容保留的 `probe_interval_seconds` 和 `log_level` 不启动周期任务或原始协议日志。密码及会话信息不得写入普通配置，详见[安全规则](docs/security.md)。

## 退出码

| login 退出码 | 含义 |
| --- | --- |
| 0 | 已联网，或认证后联网验证成功 |
| 1 | 网络状态未知，或凭据库不可用 |
| 2 | 配置或凭据输入无效 |
| 3 | 尚未配置凭据 |
| 5 | 网络或 Portal 不可达 |
| 6 | Portal 拒绝认证 |
| 7 | 可信目标、上下文或协议不符合预期 |
| 8 | 已提交认证，但联网验证未通过 |
| 130 | 操作取消 |

`status` 的退出码为在线 0、需要认证 4、不可达 5、未知 1、配置错误 2。

凭据缺失或输入无效时重新运行 `configure`。凭据库不可用时检查桌面/D-Bus 会话及后端解锁状态；程序不回退到明文文件。未认证时 HTTPS 探测可能超时，一次恢复可能需要约 10 秒。

## 开发与构建

```bash
python -m pip install -e ".[test]" build
python -m pytest -q
python -m build
```

构建产物位于 `dist/`。自动化测试使用虚构输入与本地服务，不访问真实校园网或凭据记录。HTTP/TLS 集成测试需要 OpenSSL；协议向量可通过 `node tests/auth/reference_vectors.js` 重新生成，运行 Python 测试不需要 Node。

## 验证范围

已验证 Linux IPv4 环境下的 Portal 识别、认证恢复、系统凭据读取与已联网时跳过认证。不同运营商、校区、IPv6/双栈及具体业务失败响应仍待实测；自动化测试覆盖相应的项目错误处理契约，不代表这些环境已经在线验证。

## 项目文档

- [维护状态](docs/current.md)
- [架构](docs/architecture.md)
- [安全与隐私](docs/security.md)
- [协议与验证记录](docs/protocol.md)
- [命令职责图](docs/visualizations/xduwlan-architecture.html)
- [文件职责图](docs/visualizations/xduwlan-file-architecture.html)
