#!/usr/bin/env sh
# Starts the dedicated server. Everything after the script name is passed on:
#   ./run_server.sh --port 7777 --max-players 16 --mode tdm --map docks
cd "$(dirname "$0")"
exec ./FPSGame-server.x86_64 --headless -- --server "$@"
