#!/usr/bin/env bash
# Runs the two-process multiplayer test (host + client) on localhost.
# Usage: tools/run_net_test.sh [path/to/godot]
set -u
GODOT="${1:-${GODOT:-godot}}"
PORT="${PORT:-7788}"
cd "$(dirname "$0")/.."

"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=host --port="$PORT" > /tmp/net_test_host.log 2>&1 &
HOST_PID=$!
"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=client --port="$PORT" > /tmp/net_test_client.log 2>&1
CLIENT_CODE=$?
wait "$HOST_PID"
HOST_CODE=$?

grep -h "^\[host\]\|^\[client\]\|SCRIPT ERROR\|ERROR:" /tmp/net_test_host.log /tmp/net_test_client.log \
  | grep -v "leaked\|still in use\|RID allocations"
echo "host exit=$HOST_CODE client exit=$CLIENT_CODE"
[ "$HOST_CODE" -eq 0 ] && [ "$CLIENT_CODE" -eq 0 ]
