import pytest

from xduwlan.auth.pages import find_portal_navigation, parse_portal_context
from xduwlan.errors import PortalProtocolError


PORTAL = "https://portal.example.test"
ENTRY = "http://probe.example.test/generate_204"


def test_empty_post_form_is_upgraded_to_trusted_https():
    nav = find_portal_navigation(
        '<FORM METHOD="post" ACTION="http://portal.example.test/index_8.html"></FORM>', ENTRY, PORTAL,
    )
    assert (nav.method, nav.url) == ("POST", PORTAL + "/index_8.html")


def test_meta_refresh_is_relative_to_trusted_page_and_unescapes_query():
    nav = find_portal_navigation(
        '<meta content="0; URL=/srun_portal_pc?ac_id=8&amp;theme=test" http-equiv="Refresh">',
        PORTAL + "/index_8.html", PORTAL,
    )
    assert (nav.method, nav.url) == ("GET", PORTAL + "/srun_portal_pc?ac_id=8&theme=test")


@pytest.mark.parametrize("target", [
    "https://portal.example.test.attacker.test/", "https://attacker.test/?next=portal.example.test",
    "https://user:secret@portal.example.test/", "https://portal.example.test:8443/",
    "javascript:alert(1)", "https://[invalid", "//attacker.test/",
])
def test_untrusted_form_target_is_rejected(target):
    with pytest.raises(PortalProtocolError):
        find_portal_navigation(f'<form method="post" action="{target}"></form>', ENTRY, PORTAL)


@pytest.mark.parametrize("html", [
    '<form action="https://portal.example.test/"><input name="password"></form>',
    '<form method="post" action="https://portal.example.test/"><textarea></textarea></form>',
    '<form method="get" action="https://portal.example.test/"></form>',
    '<form method="post" action="https://portal.example.test/"></form><form></form>',
])
def test_nonempty_or_ambiguous_form_is_not_replayed(html):
    assert find_portal_navigation(html, ENTRY, PORTAL) is None


def test_config_extracts_validated_context_without_executing_scripts():
    body = '<script>var CONFIG = {ip: "192.0.2.10", acid: "8", note: "} quote"};</script>'
    context = parse_portal_context(body, PORTAL)
    assert (context.ip, context.acid, context.portal_url) == ("192.0.2.10", "8", PORTAL)


@pytest.mark.parametrize("body", [
    'var CONFIG={ip:"not-an-ip",acid:"8"};',
    'var CONFIG={ip:"192.0.2.10",acid:"0"};',
    'var CONFIG={ip:"192.0.2.10"};',
    'var CONFIG={ip:"2001:db8::1",acid:"8"};',
    'var CONFIG={ip:"192.0.2.10",acid:"8",ip:"192.0.2.11"};',
])
def test_invalid_config_is_safe_protocol_error(body):
    with pytest.raises(PortalProtocolError):
        parse_portal_context(body, PORTAL)
