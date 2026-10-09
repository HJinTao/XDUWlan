"""与系统及具体 HTTP 库无关的 Portal 数据与端口。"""

from dataclasses import dataclass, field
from typing import Protocol

from xduwlan.credentials import Credentials


@dataclass(frozen=True)
class PortalContext:
    """保存一次认证的可信主机与客户端上下文，不在 repr 中暴露。"""

    portal_url: str = field(repr=False)
    ip: str = field(repr=False)
    acid: str


@dataclass(frozen=True)
class PortalResponse:
    """在协议边界内携带有限响应，禁止把正文直接展示给用户。"""

    status_code: int
    body: str = field(repr=False)
    location: str | None = field(default=None, repr=False)


class PortalTransport(Protocol):
    """声明受控 HTTP 请求能力。"""

    def request(self, method: str, url: str, timeout: float) -> PortalResponse:
        """发送一次请求，不自动跟随重定向。"""
        ...


class PortalClient(Protocol):
    """将无凭据的入口发现与凭据认证分开。"""

    def prepare(self) -> PortalContext:
        """获取并校验 Portal 上下文，不读取或发送凭据。"""
        ...

    def authenticate(self, context: PortalContext, credentials: Credentials) -> None:
        """完成一次 challenge 与登录；失败抛出安全项目异常。"""
        ...
