#!/usr/bin/env bash
set -euo pipefail

# 仅接受私有 IPv4 SSH 目标；脚本不读取密码、不接受任意远端命令。
ssh_destination=${XDUWLAN_SSH_DESTINATION:-}
local_port=${XDUWLAN_LOCAL_PROXY_PORT:-}
thinkpad_port=${XDUWLAN_THINKPAD_PROXY_PORT:-}
simulator=${XDUWLAN_SIMULATOR_DEVICE:-booted}

ssh_user=${ssh_destination%@*}
ssh_host=${ssh_destination##*@}
valid_private_host=false
if [[ "$ssh_user" =~ ^[A-Za-z0-9._-]+$ && "$ssh_host" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
  IFS=. read -r octet1 octet2 octet3 octet4 <<<"$ssh_host"
  if ((10#$octet1 <= 255 && 10#$octet2 <= 255 && 10#$octet3 <= 255 && 10#$octet4 <= 255)); then
    if ((10#$octet1 == 10)) ||
      ((10#$octet1 == 172 && 10#$octet2 >= 16 && 10#$octet2 <= 31)) ||
      ((10#$octet1 == 192 && 10#$octet2 == 168)); then
      valid_private_host=true
    fi
  fi
fi
if [[ "$valid_private_host" != true ]]; then
  printf '%s\n' 'XDUWLAN_SSH_DESTINATION must be user@RFC1918-IPv4' >&2
  exit 2
fi

is_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

if ! is_port "$local_port" || ! is_port "$thinkpad_port"; then
  printf '%s\n' 'proxy ports must be numeric values from 1 through 65535' >&2
  exit 2
fi

if [[ ! "$simulator" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf '%s\n' 'XDUWLAN_SIMULATOR_DEVICE must be a simulator name or UDID' >&2
  exit 2
fi

ssh -o ExitOnForwardFailure=yes -N \
  -L "${local_port}:127.0.0.1:${thinkpad_port}" \
  "$ssh_destination" &
ssh_pid=$!
cleanup() {
  kill "$ssh_pid" 2>/dev/null || true
  wait "$ssh_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

forward_ready=false
for _ in {1..20}; do
  if (exec 3<>"/dev/tcp/127.0.0.1/${local_port}") 2>/dev/null; then
    exec 3>&-
    forward_ready=true
    break
  fi
  sleep 0.25
done
if [[ "$forward_ready" != true ]]; then
  printf '%s\n' 'SSH local forwarding did not become ready' >&2
  exit 1
fi

# Debug 构造才接收代理；Release 与后台构造没有该 dart-define。
flutter run -d "$simulator" \
  --dart-define=XDUWLAN_TEST_PROXY_ENABLED=true \
  --dart-define=XDUWLAN_TEST_PROXY_HOST=127.0.0.1 \
  --dart-define="XDUWLAN_TEST_PROXY_PORT=${local_port}" &
flutter_pid=$!
trap 'kill "$flutter_pid" 2>/dev/null || true; cleanup' EXIT INT TERM

# 单次无凭据 HTTPS 探测，只观察代理是否能建立 CONNECT 链路。
curl --fail --silent --show-error --max-time 10 \
  --proxy "http://127.0.0.1:${local_port}" \
  --output /dev/null \
  'https://connect.rom.miui.com/generate_204'

kill "$flutter_pid" 2>/dev/null || true
wait "$flutter_pid" 2>/dev/null || true
