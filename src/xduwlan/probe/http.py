"""基于 Python 标准库的 HTTP 连通性请求适配器。"""

from __future__ import annotations

import socket
import urllib.error
from time import perf_counter
from urllib.request import HTTPRedirectHandler, OpenerDirector, Request, build_opener

from xduwlan.probe.interfaces import HttpObservation


MAX_BODY_BYTES = 65_536


class NoRedirectHandler(HTTPRedirectHandler):
    """阻止 urllib 自动跟随 HTTP 重定向。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        """拒绝创建访问重定向目标的后续请求。"""
        return None


class SystemHttpConnectivityChecker:
    """使用 urllib 发送 HTTP 连通性探测请求。"""

    def __init__(self, opener: OpenerDirector | None = None):
        """保存传入的 opener，或构建禁止自动重定向的默认实现。"""
        self._opener = (
            opener if opener is not None else build_opener(NoRedirectHandler())
        )

    def request(self, url: str, timeout: float) -> HttpObservation:
        """请求一个 URL 并返回结构化 HTTP 观察。"""
        start = perf_counter()
        request = Request(url, method="GET")
        try:
            with self._opener.open(request, timeout=timeout) as resp:
                return _observation_from_response(resp, start)
        except urllib.error.HTTPError as e:
            with e:
                return _observation_from_response(e, start)
        except socket.timeout:
            return _failure_observation(start, "HTTP 请求超时")
        except urllib.error.URLError:
            return _failure_observation(start, "HTTP 请求失败")
        except OSError:
            return _failure_observation(start, "HTTP 请求失败")


def _observation_from_response(response, start):
    status_code = response.status
    location = response.headers.get("Location")
    raw_body = response.read(MAX_BODY_BYTES)
    charset = response.headers.get_content_charset() or "utf-8"
    body = raw_body.decode(charset, errors="replace")
    elapsed_ms = (perf_counter() - start) * 1000
    detail = "HTTP 响应已接收"
    return HttpObservation(
        status_code=status_code,
        location=location,
        body=body,
        elapsed_ms=elapsed_ms,
        detail=detail,
    )


def _failure_observation(start, detail):
    status_code = None
    location = None
    body = ""
    elapsed_ms = (perf_counter() - start) * 1000
    return HttpObservation(
        status_code=status_code,
        location=location,
        body=body,
        elapsed_ms=elapsed_ms,
        detail=detail,
    )

