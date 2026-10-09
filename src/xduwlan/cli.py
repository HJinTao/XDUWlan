"""XDUWlan 命令行入口。"""

from __future__ import annotations

import argparse
import getpass
import json
import sys
import warnings
from dataclasses import replace
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

from xduwlan.auth.client import SrunPortalClient
from xduwlan.auth.transport import SystemPortalTransport
from xduwlan.config import AppConfig
from xduwlan.credential_service import (
    CredentialConfigurator,
    DefaultCredentialConfigurator,
)
from xduwlan.errors import (
    ConfigurationError,
    CredentialStoreError,
    CredentialValidationError,
    PortalProtocolError,
)
from xduwlan.keyring_store import KeyringCredentialStore
from xduwlan.models import NetworkState
from xduwlan.login_service import DefaultLoginService, LoginService, LoginState
from xduwlan.probe.dns import SystemDnsResolver
from xduwlan.probe.http import SystemHttpConnectivityChecker
from xduwlan.probe.interfaces import NetworkProbe
from xduwlan.probe.service import DefaultNetworkProbe
from xduwlan.probe.tcp import SystemTcpConnector

_STATUS_RESULTS = {
    NetworkState.ONLINE: ("已联网", 0),
    NetworkState.PORTAL_REQUIRED: ("需要认证", 4),
    NetworkState.LOCAL_NETWORK_DOWN: ("本地网络不可用", 5),
    NetworkState.INTERNET_UNREACHABLE: ("互联网不可达", 5),
    NetworkState.UNKNOWN: ("无法确定网络状态", 1),
}

COMMANDS = ("status", "login", "configure")


_LOGIN_RESULTS = {
    LoginState.ALREADY_ONLINE: ("已联网，无需认证", 0),
    LoginState.RESTORED: ("联网已恢复", 0),
    LoginState.CREDENTIALS_MISSING: ("尚未配置凭据，请先运行 xduwlan configure", 3),
    LoginState.CREDENTIALS_INVALID: ("凭据输入无效，请重新运行 xduwlan configure", 2),
    LoginState.CREDENTIAL_STORE_FAILED: ("系统凭据库读取失败，请检查或解锁凭据库", 1),
    LoginState.NETWORK_UNAVAILABLE: ("网络不可达，请先确认 Wi-Fi 连接", 5),
    LoginState.UNKNOWN_NETWORK: ("无法确认需要认证，请检查校园网连接后重试", 1),
    LoginState.AUTH_REJECTED: ("Portal 拒绝认证，请检查账号、密码或账户限制", 6),
    LoginState.PORTAL_UNAVAILABLE: ("Portal 暂时不可用，请检查连接后重试", 5),
    LoginState.PROTOCOL_ERROR: ("Portal 协议或可信目标不符合预期，请检查配置或更新程序", 7),
    LoginState.VERIFICATION_FAILED: ("认证已提交，但联网验证未通过，请稍后检查网络", 8),
}


def _http_entry_url(url: str) -> str:
    """为标准 HTTPS 探测端点构造无凭据的 HTTP 入口。"""
    parts = urlsplit(url)
    if parts.scheme != "https" or parts.port not in (None, 443):
        return url
    host = parts.hostname
    netloc = f"[{host}]" if ":" in host else host
    return urlunsplit(("http", netloc, parts.path, parts.query, ""))


def build_login_service(config: AppConfig) -> LoginService:
    """装配一次恢复服务；构造时不请求网络或读取系统凭据。"""
    return DefaultLoginService(
        build_network_probe(config), KeyringCredentialStore(),
        SrunPortalClient(config.portal_url, _http_entry_url(config.probe_url),
                         config.request_timeout_seconds, SystemPortalTransport()),
        operator_suffix=config.operator_suffix,
    )


def build_network_probe(config: AppConfig) -> NetworkProbe:
    """根据配置装配完整探测服务与系统阶段适配器。"""
    fallback_url = _http_entry_url(config.probe_url)
    fallback = None
    if fallback_url != config.probe_url:
        fallback = DefaultNetworkProbe(
            replace(config, probe_url=fallback_url), SystemDnsResolver(),
            SystemTcpConnector(), SystemHttpConnectivityChecker(),
        )
    return DefaultNetworkProbe(
        config=config,
        dns_resolver=SystemDnsResolver(),
        tcp_connector=SystemTcpConnector(),
        http_checker=SystemHttpConnectivityChecker(),
        fallback_probe=fallback,
    )


