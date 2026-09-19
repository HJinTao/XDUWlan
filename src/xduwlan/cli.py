"""XDUWlan 命令行入口。"""

from __future__ import annotations

import argparse


COMMANDS = ("status", "login", "watch", "account", "configure")


def _handle_placeholder(_args: argparse.Namespace) -> int:
    """在命令接入应用服务前提供成功占位结果。"""
    return 0


def build_parser() -> argparse.ArgumentParser:
    """创建顶层解析器并注册当前命令骨架。"""
    parser = argparse.ArgumentParser(
        prog="xduwlan",
        description="西电校园网认证与状态监测工具",
    )
    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND")

    for command in COMMANDS:
        command_parser = subparsers.add_parser(command, help=f"执行 {command} 命令")
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
