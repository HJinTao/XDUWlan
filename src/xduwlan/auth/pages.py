"""解析入口结构并约束可信目标，不运行页面脚本。"""

from __future__ import annotations

import ipaddress
import re
from dataclasses import dataclass, field
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, urlunsplit

from xduwlan.auth.interfaces import PortalContext
from xduwlan.errors import PortalProtocolError


@dataclass(frozen=True)
class PortalNavigation:
    """表示一次已校验、无凭据的页面导航。"""

    method: str
    url: str = field(repr=False)


def trusted_portal_url(target: str, base_url: str, portal_url: str) -> str:
    """精确校验主机与默认端口，并把可信 HTTP 入口提升到 HTTPS。"""
    try:
        if any(ord(char) < 33 for char in target) or "\\" in target:
            raise ValueError
        trusted = urlsplit(portal_url)
        parsed = urlsplit(urljoin(base_url, target))
        if (trusted.scheme != "https" or not trusted.hostname or trusted.port not in (None, 443)
                or trusted.username is not None or trusted.password is not None
                or trusted.query or trusted.fragment):
            raise ValueError
        if (parsed.scheme not in ("http", "https") or parsed.hostname != trusted.hostname
                or parsed.username is not None or parsed.password is not None or parsed.fragment
                or parsed.port not in (None, 80 if parsed.scheme == "http" else 443)):
            raise ValueError
        return urlunsplit(("https", trusted.hostname, parsed.path or "/", parsed.query, ""))
    except (ValueError, TypeError):
        raise PortalProtocolError("Portal 目标不可信") from None


class _NavigationParser(HTMLParser):
    """只采集空 POST 表单与 meta refresh 的结构信息。"""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.forms = []
        self.has_controls = False
        self.refreshes = []
        self.ambiguous = False

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if len(attributes) != len(attrs):
            self.ambiguous = True
        if tag == "form":
            self.forms.append(attributes)
        elif tag in {"input", "textarea", "select", "button"}:
            self.has_controls = True
        elif tag == "meta" and (attributes.get("http-equiv") or "").lower() == "refresh":
            content = attributes.get("content") or ""
            match = re.fullmatch(r"\s*\d+(?:\.\d+)?\s*;\s*url\s*=\s*(.+?)\s*", content, re.I)
            if match:
                self.refreshes.append(match.group(1).strip("\"'"))


def find_portal_navigation(body: str, base_url: str, portal_url: str) -> PortalNavigation | None:
    """返回唯一可信导航；未知或有输入字段的表单不重放。"""
    parser = _NavigationParser()
    parser.feed(body)
    if parser.ambiguous:
        return None
    candidates = [("GET", target) for target in parser.refreshes]
    if len(parser.forms) == 1 and not parser.has_controls:
        form = parser.forms[0]
        if (form.get("method") or "").lower() == "post" and form.get("action"):
            candidates.append(("POST", form["action"]))
    if len(candidates) != 1:
        return None
    method, target = candidates[0]
    return PortalNavigation(method, trusted_portal_url(target, base_url, portal_url))


def _config_block(body: str) -> str:
    match = re.search(r"\b(?:var|let|const)\s+CONFIG\s*=\s*\{", body)
    if not match:
        raise PortalProtocolError("Portal 页面缺少认证上下文")
    start = match.end() - 1
    depth = 0
    quote = None
    escaped = False
    for index in range(start, len(body)):
        char = body[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return body[start:index + 1]
    raise PortalProtocolError("Portal 上下文格式不符合预期")


def parse_portal_context(body: str, portal_url: str) -> PortalContext:
    """提取已观察的 ip/acid 字段；IPv6 与不完整上下文安全失败。"""
    origin = trusted_portal_url("/", portal_url, portal_url).rstrip("/")
    block = _config_block(body)
    values = {}
    for name in ("ip", "acid"):
        matches = re.findall(rf'''(?<![\w$])["']?{name}["']?\s*:\s*["']([^"'\\]*)["']''', block)
        if len(matches) != 1:
            raise PortalProtocolError("Portal 上下文格式不符合预期")
        values[name] = matches[0]
    try:
        ipaddress.IPv4Address(values["ip"])
        if not re.fullmatch(r"[1-9][0-9]{0,9}", values["acid"]):
            raise ValueError
    except ValueError:
        raise PortalProtocolError("Portal 上下文不受支持") from None
    return PortalContext(origin, values["ip"], values["acid"])
