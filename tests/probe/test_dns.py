import socket

from xduwlan.probe.dns import SystemDnsResolver
from xduwlan.probe.interfaces import ResolvedAddress


def test_system_dns_resolver_converts_getaddrinfo_results(monkeypatch):
    """系统地址记录应转换为可供 TCP 使用的不可变领域地址。"""
    calls = []

    def fake_getaddrinfo(host, port, *, type):
        calls.append((host, port, type))
        return [
            (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("203.0.113.10", 80)),
        ]

    monkeypatch.setattr(socket, "getaddrinfo", fake_getaddrinfo)

    addresses = SystemDnsResolver().resolve("example.test", 80)

    assert calls == [("example.test", 80, socket.SOCK_STREAM)]
    assert addresses == (
        ResolvedAddress(host="203.0.113.10", port=80, family=socket.AF_INET),
    )
