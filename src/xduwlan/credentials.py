"""认证凭据模型与存储端口。"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol


@dataclass(frozen=True)
class Credentials:
    """保存校园网账号与密码，并避免在调试表示中泄漏字段。"""

    username: str = field(repr=False)
    password: str = field(repr=False)


class CredentialStore(Protocol):
    """声明上层调用方需要的凭据保存与读取能力。"""

    def save(self, credentials: Credentials) -> None:
        """安全保存一组凭据。"""
        ...

    def load(self) -> Credentials | None:
        """读取已保存凭据；尚未配置时返回 ``None``。"""
        ...
