from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from urllib.error import URLError

import pytest

from xduwlan.auth.transport import SystemPortalTransport
from xduwlan.errors import PortalNetworkError, PortalProtocolError


@pytest.fixture
def server():
    seen = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            seen.append(('GET', self.path))
            if self.path == '/redirect':
                self.send_response(302)
                self.send_header('Location', '/unvisited')
                self.end_headers()
            else:
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.end_headers()
                self.wfile.write(b'x' * 65537 if self.path == '/large' else b'fictional-response')

        def do_POST(self):
            seen.append(('POST', self.path, self.rfile.read(int(self.headers.get('Content-Length', 0)))))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'fictional-response')

        def log_message(self, *args):
            pass

    httpd = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield f'http://127.0.0.1:{httpd.server_port}', seen
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join()


def test_real_transport_preserves_redirect_and_sends_empty_post(server):
    base, seen = server
    transport = SystemPortalTransport()
    response = transport.request('GET', base + '/redirect', 2)
    assert (response.status_code, response.location) == (302, '/unvisited')
    assert seen == [('GET', '/redirect')]
    assert transport.request('POST', base + '/entry', 2).body == 'fictional-response'
    assert seen[-1] == ('POST', '/entry', b'')


def test_oversized_body_is_not_parsed(server):
    base, _ = server
    with pytest.raises(PortalProtocolError):
        SystemPortalTransport().request('GET', base + '/large', 2)


@pytest.mark.parametrize('error', [TimeoutError('private-marker'), URLError('private-marker'), OSError('private-marker')])
def test_transport_failure_is_safe_and_drops_sensitive_exception_chain(error):
    class FailingOpener:
        def open(self, request, timeout):
            assert timeout == 5
            raise error

    with pytest.raises(PortalNetworkError) as info:
        SystemPortalTransport(FailingOpener()).request('GET', 'https://portal.example.test/?private-marker', 5)
    assert 'private-marker' not in str(info.value)
    assert info.value.__suppress_context__
