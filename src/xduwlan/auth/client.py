"""沿可信入口链取得上下文并执行一次深澜认证。"""

from __future__ import annotations

import re
import time
from collections.abc import Callable
from urllib.parse import urlencode, urlsplit

from xduwlan.auth.interfaces import PortalContext, PortalTransport
from xduwlan.auth.pages import find_portal_navigation, parse_portal_context, trusted_portal_url
from xduwlan.auth.protocol import build_login_params, parse_jsonp
from xduwlan.credentials import Credentials
from xduwlan.errors import AuthenticationRejectedError, PortalNetworkError, PortalProtocolError

MAX_ENTRY_REQUESTS = 6


class SrunPortalClient:
    """显式导航，不执行网页脚本，不发送凭据到页面给出的任意主机。"""

    def __init__(
        self, portal_url: str, entry_url: str, timeout: float,
        transport: PortalTransport, clock: Callable[[], float] = time.time,
    ) -> None:
        self._portal_url = trusted_portal_url("/", portal_url, portal_url).rstrip("/")
        self._entry_url = entry_url
        self._timeout = timeout
        self._transport = transport
        self._clock = clock

    def prepare(self) -> PortalContext:
        """沿入口导航最多六次，所有后续请求都先校验同源目标。"""
        method, url = "GET", self._entry_url
        for _ in range(MAX_ENTRY_REQUESTS):
            response = self._transport.request(method, url, self._timeout)
            if 300 <= response.status_code < 400:
                if not response.location:
                    raise PortalProtocolError("Portal 重定向缺少目标")
                url = trusted_portal_url(response.location, url, self._portal_url)
                method = "GET"
                continue
            if response.status_code != 200:
                raise PortalNetworkError("Portal 入口不可用")
            if (urlsplit(url).scheme == "https"
                    and urlsplit(url).hostname == urlsplit(self._portal_url).hostname
                    and re.search(r"\b(?:var|let|const)\s+CONFIG\s*=", response.body)):
                return parse_portal_context(response.body, self._portal_url)
            navigation = find_portal_navigation(response.body, url, self._portal_url)
            if navigation is None:
                raise PortalProtocolError("Portal 入口结构不符合预期")
            method, url = navigation.method, navigation.url
        raise PortalProtocolError("Portal 导航超过次数上限")

    def _request_jsonp(self, path: str, params: dict) -> dict:
        url = self._portal_url + path + "?" + urlencode(params)
        response = self._transport.request("GET", url, self._timeout)
        if 300 <= response.status_code < 400:
            raise PortalProtocolError("认证端点发生意外重定向")
        if response.status_code != 200:
            raise PortalNetworkError("认证端点不可用")
        return parse_jsonp(response.body, params["callback"])

    def authenticate(self, context: PortalContext, credentials: Credentials) -> None:
        """挑战、登录各一次；业务拒绝不重试，原始消息不向外传播。"""
        if context.portal_url != self._portal_url:
            raise PortalProtocolError("认证上下文目标不匹配")
        timestamp = int(self._clock() * 1000)
        callback = f"xduwlan_cb_{timestamp}"
        response = self._request_jsonp("/cgi-bin/get_challenge", {
            "callback": callback, "username": credentials.username,
            "ip": context.ip, "_": timestamp,
        })
        _require_success(response)
        challenge = response.get("challenge")
        if (not isinstance(challenge, str) or not challenge or len(challenge) > 1024
                or not challenge.isascii() or any(ord(char) < 33 for char in challenge)):
            raise PortalProtocolError("认证挑战格式不符合预期")
        if response.get("client_ip") != context.ip:
            raise PortalProtocolError("认证挑战的客户端上下文不匹配")
        params = build_login_params(credentials, context, challenge, callback, int(self._clock() * 1000))
        _require_success(self._request_jsonp("/cgi-bin/srun_portal", params))


def _require_success(response: dict) -> None:
    """根据已观察的状态字段判断业务结果，不解释未经验证的错误码。"""
    if "code" in response:
        code = response["code"]
        if type(code) is not int:
            raise PortalProtocolError("认证业务状态格式不符合预期")
        succeeded = code == 0
    elif isinstance(response.get("error"), str) and response["error"]:
        succeeded = response["error"] == "ok"
    else:
        raise PortalProtocolError("认证响应缺少业务状态")
    if not succeeded:
        raise AuthenticationRejectedError("Portal 拒绝认证")
