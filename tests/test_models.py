from dataclasses import FrozenInstanceError

import pytest

from xduwlan.models import (
    NetworkProbeResult,
    NetworkState,
    ProbeObservation,
    ProbeStage,
)


def test_network_state_values_are_stable_domain_contract():
    """网络分类名称和值应构成 CLI 和跨语言实现之间的稳定契约。"""
    assert {state.name: state.value for state in NetworkState} == {
        "ONLINE": "online",
        "PORTAL_REQUIRED": "portal_required",
        "LOCAL_NETWORK_DOWN": "local_network_down",
        "INTERNET_UNREACHABLE": "internet_unreachable",
        "UNKNOWN": "unknown",
    }


def test_probe_stage_values_cover_current_network_layers():
    """探测阶段名称和值应覆盖任务 3 将实现的三个网络层次。"""
    assert {stage.name: stage.value for stage in ProbeStage} == {
        "DNS": "dns",
        "TCP": "tcp",
        "HTTP": "http",
    }


def test_probe_observation_is_immutable_and_keeps_stage_details():
    """单阶段观察创建后应保留输入字段，并且不能被调用方修改。"""
    observation = ProbeObservation(
        stage=ProbeStage.HTTP,
        succeeded=True,
        elapsed_ms=2.5,
        detail="返回预期状态码",
    )

    assert observation.stage is ProbeStage.HTTP
    assert observation.succeeded is True
    assert observation.elapsed_ms == 2.5
    assert observation.detail == "返回预期状态码"
    with pytest.raises(FrozenInstanceError):
        observation.succeeded = False


def test_probe_result_is_immutable_and_keeps_observations_as_tuple():
    """探测结果发布后不能被调用方修改或替换其中的观察记录。"""
    observation = ProbeObservation(
        stage=ProbeStage.HTTP,
        succeeded=True,
        elapsed_ms=2.5,
        detail="返回预期状态码",
    )
    result = NetworkProbeResult(
        state=NetworkState.ONLINE,
        observations=(observation,),
    )

    assert result.state is NetworkState.ONLINE
    assert result.observations == (observation,)
    assert result.portal_url is None
    with pytest.raises(FrozenInstanceError):
        result.state = NetworkState.UNKNOWN
