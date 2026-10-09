"""有限正文、禁止重定向与代理的 Portal HTTP 适配器。"""

from __future__ import annotations

from http.client import HTTPException
from urllib.error import HTTPError, URLError
from urllib.request import OpenerDirector, ProxyHandler, Request, build_opener

from xduwlan.auth.interfaces import PortalResponse
from xduwlan.errors import PortalNetworkError, PortalProtocolError
from xduwlan.probe.http import NoRedirectHandler

MAX_PORTAL_BODY_BYTES = 65_536


class SystemPortalTransport:
    """直接请求 Portal，保留系统默认 TLS 证书验证且不记录 URL。"""

    def __init__(self, opener: OpenerDirector | None = None) -> None:
        self._opener = opener if opener is not None else build_opener(
            ProxyHandler({}), NoRedirectHandler(),
        )

    def request(self, method: str, url: str, timeout: float) -> PortalResponse:
        """发送一次 GET 或空 POST；响应与底层异常只在安全边界内流动。"""
        try:
            request = Request(url, data=b"" if method == "POST" else None, method=method)
            try:
                response = self._opener.open(request, timeout=timeout)
            except HTTPError as exc:
                response = exc
            with response:
                raw = response.read(MAX_PORTAL_BODY_BYTES + 1)
                if len(raw) > MAX_PORTAL_BODY_BYTES:
                    raise PortalProtocolError("Portal 响应超过大小上限")
                try:
                    body = raw.decode(response.headers.get_content_charset() or "utf-8")
                except (UnicodeError, LookupError):
                    raise PortalProtocolError("Portal 响应编码不受支持") from None
                return PortalResponse(response.status, body, response.headers.get("Location"))
        except (URLError, OSError, HTTPException, ValueError):
            raise PortalNetworkError("Portal 请求失败或超时") from None
