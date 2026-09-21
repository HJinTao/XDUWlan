import socket

import pytest

import xduwlan.probe.tcp as tcp_module
from xduwlan.probe.interfaces import ResolvedAddress, TcpObservation
from xduwlan.probe.tcp import SystemTcpConnector


class FakeConnection:
    """记录测试连接是否被关闭，不执行真实网络操作。"""

    def __init__(self):
        self.closed = False

    def close(self):
        self.closed = True

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()


def test_system_tcp_connector_returns_success_observation(monkeypatch):
    """连接成功时应记录目标、耗时并关闭测试连接。"""
    address = ResolvedAddress(
        host="203.0.113.10",
        port=80,
        family=socket.AF_INET,
    )
    connection = FakeConnection()
    calls = []
    clock_values = iter((10.0, 10.5))

    def fake_create_connection(target, *, timeout):
        calls.append((target, timeout))
        return connection

    monkeypatch.setattr(socket, "create_connection", fake_create_connection)
    monkeypatch.setattr(tcp_module, "perf_counter", lambda: next(clock_values))

    observation = SystemTcpConnector().connect(address, timeout=2.5)

    assert calls == [(("203.0.113.10", 80), 2.5)]
    assert connection.closed is True
    assert observation == TcpObservation(
        address=address,
        succeeded=True,
        elapsed_ms=500.0,
        detail="TCP 连接成功",
    )


@pytest.mark.parametrize(
    ("error", "expected_detail"),
    (
        (socket.timeout("不得泄漏的超时细节"), "TCP 连接超时"),
        (OSError("不得泄漏的系统错误细节"), "TCP 连接失败"),
    ),
)
def test_system_tcp_connector_converts_connection_errors_to_observations(
    monkeypatch,
    error,
    expected_detail,
):
    """连接异常应转换为带耗时且不泄漏底层正文的失败观察。"""
    address = ResolvedAddress(
        host="203.0.113.10",
        port=80,
        family=socket.AF_INET,
    )
    calls = []
    clock_values = iter((20.0, 22.5))

    def fake_create_connection(target, *, timeout):
        calls.append((target, timeout))
        raise error

    monkeypatch.setattr(socket, "create_connection", fake_create_connection)
    monkeypatch.setattr(tcp_module, "perf_counter", lambda: next(clock_values))

    observation = SystemTcpConnector().connect(address, timeout=2.5)

    assert calls == [(("203.0.113.10", 80), 2.5)]
    assert observation == TcpObservation(
        address=address,
        succeeded=False,
        elapsed_ms=2500.0,
        detail=expected_detail,
    )
    assert str(error) not in observation.detail
