"""XDUWlan 命令行入口。"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from xduwlan.config import AppConfig
from xduwlan.errors import ConfigurationError
from xduwlan.models import NetworkState
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

COMMANDS = ("status", "login", "watch", "account", "configure")


def _handle_placeholder(_args: argparse.Namespace) -> int:
    """在命令接入应用服务前提供成功占位结果。"""
    return 0


def build_network_probe(config: AppConfig) -> NetworkProbe:
    """根据配置装配完整探测服务与系统阶段适配器。"""
    return DefaultNetworkProbe(
        config=config,
        dns_resolver=SystemDnsResolver(),
        tcp_connector=SystemTcpConnector(),
        http_checker=SystemHttpConnectivityChecker(),
    )


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


def build_parser() -> argparse.ArgumentParser:
    """创建顶层解析器并注册当前命令骨架。"""
    parser = argparse.ArgumentParser(
        prog="xduwlan",
        description="西电校园网认证与状态监测工具",
    )
    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND")

    for command in COMMANDS:
        command_parser = subparsers.add_parser(command, help=f"执行 {command} 命令")
        if command == "status":
            command_parser.add_argument("--config", metavar="PATH")
            command_parser.add_argument("--json", action="store_true")
            command_parser.add_argument("--debug", action="store_true")
            command_parser.set_defaults(handler=_handle_status)
        else:
            command_parser.set_defaults(handler=_handle_placeholder)

    return parser


def main(argv: list[str] | None = None) -> int:
    """解析 ``argv`` 并运行选中的命令骨架。"""
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 0

    return args.handler(args)
