#!/usr/bin/env bash
# Zeltra: install the runtime + Lua dependencies natively (no Docker), mirroring bot/Dockerfile.
# Upstream Ducky V1 does not ship its deps/ folder, so this pins the exact libraries Zeltra runs on.
#
#   Usage: scripts/install-deps.sh            (run from the repo root; needs git, curl, and apt for system libs)
#   Env:   LUVIT_DIR (default: bot/)          where luvit/lit/luvi binaries are placed
#          SKIP_APT=1                         skip apt-get (if the system libraries are already installed)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOT="$ROOT/bot"
LUVIT_DIR="${LUVIT_DIR:-$BOT}"

if [ "${SKIP_APT:-0}" != "1" ] && command -v apt-get >/dev/null; then
  SUDO=""; [ "$(id -u)" != "0" ] && SUDO="sudo"
  $SUDO apt-get update -q
  # same system packages as bot/Dockerfile (lua-cjson is loaded via LUA_CPATH, sqlite3 via FFI)
  $SUDO apt-get install -y -q git openssl ca-certificates lua-cjson libsqlite3-dev sqlite3 procps imagemagick libssl-dev wget make curl
fi

# luvit / lit / luvi
if [ ! -x "$LUVIT_DIR/luvit" ]; then
  mkdir -p "$LUVIT_DIR"
  (cd "$LUVIT_DIR" && curl -fsSL https://github.com/luvit/lit/raw/master/get-lit.sh | sh)
fi
LIT="$LUVIT_DIR/lit"

cd "$BOT"
mkdir -p deps

# Packages from the lit registry
for pkg in \
  luvit/coro-http luvit/coro-websocket luvit/secure-socket \
  creationix/coro-spawn creationix/coro-channel creationix/base64 \
  luvit/querystring luvit/json luvit/fs luvit/timer luvit/path luvit/http \
  Bilal2453/discordia-interactions@2.0.1 \
  TohruMKDM/discordia-textchat@1.1.0 \
  NickIsADev/erlua@3.9.1 \
  truemedian/bit64@1.0.0 \
  SinisterRectus/sqlite3@1.0.1
do
  "$LIT" install "$pkg"
done

# Git dependencies, pinned (these override any registry copies pulled in above)
clone() { # <repo> <commit> <deps dir name>
  local repo="$1" commit="$2" dest="deps/$3" tmp
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  git -C "$tmp" remote add origin "https://github.com/$repo"
  git -C "$tmp" fetch -q --depth 1 origin "$commit"
  git -C "$tmp" checkout -q FETCH_HEAD
  rm -rf "$tmp/.git" "$dest"
  mv "$tmp" "$dest"
  echo "installed $repo@${commit:0:7} -> $dest"
}
# Ducky's own forks of Discordia and its extensions (Quackscordia)
clone duckyerlc/Quackscordia               a1e6458f041a9523046033009cfaf6616f41a76d discordia
clone duckyerlc/quackscordia-components    5997bdc00a12288cc3e3d1ad27befcf30c2841c7 discordia-components
clone duckyerlc/quackscordia-slash         0eca7cdf89fa3946858d693640e790adb4969c44 discordia-slash
# Other extensions not (or not in the needed version) on lit
clone Bilal2453/discordia-modals           92672581e4d9d67248e190e4943406aefc417623 discordia-modals
clone Ta-noshii/discordia-voice-plus       9cbea8ec97c479eceb9bd2164a13c7218c448721 discordia-voice-plus
clone NickIsADev/ropi                      fa74f5beaf7658701b91604533b30ba55857d29d ropi

echo "Dependencies installed in $BOT/deps"
