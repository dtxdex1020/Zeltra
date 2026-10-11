# Notice of modifications

This program, **Zeltra**, is a modified version of **Ducky V1** by duckyerlc
(https://github.com/duckyerlc/Ducky-opensource), licensed under the GNU Affero General
Public License v3.0 (see [LICENSE](LICENSE)).

Ducky - a multipurpose Discord bot focused on seamlessly integrating Discord and ERLC server.
Copyright (C) 2026 duckyerlc

Modifications Copyright (C) 2026 dtxdex1020 (Shark), also licensed under AGPL-3.0.

- 2026-10-10: Forked from duckyerlc/Ducky-opensource at commit 0dcca99 ("aka running a discord bot").
  The bot was rebranded to Zeltra in user-facing text, and credit plus a source link were added to /about
  and /help. Ducky-only links, IDs, payments and modules were removed or disabled. Unicode emoji fallbacks,
  compatibility shims (bot/libs/), a native install script (scripts/) and slash-command sync on startup
  were added. See README.md, "Changes from Ducky V1", and the git history of this repository for every change.

Source code for the running bot: https://github.com/dtxdex1020/Zeltra
- 2026-10-10: Member DMs (infractions, tickets, shifts, moderation, LOAs, ER:LC punishments, bounties,
  reminders) were restyled as Components V2 cards via bot/libs/zeltra-dmstyle.lua, with an embed fallback.
- 2026-10-10: Added a security system: bot/libs/zeltra-security-core.lua, modules/discord_moderation/security.lua
  and commands/security.lua (anti-raid with raid mode, anti-nuke, flagged action alerts, /security), plus the
  one-time seed bot/seeds/security_channel.lua that creates the security log channel.
