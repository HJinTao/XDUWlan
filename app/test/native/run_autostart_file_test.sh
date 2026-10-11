#!/bin/bash
# 仅在临时目录验证 Linux 启动项文件，不注册真实用户登录项。
set -euo pipefail
native_test_root="$(cd "$(dirname "$0")/../.." && pwd)"
workspace_tmp="$(mktemp -d "${TMPDIR:-/tmp}/xduwlan-autostart-build.XXXXXX")"
trap 'rm -rf "$workspace_tmp"' EXIT
"${CXX:-c++}" -std=c++14 -Wall -Wextra -Werror \
  -I "$native_test_root/linux/runner" \
  "$native_test_root/linux/runner/autostart_file.cc" \
  "$native_test_root/test/native/autostart_file_test.cc" \
  -o "$workspace_tmp/autostart-file-test"
"$workspace_tmp/autostart-file-test"
