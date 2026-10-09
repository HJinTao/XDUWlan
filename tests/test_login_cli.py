import json
from dataclasses import replace

import pytest

from xduwlan.cli import main, build_login_service, build_network_probe
from xduwlan.config import AppConfig
from xduwlan.login_service import LoginResult, LoginState
from xduwlan.models import NetworkState, ProbeObservation, ProbeStage


@pytest.mark.parametrize(('state', 'code', 'word'), [
    (LoginState.ALREADY_ONLINE, 0, '已联网'), (LoginState.RESTORED, 0, '恢复'),
    (LoginState.CREDENTIALS_MISSING, 3, 'configure'), (LoginState.CREDENTIALS_INVALID, 2, 'configure'),
    (LoginState.CREDENTIAL_STORE_FAILED, 1, '凭据库'),
    (LoginState.UNKNOWN_NETWORK, 1, '无法确认'), (LoginState.NETWORK_UNAVAILABLE, 5, '网络'),
    (LoginState.AUTH_REJECTED, 6, '拒绝'), (LoginState.PORTAL_UNAVAILABLE, 5, 'Portal'),
    (LoginState.PROTOCOL_ERROR, 7, '协议'), (LoginState.VERIFICATION_FAILED, 8, '验证'),
])
def test_login_results_provide_safe_text_and_stable_exit_codes(state, code, word, monkeypatch, capsys):
    class Service:
        def login(self):
            return LoginResult(state, NetworkState.UNKNOWN, ())

    monkeypatch.setattr('xduwlan.cli.build_login_service', lambda config: Service())
    assert main(['login']) == code
    captured = capsys.readouterr()
    assert word in captured.out + captured.err


@pytest.mark.parametrize('args', [['login', '--json'], ['login', '--json', '--debug'], ['login', '--debug']])
def test_login_output_omits_private_observation_details(args, monkeypatch, capsys):
    class Service:
        def login(self):
            return LoginResult(LoginState.RESTORED, NetworkState.ONLINE,
                (ProbeObservation(ProbeStage.HTTP, True, 1.5, 'private-marker'),))

    monkeypatch.setattr('xduwlan.cli.build_login_service', lambda config: Service())
    assert main(args) == 0
    output = capsys.readouterr().out
    assert 'private-marker' not in output
    if '--json' in args:
        assert json.loads(output) == {'state': 'restored', 'network_state': 'online',
            'observations': [{'stage': 'http', 'succeeded': True, 'elapsed_ms': 1.5}]}
    else:
        assert 'http' in output


def test_login_invalid_config_never_builds_or_runs_service(tmp_path, monkeypatch, capsys):
    def unexpected(*args):
        raise AssertionError('错误配置不应装配或运行网络服务')

    monkeypatch.setattr('xduwlan.cli.build_login_service', unexpected)
    assert main(['login', '--config', str(tmp_path / 'missing.toml')]) == 2
    assert '配置' in capsys.readouterr().err


def test_login_loads_explicit_config_and_handles_interrupt(tmp_path, monkeypatch, capsys):
    path = tmp_path / 'config.toml'
    path.write_text('request_timeout_seconds=7\n')
    seen = []

    class Service:
        def login(self):
            raise KeyboardInterrupt

    def builder(config):
        seen.append(config.request_timeout_seconds)
        return Service()

    monkeypatch.setattr('xduwlan.cli.build_login_service', builder)
    assert main(['login', '--config', str(path)]) == 130
    assert seen == [7]
    assert '取消' in capsys.readouterr().err


def test_login_builder_does_not_access_real_network_or_keyring():
    service = build_login_service(AppConfig.defaults())
    assert callable(service.login)


def test_cli_builder_wires_http_discovery_for_https_probe():
    probe = build_network_probe(AppConfig.defaults())
    assert probe._fallback_probe._config.probe_url == 'http://connect.rom.miui.com/generate_204'
    probe = build_network_probe(replace(AppConfig.defaults(), probe_url='http://probe.example.test/check'))
    assert probe._fallback_probe is None
