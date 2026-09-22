# XDUWlan

XDUWlan 是一个面向学习的西安电子科技大学校园网命令行工具，第一版使用 Python 实现。

## 当前能力

目前已完成 `status`：读取非敏感配置，依次执行 DNS、TCP 和 HTTP 探测，并输出中文状态、脱敏 JSON 或阶段调试信息。

`configure`、`login`、`watch` 和 `account` 已注册为命令名，但尚未实现实际功能。

## 开发安装

```bash
python -m pip install -e ".[test]"
python -m pytest -q
```

项目要求 Python 3.11 或更高版本。

## 使用 `status`

```bash
xduwlan status
xduwlan status --json
xduwlan status --debug
xduwlan status --config PATH
```

- 默认输出中文状态和稳定退出码；
- `--json` 只输出状态、探测阶段、成功标记和耗时；
- `--debug` 输出经过适配器整理的阶段说明；
- `--config` 读取非敏感 TOML 配置。

真实密码、Cookie、验证码和认证参数不得写入普通配置或项目文件。

## 文档

- [`docs/current.md`](docs/current.md)：当前开发状态和下一步；
- [`docs/roadmap.md`](docs/roadmap.md)：MVP 范围与里程碑；
- [`docs/architecture.md`](docs/architecture.md)：模块和调用关系；
- [`docs/security.md`](docs/security.md)：安全与隐私规则；
- [`docs/decisions/`](docs/decisions/)：重要技术决策；
- [`docs/protocol/`](docs/protocol/)：协议证据与待验证问题；
- [`docs/visualizations/`](docs/visualizations/)：交互式架构与文件视图。
