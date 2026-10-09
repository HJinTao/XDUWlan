"""XDUWlan 的项目级异常层次。"""


class XDUWlanError(Exception):
    """所有可预期项目异常的共同基类。"""


class ConfigurationError(XDUWlanError):
    """配置缺失、类型错误或取值非法。"""


class CredentialStoreError(XDUWlanError):
    """系统凭据库不可用，或其中的凭据记录已经损坏。"""


class CredentialValidationError(XDUWlanError):
    """用户提供的账号或密码不符合凭据配置要求。"""


class PortalProtocolError(XDUWlanError):
    """Portal 入口、认证上下文或响应不符合已确认的协议。"""


class PortalNetworkError(XDUWlanError):
    """Portal 请求超时、连接失败或返回不可用的 HTTP 状态。"""


class AuthenticationRejectedError(XDUWlanError):
    """Portal 明确拒绝认证；不猜测未经观察的细分错误原因。"""
