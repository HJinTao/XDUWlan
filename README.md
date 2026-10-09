# XDUWlan

西安电子科技大学校园网的一次认证恢复工具，要求 Python 3.11+。操作系统先连接校园 Wi-Fi；程序检查网络、按需认证、验证联网并退出。

## 安装与使用

在项目目录创建虚拟环境并安装：

```bash
python -m venv .venv
```

macOS / Linux 激活：

```bash
source .venv/bin/activate
```

Windows PowerShell 激活：

```powershell
.venv\Scripts\Activate.ps1
```

然后安装并配置凭据：

```bash
python -m pip install .
xduwlan configure
```

密码使用隐藏输入并保存到系统凭据库，不写入普通配置。网络认证失效时运行：

```bash
xduwlan login
```

已联网时直接退出，不读取凭据；只有确认可信 Portal 要求认证后才读取并提交凭据，每次最多认证一次。认证响应成功后仍需独立联网验证。

## 命令与输出

```bash
xduwlan status
xduwlan status --json
xduwlan status --debug
xduwlan login --json
xduwlan login --debug
xduwlan login --config PATH
```

`status` 检查网络；`configure` 保存凭据；`login` 尝试恢复。无子命令显示帮助。JSON 只输出固定状态、阶段成功与耗时；debug 不输出账号、IP、认证参数或原始响应。

| login 退出码 | 含义 |
| --- | --- |
| 0 | 原本已联网或恢复后验证成功 |
| 1 | 状态未知或系统凭据库不可用 |
| 2 | 配置或凭据输入无效 |
| 3 | 未配置凭据，先运行 configure |
| 5 | 网络或 Portal 暂时不可达 |
| 6 | Portal 明确拒绝认证，检查凭据或账户限制 |
| 7 | 可信目标、上下文或认证协议不符合预期 |
| 8 | 已提交认证，但联网验证未通过 |
| 130 | 用户取消 |

`status` 的退出码为在线 0、需要认证 4、不可达 5、未知 1、配置错误 2。

## 非敏感配置

`status` 和 `login` 都支持 `--config PATH`；未指定时使用默认值。示例：

```toml
portal_url = "https://w.xidian.edu.cn"
probe_url = "https://connect.rom.miui.com/generate_204"
request_timeout_seconds = 5
operator_suffix = ""
```

Portal 必须使用可信 HTTPS 主机、默认端口和有效证书。入口导航始终校验同源目标。默认 HTTPS 探测失败时，程序用同一端点的 HTTP 地址发现 Portal；HTTP 放行不会掩盖 HTTPS 验证失败。

`operator_suffix` 默认为空，只在用户显式配置时追加一次。不同运营商、IPv6 和双栈尚未真实验证。兼容保留的 `probe_interval_seconds`、`log_level` 不启动循环或输出原始协议调试信息。密码、Cookie、验证码、challenge 和认证参数不得放入 TOML、命令参数或源码。

## 系统凭据库

macOS 使用钥匙串，Windows 使用系统凭据管理器；Linux 需要可用且已解锁的 Secret Service 等安全后端。无桌面或 D-Bus 会话的 Linux 环境可能无法读取凭据；程序明确失败，不回退到明文文件。可使用 `python -m keyring diagnose` 在本机诊断，不把诊断中的个人信息提交到仓库。[keyring 官方说明](https://keyring.readthedocs.io/en/latest/)

## 开发、打包与验证

```bash
python -m pip install -e ".[test]" build
python -m pytest -q
python -m build
```

发行包位于 `dist/`；可安装构建出的 wheel。生产包仅包含 `xduwlan`，`src/login.py` 是教学实验参考，不参与发行或运行。协议固定向量可以通过 `node tests/auth/reference_vectors.js` 重新生成，运行 Python 测试不需要 Node。

自动化测试使用虚构输入、本地服务器和外部边界替代对象，不访问真实校园网、终端或系统凭据记录。CI 配置覆盖 macOS、Windows、Linux 的 Python 3.11 与 3.14。CI 尚未在远端执行时不能视为跨平台通过；项目生产流程的校园网实测另行记录。

第一版不包含后台驻留、自动连接 Wi-Fi、图形界面、开机自启或自服务账号查询。

## 文档

- [`docs/current.md`](docs/current.md)：当前工作与验证状态；
- [`docs/roadmap.md`](docs/roadmap.md)：产品范围与验收；
- [`docs/architecture.md`](docs/architecture.md)：实际模块与调用链；
- [`docs/security.md`](docs/security.md)：安全和隐私规则；
- [`docs/protocol/`](docs/protocol/)：脱敏协议证据；
- [`docs/visualizations/`](docs/visualizations/)：命令与文件职责图。
