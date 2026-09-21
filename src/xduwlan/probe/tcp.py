"""基于操作系统套接字接口的 TCP 连接探测器。"""

from __future__ import annotations

import socket
from time import perf_counter

from xduwlan.probe.interfaces import ResolvedAddress, TcpObservation


class SystemTcpConnector:
    """使用 Python 标准库尝试建立 TCP 连接。"""

    def connect(
        self,
        address: ResolvedAddress,
        timeout: float,
    ) -> TcpObservation:
        """连接一个地址候选并返回结构化观察。"""
        start = perf_counter()
        try:
            with socket.create_connection(
                (address.host, address.port),
                timeout=timeout,
            ):
                elapsed_time = (perf_counter() - start) * 1000
                return TcpObservation(
                    address=address,
                    succeeded=True,
                    elapsed_ms=elapsed_time,
                    detail="TCP 连接成功",
                )
        except socket.timeout:
            elapsed_time = (perf_counter() - start) * 1000
            return TcpObservation(
                address=address,
                succeeded=False,
                elapsed_ms=elapsed_time,
                detail="TCP 连接超时",
            )
        except OSError:
            elapsed_time = (perf_counter() - start) * 1000
            return TcpObservation(
                address=address,
                succeeded=False,
                elapsed_ms=elapsed_time,
                detail="TCP 连接失败",
            )
