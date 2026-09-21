"""把网络探测观察转换为稳定的领域状态。"""

from __future__ import annotations

from urllib.parse import urlparse

from xduwlan.models import NetworkState
from xduwlan.probe.interfaces import HttpObservation


def classify_http_observation(
    observation: HttpObservation,
    portal_hosts: frozenset[str],
) -> NetworkState:
    """根据 HTTP 状态码、重定向主机和正文特征分类。"""
    status = observation.status_code
    location = observation.location
    if status == 204:
        return NetworkState.ONLINE

    if status is not None and status // 100 == 3:
        if location:
            try:
                redirect_hostname = urlparse(location).hostname
            except ValueError:
                redirect_hostname = None
            if redirect_hostname in portal_hosts:
                return NetworkState.PORTAL_REQUIRED

    if status == 200:
        body = observation.body or ""
        if "srun_portal" in body.lower():
            return NetworkState.PORTAL_REQUIRED

    return NetworkState.UNKNOWN
