from xduwlan.cli import main
import pytest


def test_main_without_command_prints_help(capsys):
    """无命令时应展示可用子命令，并以成功状态结束。"""
    assert main([]) == 0

    output = capsys.readouterr().out
    assert "status" in output
    assert "login" in output
    assert "watch" in output
    assert "account" in output
    assert "configure" in output


def test_unknown_command_uses_argparse_error_exit():
    """未知命令交给 argparse 处理，并使用约定的退出码 2。"""
    try:
        main(["not-a-command"])
    except SystemExit as exc:
        assert exc.code == 2
    else:
        raise AssertionError("未知命令必须触发 argparse 的 SystemExit(2)")


@pytest.mark.parametrize("command", ["status", "login", "watch", "account", "configure"])
def test_registered_command_returns_success(command):
    """任务 1 中注册的命令先具备可调用的最小处理器。"""
    assert main([command]) == 0
