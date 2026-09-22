import socket
from dataclasses import replace

import pytest

from xduwlan.config import AppConfig
from xduwlan.models import NetworkState, ProbeStage
from xduwlan.probe.interfaces import HttpObservation, ResolvedAddress, TcpObservation
from xduwlan.probe.service import DefaultNetworkProbe


def test_https_probe_runs_dns_tcp_http_and_returns_online():
    """HTTPS 默认端口、阶段顺序和 204 汇总结果应形成一次完整探测。"""
    calls = []
    address = ResolvedAddress("203.0.113.10", 443, socket.AF_INET)
    config = replace(
        AppConfig.defaults(),
        probe_url="https://probe.example.test/generate_204",
        portal_url="https://portal.example.test/login",
    )

    class FakeResolver:
        def resolve(self, host, port):
            calls.append(("dns", host, port))
            return (address,)

    class FakeConnector:
        def connect(self, target, timeout):
            calls.append(("tcp", target, timeout))
            return TcpObservation(target, True, 3.0, "TCP 连接成功")

    class FakeChecker:
        def request(self, url, timeout):
            calls.append(("http", url, timeout))
            return HttpObservation(204, None, "", 4.0, "HTTP 响应已接收")

    result = DefaultNetworkProbe(
        config,
        dns_resolver=FakeResolver(),
        tcp_connector=FakeConnector(),
        http_checker=FakeChecker(),
    ).probe()

    assert calls == [
        ("dns", "probe.example.test", 443),
        ("tcp", address, 5),
        ("http", "https://probe.example.test/generate_204", 5),
    ]
    assert result.state is NetworkState.ONLINE
    assert result.portal_url is None
    assert tuple(item.stage for item in result.observations) == (
        ProbeStage.DNS,
        ProbeStage.TCP,
        ProbeStage.HTTP,
    )
    assert all(item.succeeded for item in result.observations)
    assert result.observations[0].elapsed_ms >= 0
    assert tuple(item.elapsed_ms for item in result.observations[1:]) == (3.0, 4.0)


@pytest.mark.parametrize(
    "dns_result",
    [(), socket.gaierror("private-marker")],
    ids=["no-addresses", "resolver-error"],
)
def test_dns_without_usable_addresses_stops_before_tcp_and_http(dns_result):
    """DNS 无候选或失败只能说明本次解析失败，不能证明本地网络断开。"""
    config = replace(
        AppConfig.defaults(),
        probe_url="https://probe.example.test/generate_204",
    )

    class FakeResolver:
        def resolve(self, host, port):
            assert (host, port) == ("probe.example.test", 443)
            if isinstance(dns_result, OSError):
                raise dns_result
            return dns_result

    class UnexpectedConnector:
        def connect(self, address, timeout):
            raise AssertionError("DNS 无地址时不应尝试 TCP")

    class UnexpectedChecker:
        def request(self, url, timeout):
            raise AssertionError("DNS 无地址时不应请求 HTTP")

    result = DefaultNetworkProbe(
        config,
        dns_resolver=FakeResolver(),
        tcp_connector=UnexpectedConnector(),
        http_checker=UnexpectedChecker(),
    ).probe()

    assert result.state is NetworkState.UNKNOWN
    assert tuple(item.stage for item in result.observations) == (ProbeStage.DNS,)
    assert not result.observations[0].succeeded
    assert result.observations[0].elapsed_ms >= 0
    assert "private-marker" not in result.observations[0].detail
    assert result.portal_url is None


