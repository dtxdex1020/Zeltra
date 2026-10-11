# Zeltra production image (Railway / any Docker host). Reproduces scripts/install-deps.sh.
# Secrets come from environment variables (bot/env-secrets.lua); data lives in $DATA_DIR (mount a volume at /data).
# No VOLUME instruction on purpose: Railway rejects it, attach the volume in the platform instead.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git openssl ca-certificates lua-cjson libsqlite3-dev sqlite3 procps imagemagick libssl-dev wget make curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependencies first so they stay cached between code changes
COPY scripts/install-deps.sh scripts/install-deps.sh
RUN mkdir -p bot && SKIP_APT=1 bash scripts/install-deps.sh \
    && test -x bot/luvit && test -d bot/deps/discordia

COPY . .
RUN rm -f bot/secrets.lua bot/data.db bot/data.db-shm bot/data.db-wal bot/gateway.json bot/.slash-commands.cache.json \
    && chmod +x scripts/*.sh bot/luvit bot/lit bot/luvi

ENV LUA_CPATH="/usr/local/lib/lua/5.1/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;/usr/lib/x86_64-linux-gnu/?.so;;" \
    DATA_DIR=/data

CMD ["/app/scripts/docker-start.sh"]
