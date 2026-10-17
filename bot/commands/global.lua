-- global.lua (SCRP). Bans across every server the bot is in. Hand-coded by Dex.
local K = _G.scrpKit
local T = K.TIER

local function bans(guild) return K.config(guild).scrp_globalbans or {} end

local function protectedUser(ctx, id)
	id = tostring(id)
	if id == tostring(Client.user.id) then return "I can't ban myself." end
	if id == tostring(ctx.user.id) then return "You can't ban yourself." end
	if cmdperms.isBotOwner(id, SECRETS.DEV_ACCESS_IDS) or id == cmdperms.OWNER_ID then return "You can't ban the owner." end
	local member = ctx.guild:getMember(id)
	if member and K.tier(member) >= K.tier(ctx.member) then return "That member is at or above your rank." end
end

return K.command({
	name = "global",
	description = "Global bans across all SCRP servers.",
	tier = T.MGMT,
	subs = {
		{
			name = "ban", description = "Ban a user from every server the bot is in.",
			options = {
				{ type = "user", name = "user", description = "User (ID or mention).", required = true },
				{ type = "string", name = "reason", description = "Why.", required = true, rest = true, maxLength = 400 },
			},
			run = function(ctx, args)
				local user = args.user
				local blocked = protectedUser(ctx, user.id)
				if blocked then return ctx:fail(blocked) end
				local reason = string.truncate(args.reason, 400)
				pcall(dmStyle.send, user.user or user, {
					guild = ctx.guild, title = "You were globally banned",
					intro = "You were banned from all **South Carolina Roleplay** servers.",
					fields = { { "Reason", reason }, { "Date", dmStyle.time(os.time()) } }, footer = "Moderation",
				})
				local done, failed = 0, {}
				for guild in Client.guilds:iter() do
					local ok, err = guild:banUser(user.id, "Global ban by " .. ctx.user.username .. ": " .. reason)
					if ok then done = done + 1 else table.insert(failed, guild.name) end
				end
				local list = bans(ctx.guild)
				list[tostring(user.id)] = { reason = reason, by = ctx.user.id, at = os.time() }
				K.save(ctx.guild, { scrp_globalbans = list }, "SCRP_GLOBAL_BAN")
				local card = K.card({
					title = "Global Ban",
					blocks = {
						{ { "User", "<@" .. user.id .. "> (" .. user.id .. ")", true }, { "Reason", reason } },
						{ { "Banned From", done .. " server" .. (done == 1 and "" or "s") }, { "Failed", (#failed > 0) and table.concat(failed, ", ") or nil }, { "Banned By", ctx.user.mentionString, true } },
					},
				})
				pcall(db.send, db, ctx.guild, "modlogchannel", { embeds = card.embeds, files = card.files })
				return ctx:send(card)
			end
		},
		{
			name = "unban", description = "Remove a global ban.",
			options = {
				{ type = "user", name = "user", description = "User (ID or mention).", required = true },
				{ type = "string", name = "reason", description = "Why.", rest = true },
			},
			run = function(ctx, args)
				local id = tostring(args.user.id)
				local done = 0
				for guild in Client.guilds:iter() do
					if guild:unbanUser(id, "Global unban by " .. ctx.user.username) then done = done + 1 end
				end
				local list = bans(ctx.guild)
				local had = list[id] ~= nil
				list[id] = nil
				K.save(ctx.guild, { scrp_globalbans = list }, "SCRP_GLOBAL_UNBAN")
				if not had and done == 0 then return ctx:fail("That user is not globally banned.") end
				return ctx:card({
					title = "Global Unban",
					blocks = { { { "User", "<@" .. id .. "> (" .. id .. ")", true }, { "Unbanned In", done .. " server" .. (done == 1 and "" or "s") }, { "Reason", args.reason or "No reason given" } } },
					banner = false,
				})
			end
		},
		{
			name = "reason", description = "See why a user is globally banned.", tier = T.STAFF,
			options = { { type = "user", name = "user", description = "User (ID or mention).", required = true } },
			run = function(ctx, args)
				local id = tostring(args.user.id)
				local entry = bans(ctx.guild)[id]
				if not entry then return ctx:fail("That user is not globally banned.") end
				return ctx:card({
					title = "Global Ban Reason",
					blocks = {
						{ { "User", "<@" .. id .. "> (" .. id .. ")", true }, { "Reason", entry.reason } },
						{ { "Banned By", "<@" .. tostring(entry.by) .. ">", true }, { "Date", "<t:" .. tostring(entry.at) .. ":F>", true } },
					},
					banner = false,
				})
			end
		},
	}
})