def test_tcp_tries_next_address_and_requests_http_after_success():
    """一个地址不可连接时应尝试下一地址，成功后不再尝试其他候选。"""
    addresses = tuple(
        ResolvedAddress(f"203.0.113.{number}", 443, socket.AF_INET)
        for number in (10, 11, 12)
    )
    calls = []

    class FakeResolver:
        def resolve(self, host, port):
            assert (host, port) == ("probe.example.test", 443)
            return addresses

    class FakeConnector:
        def connect(self, address, timeout):
            calls.append(("tcp", address, timeout))
            return TcpObservation(
                address,
                address == addresses[1],
                2.0,
                "TCP 连接成功" if address == addresses[1] else "TCP 连接失败",
            )

    class FakeChecker:
        def request(self, url, timeout):
            calls.append(("http", url, timeout))
            return HttpObservation(204, None, "", 4.0, "HTTP 响应已接收")

    config = replace(
        AppConfig.defaults(),
        probe_url="https://probe.example.test/generate_204",
    )
    result = DefaultNetworkProbe(
        config,
        dns_resolver=FakeResolver(),
        tcp_connector=FakeConnector(),
        http_checker=FakeChecker(),
    ).probe()

    assert calls == [
        ("tcp", addresses[0], 5),
        ("tcp", addresses[1], 5),
        ("http", "https://probe.example.test/generate_204", 5),
    ]
    assert result.state is NetworkState.ONLINE
    assert any(
        item.stage is ProbeStage.TCP and item.succeeded
        for item in result.observations
    )


def test_all_tcp_candidates_fail_without_requesting_http():
    """所有 TCP 候选不可连接时应返回目标不可达，不再发送 HTTP。"""
    addresses = (
        ResolvedAddress("203.0.113.10", 443, socket.AF_INET),
        ResolvedAddress("203.0.113.11", 443, socket.AF_INET),
    )
    calls = []

    class FakeResolver:
        def resolve(self, host, port):
            assert (host, port) == ("probe.example.test", 443)
            return addresses

    class FakeConnector:
        def connect(self, address, timeout):
            calls.append((address, timeout))
            return TcpObservation(address, False, 2.0, "TCP 连接失败")

    class UnexpectedChecker:
        def request(self, url, timeout):
            raise AssertionError("全部 TCP 候选失败时不应请求 HTTP")

    config = replace(
        AppConfig.defaults(),
        probe_url="https://probe.example.test/generate_204",
    )
    result = DefaultNetworkProbe(
        config,
        dns_resolver=FakeResolver(),
        tcp_connector=FakeConnector(),
        http_checker=UnexpectedChecker(),
    ).probe()

    assert calls == [(addresses[0], 5), (addresses[1], 5)]
    assert result.state is NetworkState.INTERNET_UNREACHABLE
    assert result.observations[0].stage is ProbeStage.DNS
    assert any(
        item.stage is ProbeStage.TCP and not item.succeeded
        for item in result.observations
    )
    assert all(item.stage is not ProbeStage.HTTP for item in result.observations)
    assert result.portal_url is None


@pytest.mark.parametrize(
    ("http_result", "expected_state", "http_succeeded"),
    [
        (
            HttpObservation(
                302,
                "https://portal.example.test/landing?note=private-marker",
                "",
                3.0,
                "HTTP 响应已接收",
            ),
            NetworkState.PORTAL_REQUIRED,
            True,
        ),
        (
            HttpObservation(None, None, "", 3.0, "HTTP 请求失败"),
            NetworkState.UNKNOWN,
            False,
        ),
    ],
    ids=["known-portal", "http-failure"],
)
def test_http_result_is_classified_without_exposing_location(
    http_result, expected_state, http_succeeded
):
    """服务只保留 HTTP 阶段观察与分类，不传播原始重定向 URL。"""
    config = replace(
        AppConfig.defaults(),
        probe_url="http://probe.example.test:8080/check",
        portal_url="https://portal.example.test/login",
    )
    address = ResolvedAddress("203.0.113.10", 8080, socket.AF_INET)

    class FakeResolver:
        def resolve(self, host, port):
            assert (host, port) == ("probe.example.test", 8080)
            return (address,)

    class FakeConnector:
        def connect(self, target, timeout):
            return TcpObservation(target, True, 2.0, "TCP 连接成功")

    class FakeChecker:
        def request(self, url, timeout):
            assert (url, timeout) == ("http://probe.example.test:8080/check", 5)
            return http_result

    result = DefaultNetworkProbe(
        config,
        dns_resolver=FakeResolver(),
        tcp_connector=FakeConnector(),
        http_checker=FakeChecker(),
    ).probe()

    assert result.state is expected_state
    assert result.observations[-1].stage is ProbeStage.HTTP
    assert result.observations[-1].succeeded is http_succeeded
    assert result.portal_url is None
    assert "private-marker" not in str(result)
