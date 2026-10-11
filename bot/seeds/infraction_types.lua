--[[
	Zeltra one-time seed (added by Zeltra; not part of upstream Ducky V1).

	Adds infraction types for Tennessee State Roleplay, one per punishment role, ordered by
	severity. Only runs when SEED_INFRACTION_TYPES=1, and only writes if the guild has zero
	infraction types, so running it again is harmless. Only the `infractiontypes` key is
	written; no other guild config is touched.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local GUILD_ID = "1522997818330058772"

-- name -> punishment role, least to most severe (role IDs checked against the live guild)
local TYPES = {
	{ name = "Warning", role = "1529009878373499034" },
	{ name = "Strike 1", role = "1529009898875129958" },
	{ name = "Strike 2", role = "1529009910879092866" },
	{ name = "Strike 3", role = "1529009932395872317" },
	{ name = "Under Investigation", role = "1522997818531512547" },
	{ name = "Zero Tolerance Policy", role = "1522997818531512546" },
	{ name = "Staff Suspension", role = "1522997818531512549" },
	{ name = "Staff Blacklist", role = "1522997818531512548" },
}

return function(Client, sqldb, timer)
	local function say(msg) print("[seed] infraction types: " .. msg) end

	local guild = Client:getGuild(GUILD_ID)
	if not guild then
		return say("guild " .. GUILD_ID .. " not found, nothing done")
	end

	-- the config must already be loaded, otherwise sqldb:set would start an empty cached config
	local cached = sqldb:get(GUILD_ID)
	if type(cached) ~= "table" then
		return say("guild config is not loaded, nothing done")
	end

	-- check both the cache and the database itself before writing
	local stored = sqldb:get(GUILD_ID, true) or {}
	for _, existing in ipairs({ cached.infractiontypes, stored.infractiontypes }) do
		if type(existing) == "table" and next(existing) then
			return say("guild already has " .. #existing .. " type(s), nothing done")
		end
	end

	local types = {}
	for _, t in ipairs(TYPES) do
		local role = guild:getRole(t.role)
		if role then
			table.insert(types, { name = t.name, role = t.role })
		else
			say("skipped " .. t.name .. ", role " .. t.role .. " no longer exists")
		end
	end

	if #types == 0 then
		return say("no punishment roles found, nothing done")
	end

	local ok, err = sqldb:set(GUILD_ID, { infractiontypes = types }, "SEED_INFRACTION_TYPES")
	if not ok then
		return say("write failed: " .. tostring(err))
	end
	say("inserted " .. #types .. " type(s)")

	-- read back from the database (not the cache) once the write queue has flushed
	timer.setTimeout(5000, coroutine.wrap(function()
		local fresh = sqldb:get(GUILD_ID, true) or {}
		local names = {}
		for _, t in ipairs(fresh.infractiontypes or {}) do
			table.insert(names, t.name .. "=" .. tostring(t.role))
		end
		say("read back " .. #names .. " from database: " .. table.concat(names, ", "))
	end))
end
