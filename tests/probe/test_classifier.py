from xduwlan.models import NetworkState
from xduwlan.probe.classifier import classify_http_observation
from xduwlan.probe.interfaces import HttpObservation


PORTAL_HOSTS = frozenset({"w.xidian.edu.cn"})


def test_expected_204_is_online():
    """连通性端点返回 204 时应判断为已联网。"""
    observation = HttpObservation(
        status_code=204,
        location=None,
        body="",
        elapsed_ms=2.0,
    )

    state = classify_http_observation(observation, PORTAL_HOSTS)

    assert state is NetworkState.ONLINE


def test_redirect_to_known_portal_requires_authentication():
    """重定向到明确允许的 Portal 主机时应判断为需要认证。"""
    observation = HttpObservation(
        status_code=302,
        location="https://w.xidian.edu.cn/srun_portal",
        body="",
        elapsed_ms=3.0,
    )

    state = classify_http_observation(observation, PORTAL_HOSTS)

    assert state is NetworkState.PORTAL_REQUIRED


def test_redirect_to_unknown_host_is_unknown():
    """普通网站重定向不能仅凭 302 被误判为校园 Portal。"""
    observation = HttpObservation(
        status_code=302,
        location="https://redirect.example.test/landing",
        body="",
        elapsed_ms=3.0,
    )

    state = classify_http_observation(observation, PORTAL_HOSTS)

    assert state is NetworkState.UNKNOWN


def test_location_query_text_does_not_impersonate_portal_host():
    """查询参数包含 Portal 文本时仍应按真实 hostname 分类。"""
    observation = HttpObservation(
        status_code=302,
        location="https://redirect.example.test/?next=w.xidian.edu.cn",
        body="",
        elapsed_ms=3.0,
    )

    state = classify_http_observation(observation, PORTAL_HOSTS)

    assert state is NetworkState.UNKNOWN


def test_srun_feature_in_200_body_requires_authentication():
    """200 正文包含大小写不同的深澜特征时应判断为需要认证。"""
    observation = HttpObservation(
        status_code=200,
        location=None,
        body='<script src="/SRUN_PORTAL.js"></script>',
        elapsed_ms=4.0,
    )

    state = classify_http_observation(observation, PORTAL_HOSTS)

    assert state is NetworkState.PORTAL_REQUIRED


def test_plain_200_response_is_unknown():
    """没有 Portal 证据的普通 200 响应不能直接视为已联网。"""
    observation = HttpObservation(
        status_code=200,
        location=None,
        body="ordinary response",
        elapsed_ms=4.0,
    )

    state = classify_http_observation(observation, PORTAL_HOSTS)

    assert state is NetworkState.UNKNOWN


def test_network_failure_observation_is_unknown():
    """没有 HTTP 状态码的网络失败应交给完整探测服务继续分类。"""
    observation = HttpObservation(
        status_code=None,
        location=None,
        body="",
        elapsed_ms=5.0,
        detail="HTTP 请求失败",
    )

    state = classify_http_observation(observation, PORTAL_HOSTS)

    assert state is NetworkState.UNKNOWN


def test_missing_or_malformed_location_is_unknown():
    """缺失或畸形的 Location 不应导致分类器崩溃或误判。"""
    observations = (
        HttpObservation(302, None, "", 3.0),
        HttpObservation(302, "https://[invalid", "", 3.0),
    )

    states = tuple(
        classify_http_observation(observation, PORTAL_HOSTS)
        for observation in observations
    )

    assert states == (NetworkState.UNKNOWN, NetworkState.UNKNOWN)
