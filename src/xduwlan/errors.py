"""XDUWlan 的项目级异常层次。"""


class XDUWlanError(Exception):
    """所有可预期项目异常的共同基类。"""


class ConfigurationError(XDUWlanError):
    """配置缺失、类型错误或取值非法。"""


class CredentialStoreError(XDUWlanError):
    """系统凭据库不可用，或其中的凭据记录已经损坏。"""


class CredentialValidationError(XDUWlanError):
    """用户提供的账号或密码不符合凭据配置要求。"""
