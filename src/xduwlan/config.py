"""非敏感 TOML 配置的领域入口。"""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path

from xduwlan.errors import ConfigurationError


@dataclass(frozen=True)
class AppConfig:
    """保存应用运行所需的非敏感配置。

    该类型只负责默认值、TOML 合并和字段校验，不读取密码或会话凭据。
    """

    portal_url: str
    probe_url: str
    probe_interval_seconds: float
    request_timeout_seconds: float
    operator_suffix: str
    log_level: str

    @classmethod
    def defaults(cls) -> AppConfig:
        """返回不包含密码、Cookie 等敏感信息的默认配置。"""
        return cls(
            portal_url="https://w.xidian.edu.cn",
            probe_url="http://connectivitycheck.gstatic.com/generate_204",
            probe_interval_seconds=30,
            request_timeout_seconds=5,
            operator_suffix="",
            log_level="INFO",
        )

    @classmethod
    def load(cls, path: Path) -> AppConfig:
        """从 ``path`` 读取 TOML，合并默认值并校验已知字段。

        未知字段应忽略；非法数值或类型应转换为
        ``xduwlan.errors.ConfigurationError``。底层异常需要保留异常链。
        """
        text = path.read_text(encoding="utf-8")
        try:
            data = tomllib.loads(text)
        except tomllib.TOMLDecodeError as exc:
            raise ConfigurationError("配置文件不是有效的 TOML") from exc

        defaults = cls.defaults()
        probe_interval_seconds = data.get(
            "probe_interval_seconds",
            defaults.probe_interval_seconds,
        )
        request_timeout_seconds = data.get(
            "request_timeout_seconds",
            defaults.request_timeout_seconds,
        )

        for field_name, value in (
            ("probe_interval_seconds", probe_interval_seconds),
            ("request_timeout_seconds", request_timeout_seconds),
        ):
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ConfigurationError(f"{field_name} 必须是数字")
            if value <= 0:
                raise ConfigurationError(f"{field_name} 必须大于 0")

        return cls(
            portal_url=data.get("portal_url", defaults.portal_url),
            probe_url=data.get("probe_url", defaults.probe_url),
            probe_interval_seconds=probe_interval_seconds,
            request_timeout_seconds=request_timeout_seconds,
            operator_suffix=data.get("operator_suffix", defaults.operator_suffix),
            log_level=data.get("log_level", defaults.log_level),
        )
