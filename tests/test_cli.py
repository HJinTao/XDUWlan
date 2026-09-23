import getpass
import json
import warnings
from pathlib import Path

import pytest

from xduwlan.cli import build_credential_configurator, build_network_probe, main
from xduwlan.config import AppConfig
from xduwlan.credential_service import DefaultCredentialConfigurator
from xduwlan.errors import (
    ConfigurationError,
    CredentialStoreError,
    CredentialValidationError,
)
from xduwlan.keyring_store import KeyringCredentialStore
from xduwlan.models import NetworkProbeResult, NetworkState, ProbeObservation, ProbeStage
from xduwlan.probe.dns import SystemDnsResolver
from xduwlan.probe.http import SystemHttpConnectivityChecker
from xduwlan.probe.service import DefaultNetworkProbe
from xduwlan.probe.tcp import SystemTcpConnector


def test_main_without_command_prints_help(capsys):
    """无命令时应展示可用子命令，并以成功状态结束。"""
    assert main([]) == 0

    output = capsys.readouterr().out
    assert "status" in output
    assert "login" in output
    assert "watch" in output
    assert "account" in output
    assert "configure" in output


def test_unknown_command_uses_argparse_error_exit():
    """未知命令交给 argparse 处理，并使用约定的退出码 2。"""
    try:
        main(["not-a-command"])
    except SystemExit as exc:
        assert exc.code == 2
    else:
        raise AssertionError("未知命令必须触发 argparse 的 SystemExit(2)")


@pytest.mark.parametrize("command", ["login", "watch", "account"])
def test_registered_command_returns_success(command):
    """未接入的命令仍使用任务一的最小处理器。"""
    assert main([command]) == 0


def test_status_online_returns_zero_and_prints_chinese_state(monkeypatch, capsys):
    """status 应使用默认配置和探测结果输出已联网，不访问真实网络。"""
    configurations = []

    class FakeOnlineProbe:
        def probe(self):
            return NetworkProbeResult(
                state=NetworkState.ONLINE,
                observations=(
                    ProbeObservation(ProbeStage.HTTP, True, 3.0, "响应已接收"),
                ),
            )

    def fake_build_network_probe(config):
        configurations.append(config)
        return FakeOnlineProbe()

    monkeypatch.setattr("xduwlan.cli.build_network_probe", fake_build_network_probe)

    assert main(["status"]) == 0
    assert configurations == [AppConfig.defaults()]
    assert "已联网" in capsys.readouterr().out


@pytest.mark.parametrize(
    ("state", "expected_text", "expected_exit_code"),
    [
        (NetworkState.PORTAL_REQUIRED, "需要认证", 4),
        (NetworkState.LOCAL_NETWORK_DOWN, "本地网络不可用", 5),
        (NetworkState.INTERNET_UNREACHABLE, "互联网不可达", 5),
        (NetworkState.UNKNOWN, "无法确定网络状态", 1),
    ],
)
def test_status_maps_non_online_states_to_text_and_exit_code(
    state,
    expected_text,
    expected_exit_code,
    monkeypatch,
    capsys,
):
    """status 应把领域状态转换为稳定的中文摘要与进程退出码。"""

    class FakeProbe:
        def probe(self):
            return NetworkProbeResult(state=state, observations=())

    monkeypatch.setattr(
        "xduwlan.cli.build_network_probe",
        lambda config: FakeProbe(),
    )

    assert main(["status"]) == expected_exit_code
    assert expected_text in capsys.readouterr().out


