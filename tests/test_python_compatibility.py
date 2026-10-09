"""使用当前解释器验证配置模块在独立进程中可运行。"""

import subprocess
import sys


def test_config_loads_and_wraps_invalid_toml_in_current_interpreter(tmp_path):
    """旧版解释器缺少标准库 TOML 时，兼容依赖仍须保持配置契约。"""
    valid = tmp_path / "valid.toml"
    invalid = tmp_path / "invalid.toml"
    valid.write_text("request_timeout_seconds = 7\n", encoding="utf-8")
    invalid.write_text("request_timeout_seconds = [", encoding="utf-8")
    source = '''
import sys
from pathlib import Path
from xduwlan.config import AppConfig
from xduwlan.errors import ConfigurationError
assert AppConfig.load(Path(sys.argv[1])).request_timeout_seconds == 7
try:
    AppConfig.load(Path(sys.argv[2]))
except ConfigurationError:
    pass
else:
    raise AssertionError("非法 TOML 必须转换为配置错误")
'''
    result = subprocess.run(
        [sys.executable, "-c", source, str(valid), str(invalid)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
