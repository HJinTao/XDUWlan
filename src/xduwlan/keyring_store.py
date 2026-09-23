"""使用系统凭据库保存校园网凭据的适配器。"""

from __future__ import annotations

import json
from typing import Protocol

from keyring.errors import KeyringError

from xduwlan.credentials import Credentials
from xduwlan.errors import CredentialStoreError

KEYRING_SERVICE = "XDUWlan"
KEYRING_RECORD_KEY = "campus-network-credentials"
_SAFE_ERROR_MESSAGE = "系统凭据库中的校园网凭据操作失败"


class KeyringBackend(Protocol):
    """描述适配器实际使用的 ``keyring`` 模块能力。"""

    def set_password(self, service: str, username: str, password: str) -> None:
        """向固定查询键写入一个字符串记录。"""
        ...

    def get_password(self, service: str, username: str) -> str | None:
        """读取固定查询键下的字符串记录。"""
        ...


class KeyringCredentialStore:
    """把一组校园网凭据作为单条 JSON 记录保存到系统凭据库。"""

    def __init__(self, backend: KeyringBackend | None = None) -> None:
        if backend is None:
            import keyring
            backend = keyring
        self._backend = backend

    def save(self, credentials: Credentials) -> None:
        """把账号和密码一次写入系统凭据库。"""
        payload = {
            "username": credentials.username,
            "password": credentials.password,
        }
        try:
            self._backend.set_password(
                KEYRING_SERVICE,
                KEYRING_RECORD_KEY,
                json.dumps(payload),
            )
        except KeyringError as exc:
            raise CredentialStoreError(_SAFE_ERROR_MESSAGE) from exc

    def load(self) -> Credentials | None:
        """读取并校验系统凭据库中的 JSON 记录。"""
        try:
            payload = self._backend.get_password(
                service=KEYRING_SERVICE,
                username=KEYRING_RECORD_KEY,
            )
        except KeyringError as exc:
            raise CredentialStoreError(_SAFE_ERROR_MESSAGE) from exc

        if payload is None:
            return None

        try:
            payload = json.loads(payload)
        except json.JSONDecodeError as exc:
            raise CredentialStoreError(_SAFE_ERROR_MESSAGE) from exc

        if not isinstance(payload, dict):
            raise CredentialStoreError(_SAFE_ERROR_MESSAGE)

        username = payload.get("username")
        password = payload.get("password")

        if not isinstance(username, str) or not isinstance(password, str):
            raise CredentialStoreError(_SAFE_ERROR_MESSAGE)

        return Credentials(username, password)