def test_status_loads_explicit_config_path(monkeypatch, tmp_path, capsys):
    """--config 应通过 Path 读取指定 TOML，并把结果交给探测器。"""
    config_path = tmp_path / "xduwlan.toml"
    loaded_config = AppConfig.defaults()
    loaded_paths = []
    probe_configs = []

    def fake_load(path):
        loaded_paths.append(path)
        return loaded_config

    class FakeProbe:
        def probe(self):
            return NetworkProbeResult(NetworkState.ONLINE, ())

    monkeypatch.setattr(AppConfig, "load", fake_load)
    monkeypatch.setattr(
        "xduwlan.cli.build_network_probe",
        lambda config: probe_configs.append(config) or FakeProbe(),
    )

    assert main(["status", "--config", str(config_path)]) == 0
    assert loaded_paths == [Path(config_path)]
    assert probe_configs == [loaded_config]
    assert "已联网" in capsys.readouterr().out


@pytest.mark.parametrize(
    "error",
    [
        ConfigurationError("private-marker"),
        FileNotFoundError("private-marker"),
    ],
)
def test_status_config_error_returns_two_without_leaking_details(
    error,
    monkeypatch,
    capsys,
):
    """配置内容或文件读取失败都应安全转换为退出码 2。"""

    def fake_load(path):
        raise error

    monkeypatch.setattr(AppConfig, "load", fake_load)

    assert main(["status", "--config", "missing.toml"]) == 2
    captured = capsys.readouterr()
    assert "配置" in captured.err
    assert "private-marker" not in captured.err


@pytest.mark.parametrize(
    "extra_args",
    [("--json",), ("--json", "--debug")],
)
def test_status_json_is_structured_and_omits_sensitive_fields(
    extra_args,
    monkeypatch,
    capsys,
):
    """JSON 只公开状态、阶段成功和耗时，即使同时启用 debug。"""
    result = NetworkProbeResult(
        state=NetworkState.PORTAL_REQUIRED,
        observations=(
            ProbeObservation(
                ProbeStage.HTTP,
                True,
                3.25,
                "private-marker",
            ),
        ),
        portal_url="https://portal.example.test/?note=private-marker",
    )

    class FakeProbe:
        def probe(self):
            return result

    monkeypatch.setattr(
        "xduwlan.cli.build_network_probe",
        lambda config: FakeProbe(),
    )

    assert main(["status", *extra_args]) == 4
    output = capsys.readouterr().out
    assert json.loads(output) == {
        "state": "portal_required",
        "observations": [
            {
                "stage": "http",
                "succeeded": True,
                "elapsed_ms": 3.25,
            },
        ],
    }
    assert "private-marker" not in output


def test_status_debug_prints_safe_stage_details(monkeypatch, capsys):
    """文本 debug 模式应在摘要后展示已脱敏的阶段观察。"""
    result = NetworkProbeResult(
        state=NetworkState.ONLINE,
        observations=(
            ProbeObservation(ProbeStage.DNS, True, 1.25, "DNS 解析成功"),
        ),
    )

    class FakeProbe:
        def probe(self):
            return result

    monkeypatch.setattr(
        "xduwlan.cli.build_network_probe",
        lambda config: FakeProbe(),
    )

    assert main(["status", "--debug"]) == 0
    output = capsys.readouterr().out
    assert "已联网" in output
    assert "dns" in output
    assert "成功" in output
    assert "1.25" in output
    assert "DNS 解析成功" in output


def test_build_network_probe_wires_system_adapters():
    """CLI 装配边界应组合默认服务和三个系统阶段适配器。"""
    config = AppConfig.defaults()

    probe = build_network_probe(config)

    assert isinstance(probe, DefaultNetworkProbe)
    assert probe._config is config
    assert isinstance(probe._dns_resolver, SystemDnsResolver)
    assert isinstance(probe._tcp_connector, SystemTcpConnector)
    assert isinstance(probe._http_checker, SystemHttpConnectivityChecker)


