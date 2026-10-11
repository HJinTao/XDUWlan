# Task 5 报告

## Status

已完成协议观察与规则提升门槛的离线实现。没有执行真实校园网、ThinkPad `down/up`、真实账号或候选输入。

## 改动

- `srun_protocol.dart` 增加候选后缀只追加一次的 Unicode 安全辅助函数，并定义只传递内存数据的 Srun 观察 sink 接口。
- `recovery_validation_support.dart` 增加脱敏 `ProtocolObservation`、固定失败类别、内存观察 sink、ThinkPad 观察器和两次成功提升门。观察器只接受一个受限候选，执行一次 challenge/login 和独立联网复查。
- `recovery_validation.dart` 增加 `--scenario=protocol-observe`，只在 Linux 入口中构造观察器；候选从私有会话目录的一次性 `candidate` 文件读取并立即删除，不从命令行接收账号、密码或候选。
- `srun_client.dart` 在观察 sink 存在时只回调请求/提交计数与派生字段一致性检查，不保存 URL、参数或响应。
- 新增 `protocol_observation_test.dart`，扩展 Srun 协议后缀/Unicode/摘要测试；更新协议与维护状态文档。

## Tests

- `flutter analyze`：通过。
- `flutter test --no-pub test/core/srun_protocol_test.dart test/tool/protocol_observation_test.dart test/tool/recovery_validation_test.dart`：38 项通过。

## 担忧与限制

真实候选仍需在授权 ThinkPad 上分别完成两次成功认证和独立 HTTPS 复查，且至少一次经过固定无线 `down/up`；本提交没有把任何真实观察结论提升为产品默认规则。共享工作区同时包含其他任务对网络观察/恢复模块的改动，本任务未覆盖或回滚这些来源不明的改动。
