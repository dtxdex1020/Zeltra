#!/usr/bin/env bash
# Zeltra: start the bot natively (equivalent of the Dockerfile CMD, without the watchdog;
# use a supervisor such as pm2 or systemd for restarts).
set -euo pipefail
cd "$(dirname "$0")/../bot"
export LUA_CPATH="/usr/local/lib/lua/5.1/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;/usr/lib/x86_64-linux-gnu/?.so;;"
LUVIT="${LUVIT:-./luvit}"
[ -x "$LUVIT" ] || LUVIT="$(command -v luvit)"
exec "$LUVIT" main.lua
