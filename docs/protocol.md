# 协议与验证记录

本文记录实现所需的脱敏协议事实，不包含真实凭据、网络标识、页面或请求内容。产品范围见 [README](../README.md)，维护原则见 [AGENTS.md](../AGENTS.md)。

## 证据等级

- **项目验证**：固定虚构向量或本地服务证明项目契约。
- **真实观察/验收**：在授权环境中得到的脱敏结果，只适用于记录的设备和网络条件。
- **待验证**：推断或尚未在目标平台确认的行为。

## 探测与认证契约

Flutter 实现位于 `app/lib/core/`、`app/lib/application/` 和 `app/lib/platform/`，对应验证位于 `app/test/`。

认证流程为：

```text
联网探测
  -> ONLINE：跳过认证
  -> PORTAL_REQUIRED：获取并校验 Portal 上下文
      -> 加载凭据 -> challenge -> 构造参数 -> login
      -> 独立联网复查，仅 ONLINE 才报告恢复成功
  -> 其他状态：结束本次恢复
```

已联网或未确认需要认证时不读取凭据，也不发起 Portal 认证请求。Portal 业务响应成功不足以证明网络已恢复，必须通过独立复查确认。

主 HTTPS 探测返回 204 才作为在线证据；确认在线或需要认证后不再执行回退。主探测未取得上述结论时，HTTP 回退只用于发现认证入口，只有需要认证的分类可以替代主结果；HTTP 204 不覆盖主 HTTPS 的 TLS/传输失败或未知状态。此边界由 [`IoNetworkProbe`](../app/lib/platform/network_probe.dart) 与[虚构响应测试](../app/test/platform/network_probe_test.dart)验证，属于项目契约。

可信 Portal 重定向、srun 特征页面或唯一空 POST 入口表示需要认证；普通 200、未知重定向、缺少证据、超时和畸形响应均不能直接判定为在线。请求禁止自动跟随重定向，并限制正文大小、请求次数和单次超时。

Portal 入口只接受校验后的可信主机和默认端口；认证提交只允许发往配置的 HTTPS 同源目标。入口阶段不携带凭据，单轮 challenge 和 login 各最多请求一次，不在轮内重试；跨轮调度与账号错误暂停策略见 [产品行为](../README.md#产品目标)。凭据、认证派生值、Portal 上下文和原始响应不写入日志或普通配置。

## 测试资产

- `app/test/fixtures/srun_vectors.json`：固定虚构协议向量，覆盖 ASCII、中文和 emoji 输入。
- `app/test/fixtures/tls/`：仅用于本地测试的 TLS 证书和私钥，不对应真实服务。
- `app/test/platform/` 与 `app/test/application/`：本地传输、Portal 导航和一次恢复流程验证。

测试通过不代表所有校区、运营商、IPv6/双栈环境或移动端网络通路已经验收；未经授权不得连接真实校园网或使用真实凭据进行自动化测试。
