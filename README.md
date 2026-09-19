# XDUWlan

XDUWlan 是一个面向学习的校园网自动认证与校园网状态监测项目，目标平台为西安电子科技大学校园网络。

## 当前状态

项目已建立可安装的 Python CLI 骨架。当前五个命令已注册，但仍使用占位处理器；后续按 M1 至 M5 逐步实现网络探测、认证、自服务监测和凭据保护。

## 第一版目标

- `status`：判断已联网、需要校园网认证、网络不可用或无法确定。
- `login`：执行一次西电深澜 Portal 认证，并给出可理解的结果。
- `watch`：前台周期探测，掉线后自动重连。
- `account`：读取自服务平台中的在线设备、流量和套餐信息。
- `configure`：通过交互输入凭据并保存到系统凭据库。

第一版不包含图形界面、系统托盘、开机自启、移动端、云同步、验证码绕过和远程上传数据。

## 学习方式

每个阶段遵循“原理讲解、逻辑结构、API 检索、你实现、代码审查、自动测试、受控实测、文档记录”的循环。请先阅读 `AGENTS.md` 和 `docs/session-handoff.md`。

测试由指导者编写和维护，生产代码由学习者实现。每个小步骤开始前先对齐具体文件、函数/类、职责、调用关系和测试逻辑。

## 开发安装

```bash
python -m pip install -e ".[test]"
python -m pytest -q
```

## 文档

- `docs/superpowers/specs/2026-09-19-xduwlan-design.md`：已确认的正式设计规格。
- `docs/architecture.md`：模块边界和依赖方向。
- `docs/security.md`：凭据、会话、日志和测试数据规则。
- `docs/progress.md`：里程碑进度和下一步。
- `docs/session-handoff.md`：下一次会话的最短恢复入口。
- `docs/learning/`：按网络主题记录学习内容。
- `docs/protocol/`：记录经过观察、验证或推断的协议事实。
- `docs/decisions/`：记录重要技术决策及其理由。
