import json
from pathlib import Path

import pytest

from xduwlan.auth.interfaces import PortalContext
from xduwlan.auth.protocol import build_login_params, parse_jsonp
from xduwlan.credentials import Credentials
from xduwlan.errors import PortalProtocolError


@pytest.mark.parametrize("vector", json.loads(Path(__file__).with_name("vectors.json").read_text()))
def test_encoding_matches_independent_javascript_vectors(vector):
    """字节截断、字段次序和校验串错误应被独立 JavaScript 向量发现。"""
    params = build_login_params(
        Credentials(vector["username"], vector["password"]),
        PortalContext("https://portal.example.test", vector["ip"], vector["acid"]),
        vector["challenge"], "xduwlan_cb", 1234,
    )
    assert list(params) == [
        "callback", "action", "username", "password", "os", "name",
        "double_stack", "chksum", "info", "ac_id", "ip", "n", "type", "_",
    ]
    assert params["password"] == "{MD5}" + vector["hmd5"]
    assert params["info"] == vector["info"]
    assert params["chksum"] == vector["checksum"]
    assert params["ac_id"] == "8"
    assert params["n"] == "200"
    assert params["type"] == "1"


def test_jsonp_accepts_only_matching_callback_and_object():
    assert parse_jsonp('  xduwlan_cb({"error":"ok"});  ', "xduwlan_cb") == {"error": "ok"}


@pytest.mark.parametrize("text", [
    'wrong({"error":"ok"})', 'xduwlan_cb([])', 'xduwlan_cb(null)',
    'xduwlan_cb({broken})', 'xduwlan_cb({});alert(1)',
    'xduwlan_cb({"challenge": NaN})',
])
def test_malformed_jsonp_is_safe_protocol_error(text):
    with pytest.raises(PortalProtocolError) as info:
        parse_jsonp(text, "xduwlan_cb")
    assert text not in str(info.value)


def test_context_repr_hides_network_identity():
    context = PortalContext("https://portal.example.test/private-marker", "192.0.2.10", "8")
    assert "192.0.2.10" not in repr(context)
    assert "private-marker" not in repr(context)
