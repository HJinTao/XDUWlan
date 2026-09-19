# 00. Python CLI 骨架

## 本节问题

如何用 Python 标准库建立一个可安装、可测试、可扩展的子命令 CLI？

## 本节目标

- 使用 `argparse.ArgumentParser` 创建顶层解析器；
- 使用 `add_subparsers` 注册 `status`、`login`、`watch`、`account` 和 `configure`；
- 使用 `project.scripts` 暴露 `xduwlan` 命令；
- 让测试可以直接调用 `main(list[str])`，而不依赖真实终端进程。

## 文件与符号

- `pyproject.toml`：声明项目元数据、`pytest` 测试依赖和 `xduwlan = xduwlan.cli:main` 入口。
- `src/xduwlan/__init__.py`：保存包版本 `__version__`。
- `src/xduwlan/cli.py`：
  - `COMMANDS`：当前已注册的命令名；
  - `_handle_placeholder(args)`：任务 1 的占位处理器；
  - `build_parser()`：创建解析器并注册子命令；
  - `main(argv)`：解析参数，处理无命令情况并调用命令处理器。
- `tests/test_cli.py`：验证帮助、未知命令和五个命令的最小行为。

## 调用流程

```text
console script xduwlan
  -> xduwlan.cli.main()
  -> build_parser()
  -> parse_args(argv)
  -> 无命令：print_help()，返回 0
  -> 有命令：调用占位处理器，返回 0
  -> 未知命令：argparse 退出并使用状态码 2
```

## API 检索问题

- `argparse.ArgumentParser` 如何生成帮助文本？
- `add_subparsers(dest=...)` 如何保存选中的子命令？
- `set_defaults(handler=...)` 如何把子命令映射到处理函数？
- `project.scripts` 如何把 Python 函数安装为命令？
- pytest 的 `capsys` 如何捕获标准输出？

## 测试条件和结果

在 Conda 环境 `xduwlan`（Python 3.11.16、pytest 9.1.1）中运行：

```bash
python -m pytest tests/test_cli.py -q
```

预期并已验证：7 个测试通过。editable 安装后，`xduwlan --help` 能显示五个子命令。

## 当前边界

五个命令目前只有占位处理器，不读取配置、不访问网络、不读取凭据。后续任务会逐步替换占位处理器，但保留 `main` 和解析器的边界。
