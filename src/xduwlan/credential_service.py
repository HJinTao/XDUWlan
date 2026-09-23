"""校园网凭据配置应用服务。"""

from __future__ import annotations

from typing import Protocol

from xduwlan.credentials import CredentialStore, Credentials
from xduwlan.errors import CredentialValidationError


class CredentialConfigurator(Protocol):
    """声明 CLI 所需的凭据配置能力。"""

    def configure(self, username: str, password: str) -> None:
        """校验并保存一组用户输入的凭据。"""
        ...


class DefaultCredentialConfigurator:
    """校验用户输入，并通过凭据存储端口长期保存。"""

    def __init__(self, store: CredentialStore) -> None:
        self._store = store

    def configure(self, username: str, password: str) -> None:
        """整理账号、校验输入并保存凭据。"""
        username = username.strip()
        if not username or password == "":
            raise CredentialValidationError
        return self._store.save(Credentials(username, password))
