"""基于操作系统套接字接口的 DNS 地址解析器。"""

from __future__ import annotations

import socket

from xduwlan.probe.interfaces import ResolvedAddress


class SystemDnsResolver:
    """使用 Python 标准库连接操作系统名称解析能力。"""

    def resolve(self, host: str, port: int) -> tuple[ResolvedAddress, ...]:
        """把主机名解析为可供 TCP 使用的地址候选。"""
        addr_infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
        resolved_addresses: list[ResolvedAddress] = []
        for family, _type, _proto, _canonname, sockaddr in addr_infos:
            resolved_addresses.append(
                ResolvedAddress(
                    host=sockaddr[0],
                    port=sockaddr[1],
                    family=family,
                )
            )
        return tuple(resolved_addresses)
