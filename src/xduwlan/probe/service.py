"""编排 DNS、TCP 与 HTTP 的完整网络探测服务。"""

from __future__ import annotations

from time import perf_counter
from urllib.parse import urlparse

from xduwlan.config import AppConfig
from xduwlan.models import NetworkProbeResult, NetworkState, ProbeObservation, ProbeStage
from xduwlan.probe.classifier import classify_http_observation
from xduwlan.probe.interfaces import (
    DnsResolver,
    HttpConnectivityChecker,
    TcpConnector,
)


class DefaultNetworkProbe:
    """通过注入的阶段适配器执行一次连通性探测。"""

    def __init__(
        self,
        config: AppConfig,
        dns_resolver: DnsResolver,
        tcp_connector: TcpConnector,
        http_checker: HttpConnectivityChecker,
    ) -> None:
        self._config = config
        self._dns_resolver = dns_resolver
        self._tcp_connector = tcp_connector
        self._http_checker = http_checker

    def probe(self) -> NetworkProbeResult:
        """按 DNS、TCP、HTTP 顺序汇总阶段观察。"""
        parsed_url = urlparse(self._config.probe_url)
        host = parsed_url.hostname
        port = parsed_url.port

        if port is None:
            if parsed_url.scheme == "https":
                port = 443
            elif parsed_url.scheme == "http":
                port = 80

        start = perf_counter()

        try:
            resolved_addresses = self._dns_resolver.resolve(host, port)
        except OSError:
            resolved_addresses = ()

        dns_ok = bool(resolved_addresses)

        elapsed_time = (perf_counter() - start) * 1000

        dns_obs = ProbeObservation(
            stage=ProbeStage.DNS,
            succeeded=dns_ok,
            elapsed_ms=elapsed_time,
            detail="DNS 解析成功" if dns_ok else "DNS 解析失败",
        )

        if not dns_ok:
            return NetworkProbeResult(
                state=NetworkState.UNKNOWN,
                observations=(dns_obs,),
                portal_url=None,
            )

        last_tcp = None
        for address in resolved_addresses:
            last_tcp = self._tcp_connector.connect(
                address,
                self._config.request_timeout_seconds,
            )
            if last_tcp.succeeded:
                break

        tcp_obs = ProbeObservation(
            stage=ProbeStage.TCP,
            succeeded=last_tcp.succeeded,
            elapsed_ms=last_tcp.elapsed_ms,
            detail=last_tcp.detail,
        )

        if not last_tcp.succeeded:
            return NetworkProbeResult(
                state=NetworkState.INTERNET_UNREACHABLE,
                observations=(dns_obs, tcp_obs),
                portal_url=None,
            )

        http_res = self._http_checker.request(
            self._config.probe_url,
            self._config.request_timeout_seconds,
        )
        http_obs = ProbeObservation(
            stage=ProbeStage.HTTP,
            succeeded=http_res.status_code is not None,
            elapsed_ms=http_res.elapsed_ms,
            detail=http_res.detail,
        )

        portal_hosts = frozenset({urlparse(self._config.portal_url).hostname})

        state = classify_http_observation(http_res, portal_hosts)

        return NetworkProbeResult(
            state=state,
            observations=(dns_obs, tcp_obs, http_obs),
            portal_url=None,
        )
