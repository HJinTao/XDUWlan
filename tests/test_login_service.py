import pytest

from xduwlan.auth.interfaces import PortalContext
from xduwlan.credentials import Credentials
from xduwlan.errors import AuthenticationRejectedError, CredentialStoreError, PortalNetworkError, PortalProtocolError
from xduwlan.login_service import DefaultLoginService, LoginState
from xduwlan.models import NetworkProbeResult, NetworkState


class Boundaries:
    def __init__(self, states, credentials=Credentials('student@example.test', 'fictional-password'), prepare_error=None, auth_error=None):
        self.states = iter(states)
        self.credentials = credentials
        self.prepare_error = prepare_error
        self.auth_error = auth_error
        self.calls = []

    def probe(self):
        self.calls.append('probe')
        return NetworkProbeResult(next(self.states), ())

    def load(self):
        self.calls.append('load')
        if isinstance(self.credentials, Exception):
            raise self.credentials
        return self.credentials

    def prepare(self):
        self.calls.append('prepare')
        if self.prepare_error:
            raise self.prepare_error
        return PortalContext('https://portal.example.test', '192.0.2.10', '8')

    def authenticate(self, context, credentials):
        self.calls.append(('authenticate', context, credentials))
        if self.auth_error:
            raise self.auth_error


def test_recovery_orders_trust_credentials_authentication_and_verification():
    boundaries = Boundaries([NetworkState.PORTAL_REQUIRED, NetworkState.ONLINE])
    result = DefaultLoginService(boundaries, boundaries, boundaries).login()
    assert result.state is LoginState.RESTORED
    assert result.network_state is NetworkState.ONLINE
    assert boundaries.calls[:3] == ['probe', 'prepare', 'load']
    assert boundaries.calls[3][0] == 'authenticate'
    assert boundaries.calls[4:] == ['probe']


@pytest.mark.parametrize(('initial', 'outcome'), [
    (NetworkState.ONLINE, LoginState.ALREADY_ONLINE),
    (NetworkState.UNKNOWN, LoginState.UNKNOWN_NETWORK),
    (NetworkState.LOCAL_NETWORK_DOWN, LoginState.NETWORK_UNAVAILABLE),
    (NetworkState.INTERNET_UNREACHABLE, LoginState.NETWORK_UNAVAILABLE),
])
def test_nonportal_state_never_reads_or_sends_credentials(initial, outcome):
    boundaries = Boundaries([initial])
    assert DefaultLoginService(boundaries, boundaries, boundaries).login().state is outcome
    assert boundaries.calls == ['probe']


@pytest.mark.parametrize(('credentials', 'outcome'), [
    (None, LoginState.CREDENTIALS_MISSING),
    (CredentialStoreError('private-marker'), LoginState.CREDENTIAL_STORE_FAILED),
    (Credentials('', 'fictional-password'), LoginState.CREDENTIALS_INVALID),
    (Credentials('student@example.test', ''), LoginState.CREDENTIALS_INVALID),
    (Credentials('student@example.test', '\ud800'), LoginState.CREDENTIALS_INVALID),
])
def test_unusable_credentials_stop_before_authentication(credentials, outcome):
    boundaries = Boundaries([NetworkState.PORTAL_REQUIRED], credentials=credentials)
    assert DefaultLoginService(boundaries, boundaries, boundaries).login().state is outcome
    assert boundaries.calls == ['probe', 'prepare', 'load']


@pytest.mark.parametrize(('error', 'outcome'), [
    (PortalNetworkError('private-marker'), LoginState.PORTAL_UNAVAILABLE),
    (PortalProtocolError('private-marker'), LoginState.PROTOCOL_ERROR),
])
def test_prepare_failure_does_not_even_load_credentials(error, outcome):
    boundaries = Boundaries([NetworkState.PORTAL_REQUIRED], prepare_error=error)
    assert DefaultLoginService(boundaries, boundaries, boundaries).login().state is outcome
    assert boundaries.calls == ['probe', 'prepare']


@pytest.mark.parametrize(('error', 'outcome'), [
    (AuthenticationRejectedError('private-marker'), LoginState.AUTH_REJECTED),
    (PortalNetworkError('private-marker'), LoginState.PORTAL_UNAVAILABLE),
    (PortalProtocolError('private-marker'), LoginState.PROTOCOL_ERROR),
])
def test_authentication_failure_is_not_retried_or_reported_as_restored(error, outcome):
    boundaries = Boundaries([NetworkState.PORTAL_REQUIRED], auth_error=error)
    result = DefaultLoginService(boundaries, boundaries, boundaries).login()
    assert result.state is outcome
    assert 'private-marker' not in repr(result)
    assert len(boundaries.calls) == 4


@pytest.mark.parametrize('final', [NetworkState.PORTAL_REQUIRED, NetworkState.UNKNOWN, NetworkState.INTERNET_UNREACHABLE])
def test_portal_success_is_insufficient_when_verification_fails(final):
    boundaries = Boundaries([NetworkState.PORTAL_REQUIRED, final])
    result = DefaultLoginService(boundaries, boundaries, boundaries).login()
    assert result.state is LoginState.VERIFICATION_FAILED
    assert result.network_state is final
    assert len(boundaries.calls) == 5


def test_explicit_operator_suffix_is_added_once():
    boundaries = Boundaries([NetworkState.PORTAL_REQUIRED, NetworkState.ONLINE])
    DefaultLoginService(boundaries, boundaries, boundaries, operator_suffix='@fictional').login()
    assert boundaries.calls[3][2].username == 'student@example.test@fictional'
    assert boundaries.credentials.username == 'student@example.test'
