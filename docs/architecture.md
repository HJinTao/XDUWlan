# 架构说明

## 目标

本项目先用 Python 验证协议和流程，未来允许使用 Java、Go、Rust 等语言重写。因此核心边界必须与 Python 的具体库和操作系统解耦。

## 交互架构图

[在浏览器中打开 XDUWlan 交互架构图](visualizations/xduwlan-architecture.html)。图中可以切换 `status`、`login`、`watch`、`account` 和 `configure`，观察每条命令经过的分层与数据流。

## 依赖方向

```text
CLI → 应用服务 → 核心模型与端口接口
                     ↑
HTTP、凭据库、文件和日志适配器
```

核心不能导入 CLI、`httpx`、`keyring` 或操作系统专属模块。平台差异集中在适配器中。

## 主要组件

- `models`：不可变领域数据和枚举。
- `probe`：DNS、TCP、HTTP 和 Portal 识别。
- `portal`：深澜 challenge、编码、请求和响应解析。
- `watcher`：周期探测、认证、验证、退避和停止。
- `monitor`：自服务登录、会话恢复和 HTML 解析。
- `credentials`：系统凭据库适配器。
- `storage`：会话及后续 SQLite 存储。
- `cli`：命令解析和输出格式化。

## 纵向切片实施方式

架构按层保持解耦，开发顺序则按用户可运行的命令纵向穿过各层：

```text
status：CLI → 探测服务 → 网络模型与配置 → DNS/TCP/HTTP 适配器 → 真实或本地测试网络
configure：CLI → 配置流程 → CredentialStore → keyring 适配器 → 操作系统凭据库
login：CLI → 登录服务 → 探测与认证模型 → PortalClient → 校园网 Portal
watch：CLI → WatchService → 复用探测和登录 → 计时与停止边界
account：CLI → AccountService → 账户模型 → 自服务客户端与解析器 → 自服务平台
```

每个切片只实现当前命令需要的领域词汇和接口。例如 `status` 阶段不实现 `AuthenticationResult` 或 `AccountSnapshot`。切片内部仍然先测试后实现，但测试只覆盖当前目标，保证通过后可以立即运行对应 CLI 命令。

## 关键隔离

Portal 认证与自服务监测是两条独立链路。Portal 负责让设备联网；自服务平台负责读取设备和套餐数据。自服务验证码或页面改版不能直接破坏 Portal 认证。

## 未来迁移

跨语言迁移优先复用：

1. 网络状态枚举和认证状态枚举；
2. 状态机转换规则；
3. JSON 协议测试向量；
4. 脱敏和错误分类规则；
5. CLI 输入输出约定。
