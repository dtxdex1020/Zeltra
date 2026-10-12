--[[
	Zeltra one-time seed (added by Zeltra; not part of upstream Ducky V1).

	Points the bot's own logs at the Log's category. A key is only written when it is unset or its channel no
	longer exists, so anything set in /setup is left alone. Only runs when SEED_SCRP_LOGS=1.
	  * modlogs, server-logs (audit logs through a webhook, command and config logs), case-logs (Roblox
	    punishments, BOLOs, ER:LC kick/ban logs), economy-logs, activity-alerts (security staff activity copy),
	    erlc-join-logs / erlc-leave-logs / mod-calls (ER:LC logs, need the ER:LC API key from /setup) and
	    erlc-commands (where ER:LC's own command log webhook posts).

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local GUILD_ID = "1522997818330058772"
local C = {
	serverlogs = "1522997828127948837",
	modlogs = "1522997828484468849",
	caselogs = "1522997830321701004",
	economy = "1522997830321701006",
	activity = "1522997828484468851",
	erlcjoin = "1522997828127948834",
	erlcleave = "1522997828127948835",
	erlccmds = "1522997828127948836",
	modcalls = "1522997828127948839",
}
local SCALARS = {
	{ "modlogchannel", C.modlogs },
	{ "commandlogschannel", C.serverlogs },
	{ "configlogchannel", C.serverlogs },
	{ "economylogchannel", C.economy },
	{ "punishmentlogschannel", C.caselogs },
	{ "bolologschannel", C.caselogs },
	{ "erlckickbanchannel", C.caselogs },
	{ "erlccmdschannel", C.erlccmds },
}
local AUDIT_TYPES = { "msgedit", "msgdelete", "memberjoin", "memberupdate", "memberleave", "channelcreate", "channelupdate",
	"channeldelete", "rolecreate", "roleupdate", "roledelete", "guildupdate", "msgpin", "emojiupdate" }

return function(Client, sqldb, timer)
	local function say(msg) print("[seed] logs: " .. msg) end
	local guild = Client:getGuild(GUILD_ID)
	if not guild then return say("guild not found, nothing done") end
	local cached = sqldb:get(GUILD_ID)
	if type(cached) ~= "table" then return say("guild config is not loaded, nothing done") end
	local stored = sqldb:get(GUILD_ID, true) or {}
	local function cur(k) local v = stored[k]; if v == nil then v = cached[k] end; return v end
	local changes, n = {}, 0

	for _, pair in ipairs(SCALARS) do
		local key, id = pair[1], pair[2]
		local v = cur(key)
		if v and guild:getChannel(v) then
			say(key .. " already set to " .. tostring(v) .. ", left as is")
		elseif guild:getChannel(id) then
			changes[key] = id; n = n + 1; say(key .. " -> " .. id)
		end
	end

	-- audit logs (server-logs) go through a webhook owned by the bot
	local audit = cur("auditlogchannels")
	audit = type(audit) == "table" and audit or {}
	if not (audit.primary and audit.primary.channel and guild:getChannel(audit.primary.channel)) then
		local channel = guild:getChannel(C.serverlogs)
		local webhook = channel and channel:createWebhook("South Carolina Roleplay", "audit logs for South Carolina Roleplay")
		if webhook then pcall(function() webhook:setAvatar("images/scrp-icon.png") end) end
		if webhook then
			pcall(function() webhook:setAvatar("./images/avatars/Zeltra.png") end)
			audit.primary = { channel = C.serverlogs, webhook = { ID = webhook.id, TOKEN = webhook.token } }
			changes.auditlogchannels = audit; n = n + 1; say("audit logs -> server-logs (webhook " .. webhook.id .. ")")
		else
			say("warning: could not create the audit log webhook in server-logs")
		end
	else
		say("audit logs already set to " .. tostring(audit.primary.channel) .. ", left as is")
	end
	local types = cur("audittypes")
	if type(types) ~= "table" or not next(types) then
		changes.audittypes = AUDIT_TYPES; n = n + 1; say("audit types: " .. table.concat(AUDIT_TYPES, ", "))
	end

	-- ER:LC logs (only post while the ER:LC API key is set)
	local erlc = cur("erlclogs")
	erlc = type(erlc) == "table" and erlc or {}
	local erlcChanged = false
	local function erlcLog(key, channel, text)
		if not (erlc[key] and erlc[key].channel and guild:getChannel(erlc[key].channel)) then
			erlc[key] = { channel = channel, tosend = { content = text } }; erlcChanged = true; say("erlc " .. key .. " -> " .. channel)
		end
	end
	erlcLog("playerjoin", C.erlcjoin, "**<t:{timestamp}:T>** {player.hyperlink} joined the server.")
	erlcLog("playerleave", C.erlcleave, "**<t:{timestamp}:T>** {player.hyperlink} left the server.")
	erlcLog("modcall", C.modcalls, "**<t:{timestamp}:T>** {moderator.hyperlink} answered {caller.hyperlink}'s mod call.")
	if erlcChanged then changes.erlclogs = erlc; n = n + 1 end
	if not cur("apikey") then say("note: no ER:LC API key is set, ER:LC logs stay quiet until one is added in /setup") end

	-- security staff activity copy
	local sec = cur("security")
	if type(sec) == "table" and not (sec.activitychannel and guild:getChannel(sec.activitychannel)) then
		sec.activitychannel = C.activity; changes.security = sec; n = n + 1; say("security activity alerts -> activity-alerts")
	elseif type(sec) ~= "table" then
		say("warning: security settings not found, activity-alerts not set")
	end

	if n == 0 then return say("nothing to change") end
	local ok, err = sqldb:set(GUILD_ID, changes, "SEED_SCRP_LOGS")
	if not ok then return say("could not save: " .. tostring(err)) end
	if timer then timer.sleep(3000) end
	local fresh = sqldb:get(GUILD_ID, true) or {}
	say("read back: modlogchannel=" .. tostring(fresh.modlogchannel) .. " economylogchannel=" .. tostring(fresh.economylogchannel)
		.. " audit=" .. tostring(fresh.auditlogchannels and fresh.auditlogchannels.primary and fresh.auditlogchannels.primary.channel)
		.. " erlc=" .. tostring(fresh.erlclogs and fresh.erlclogs.playerjoin and fresh.erlclogs.playerjoin.channel)
		.. " activity=" .. tostring(fresh.security and fresh.security.activitychannel))
end
