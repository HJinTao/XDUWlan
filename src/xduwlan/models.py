"""与 CLI、网络库和操作系统无关的核心领域模型。"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class NetworkState(Enum):
    """表示一次完整探测得出的网络状态。"""
    ONLINE = "online"
    PORTAL_REQUIRED = "portal_required"
    LOCAL_NETWORK_DOWN = "local_network_down"
    INTERNET_UNREACHABLE = "internet_unreachable"
    UNKNOWN = "unknown"


class ProbeStage(Enum):
    """标识一条探测观察所属的网络阶段。"""
    DNS = "dns"
    TCP = "tcp"
    HTTP = "http"


@dataclass(frozen=True)
class ProbeObservation:
    """记录一个探测阶段的结果和耗时，不负责执行网络请求。"""

    stage: ProbeStage
    succeeded: bool
    elapsed_ms: float
    detail: str


@dataclass(frozen=True)
class NetworkProbeResult:
    """汇总网络分类、阶段观察和可选 Portal 地址。"""

    state: NetworkState
    observations: tuple[ProbeObservation, ...]
    portal_url: str | None = None
