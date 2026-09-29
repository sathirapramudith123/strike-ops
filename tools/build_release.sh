#!/usr/bin/env bash
# Builds every release package into dist/.
#
#   tools/build_release.sh [path/to/godot] [--verify]
#
# Needs Godot 4.4.x and its export templates installed
# (Editor → Manage Export Templates, or unpack the .tpz into
#  ~/.local/share/godot/export_templates/<version>/).
#
# Output (VERSION from project.godot):
#   dist/StrikeOps-VERSION-windows-x86_64.zip      game for Windows (+ installer via CI)
#   dist/StrikeOps-VERSION-linux-x86_64.tar.gz     game for Linux (+ .desktop file)
#   dist/StrikeOps-VERSION-macos-universal.zip     game for macOS (ad-hoc signed)
#   dist/StrikeOps-VERSION-server-linux-x86_64.tar.gz  headless dedicated server
#   dist/SHA256SUMS
#
# --verify boots the exported builds: the server must accept a client and the
# Linux game must load every map (headless benchmark).
set -euo pipefail
GODOT="${1:-${GODOT:-godot}}"
VERIFY=0
[ "${2:-}" = "--verify" ] && VERIFY=1
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
CHANNEL=$(sed -n 's/^config\/release_channel="\(.*\)"/\1/p' project.godot)
[ -n "$CHANNEL" ] && VERSION="$VERSION-$CHANNEL"
echo "== Building Strike Ops $VERSION"

rm -rf builds dist
mkdir -p builds/windows builds/linux builds/macos builds/server dist
"$GODOT" --headless --path . --editor --quit >/dev/null 2>&1 || true   # (re)import

export_preset() {
  echo "-- export: $1"
  "$GODOT" --headless --path . --export-release "$1" 2>&1 | grep -iE "^ERROR|error:" && { echo "export of $1 failed"; exit 1; } || true
  [ -s "$2" ] || { echo "missing $2"; exit 1; }
}
export_preset "Windows Desktop" builds/windows/StrikeOps.exe
export_preset "Linux"           builds/linux/StrikeOps.x86_64
export_preset "macOS"           builds/macos/StrikeOps.zip
export_preset "Linux Server"    builds/server/StrikeOps-server.x86_64

# Player-facing notes go into every package.
cp installer/PLAYERS.txt builds/windows/README.txt
cp installer/PLAYERS.txt builds/linux/README.txt
cp installer/linux/strikeops.desktop icon.svg builds/linux/
cp server/README.md builds/server/README.md
cp server/run_server.sh builds/server/
# Licenses of the bundled Opus codec (BSD / MIT require shipping them).
for d in windows linux server macos; do
  cp addons/opus_voice/THIRD_PARTY_LICENSES.txt builds/$d/
done
(cd builds/macos && zip -q StrikeOps.zip THIRD_PARTY_LICENSES.txt)

echo "-- packaging"
(cd builds/windows && zip -qr "../../dist/StrikeOps-$VERSION-windows-x86_64.zip" .)
tar -czf "dist/StrikeOps-$VERSION-linux-x86_64.tar.gz" -C builds linux --transform "s,^linux,StrikeOps-$VERSION,"
cp builds/macos/StrikeOps.zip "dist/StrikeOps-$VERSION-macos-universal.zip"
tar -czf "dist/StrikeOps-$VERSION-server-linux-x86_64.tar.gz" -C builds server --transform "s,^server,StrikeOps-server-$VERSION,"
(cd dist && sha256sum ./*.zip ./*.tar.gz > SHA256SUMS)
ls -lh dist

if [ "$VERIFY" = 1 ]; then
  echo "-- verify: dedicated server + client"
  PORT=7797
  ./builds/server/StrikeOps-server.x86_64 --port "$PORT" > /tmp/fps_verify_server.log 2>&1 &
  SERVER=$!
  sleep 3
  "$GODOT" --headless --path . res://tests/net_test.tscn -- --role=observer --port="$PORT" 2>&1 | grep "^\[observer\]"
  kill -0 "$SERVER" || { echo "server died"; exit 1; }
  kill "$SERVER"; wait "$SERVER" 2>/dev/null || true
  echo "-- verify: Linux build loads every map"
  ./builds/linux/StrikeOps.x86_64 --headless -- --benchmark --duration 2 --bots 4 --quit 2>&1 | grep "\[benchmark\]" | tail -4
fi
echo "== Done: dist/"
