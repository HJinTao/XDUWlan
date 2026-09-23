import pytest

from xduwlan.credential_service import DefaultCredentialConfigurator
from xduwlan.credentials import Credentials
from xduwlan.errors import CredentialStoreError, CredentialValidationError


class RecordingCredentialStore:
    """记录保存调用、不访问系统凭据库的测试替身。"""

    def __init__(self):
        self.saved = []

    def save(self, credentials):
        self.saved.append(credentials)

    def load(self):
        raise AssertionError("凭据配置服务不应读取已有记录")


def test_configurator_normalizes_username_and_preserves_password():
    """应用服务应只整理账号，并把密码逐字保存。"""
    store = RecordingCredentialStore()
    configurator = DefaultCredentialConfigurator(store)

    configurator.configure(
        "  student@example.test  ",
        " fictional-password ",
    )

    assert store.saved == [
        Credentials("student@example.test", " fictional-password ")
    ]


@pytest.mark.parametrize(
    ("username", "password"),
    [
        ("", "fictional-password"),
        ("   ", "fictional-password"),
        ("student@example.test", ""),
    ],
)
def test_configurator_rejects_empty_fields_without_saving(username, password):
    """空账号或空密码应作为输入错误，且不得写入凭据库。"""
    store = RecordingCredentialStore()
    configurator = DefaultCredentialConfigurator(store)

    with pytest.raises(CredentialValidationError):
        configurator.configure(username, password)

    assert store.saved == []


def test_configurator_preserves_credential_store_errors():
    """应用服务应让稳定存储错误交给用户边界映射。"""

    class FailingStore:
        def save(self, credentials):
            raise CredentialStoreError("private-marker")

        def load(self):
            return None

    configurator = DefaultCredentialConfigurator(FailingStore())

    with pytest.raises(CredentialStoreError, match="private-marker"):
        configurator.configure("student@example.test", "fictional-password")
