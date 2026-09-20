"""XDUWlan 的项目级异常层次。"""


class XDUWlanError(Exception):
    """所有可预期项目异常的共同基类。"""


class ConfigurationError(XDUWlanError):
    """配置缺失、类型错误或取值非法。"""
