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
- 2026-10-10: Added ownership applications: bot/libs/zeltra-ownership-core.lua, modules/server_management/ownership.lua,
  commands/ownership.lua and the one-time seed bot/seeds/ownership_channel.lua (private review channel). Ducky V1 had
  no application system to build on. bot/libs/zeltra-dmstyle.lua gained action (non-link) buttons.
- 2026-10-11: Security system: raid/nuke keyword detection (applies to everyone) with alert, owner pings, message
  delete, DM + timeout, and a full lockdown whose previous overwrites are saved and restored by /security unlock
  (bot owners only).
- 2026-10-11: Removed ownership applications (/ownership, its module, core lib, seed and tests); the owners moved
  to a Google Form. The code is still in git history (last version at commit 7b98b83).
- 2026-10-11: Fixed "Unknown interaction" (10062) errors. bot/libs/zeltra-http.lua replaces coro-http's request so
  idle pooled connections are not reused and responses have a timeout; bot/libs/zeltra-interactions.lua adds
  per-command timing logs, an auto-defer in the slash command dispatcher and an event loop monitor. /purge skips
  empty batches.
- 2026-10-11: TSRP ticket hub on top of Ducky's ticket module. bot/libs/zeltra-tickets-tsrp.lua holds the 8 ticket
  types and the Components V2 panel, bot/seeds/ticket_panel.lua is the one-time seed that posts it. Ticket channels
  are now created with their permission overwrites in one request (category overwrites, @everyone hidden, support
  roles and the opener allowed), names support {ticket.number}, welcome pings only go to the ticket's roles, and
  the Web Transcript button is hidden when no web URL is set.
