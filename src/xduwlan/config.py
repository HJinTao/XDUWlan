"""非敏感 TOML 配置的领域入口。"""

from __future__ import annotations

import tomllib
import math
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit

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
            probe_url="https://connect.rom.miui.com/generate_204",
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
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeError:
            raise ConfigurationError("配置文件不是有效的 UTF-8") from None
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
            if not math.isfinite(value) or value <= 0:
                raise ConfigurationError(f"{field_name} 必须大于 0")

        values = {}
        for name in ("portal_url", "probe_url", "operator_suffix", "log_level"):
            value = data.get(name, getattr(defaults, name))
            if not isinstance(value, str):
                raise ConfigurationError(f"{name} 必须是字符串")
            values[name] = value
        for name in ("portal_url", "probe_url"):
            value = values[name]
            try:
                parsed = urlsplit(value)
                if (not parsed.hostname or parsed.scheme not in ("http", "https")
                        or parsed.username is not None or parsed.password is not None
                        or parsed.fragment or "\\" in value or any(ord(c) < 33 for c in value)):
                    raise ValueError
                port = parsed.port
                if name == "portal_url" and (parsed.scheme != "https" or port not in (None, 443) or parsed.query):
                    raise ValueError
            except ValueError:
                raise ConfigurationError(f"{name} 地址无效") from None

        return cls(
            portal_url=values["portal_url"],
            probe_url=values["probe_url"],
            probe_interval_seconds=probe_interval_seconds,
            request_timeout_seconds=request_timeout_seconds,
            operator_suffix=values["operator_suffix"],
            log_level=values["log_level"],
        )
