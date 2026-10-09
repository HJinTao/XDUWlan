"""一次认证恢复的领域结果与应用服务。"""

from dataclasses import dataclass
from enum import Enum
from typing import Protocol

from xduwlan.auth.interfaces import PortalClient
from xduwlan.credentials import Credentials, CredentialStore
from xduwlan.errors import (
    AuthenticationRejectedError, CredentialStoreError, PortalNetworkError, PortalProtocolError,
)
from xduwlan.models import NetworkState, ProbeObservation
from xduwlan.probe.interfaces import NetworkProbe


class LoginState(Enum):
    """一次运行的稳定结果类别。"""

    ALREADY_ONLINE = 'already_online'
    RESTORED = 'restored'
    CREDENTIALS_MISSING = 'credentials_missing'
    CREDENTIALS_INVALID = 'credentials_invalid'
    CREDENTIAL_STORE_FAILED = 'credential_store_failed'
    NETWORK_UNAVAILABLE = 'network_unavailable'
    UNKNOWN_NETWORK = 'unknown_network'
    AUTH_REJECTED = 'auth_rejected'
    PORTAL_UNAVAILABLE = 'portal_unavailable'
    PROTOCOL_ERROR = 'protocol_error'
    VERIFICATION_FAILED = 'verification_failed'


@dataclass(frozen=True)
class LoginResult:
    """只携带可公开的状态与探测观察，不持有任何认证信息。"""

    state: LoginState
    network_state: NetworkState
    observations: tuple[ProbeObservation, ...]


class LoginService(Protocol):
    """声明一次认证恢复能力。"""

    def login(self) -> LoginResult:
        """按需认证并验证，然后返回单一结果。"""
        ...


class DefaultLoginService:
    """按可信探测结果执行一次恢复，不依赖终端、系统或具体 HTTP 库。"""

    def __init__(
        self, probe: NetworkProbe, store: CredentialStore, portal: PortalClient,
        operator_suffix: str = "",
    ) -> None:
        self._probe = probe
        self._store = store
        self._portal = portal
        self._operator_suffix = operator_suffix

    def login(self) -> LoginResult:
        """先确认目标再加载凭据；认证成功后仍需独立探测。"""
        initial = self._probe.probe()
        if initial.state is NetworkState.ONLINE:
            return LoginResult(LoginState.ALREADY_ONLINE, initial.state, initial.observations)
        if initial.state is not NetworkState.PORTAL_REQUIRED:
            state = (LoginState.UNKNOWN_NETWORK if initial.state is NetworkState.UNKNOWN
                     else LoginState.NETWORK_UNAVAILABLE)
            return LoginResult(state, initial.state, initial.observations)

        try:
            context = self._portal.prepare()
            credentials = self._store.load()
            if credentials is None:
                return LoginResult(LoginState.CREDENTIALS_MISSING, initial.state, initial.observations)
            if not credentials.username.strip() or not credentials.password:
                return LoginResult(LoginState.CREDENTIALS_INVALID, initial.state, initial.observations)
            try:
                credentials.username.encode("utf-8")
                credentials.password.encode("utf-8")
            except UnicodeError:
                return LoginResult(LoginState.CREDENTIALS_INVALID, initial.state, initial.observations)
            username = credentials.username
            if self._operator_suffix and not username.endswith(self._operator_suffix):
                username += self._operator_suffix
            self._portal.authenticate(context, Credentials(username, credentials.password))
        except CredentialStoreError:
            state = LoginState.CREDENTIAL_STORE_FAILED
        except AuthenticationRejectedError:
            state = LoginState.AUTH_REJECTED
        except PortalNetworkError:
            state = LoginState.PORTAL_UNAVAILABLE
        except PortalProtocolError:
            state = LoginState.PROTOCOL_ERROR
        else:
            final = self._probe.probe()
            state = LoginState.RESTORED if final.state is NetworkState.ONLINE else LoginState.VERIFICATION_FAILED
            return LoginResult(state, final.state, initial.observations + final.observations)
        return LoginResult(state, initial.state, initial.observations)
