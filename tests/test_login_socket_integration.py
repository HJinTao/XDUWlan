"""用真实 loopback HTTP/TLS 验证完整恢复链，所有输入均为虚构数据。"""

import json
import shutil
import ssl
import subprocess
from dataclasses import replace
from http.client import HTTPSConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from urllib.parse import parse_qs, urlsplit
from urllib.request import HTTPSHandler, ProxyHandler, build_opener

import pytest

from xduwlan.auth.client import SrunPortalClient
from xduwlan.auth.transport import SystemPortalTransport
from xduwlan.cli import main
from xduwlan.config import AppConfig
from xduwlan.credentials import Credentials
from xduwlan.keyring_store import KeyringCredentialStore
from xduwlan.login_service import DefaultLoginService
from xduwlan.probe.dns import SystemDnsResolver
from xduwlan.probe.http import NoRedirectHandler, SystemHttpConnectivityChecker
from xduwlan.probe.service import DefaultNetworkProbe
from xduwlan.probe.tcp import SystemTcpConnector


@pytest.mark.skipif(shutil.which('openssl') is None, reason='本地 TLS 集成验证需要 openssl')
@pytest.mark.parametrize(('scenario', 'expected_state', 'expected_exit'), [
    ('success', 'restored', 0),
    ('rejected', 'auth_rejected', 6),
    ('verification-failed', 'verification_failed', 8),
])
def test_real_http_tls_probe_authentication_and_cli(scenario, expected_state, expected_exit, tmp_path, monkeypatch, capsys):
    """真实探测与传输必须协作；拒绝或联网复查失败不得输出恢复成功。"""
    vector = json.loads((Path(__file__).parent / 'auth/vectors.json').read_text(encoding='utf-8'))[0]
    certificate, private_key = tmp_path / 'localhost.crt', tmp_path / 'localhost.key'
    subprocess.run([
        shutil.which('openssl'), 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
        '-keyout', str(private_key), '-out', str(certificate), '-days', '1',
        '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
    ], capture_output=True, check=True)
    observed = {'online': False, 'login_requests': 0, 'challenge_requests': 0, 'credential_reads': 0}
    paths = []

    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, body=''):
            encoded = body.encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

        def do_GET(self):
            parsed = urlsplit(self.path)
            paths.append(('GET', parsed.path))
            if parsed.path == '/check':
                if observed['online']:
                    self.reply(204)
                else:
                    self.reply(200, '<form method="post" action="https://localhost/index_8.html"></form>')
            elif parsed.path == '/srun_portal_pc':
                self.reply(200, 'var CONFIG={ip:"192.0.2.10",acid:"8"};')
            elif parsed.path in ('/cgi-bin/get_challenge', '/cgi-bin/srun_portal'):
                query = parse_qs(parsed.query)
                if parsed.path == '/cgi-bin/get_challenge':
                    observed['challenge_requests'] += 1
                    data = {'error': 'ok', 'challenge': vector['challenge'], 'client_ip': vector['ip']}
                else:
                    observed['login_requests'] += 1
                    observed['encoded_request_correct'] = (
                        query.get('username') == [vector['username']]
                        and query.get('password') == ['{MD5}' + vector['hmd5']]
                        and query.get('info') == [vector['info']]
                        and query.get('chksum') == [vector['checksum']]
                        and query.get('ac_id') == ['8']
                        and query.get('ip') == ['192.0.2.10']
                    )
                    if scenario == 'success':
                        observed['online'] = True
                    data = {'error': 'fictional-rejection'} if scenario == 'rejected' else {'error': 'ok'}
                self.reply(200, query['callback'][0] + '(' + json.dumps(data) + ');')
            else:
                self.reply(404)

        def do_POST(self):
            paths.append(('POST', self.path))
            observed['empty_post'] = self.rfile.read(int(self.headers.get('Content-Length', 0))) == b''
            self.reply(200, '<meta http-equiv="refresh" content="0;url=/srun_portal_pc">')

        def log_message(self, *args):
            """协议字段与虚构认证参数也不写入访问日志。"""

    http_server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    tls_server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_context.load_cert_chain(certificate, private_key)
    tls_server.socket = server_context.wrap_socket(tls_server.socket, server_side=True)
    servers = (http_server, tls_server)
    threads = [Thread(target=server.serve_forever, daemon=True) for server in servers]
    for thread in threads:
        thread.start()

    class LocalHttpsHandler(HTTPSHandler):
        def https_open(self, request):
            """仅将默认 HTTPS 端口映射到临时 loopback，保持证书与主机验证。"""
            def connection(host, **kwargs):
                assert host == 'localhost'
                return HTTPSConnection('localhost', port=tls_server.server_port, **kwargs)
            return self.do_open(connection, request, context=self._context)

    class MemoryBackend:
        def set_password(self, service, username, password):
            self.record = password

        def get_password(self, service, username):
            observed['credential_reads'] += 1
            return self.record

    try:
        config = replace(AppConfig.defaults(), portal_url='https://localhost',
            probe_url=f'http://127.0.0.1:{http_server.server_port}/check', request_timeout_seconds=2)
        checker = SystemHttpConnectivityChecker(build_opener(ProxyHandler({}), NoRedirectHandler()))
        probe = DefaultNetworkProbe(config, SystemDnsResolver(), SystemTcpConnector(), checker)
        client_context = ssl.create_default_context(cafile=str(certificate))
        assert client_context.check_hostname
        assert client_context.verify_mode == ssl.CERT_REQUIRED
        transport = SystemPortalTransport(build_opener(
            ProxyHandler({}), NoRedirectHandler(), LocalHttpsHandler(context=client_context)))
        portal = SrunPortalClient(config.portal_url, config.probe_url, 2, transport)
        store = KeyringCredentialStore(MemoryBackend())
        store.save(Credentials(vector['username'], vector['password']))
        service = DefaultLoginService(probe, store, portal)
        monkeypatch.setattr('xduwlan.cli.build_login_service', lambda config: service)
        assert main(['login', '--json']) == expected_exit
        output = capsys.readouterr().out
        assert json.loads(output)['state'] == expected_state
        assert observed['empty_post']
        assert observed['encoded_request_correct']
        assert observed['credential_reads'] == 1
        assert observed['challenge_requests'] == observed['login_requests'] == 1
        assert paths[:6] == [('GET', '/check'), ('GET', '/check'), ('POST', '/index_8.html'),
            ('GET', '/srun_portal_pc'), ('GET', '/cgi-bin/get_challenge'), ('GET', '/cgi-bin/srun_portal')]
        if scenario != 'rejected':
            assert paths[-1] == ('GET', '/check')
        for sensitive in (vector['username'], vector['password'], vector['challenge'], vector['ip'], vector['info']):
            assert sensitive not in output
        if scenario == 'success':
            assert main(['login', '--json']) == 0
            assert json.loads(capsys.readouterr().out)['state'] == 'already_online'
            assert observed['credential_reads'] == 1
            assert observed['challenge_requests'] == observed['login_requests'] == 1
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
        for thread in threads:
            thread.join(timeout=3)
            assert not thread.is_alive()
