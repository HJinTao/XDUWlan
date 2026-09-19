# XDUWlan

XDUWlan 是一个面向学习的校园网自动认证与校园网状态监测项目，目标平台为西安电子科技大学校园网络。

## 当前状态

项目正在进行设计阶段，尚未实现功能代码。第一版计划先使用 Python 命令行程序跑通核心流程，再为其他语言和桌面界面保留清晰的迁移边界。

## 第一版目标

- `status`：判断已联网、需要校园网认证、网络不可用或无法确定。
- `login`：执行一次西电深澜 Portal 认证，并给出可理解的结果。
- `watch`：前台周期探测，掉线后自动重连。
- `account`：读取自服务平台中的在线设备、流量和套餐信息。
- `configure`：通过交互输入凭据并保存到系统凭据库。

第一版不包含图形界面、系统托盘、开机自启、移动端、云同步、验证码绕过和远程上传数据。

## 学习方式

每个阶段遵循“原理讲解、逻辑结构、API 检索、你实现、代码审查、自动测试、受控实测、文档记录”的循环。请先阅读 `AGENTS.md` 和 `docs/session-handoff.md`。

## 文档

- `docs/superpowers/specs/2026-09-19-xduwlan-design.md`：已确认的正式设计规格。
- `docs/architecture.md`：模块边界和依赖方向。
- `docs/security.md`：凭据、会话、日志和测试数据规则。
- `docs/progress.md`：里程碑进度和下一步。
- `docs/session-handoff.md`：下一次会话的最短恢复入口。
- `docs/learning/`：按网络主题记录学习内容。
- `docs/protocol/`：记录经过观察、验证或推断的协议事实。
- `docs/decisions/`：记录重要技术决策及其理由。
