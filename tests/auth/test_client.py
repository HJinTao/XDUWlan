from dataclasses import replace
from urllib.parse import parse_qsl, urlsplit
import json

import pytest

from xduwlan.auth.client import SrunPortalClient
from xduwlan.auth.interfaces import PortalContext, PortalResponse
from xduwlan.credentials import Credentials
from xduwlan.errors import AuthenticationRejectedError, PortalNetworkError, PortalProtocolError

PORTAL = 'https://portal.example.test'
ENTRY = 'http://probe.example.test/generate_204'
CONTEXT = PortalContext(PORTAL, '192.0.2.10', '8')
CREDENTIALS = Credentials('student@example.test', 'fictional-password')


class RecordingTransport:
    def __init__(self, replies):
        self.replies = iter(replies)
        self.calls = []

    def request(self, method, url, timeout):
        self.calls.append((method, url, timeout))
        reply = next(self.replies)
        if isinstance(reply, Exception):
            raise reply
        if isinstance(reply, dict):
            callback = dict(parse_qsl(urlsplit(url).query))['callback']
            return PortalResponse(200, callback + '(' + json.dumps(reply) + ');')
        return reply


def client(transport):
    return SrunPortalClient(PORTAL, ENTRY, 5, transport, clock=lambda: 1.234)


def test_prepare_follows_empty_post_and_refresh_without_credentials():
    transport = RecordingTransport([
        PortalResponse(200, '<form method="post" action="http://portal.example.test/index_8.html"></form>'),
        PortalResponse(200, '<meta http-equiv="refresh" content="0;url=/srun_portal_pc?ac_id=8">'),
        PortalResponse(200, 'var CONFIG={ip:"192.0.2.10",acid:"8"};'),
    ])
    assert client(transport).prepare() == CONTEXT
    assert transport.calls == [
        ('GET', ENTRY, 5), ('POST', PORTAL + '/index_8.html', 5),
        ('GET', PORTAL + '/srun_portal_pc?ac_id=8', 5),
    ]


def test_prepare_handles_trusted_redirect_before_parsing_context():
    transport = RecordingTransport([
        PortalResponse(302, '', PORTAL + '/srun_portal_pc'),
        PortalResponse(200, 'var CONFIG={ip:"192.0.2.10",acid:"8"};'),
    ])
    assert client(transport).prepare() == CONTEXT
    assert len(transport.calls) == 2


@pytest.mark.parametrize('reply', [
    PortalResponse(302, '', 'https://attacker.test/?private-marker'),
    PortalResponse(200, '<form method="post" action="https://attacker.test/"></form>'),
    PortalResponse(200, 'var CONFIG={ip:"192.0.2.10",acid:"8"};'),
])
def test_prepare_does_not_trust_unverified_entry_or_follow_unknown_host(reply):
    transport = RecordingTransport([reply])
    with pytest.raises(PortalProtocolError):
        client(transport).prepare()
    assert len(transport.calls) == 1


def test_prepare_bounds_navigation_loops():
    transport = RecordingTransport([PortalResponse(302, '', PORTAL + '/loop')] * 10)
    with pytest.raises(PortalProtocolError):
        client(transport).prepare()
    assert len(transport.calls) <= 6


@pytest.mark.parametrize('success', [{'error': 'ok', 'ecode': 0}, {'code': 0}])
def test_authenticate_sends_one_challenge_then_one_login(success):
    transport = RecordingTransport([
        {'error': 'ok', 'challenge': '0123456789abcdef0123456789abcdef', 'client_ip': CONTEXT.ip}, success,
    ])
    assert client(transport).authenticate(CONTEXT, CREDENTIALS) is None
    assert len(transport.calls) == 2
    first, second = transport.calls
    assert first[0] == second[0] == 'GET'
    assert first[2] == second[2] == 5
    assert urlsplit(first[1]).path == '/cgi-bin/get_challenge'
    assert urlsplit(second[1]).path == '/cgi-bin/srun_portal'
    assert urlsplit(second[1]).netloc == 'portal.example.test'
    challenge_params = dict(parse_qsl(urlsplit(first[1]).query))
    assert list(challenge_params) == ['callback', 'username', 'ip', '_']
    assert challenge_params['username'] == CREDENTIALS.username
    login_params = dict(parse_qsl(urlsplit(second[1]).query))
    assert list(login_params) == ['callback', 'action', 'username', 'password', 'os', 'name', 'double_stack', 'chksum', 'info', 'ac_id', 'ip', 'n', 'type', '_']
    assert login_params['password'].startswith('{MD5}')
    assert CREDENTIALS.password not in second[1]
    assert login_params['ip'] == CONTEXT.ip


@pytest.mark.parametrize('challenge', [
    {'error': 'ok', 'challenge': '', 'client_ip': CONTEXT.ip},
    {'error': 'ok', 'challenge': 'fictional-token', 'client_ip': '192.0.2.11'},
    {'error': 'ok', 'challenge': 123, 'client_ip': CONTEXT.ip},
    {'challenge': 'fictional-token'},
])
def test_invalid_challenge_never_reaches_login(challenge):
    transport = RecordingTransport([challenge])
    with pytest.raises(PortalProtocolError):
        client(transport).authenticate(CONTEXT, CREDENTIALS)
    assert len(transport.calls) == 1


@pytest.mark.parametrize(('reply', 'error'), [
    ({'error': 'fictional-rejection', 'error_msg': 'private-marker'}, AuthenticationRejectedError),
    ({'code': 1, 'message': 'private-marker'}, AuthenticationRejectedError),
    ({'code': True}, PortalProtocolError),
    ({'unknown': 'private-marker'}, PortalProtocolError),
    (PortalResponse(503, 'private-marker'), PortalNetworkError),
    (PortalResponse(302, '', 'https://attacker.test/'), PortalProtocolError),
])
def test_login_errors_are_distinct_and_safe_without_retry(reply, error):
    transport = RecordingTransport([
        {'error': 'ok', 'challenge': 'fictional-token', 'client_ip': CONTEXT.ip}, reply,
    ])
    with pytest.raises(error) as info:
        client(transport).authenticate(CONTEXT, CREDENTIALS)
    assert 'private-marker' not in str(info.value)
    assert len(transport.calls) == 2


def test_context_for_other_host_is_rejected_before_any_request():
    transport = RecordingTransport([])
    with pytest.raises(PortalProtocolError):
        client(transport).authenticate(replace(CONTEXT, portal_url='https://attacker.test'), CREDENTIALS)
    assert transport.calls == []