def test_configure_collects_and_delegates_without_echoing_values(
    monkeypatch,
    capsys,
):
    """CLI 应收集原始输入、交给应用服务并只输出安全摘要。"""
    prompts = []
    calls = []

    class RecordingConfigurator:
        def configure(self, username, password):
            calls.append((username, password))

    def fake_input(prompt):
        prompts.append(prompt)
        return "  student@example.test  "

    def fake_getpass(prompt):
        prompts.append(prompt)
        return " fictional-password "

    monkeypatch.setattr("builtins.input", fake_input)
    monkeypatch.setattr("xduwlan.cli.getpass.getpass", fake_getpass)
    monkeypatch.setattr(
        "xduwlan.cli.build_credential_configurator",
        lambda: RecordingConfigurator(),
    )

    assert main(["configure"]) == 0
    assert calls == [("  student@example.test  ", " fictional-password ")]
    assert any("账号" in prompt for prompt in prompts)
    assert any("密码" in prompt for prompt in prompts)

    captured = capsys.readouterr()
    assert "保存" in captured.out
    assert "student@example.test" not in captured.out + captured.err
    assert "fictional-password" not in captured.out + captured.err


@pytest.mark.parametrize(
    ("error", "expected_exit_code"),
    [
        (CredentialValidationError("private-marker"), 2),
        (CredentialStoreError("private-marker"), 1),
    ],
)
def test_configure_maps_project_errors_without_leaking_details(
    error,
    expected_exit_code,
    monkeypatch,
    capsys,
):
    """输入和存储失败应映射为稳定退出码与安全错误摘要。"""

    class FailingConfigurator:
        def configure(self, username, password):
            raise error

    monkeypatch.setattr("builtins.input", lambda prompt: "student@example.test")
    monkeypatch.setattr(
        "xduwlan.cli.getpass.getpass",
        lambda prompt: "fictional-password",
    )
    monkeypatch.setattr(
        "xduwlan.cli.build_credential_configurator",
        lambda: FailingConfigurator(),
    )

    assert main(["configure"]) == expected_exit_code
    captured = capsys.readouterr()
    assert "凭据" in captured.err
    assert "private-marker" not in captured.out + captured.err
    assert "student@example.test" not in captured.out + captured.err
    assert "fictional-password" not in captured.out + captured.err


@pytest.mark.parametrize("error", [EOFError(), KeyboardInterrupt()])
def test_configure_handles_cancelled_input_without_building_service(
    error,
    monkeypatch,
    capsys,
):
    """关闭输入或主动中断时应安全退出，且不装配外部依赖。"""

    def cancel_input(prompt):
        raise error

    def unexpected_call(*args, **kwargs):
        raise AssertionError("取消输入后不应继续调用其他边界")

    monkeypatch.setattr("builtins.input", cancel_input)
    monkeypatch.setattr("xduwlan.cli.getpass.getpass", unexpected_call)
    monkeypatch.setattr(
        "xduwlan.cli.build_credential_configurator",
        unexpected_call,
    )

    assert main(["configure"]) == 130
    captured = capsys.readouterr()
    assert "取消" in captured.err


def test_configure_fails_when_password_cannot_be_hidden(monkeypatch, capsys):
    """终端无法关闭回显时不得退化为可能泄漏密码的普通输入。"""

    def unsafe_getpass(prompt):
        warnings.warn("private-marker", category=getpass.GetPassWarning)
        return "fictional-password"

    def unexpected_call(*args, **kwargs):
        raise AssertionError("无法隐藏密码时不应装配应用服务")

    monkeypatch.setattr("builtins.input", lambda prompt: "student@example.test")
    monkeypatch.setattr("xduwlan.cli.getpass.getpass", unsafe_getpass)
    monkeypatch.setattr(
        "xduwlan.cli.build_credential_configurator",
        unexpected_call,
    )

    assert main(["configure"]) == 1
    captured = capsys.readouterr()
    assert "隐藏" in captured.err
    assert "private-marker" not in captured.out + captured.err
    assert "fictional-password" not in captured.out + captured.err


def test_build_credential_configurator_wires_service_and_keyring_adapter():
    """CLI 装配边界应组合应用服务与系统凭据库适配器。"""
    configurator = build_credential_configurator()

    assert isinstance(configurator, DefaultCredentialConfigurator)
    assert isinstance(configurator._store, KeyringCredentialStore)
