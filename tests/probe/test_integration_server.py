from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread

import pytest

from xduwlan.models import NetworkState
from xduwlan.probe.classifier import classify_http_observation
from xduwlan.probe.http import SystemHttpConnectivityChecker


class ConnectivityHandler(BaseHTTPRequestHandler):
    """返回连通性探测需要的三种本地 HTTP 响应。"""

    def do_GET(self):
        self.server.received_paths.append(self.path)

        if self.path == "/online":
            self.send_response(204)
            self.end_headers()
            return

        if self.path == "/portal":
            location = f"http://127.0.0.1:{self.server.server_port}/login"
            self.send_response(302)
            self.send_header("Location", location)
            self.end_headers()
            return

        if self.path == "/login":
            body = b'<html><form id="srun_portal"></form></html>'
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, format_string, *args):
        """禁止测试服务器向终端输出访问日志。"""


@pytest.fixture
def local_http_server():
    """在 loopback 临时端口启动服务器，并在测试后完整清理。"""
    server = ThreadingHTTPServer(("127.0.0.1", 0), ConnectivityHandler)
    server.received_paths = []
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f"http://127.0.0.1:{server.server_port}"

    try:
        yield server, base_url
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        assert thread.is_alive() is False


def test_local_204_response_is_online(local_http_server):
    """真实 urllib 收到本地 204 时应观察并分类为已联网。"""
    server, base_url = local_http_server

    observation = SystemHttpConnectivityChecker().request(
        f"{base_url}/online",
        timeout=2.0,
    )
    state = classify_http_observation(observation, frozenset())

    assert observation.status_code == 204
    assert observation.location is None
    assert observation.body == ""
    assert state is NetworkState.ONLINE
    assert server.received_paths == ["/online"]


def test_local_redirect_is_preserved_without_following(local_http_server):
    """真实 urllib 应保留本地 302，且不得继续请求登录页。"""
    server, base_url = local_http_server

    observation = SystemHttpConnectivityChecker().request(
        f"{base_url}/portal",
        timeout=2.0,
    )
    state = classify_http_observation(
        observation,
        frozenset({"127.0.0.1"}),
    )

    assert observation.status_code == 302
    assert observation.location == f"{base_url}/login"
    assert state is NetworkState.PORTAL_REQUIRED
    assert server.received_paths == ["/portal"]


def test_local_srun_page_requires_authentication(local_http_server):
    """真实 urllib 收到深澜特征页面时应分类为需要认证。"""
    server, base_url = local_http_server

    observation = SystemHttpConnectivityChecker().request(
        f"{base_url}/login",
        timeout=2.0,
    )
    state = classify_http_observation(observation, frozenset())

    assert observation.status_code == 200
    assert "srun_portal" in observation.body
    assert state is NetworkState.PORTAL_REQUIRED
    assert server.received_paths == ["/login"]
