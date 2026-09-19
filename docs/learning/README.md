# 学习文档目录

学习文档按网络主题组织。每篇文档应包含：本节问题、相关概念、数据流、本项目应用、需要检索的 API、实验步骤、实现结果、易错点和延伸问题。

学习主题按纵向切片实际用到的顺序编写：

1. `00-python-cli.md`：Python CLI 骨架；
2. `01-models-and-config.md`：`status` 使用的枚举、不可变数据和 TOML；
3. `02-dns.md`：DNS 与地址解析；
4. `03-tcp.md`：TCP 连接和超时；
5. `04-http.md`：HTTP 状态码、重定向和 Captive Portal；
6. `05-credentials.md`：Protocol、凭据边界和 keyring；
7. `06-portal-authentication.md`：深澜认证字段、纯函数和 HTTP 客户端；
8. `07-state-machine-and-retry.md`：状态机、退避和可观测性；
9. `08-session-cookie-csrf.md`：会话、验证码、CSRF 和 HTML 解析；
10. `09-packaging.md`：跨平台测试和程序打包。

未来切片的学习文档不提前撰写。每篇文档在对应代码完成并通过测试后记录实际实现、失败现象和复盘。
