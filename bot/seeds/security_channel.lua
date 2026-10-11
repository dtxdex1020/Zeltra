--[[
	Zeltra one-time seed (added by Zeltra; not part of upstream Ducky V1).

	Sets up the security system for Tennessee State Roleplay. Only runs when SEED_SECURITY=1.
	  * If no channel named like "security-logs" exists, creates a private
	    「🛡️」security-logs in the Log's category. @everyone can't see it; Community Leadership
	    and Senior High Rank (the roles that can already see the Log's category) can read it.
	  * Writes the `security` config key (defaults + log channel) only if it has no log
	    channel yet, so running it again is harmless. No other key is touched.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local GUILD_ID = "1522997818330058772"
local CATEGORY_ID = "1522997828127948833" -- Log's
local CHANNEL_NAME = "「🛡️」security-logs"
local VIEW, HISTORY, SEND = 1024, 65536, 2048
local ROLES = {
	{ id = "1522997818384580634", name = "Community Leadership" },
	{ id = "1522997818447626452", name = "Senior High Rank" },
}

return function(Client, sqldb, timer)
	local S = _G.securityCore
	local function say(msg) print("[seed] security: " .. msg) end

	local guild = Client:getGuild(GUILD_ID)
	if not guild then
		return say("guild " .. GUILD_ID .. " not found, nothing done")
	end
	if type(sqldb:get(GUILD_ID)) ~= "table" then
		return say("guild config is not loaded, nothing done")
	end
	local stored = sqldb:get(GUILD_ID, true) or {}
	local sec = S.withDefaults(stored.security)

	if sec.logchannel and guild:getChannel(sec.logchannel) then
		return say("log channel already set to " .. tostring(sec.logchannel) .. ", left as is")
	end

	local channelId
	for channel in guild.textChannels:iter() do
		if channel.name:lower():find("security-logs", 1, true) then
			channelId = channel.id
			say("found existing channel #" .. channel.name .. " (" .. channel.id .. ")")
			break
		end
	end

	if not channelId then
		local overwrites = { { id = GUILD_ID, type = 0, allow = "0", deny = tostring(VIEW) } }
		local chosen = {}
		for _, r in ipairs(ROLES) do
			if guild:getRole(r.id) then
				table.insert(overwrites, { id = r.id, type = 0, allow = tostring(VIEW + HISTORY), deny = tostring(SEND) })
				table.insert(chosen, r.name .. " (" .. r.id .. ")")
			else
				say("role " .. r.name .. " (" .. r.id .. ") not found, skipped")
			end
		end
		local payload = {
			name = CHANNEL_NAME, type = 0,
			topic = "Security alerts from the bot (anti-raid, anti-nuke, flagged actions).",
			permission_overwrites = overwrites,
		}
		if guild:getChannel(CATEGORY_ID) then payload.parent_id = CATEGORY_ID end
		local data, err = Client._api:createGuildChannel(GUILD_ID, payload)
		if not data then
			return say("could not create the channel: " .. tostring(err))
		end
		channelId = data.id
		say("created #" .. tostring(data.name) .. " (" .. tostring(data.id) .. ") in category " .. tostring(data.parent_id)
			.. ", visible to: " .. ((#chosen > 0) and table.concat(chosen, ", ") or "admins only"))
	end

	sec.logchannel = channelId
	local ok, err = sqldb:set(GUILD_ID, { security = sec }, "SEED_SECURITY")
	if not ok then
		return say("write failed: " .. tostring(err))
	end
	say("security config written with log channel " .. channelId)

	timer.setTimeout(5000, coroutine.wrap(function()
		local fresh = sqldb:get(GUILD_ID, true) or {}
		local s = fresh.security
		say("read back from database: logchannel=" .. tostring(s and s.logchannel)
			.. ", antiraid.joins=" .. tostring(s and s.antiraid and s.antiraid.joins)
			.. ", antinuke.count=" .. tostring(s and s.antinuke and s.antinuke.count))
	end))
end
