# 第一版认证恢复实施计划

> 执行者按阶段在当前会话串行完成 RED/GREEN；设计与实现均由指导者负责，不设置学习者实现或技术方案批准关卡。

**目标：** 交付路线图内的一次认证恢复 CLI。

**架构：** 复用探测与系统凭据端口，将认证纯逻辑、入口解析、HTTP 适配器和应用编排隔离。

**技术栈：** Python 3.10+、标准库、keyring、pytest、setuptools。

**设计：** [第一版认证恢复设计](../specs/2026-10-09-login-delivery-design.md)。

## 共同约束

- 中文文档、注释和 docstring；测试全部使用虚构数据。
- 不执行 `src/login.py` 网络入口，不自行实验真实校园网或系统凭据记录。
- 保留既有未提交资料；本次分支为 `codex/complete-login-mvp`。
- 自动化通过与真实环境验收分开记录；不提交秘密。

## 阶段一：协议纯函数与可信入口

文件：新增 `src/xduwlan/auth/{__init__,interfaces,protocol,pages}.py` 和 `tests/auth/{test_protocol,test_pages}.py`；修改 `errors.py`、`probe/classifier.py` 及其测试。

接口：`build_login_params(credentials, context, challenge, callback, timestamp)` 返回有序字段；`parse_jsonp(text, callback)` 返回对象；`find_portal_navigation(body, base_url, portal_url)` 返回已校验的 URL 与方法；`parse_portal_context(body, portal_url)` 返回 `PortalContext`。

- [x] 用独立 JavaScript 参考生成 ASCII、中文与代理对输入的固定虚构向量；纯函数测试断言 HMAC、info、checksum，不以被测函数生成预期值。
- [x] 为可信空 POST、meta refresh、CONFIG、恶意主机、userinfo、异常端口及畸形 JSONP 建立 RED；目标命令 `conda run -n xduwlan python -m pytest -q tests/auth/test_protocol.py tests/auth/test_pages.py tests/probe/test_classifier.py`，预期缺少新接口和入口分类失败。
- [x] 实现纯函数、解析与安全异常，运行同一组测试到 GREEN。

## 阶段二：Portal 适配器与探测回退

文件：新增 `auth/{transport,client}.py` 与相应测试；修改 `probe/service.py`、`cli.py` 的探测装配及测试。

接口：`PortalTransport.request(method, url, timeout) -> PortalResponse`；`SrunPortalClient.prepare() -> PortalContext`；`authenticate(context, credentials) -> None`；`DefaultNetworkProbe` 接收可选 `fallback_probe`，只接受回退的可信 Portal 结果。

- [x] 用替代传输断言空 POST → meta refresh → CONFIG → challenge → login 的方法、目标和参数顺序；非法目标在发送前失败，challenge IP 不一致时不登录。
- [x] 用本地服务器与替代 opener 验证 302 不自动跟随、空 POST、正文上限、超时和异常脱敏；用替代探测器验证 HTTPS 成功不回退、失败可发现 Portal、HTTP 204 不掩盖 HTTPS 失败。
- [x] 运行 `conda run -n xduwlan python -m pytest -q tests/auth tests/probe tests/test_cli.py`，确认 RED 后实现并用相同命令到 GREEN。

## 阶段三：应用编排、CLI 与安装交付

文件：新增 `login_service.py`、`tests/test_login_service.py`、`tests/test_login_cli.py`、`.github/workflows/tests.yml`；修改配置校验、CLI、README、项目文档与两份 HTML。

接口：`DefaultLoginService(probe, store, portal).login() -> LoginResult`；`build_login_service(config) -> LoginService`；`_handle_login(args) -> int`。

- [x] 为所有登录结果建立 RED；测试中替代对象记录实际调用顺序，断言已联网/未知状态不加载凭据，失败不继续后续请求，成功必须再次探测。
- [x] CLI 测试断言中文/JSON/debug、配置错误、取消与敏感标记缺失；移除旧的占位成功断言，保留无命令帮助行为。运行 `conda run -n xduwlan python -m pytest -q tests/test_login_service.py tests/test_login_cli.py tests/test_cli.py tests/test_config.py` 确認 RED 后实现到 GREEN。
- [x] 三平台 CI 安装 `.[test]`、运行全部离线测试并验证 CLI 帮助；打包构建 wheel/sdist，在临时环境验证安装和命令入口，检查产物不含参考脚本或个人配置。
- [x] 同步实际实现与离线证据；运行全量 pytest、HTML 脚本语法检查、敏感输出检查和 `git diff --check`，报告仍待执行的真实验收与原有改动。
