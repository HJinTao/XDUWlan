"""Command-line entry point for XDUWlan."""

from __future__ import annotations

import argparse


COMMANDS = ("status", "login", "watch", "account", "configure")


def _handle_placeholder(_args: argparse.Namespace) -> int:
    """Return success until a command receives its application service."""
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the top-level parser and register the current command skeleton."""
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
    """Parse ``argv`` and run the selected command skeleton."""
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 0

    return args.handler(args)
