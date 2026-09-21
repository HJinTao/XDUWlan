import io
import socket
import urllib.error
import urllib.request
from email.message import Message

import pytest

import xduwlan.probe.http as http_module
from xduwlan.probe.http import (
    NoRedirectHandler,
    SystemHttpConnectivityChecker,
)
from xduwlan.probe.interfaces import HttpObservation


class FakeResponse:
    """模拟可关闭、可限量读取的标准库 HTTP 响应。"""

    def __init__(
        self,
        status: int,
        body: bytes = b"",
        *,
        location: str | None = None,
        content_type: str = "text/plain; charset=utf-8",
    ):
        self.status = status
        self.headers = Message()
        self.headers["Content-Type"] = content_type
        if location is not None:
            self.headers["Location"] = location
        self._body = body
        self.read_sizes = []
        self.closed = False

    def read(self, size=-1):
        self.read_sizes.append(size)
        return self._body[:size] if size >= 0 else self._body

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.closed = True


class FakeOpener:
    """返回预设响应或抛出预设异常，不执行真实 HTTP 请求。"""

    def __init__(self, outcome):
        self.outcome = outcome
        self.calls = []

    def open(self, request, *, timeout):
        self.calls.append((request.full_url, request.get_method(), timeout))
        if isinstance(self.outcome, BaseException):
            raise self.outcome
        return self.outcome


def test_no_redirect_handler_refuses_to_create_follow_up_request():
    """收到 302 时不得创建访问 Location 的后续请求。"""
    request = urllib.request.Request("https://probe.example.test/check")
    headers = Message()
    headers["Location"] = "https://portal.example.test/login"

    redirected = NoRedirectHandler().redirect_request(
        request,
        None,
        302,
        "Found",
        headers,
        headers["Location"],
    )

    assert redirected is None


def test_http_checker_installs_no_redirect_handler(monkeypatch):
    """默认 HTTP opener 必须安装禁止自动重定向的处理器。"""
    opener = FakeOpener(FakeResponse(204))
    installed_handlers = []

    def fake_build_opener(*handlers):
        installed_handlers.extend(handlers)
        return opener

    monkeypatch.setattr(http_module, "build_opener", fake_build_opener)

    SystemHttpConnectivityChecker()

    assert len(installed_handlers) == 1
    assert isinstance(installed_handlers[0], NoRedirectHandler)


def test_http_checker_converts_204_response(monkeypatch):
    """204 响应应保留状态码、空正文、耗时并关闭响应。"""
    response = FakeResponse(204)
    opener = FakeOpener(response)
    clock_values = iter((10.0, 10.25))
    monkeypatch.setattr(http_module, "perf_counter", lambda: next(clock_values))

    observation = SystemHttpConnectivityChecker(opener).request(
        "https://probe.example.test/check",
        timeout=3.0,
    )

    assert opener.calls == [("https://probe.example.test/check", "GET", 3.0)]
    assert response.closed is True
    assert observation == HttpObservation(
        status_code=204,
        location=None,
        body="",
        elapsed_ms=250.0,
        detail="HTTP 响应已接收",
    )


def test_http_checker_decodes_body_with_bounded_read(monkeypatch):
    """响应正文应按声明字符集解码，并限制单次读取量。"""
    response = FakeResponse(
        200,
        "认证页面".encode("gb18030"),
        content_type="text/html; charset=gb18030",
    )
    opener = FakeOpener(response)
    clock_values = iter((20.0, 20.5))
    monkeypatch.setattr(http_module, "perf_counter", lambda: next(clock_values))

    observation = SystemHttpConnectivityChecker(opener).request(
        "https://probe.example.test/check",
        timeout=3.0,
    )

    assert response.read_sizes == [65_536]
    assert observation.body == "认证页面"
    assert observation.elapsed_ms == 500.0


def test_http_checker_preserves_redirect_response(monkeypatch):
    """禁止跟随后产生的 HTTPError 应作为原始 302 响应保存。"""
    headers = Message()
    headers["Content-Type"] = "text/plain; charset=utf-8"
    headers["Location"] = "https://portal.example.test/login"
    body_stream = io.BytesIO(b"redirect")
    error = urllib.error.HTTPError(
        "https://probe.example.test/check",
        302,
        "Found",
        headers,
        body_stream,
    )
    opener = FakeOpener(error)
    clock_values = iter((30.0, 30.75))
    monkeypatch.setattr(http_module, "perf_counter", lambda: next(clock_values))

    observation = SystemHttpConnectivityChecker(opener).request(
        "https://probe.example.test/check",
        timeout=3.0,
    )

    assert body_stream.closed is True
    assert observation == HttpObservation(
        status_code=302,
        location="https://portal.example.test/login",
        body="redirect",
        elapsed_ms=750.0,
        detail="HTTP 响应已接收",
    )


@pytest.mark.parametrize(
    ("error", "expected_detail"),
    (
        (socket.timeout("不得泄漏的超时细节"), "HTTP 请求超时"),
        (urllib.error.URLError("不得泄漏的 URL 错误细节"), "HTTP 请求失败"),
        (OSError("不得泄漏的系统错误细节"), "HTTP 请求失败"),
    ),
)
def test_http_checker_converts_network_errors_to_observations(
    monkeypatch,
    error,
    expected_detail,
):
    """网络异常应转换为带耗时且不泄漏底层正文的失败观察。"""
    opener = FakeOpener(error)
    clock_values = iter((40.0, 41.25))
    monkeypatch.setattr(http_module, "perf_counter", lambda: next(clock_values))

    observation = SystemHttpConnectivityChecker(opener).request(
        "https://probe.example.test/check",
        timeout=3.0,
    )

    assert observation == HttpObservation(
        status_code=None,
        location=None,
        body="",
        elapsed_ms=1250.0,
        detail=expected_detail,
    )
    assert str(error) not in observation.detail
