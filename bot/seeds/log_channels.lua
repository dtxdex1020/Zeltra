--[[
	Zeltra one-time seed (added by Zeltra; not part of upstream Ducky V1).

	Points the bot's infraction and promotion logs at #infractions and #promotions in
	Tennessee State Roleplay. Only runs when SEED_LOG_CHANNELS=1, and only writes a key
	that is unset or points at a channel that no longer exists, so running it again is
	harmless. Only `infractionschannel` and `promotionschannel` are written.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local GUILD_ID = "1522997818330058772"

local CHANNELS = {
	{ key = "infractionschannel", id = "1522997824906854434", name = "#infractions" },
	{ key = "promotionschannel", id = "1522997824906854433", name = "#promotions" },
}

return function(Client, sqldb, timer)
	local function say(msg) print("[seed] log channels: " .. msg) end

	local guild = Client:getGuild(GUILD_ID)
	if not guild then
		return say("guild " .. GUILD_ID .. " not found, nothing done")
	end

	local cached = sqldb:get(GUILD_ID)
	if type(cached) ~= "table" then
		return say("guild config is not loaded, nothing done")
	end
	local stored = sqldb:get(GUILD_ID, true) or {}

	local changes, count = {}, 0
	for _, c in ipairs(CHANNELS) do
		local current = stored[c.key] or cached[c.key]
		if current and guild:getChannel(current) then
			say(c.key .. " already set to " .. tostring(current) .. ", left as is")
		elseif not guild:getChannel(c.id) then
			say(c.name .. " (" .. c.id .. ") not found, skipped")
		else
			changes[c.key] = c.id
			count = count + 1
		end
	end

	if count == 0 then
		return say("nothing to change")
	end

	local ok, err = sqldb:set(GUILD_ID, changes, "SEED_LOG_CHANNELS")
	if not ok then
		return say("write failed: " .. tostring(err))
	end
	say("set " .. count .. " key(s)")

	timer.setTimeout(5000, coroutine.wrap(function()
		local fresh = sqldb:get(GUILD_ID, true) or {}
		say("read back from database: infractionschannel=" .. tostring(fresh.infractionschannel) .. ", promotionschannel=" .. tostring(fresh.promotionschannel))
	end))
end
