# Tennessee State Roleplay

The Discord bot runs as **Tennessee State Roleplay** (formerly Zeltra). The public git repository remains [dtxdex1020/Zeltra](https://github.com/dtxdex1020/Zeltra).

**Tennessee State Roleplay** is a multipurpose Discord + ER:LC bot run by [Shark (dtxdex1020)](https://github.com/dtxdex1020): moderation, tickets, verification, staff management (shifts, LOAs, promotions), ER:LC server integration, economy, giveaways and more.

> [!IMPORTANT]
> **Credits: Tennessee State Roleplay is a modified version of Ducky V1 by duckyerlc (https://github.com/duckyerlc/Ducky-opensource), licensed under AGPL-3.0.**
> Changes were made (see [Changes from Ducky V1](#changes-from-ducky-v1)). All original copyright and license notices are kept intact.

- **Source code:** https://github.com/dtxdex1020/Zeltra (this repository; it is the complete source of the running bot, including all modifications)
- **Upstream:** https://github.com/duckyerlc/Ducky-opensource (Ducky V1 by duckyerlc)
- **License:** [GNU Affero General Public License v3.0](LICENSE). Copyright (C) 2026 duckyerlc, with modifications by dtxdex1020.
- **In Discord:** `/about` shows the credit and the source link, as required by AGPL-3.0 section 13.

## Changes from Ducky V1

Tennessee State Roleplay keeps Ducky's features and code; the changes are kept small:

- **Branding:** user-facing "Ducky" text (embeds, help, about, footers, command descriptions) now says "Tennessee State Roleplay". Internal identifiers (variable names, database keys) are unchanged.
- **Credit and source offer:** `/about` and `/help` credit Ducky V1 by duckyerlc and link this repository (AGPL-3.0 section 13).
- **Ducky-only links and IDs removed or replaced:**
  - Ducky's support server and website support links now point to [this repo's issues](https://github.com/dtxdex1020/Zeltra/issues).
  - Ducky's founder user ID no longer has owner powers. Owner/dev access comes from `DEV_ACCESS_IDS` in `secrets.lua`.
  - Ducky's home server ("Ducky's Pond") and its staff-role checks and log channels are replaced by the optional `HOME_GUILD_ID` / `LOG_CHANNEL_ID` settings. When those aren't set, the lookups do nothing.
  - **Plus+ purchases are disabled.** Upstream payments go to Ducky's Roblox group and catalog items. Set `PLUS_PURCHASES_ENABLED` only if you rewire them to your own.
  - The community-support module (hard-wired to Ducky's forum) is disabled, and the `/botreview` command (reviews for Ducky's website) was removed.
  - Images hotlinked from duckybot.xyz were removed. Ducky's web features (Roblox OAuth `/link`, web transcripts, web editor) now use the optional `WEB_BASE_URL`. See [Web features](#web-features).
  - The built-in HTTP API listens on `127.0.0.1` by default (it was `0.0.0.0`).
  - The crash-report webhook in `watchduck.lua` is optional.
  - Documentation links still point to Ducky's docs (https://docs.duckybot.xyz), because they describe the same features.
- **Emojis:** Ducky's custom application emojis only render for Ducky's own bot, so `bot/libs/zeltra-emojis.lua` maps them to Unicode. To keep custom emojis, set `KEEP_CUSTOM_EMOJIS = true` (for example after uploading your own).
- **Runs without Docker:** `scripts/install-deps.sh` installs luvit/lit plus the exact dependencies at pinned versions, using the system packages listed in `bot/Dockerfile`. The upstream repo doesn't ship its `deps/` folder. Dependencies include Ducky's [Quackscordia](https://github.com/duckyerlc/Quackscordia) fork of Discordia and its components and slash forks.
- **Compatibility shims:** `bot/libs/zeltra-compat.lua` adds the few helpers the code expects that the published libraries lack, such as `Interaction:fail/success/...` and `Client:waitModal(id, userId)`. `bot/libs/snowflake.lua` is a small ID generator.
- **Slash commands** are bulk-registered on startup whenever they change. Upstream only did this through the dev-only `/sync` command.

## Running it

Requirements: Linux x86_64, `git`, `curl`, and the system packages from `bot/Dockerfile`. The install script installs them through apt.

```bash
git clone https://github.com/dtxdex1020/Zeltra && cd Zeltra
scripts/install-deps.sh                 # luvit + lit + Lua deps (into bot/), system libs via apt
cp bot/example.secrets.lua bot/secrets.lua && chmod 600 bot/secrets.lua   # then fill it in (never commit it)
scripts/start.sh                        # or: docker compose up -d (upstream Dockerfile)
```

Data is stored in SQLite (`bot/data.db`, backups in `bot/sqlbackups/`). Postgres support (`sqlpg.lua`) is optional and not used by default.

Run it under a supervisor such as pm2 or systemd so it restarts automatically. `watchduck.lua` is upstream's watchdog. Your bot needs the **Server Members** and **Message Content** privileged intents.

## Web features

Ducky hosted some features on its website (duckybot.xyz): Roblox OAuth account linking, web ticket transcripts and the web embed editor. Tennessee State Roleplay doesn't host a website. Unless `WEB_BASE_URL` is set in `secrets.lua`, those links lead here. For Roblox account linking, use **Legacy Verification** in `/link`, which works fully inside Discord.

## Terms and Privacy

Tennessee State Roleplay stores the data that its features need. That includes server configuration, moderation cases, Roblox links, economy balances, tickets and transcripts. The data is kept in the bot's own database and used only to provide these features. Server managers can wipe their server's configuration through `/setup`. For data questions or removal requests, [open an issue](https://github.com/dtxdex1020/Zeltra/issues) or contact Shark on Discord.

---

## Original Ducky V1 README

### Ducky V1 open source
This is the source code of Ducky V1.

Licensed under the [GNU Affero General Public License v3.0](LICENSE).

## Okay so what does this AGPLv3 license mean??
> [!WARNING]
> This is NOT legal advice.

* Commercial Use: You can use, modify, and distribute the software for commercial purposes, including selling services that are built on top of it.

* Distribution: You are free to distribute the original or modified software.

* Modification: You can modify the software, as long as you meet the conditions of the license.

* Private Use: You are free to use and modify the software privately, without having to release your modifications unless you choose to distribute them.

* Disclose Source: If you distribute the software or use it to provide a service (aka running a discord bot), you must provide access to the source code, including any modifications you made.

* License and Copyright Notice: The license and copyright notice must accompany the software, whether you're distributing the original or a modified version.

* Same License: If you distribute modified versions of the software, you must also distribute them under the AGPLv3. This ensures that the freedoms provided by the license are preserved.

In short: if you want to run a Discord bot, this can only fall under private use if it fully ignores requests from anyone besides you AND you don't give anyone else access to your code. Otherwise, you need to make the code open source under the same license.

> [!WARNING]
> The above is NOT legal advice.

## Why is there no old commits?
This is a new repository as we prefer to keep the commit history private.

## Can I propose changes?
We will only accept bug fixes, nothing else. If you wish to make other changes, just fork the repo.

## Command permissions (Tennessee State Roleplay fork)

- **Owner bypass:** the bot owner (Discord ID `1307878235383795732` plus `DEV_ACCESS_IDS` in `bot/secrets.lua`) and each server's owner bypass the bot's staff-role checks, the moderator-vs-target role hierarchy, Plus gates, cooldowns and module/command-disabled checks. The bot's own role hierarchy still applies, and nobody can moderate the server owner or the bot. Server owners don't get bot-developer commands.
- **`/permissions`** (bot owner only): `set`, `remove-role`, `add-user`, `remove-user`, `mode` (`default` | `roles-only` | `everyone` | `disabled`), `reset`, `view`, `list`, `copy`, `preset` (`moderator`, `shift`), `panel`, `role`. Rules can target a whole command (`shift`) or a single subcommand (`shift manage`), and the most specific rule wins. Rules are stored per server in the `command_permissions` table and enforced centrally in `bot/main.lua` (`checkCommandAccess`) before every command runs.
- Tests: `cd bot && ./luvit tests/cmdperms_test.lua` (resolver) and `LUA_CPATH=... ./luvit tests/sqldb_permissions_test.lua` (DB, uses a temp database).

## Deploying with Docker / Railway

The root `Dockerfile` builds a production image (it reproduces `scripts/install-deps.sh`), and `railway.json`
tells Railway to use it with an always-restart policy. In a container no `secrets.lua` is needed:
`scripts/docker-start.sh` generates it from environment variables via `bot/env-secrets.lua`
(every key of `bot/example.secrets.lua` is an environment variable of the same name; the token may be `DISCORD_TOKEN`).

- `DISCORD_TOKEN`, `DEV_ACCESS_IDS` (comma-separated), `DUCKY_CLIENT_SECRET`, `DUCKY_API_KEY`, ... as needed
- `DATA_DIR` (default `/data` in the image): where `data.db` and `sqlbackups/` live. Mount a persistent volume there.
- `SEED_DB_B64` (optional, one-time): base64 of a gzip'd SQLite file, restored only if `$DATA_DIR/data.db` does not exist yet.
- `BOT_HOLD=1` (optional): start the container without logging in to Discord.

The bot needs no public port; its internal API listens on 127.0.0.1:8001.
