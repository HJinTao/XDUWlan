#!/bin/bash
# 仅在临时目录验证原生登录启动配置，不启动产品或修改用户登录项。
set -euo pipefail
native_test_root="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -n "${XDUWLAN_FLUTTER_SDK:-}" ]]; then
  flutter_sdk="$XDUWLAN_FLUTTER_SDK"
else
  flutter_sdk="$(dirname "$(dirname "$(command -v flutter)")")"
fi
frameworks="$flutter_sdk/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64"
workspace_tmp="$(mktemp -d "${TMPDIR:-/tmp}/xduwlan-native-test.XXXXXX")"
trap 'rm -rf "$workspace_tmp"' EXIT
swiftc -F "$frameworks" -framework FlutterMacOS \
  -Xlinker -rpath -Xlinker "$frameworks" \
  "$native_test_root/macos/Runner/MainFlutterWindow.swift" \
  "$native_test_root/test/native/plugin_registration_stub.swift" \
  "$native_test_root/test/native/login_agent_test.swift" \
  -o "$workspace_tmp/login-agent-test"
"$workspace_tmp/login-agent-test"
