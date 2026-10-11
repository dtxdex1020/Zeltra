#!/bin/sh
# Zeltra: container entrypoint (Dockerfile / Railway).
#  - writes bot/secrets.lua from environment variables (see bot/env-secrets.lua)
#  - keeps the SQLite database in $DATA_DIR (default /data, mount a persistent volume there)
#  - optional one-time seed: if $DATA_DIR/data.db does not exist and SEED_DB_B64 is set
#    (base64 of a gzip'd SQLite file), it is restored before the bot starts
#  - BOT_HOLD=1 keeps the container idle without logging in to Discord (useful during a migration)
set -eu
cd "$(dirname "$0")/../bot"

DATA_DIR="${DATA_DIR:-/data}"
export DATA_DIR
mkdir -p "$DATA_DIR"

if [ ! -f "$DATA_DIR/data.db" ] && [ -n "${SEED_DB_B64:-}" ]; then
  echo "[start] Seeding $DATA_DIR/data.db from SEED_DB_B64"
  printf '%s' "$SEED_DB_B64" | base64 -d | gunzip > "$DATA_DIR/data.db.seed"
  if [ "$(sqlite3 "$DATA_DIR/data.db.seed" 'PRAGMA integrity_check;')" = "ok" ]; then
    mv "$DATA_DIR/data.db.seed" "$DATA_DIR/data.db"
    echo "[start] Seed database restored"
  else
    echo "[start] Seed database failed the integrity check, not using it" >&2
    rm -f "$DATA_DIR/data.db.seed"
    exit 1
  fi
fi
unset SEED_DB_B64

# one-time backup before any gated seed (bot/seeds/), seeds are skipped if the backup fails
if { [ "${SEED_INFRACTION_TYPES:-0}" = "1" ] || [ "${SEED_LOG_CHANNELS:-0}" = "1" ] || [ "${SEED_SECURITY:-0}" = "1" ] || [ "${SEED_TICKETS:-0}" = "1" ] || [ "${SEED_WELCOME:-0}" = "1" ]; } && [ -f "$DATA_DIR/data.db" ]; then
  mkdir -p "$DATA_DIR/sqlbackups"
  BACKUP="$DATA_DIR/sqlbackups/data-$(date -u +%Y%m%d-%H%M%S)-pre-seed.db"
  if sqlite3 "$DATA_DIR/data.db" ".backup '$BACKUP'" && [ "$(sqlite3 "$BACKUP" 'PRAGMA integrity_check;')" = "ok" ]; then
    echo "[start] Backed up database to $BACKUP ($(wc -c < "$BACKUP") bytes)"
  else
    echo "[start] Database backup failed, not running seeds" >&2
    unset SEED_INFRACTION_TYPES SEED_LOG_CHANNELS SEED_SECURITY SEED_TICKETS SEED_WELCOME
  fi
fi

if [ -f "$DATA_DIR/data.db" ]; then
  echo "[start] Using database $DATA_DIR/data.db ($(wc -c < "$DATA_DIR/data.db") bytes)"
else
  echo "[start] No database in $DATA_DIR yet, the bot will create a new one"
fi

if [ "${SECRETS_FROM_ENV:-1}" = "1" ] || [ ! -f secrets.lua ]; then
  cp env-secrets.lua secrets.lua
  chmod 600 secrets.lua
fi

if [ "${BOT_HOLD:-0}" = "1" ]; then
  echo "[start] BOT_HOLD=1: build and volume OK, not starting the bot"
  exec sleep infinity
fi

export LUA_CPATH="${LUA_CPATH:-/usr/local/lib/lua/5.1/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;/usr/lib/x86_64-linux-gnu/?.so;;}"
exec ./luvit main.lua
