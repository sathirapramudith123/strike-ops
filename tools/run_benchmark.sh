#!/usr/bin/env bash
# Runs the built-in benchmark (see scripts/tools/benchmark_runner.gd).
#
#   tools/run_benchmark.sh [path/to/godot] [extra benchmark args...]
#
# Examples:
#   tools/run_benchmark.sh godot                         # current settings, all maps
#   tools/run_benchmark.sh godot --preset low --bots 16  # Low preset, 16 bots
#   tools/run_benchmark.sh godot --preset low --set dynamic_lights=true   # A/B one option
#   tools/run_benchmark.sh godot --no-batching           # A/B static batching
#
# Needs a display (it renders). On a headless Linux box it uses xvfb-run
# automatically; results there are CPU/software-rendered and only useful
# for comparing changes, not for real FPS.
set -u
GODOT="${1:-${GODOT:-godot}}"
shift || true
cd "$(dirname "$0")/.."
ARGS=(--path . --windowed --resolution 1280x720 -- --benchmark --quit "$@")
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" "${ARGS[@]}" 2>&1 | grep "\[benchmark\]"
else
  "$GODOT" "${ARGS[@]}" 2>&1 | grep "\[benchmark\]"
fi
