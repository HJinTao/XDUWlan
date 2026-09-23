import json
from dataclasses import FrozenInstanceError

import pytest
from keyring.errors import KeyringError

from xduwlan.credentials import CredentialStore, Credentials
from xduwlan.errors import CredentialStoreError
from xduwlan.keyring_store import (
    KEYRING_RECORD_KEY,
    KEYRING_SERVICE,
    KeyringCredentialStore,
)


class MemoryKeyring:
    """只在内存中记录调用的 ``keyring`` 测试替身。"""

    def __init__(self, record=None, error=None):
        self.record = record
        self.error = error
        self.set_calls = []
        self.get_calls = []

    def set_password(self, service, username, password):
        self.set_calls.append((service, username, password))
        if self.error is not None:
            raise self.error
        self.record = password

    def get_password(self, service, username):
        self.get_calls.append((service, username))
        if self.error is not None:
            raise self.error
        return self.record


def test_credentials_are_immutable_and_hide_both_fields_from_repr():
    """凭据不可变，调试表示也不能暴露账号或密码。"""
    credentials = Credentials("student@example.test", "fictional-password")

    representation = repr(credentials)
    assert "student@example.test" not in representation
    assert "fictional-password" not in representation

    with pytest.raises(FrozenInstanceError):
        credentials.password = "changed"


def test_memory_store_can_replace_credential_store_protocol():
    """上层代码应能只依赖端口，用内存实现替换系统适配器。"""

    class MemoryCredentialStore:
        def __init__(self):
            self.credentials = None

        def save(self, credentials):
            self.credentials = credentials

        def load(self):
            return self.credentials

    store: CredentialStore = MemoryCredentialStore()
    credentials = Credentials("student@example.test", "fictional-password")

    store.save(credentials)

    assert store.load() == credentials


def test_keyring_store_saves_credentials_as_one_json_record():
    """账号和密码应编码为一条记录，并只调用一次系统凭据库。"""
    backend = MemoryKeyring()
    store = KeyringCredentialStore(backend)

    store.save(Credentials("student@example.test", "fictional-password"))

    assert len(backend.set_calls) == 1
    service, record_key, record = backend.set_calls[0]
    assert (service, record_key) == (KEYRING_SERVICE, KEYRING_RECORD_KEY)
    assert json.loads(record) == {
        "username": "student@example.test",
        "password": "fictional-password",
    }


def test_keyring_store_returns_none_when_no_record_exists():
    """固定查询键尚无记录表示用户还没有配置凭据。"""
    backend = MemoryKeyring(record=None)

    assert KeyringCredentialStore(backend).load() is None
    assert backend.get_calls == [(KEYRING_SERVICE, KEYRING_RECORD_KEY)]


def test_keyring_store_loads_credentials_from_json_record():
    """有效 JSON 记录应还原成领域凭据。"""
    backend = MemoryKeyring(
        record=json.dumps(
            {
                "username": "student@example.test",
                "password": "fictional-password",
            }
        )
    )

    credentials = KeyringCredentialStore(backend).load()

    assert credentials == Credentials("student@example.test", "fictional-password")


@pytest.mark.parametrize("operation", ["save", "load"])
def test_keyring_backend_errors_are_converted_without_leaking_details(operation):
    """系统后端失败应转换为稳定项目错误，且不泄漏底层消息。"""
    backend = MemoryKeyring(error=KeyringError("private-marker"))
    store = KeyringCredentialStore(backend)

    with pytest.raises(CredentialStoreError) as exc_info:
        if operation == "save":
            store.save(Credentials("student@example.test", "fictional-password"))
        else:
            store.load()

    assert "private-marker" not in str(exc_info.value)
    assert isinstance(exc_info.value.__cause__, KeyringError)


@pytest.mark.parametrize(
    "record",
    [
        "private-marker:not-json",
        json.dumps(["student@example.test", "fictional-password"]),
        json.dumps({"username": "student@example.test"}),
        json.dumps(
            {
                "username": "student@example.test",
                "password": 123,
            }
        ),
    ],
)
def test_damaged_keyring_records_are_converted_without_leaking_contents(record):
    """语法、形状或字段类型错误都应转换为不含记录内容的项目错误。"""
    store = KeyringCredentialStore(MemoryKeyring(record=record))

    with pytest.raises(CredentialStoreError) as exc_info:
        store.load()

    assert "private-marker" not in str(exc_info.value)
    assert "student@example.test" not in str(exc_info.value)
    assert "fictional-password" not in str(exc_info.value)
