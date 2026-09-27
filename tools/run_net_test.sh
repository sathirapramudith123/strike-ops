#!/usr/bin/env bash
# Runs the two-process multiplayer tests (host + client) on localhost:
# a Team Deathmatch round with map rotation, then a Bomb Defusal match.
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

# Second match: Bomb Defusal (plant, defuse, elimination, explosion).
BPORT=$((PORT + 1))
"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=bomb_host --port="$BPORT" > /tmp/net_test_bomb_host.log 2>&1 &
BHOST_PID=$!
"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=bomb_client --port="$BPORT" > /tmp/net_test_bomb_client.log 2>&1
BCLIENT_CODE=$?
wait "$BHOST_PID"
BHOST_CODE=$?

grep -h "^\[host\]\|^\[client\]\|^\[bomb_host\]\|^\[bomb_client\]\|SCRIPT ERROR\|ERROR:" \
  /tmp/net_test_host.log /tmp/net_test_client.log /tmp/net_test_bomb_host.log /tmp/net_test_bomb_client.log \
  | grep -v "leaked\|still in use\|RID allocations"
echo "host exit=$HOST_CODE client exit=$CLIENT_CODE bomb_host exit=$BHOST_CODE bomb_client exit=$BCLIENT_CODE"
[ "$HOST_CODE" -eq 0 ] && [ "$CLIENT_CODE" -eq 0 ] && [ "$BHOST_CODE" -eq 0 ] && [ "$BCLIENT_CODE" -eq 0 ]
