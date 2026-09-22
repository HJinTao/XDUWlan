"""网络探测适配器共享的领域记录与 Protocol。"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from xduwlan.models import NetworkProbeResult


@dataclass(frozen=True)
class ResolvedAddress:
    """保存一个可供 TCP 连接使用的数值地址。"""

    host: str
    port: int
    family: int


@dataclass(frozen=True)
class TcpObservation:
    """记录一次 TCP 连接尝试的目标、结果和耗时。"""

    address: ResolvedAddress
    succeeded: bool
    elapsed_ms: float
    detail: str


@dataclass(frozen=True)
class HttpObservation:
    """记录一次 HTTP 请求得到的响应或网络失败。"""

    status_code: int | None
    location: str | None
    body: str
    elapsed_ms: float
    detail: str = ""


class DnsResolver(Protocol):
    """声明调用方需要的 DNS 地址解析能力。"""

    def resolve(self, host: str, port: int) -> tuple[ResolvedAddress, ...]:
        """把主机名解析成一个或多个候选地址。"""
        ...


class TcpConnector(Protocol):
    """声明调用方需要的 TCP 连接探测能力。"""

    def connect(
        self,
        address: ResolvedAddress,
        timeout: float,
    ) -> TcpObservation:
        """尝试连接一个地址候选并返回结构化观察。"""
        ...


class HttpConnectivityChecker(Protocol):
    """声明调用方需要的 HTTP 连通性请求能力。"""

    def request(self, url: str, timeout: float) -> HttpObservation:
        """请求连通性地址并返回结构化观察。"""
        ...


class NetworkProbe(Protocol):
    """声明上层调用方需要的完整网络探测能力。"""

    def probe(self) -> NetworkProbeResult:
        """汇总阶段观察并返回网络状态。"""
        ...