def build_credential_configurator() -> CredentialConfigurator:
    """装配凭据配置应用服务与系统凭据库适配器。"""
    return DefaultCredentialConfigurator(KeyringCredentialStore())


def _handle_configure(_args: argparse.Namespace) -> int:
    """交互收集校园网凭据并安全保存。"""
    try:
        username = input("账号: ")
        with warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            password = getpass.getpass("密码: ")
    except getpass.GetPassWarning:
        print("无法安全隐藏密码", file=sys.stderr)
        return 1
    except (EOFError, KeyboardInterrupt):
        print("输入已取消", file=sys.stderr)
        return 130

    try:
        build_credential_configurator().configure(username, password)
    except CredentialValidationError:
        print("凭据输入无效", file=sys.stderr)
        return 2
    except CredentialStoreError:
        print("凭据保存失败", file=sys.stderr)
        return 1
    print("凭据已保存")
    return 0


def _handle_status(args: argparse.Namespace) -> int:
    """读取配置、执行探测并输出非敏感状态。"""
    try:
        if args.config is not None:
            config = AppConfig.load(Path(args.config))
        else:
            config = AppConfig.defaults()
    except (ConfigurationError, OSError):
        print("配置读取失败", file=sys.stderr)
        return 2

    probe = build_network_probe(config)
    result = probe.probe()
    message, exit_code = _STATUS_RESULTS[result.state]
    if args.json:
        observations = []
        for observation in result.observations:
            observations.append(
                {
                    "stage": observation.stage.value,
                    "succeeded": observation.succeeded,
                    "elapsed_ms": observation.elapsed_ms,
                }
            )
        payload = {
            "state": result.state.value,
            "observations": observations,
        }
        print(json.dumps(payload, ensure_ascii=False))
    else:
        print(message)
        if args.debug:
            for observation in result.observations:
                status_text = "成功" if observation.succeeded else "失败"
                print(
                    f"{observation.stage.value}: {status_text}, "
                    f"{observation.elapsed_ms} ms, {observation.detail}"
                )
    return exit_code


def _handle_login(args: argparse.Namespace) -> int:
    """执行一次恢复，输出固定结果与脱敏阶段信息。"""
    try:
        config = AppConfig.load(Path(args.config)) if args.config is not None else AppConfig.defaults()
        service = build_login_service(config)
    except (ConfigurationError, OSError, PortalProtocolError):
        print("配置读取失败", file=sys.stderr)
        return 2
    try:
        result = service.login()
    except KeyboardInterrupt:
        print("操作已取消", file=sys.stderr)
        return 130
    message, exit_code = _LOGIN_RESULTS[result.state]
    if args.json:
        print(json.dumps({
            "state": result.state.value, "network_state": result.network_state.value,
            "observations": [{"stage": item.stage.value, "succeeded": item.succeeded,
                              "elapsed_ms": item.elapsed_ms} for item in result.observations],
        }, ensure_ascii=False))
    else:
        stream = sys.stdout if exit_code == 0 else sys.stderr
        print(message, file=stream)
        if args.debug:
            for item in result.observations:
                state = "成功" if item.succeeded else "失败"
                print(f"{item.stage.value}: {state}, {item.elapsed_ms} ms", file=stream)
    return exit_code


def build_parser() -> argparse.ArgumentParser:
    """创建顶层解析器并注册当前命令骨架。"""
    parser = argparse.ArgumentParser(
        prog="xduwlan",
        description="西电校园网一次认证恢复工具",
    )
    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND")

    for command in COMMANDS:
        command_parser = subparsers.add_parser(command, help=f"执行 {command} 命令")
        if command in ("status", "login"):
            command_parser.add_argument("--config", metavar="PATH")
            command_parser.add_argument("--json", action="store_true")
            command_parser.add_argument("--debug", action="store_true")
            command_parser.set_defaults(handler=_handle_status if command == "status" else _handle_login)
        elif command == "configure":
            command_parser.set_defaults(handler=_handle_configure)

    return parser


def main(argv: list[str] | None = None) -> int:
    """解析 ``argv`` 并运行选中的命令骨架。"""
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 0

    return args.handler(args)
