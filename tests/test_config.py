import tomllib

import tomllib
from dataclasses import FrozenInstanceError
from pathlib import Path

import pytest

from xduwlan.config import AppConfig
from xduwlan.errors import ConfigurationError


def test_default_config_has_explicit_operational_values():
    """默认配置应提供可用且有界的周期、超时和日志等级。"""
    config = AppConfig.defaults()

    assert config.portal_url.startswith(("http://", "https://"))
    assert config.probe_url == "https://connect.rom.miui.com/generate_204"
    assert config.probe_interval_seconds == 30
    assert config.request_timeout_seconds == 5
    assert config.operator_suffix == ""
    assert config.log_level == "INFO"


def test_config_is_immutable_after_creation():
    """配置创建后不能被调用方绕过加载和校验流程直接修改。"""
    config = AppConfig.defaults()

    with pytest.raises(FrozenInstanceError):
        config.request_timeout_seconds = 60


def test_empty_toml_uses_all_defaults(tmp_path: Path):
    """空 TOML 文件应与直接调用 defaults 得到相同配置。"""
    path = tmp_path / "config.toml"
    path.write_text("", encoding="utf-8")

    assert AppConfig.load(path) == AppConfig.defaults()


def test_partial_toml_overrides_known_fields_and_keeps_other_defaults(tmp_path: Path):
    """部分配置只覆盖给定字段，未提供字段继续使用默认值。"""
    path = tmp_path / "config.toml"
    path.write_text(
        'probe_interval_seconds = 45\nlog_level = "DEBUG"\n',
        encoding="utf-8",
    )

    config = AppConfig.load(path)
    defaults = AppConfig.defaults()

    assert config.probe_interval_seconds == 45
    assert config.log_level == "DEBUG"
    assert config.request_timeout_seconds == defaults.request_timeout_seconds
    assert config.portal_url == defaults.portal_url


def test_unknown_toml_fields_are_ignored(tmp_path: Path):
    """较新版本写入的未知字段不应阻止当前版本读取配置。"""
    path = tmp_path / "config.toml"
    path.write_text('future_option = "ignored"\n', encoding="utf-8")

    assert AppConfig.load(path) == AppConfig.defaults()


def test_malformed_toml_is_wrapped_and_preserves_cause(tmp_path: Path):
    """TOML 语法错误应转换为配置错误，并保留原始解析异常。"""
    path = tmp_path / "config.toml"
    path.write_text("request_timeout_seconds = [", encoding="utf-8")

    with pytest.raises(ConfigurationError) as exc_info:
        AppConfig.load(path)

    assert isinstance(exc_info.value.__cause__, tomllib.TOMLDecodeError)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("probe_interval_seconds", "0"),
        ("probe_interval_seconds", "-1"),
        ("request_timeout_seconds", "0"),
        ("request_timeout_seconds", "-0.5"),
    ],
)
def test_non_positive_numeric_config_is_rejected(
    tmp_path: Path,
    field: str,
    value: str,
):
    """周期和超时为零或负数时应给出统一的配置错误。"""
    path = tmp_path / "config.toml"
    path.write_text(f"{field} = {value}\n", encoding="utf-8")

    with pytest.raises(ConfigurationError):
        AppConfig.load(path)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("probe_interval_seconds", '"five"'),
        ("probe_interval_seconds", "true"),
        ("request_timeout_seconds", '"five"'),
        ("request_timeout_seconds", "true"),
    ],
)
def test_invalid_numeric_type_is_rejected_as_configuration_error(
    tmp_path: Path,
    field: str,
    value: str,
):
    """数值字段写成字符串或布尔值时应给出统一配置错误。"""
    path = tmp_path / "config.toml"
    path.write_text(f"{field} = {value}\n", encoding="utf-8")

    with pytest.raises(ConfigurationError):
        AppConfig.load(path)
