"""深澜参数编码；所有函数均不访问网络或凭据库。"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import re

from xduwlan.auth.interfaces import PortalContext
from xduwlan.credentials import Credentials
from xduwlan.errors import PortalProtocolError

PORTAL_ALPHABET = "LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA"
STANDARD_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
MASK = 0xFFFFFFFF
DELTA = 0x9E3779B9
N = "200"
TYPE = "1"
ENC_VER = "srun_bx1"


def _pack_words(text: str, include_length: bool) -> list[int]:
    """按 JavaScript charCodeAt 的 UTF-16 单元装包，保留高位重叠语义。"""
    raw = text.encode("utf-16-le", errors="surrogatepass")
    units = [int.from_bytes(raw[i:i + 2], "little") for i in range(0, len(raw), 2)]
    words = []
    for start in range(0, len(units), 4):
        word = 0
        for offset, unit in enumerate(units[start:start + 4]):
            word |= unit << (8 * offset)
        words.append(word & MASK)
    if include_length:
        words.append(len(units))
    return words


def _xencode(message: str, key: str) -> bytes:
    """复现已观察的 XEncode 位运算，而非通用 XXTEA 库的默认变体。"""
    if not message:
        return b""
    words = _pack_words(message, True)
    keys = _pack_words(key, False)
    keys.extend([0] * max(0, 4 - len(keys)))
    size = len(words)
    z = words[-1]
    total = 0
    for _ in range(6 + 52 // size):
        total = (total + DELTA) & MASK
        e = (total >> 2) & 3
        for p in range(size):
            y = words[(p + 1) % size]
            mix = (z >> 5) ^ ((y << 2) & MASK)
            mix += (y >> 3) ^ ((z << 4) & MASK) ^ total ^ y
            mix += keys[(p & 3) ^ e] ^ z
            z = words[p] = (words[p] + mix) & MASK
    return b"".join(word.to_bytes(4, "little") for word in words)


def build_login_params(
    credentials: Credentials, context: PortalContext, challenge: str,
    callback: str, timestamp: int,
) -> dict[str, str | int]:
    """按已观察的字段顺序构造一次登录请求，不暴露原始密码。"""
    hmd5 = hmac.new(challenge.encode("utf-8"), credentials.password.encode("utf-8"), hashlib.md5).hexdigest()
    plain = json.dumps({
        "username": credentials.username, "password": credentials.password,
        "ip": context.ip, "acid": context.acid, "enc_ver": ENC_VER,
    }, separators=(",", ":"), ensure_ascii=False)
    encoded = base64.b64encode(_xencode(plain, challenge)).decode("ascii")
    info = "{SRBX1}" + encoded.translate(str.maketrans(STANDARD_ALPHABET, PORTAL_ALPHABET))
    checksum = hashlib.sha1("".join(
        challenge + value for value in (
            credentials.username, hmd5, context.acid, context.ip, N, TYPE, info,
        )
    ).encode("utf-8")).hexdigest()
    return {
        "callback": callback, "action": "login", "username": credentials.username,
        "password": "{MD5}" + hmd5, "os": "Python", "name": "XDUWlan",
        "double_stack": 0, "chksum": checksum, "info": info,
        "ac_id": context.acid, "ip": context.ip, "n": N, "type": TYPE, "_": timestamp,
    }


def parse_jsonp(text: str, callback: str) -> dict:
    """只接受匹配的回调和严格 JSON 对象，绝不执行 JavaScript。"""
    def reject_constant(_value):
        raise ValueError

    body = text.strip().removesuffix(";")
    prefix = callback + "("
    if not re.fullmatch(r"[A-Za-z_$][\w$]*", callback, flags=re.ASCII):
        raise PortalProtocolError("Portal 回调格式不符合预期")
    if not body.startswith(prefix) or not body.endswith(")"):
        raise PortalProtocolError("Portal 回调格式不符合预期")
    try:
        result = json.loads(body[len(prefix):-1], parse_constant=reject_constant)
    except (ValueError, RecursionError):
        raise PortalProtocolError("Portal 响应不是有效 JSON") from None
    if not isinstance(result, dict):
        raise PortalProtocolError("Portal 响应不是对象")
    return result
