# Task 4 报告：ThinkPad Ubuntu lab controller

## Status

完成离线控制器与聚焦测试。真实 ThinkPad `down/up` 未执行。

## 实现

- 新增 `app/lib/tool/thinkpad_lab.dart`。
- 固定动作：`status`、`down`、`up`、`observe`。
- 固定 NetworkManager 连接：`xduwlan-lab-b`；不接受任意 shell、连接名、密码或其他凭据参数。
- 结果序列化为脱敏 JSON，字段仅包含时间、动作、固定结果类别、主机链路类别、协议计数和可选脱敏批次标识。
- 证据目录必须由调用方提供、绝对路径且新建为空；工具写入 `thinkpad-lab.jsonl`。
- 进程执行器、主机链路和时钟可注入，便于离线验证。

## 测试

- 先运行缺少实现的 `flutter test --no-pub test/tool/thinkpad_lab_test.dart`，按 TDD 确认失败。
- `flutter analyze lib/tool/thinkpad_lab.dart test/tool/thinkpad_lab_test.dart` 通过。
- `flutter test --no-pub test/tool/thinkpad_lab_test.dart`：3 tests passed。

## 审查修复

- 所有动作要求 ThinkPad 管理链路为 `wired`；`down/up` 执行后重新读取链路，链路丢失分类为 `unavailable`。
- `--evidence-directory` 现为必填，只接受新建空目录并拒绝目录本身的符号链接；尽可能设置目录 `0700`、证据文件 `0600`。
- `--duration-seconds` 仅允许 `observe`，观察器必须由调用方注入并返回固定安全结果；缺少观察器直接拒绝，不伪造成功。
- `platformIsLinux` 默认读取真实 `Platform.isLinux`，测试可显式注入，避免直接调用默认启用 Linux 行为。
- 修复后聚焦测试 5 项通过，静态分析无问题。

## 限制与担忧

- `observe` 当前只生成安全的零计数完成事件；复用既有 Linux recovery/protocol 观察流程由后续 Task 5 负责。
- `status` 离线实现确认固定连接出现在 `nmcli -t -f NAME connection show` 输出，并记录注入的主机链路类别；未验证真实 SSH 有线路径。
- 文档改动已写入共享工作区；README/current/protocol 同时包含其他任务的现有改动，未在本提交中覆盖或回退。
