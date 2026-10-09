"""离线贯穿实际 CLI、应用服务、入口解析和编码的纵向验证。"""

import json
from urllib.parse import parse_qs, urlsplit

from xduwlan.auth.client import SrunPortalClient
from xduwlan.auth.interfaces import PortalResponse
from xduwlan.cli import main
from xduwlan.credentials import Credentials
from xduwlan.login_service import DefaultLoginService
from xduwlan.models import NetworkProbeResult, NetworkState


def test_cli_recovers_through_real_services_with_fictional_external_boundaries(monkeypatch, capsys):
    events = []
    states = iter([NetworkState.PORTAL_REQUIRED, NetworkState.ONLINE])

    class Probe:
        def probe(self):
            events.append('probe')
            return NetworkProbeResult(next(states), ())

    class Store:
        def load(self):
            events.append('load')
            return Credentials('student@example.test', 'fictional-password')

    class Transport:
        def request(self, method, url, timeout):
            events.append((method, urlsplit(url).path))
            assert timeout == 5
            parsed = urlsplit(url)
            if parsed.hostname == 'probe.example.test':
                return PortalResponse(200, '<form method="post" action="http://portal.example.test/index_8.html"></form>')
            assert parsed.scheme == 'https'
            assert parsed.hostname == 'portal.example.test'
            if parsed.path == '/index_8.html':
                assert method == 'POST'
                return PortalResponse(200, '<meta http-equiv="refresh" content="0;url=/srun_portal_pc">')
            if parsed.path == '/srun_portal_pc':
                return PortalResponse(200, 'var CONFIG={ip:"192.0.2.10",acid:"8"};')
            query = parse_qs(parsed.query)
            body = {'error': 'ok'}
            if parsed.path == '/cgi-bin/get_challenge':
                body.update(challenge='fictional-token', client_ip='192.0.2.10')
            else:
                assert query['password'][0].startswith('{MD5}')
                assert 'fictional-password' not in url
                assert query['username'] == ['student@example.test']
            return PortalResponse(200, query['callback'][0] + '(' + json.dumps(body) + ')')

    portal = SrunPortalClient('https://portal.example.test', 'http://probe.example.test/check', 5, Transport())
    monkeypatch.setattr('xduwlan.cli.build_login_service', lambda config: DefaultLoginService(Probe(), Store(), portal))
    assert main(['login', '--json', '--debug']) == 0
    output = capsys.readouterr().out
    assert json.loads(output)['state'] == 'restored'
    assert 'fictional-token' not in output
    assert 'student@example.test' not in output
    assert '192.0.2.10' not in output
    assert events == ['probe', ('GET', '/check'), ('POST', '/index_8.html'),
        ('GET', '/srun_portal_pc'), 'load', ('GET', '/cgi-bin/get_challenge'),
        ('GET', '/cgi-bin/srun_portal'), 'probe']
