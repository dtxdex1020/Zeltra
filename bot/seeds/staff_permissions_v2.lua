--[[
	Zeltra one-time seed v2 (13 Oct 2026, Shark's corrections): explicit per-rank /permissions, no inheritance.
	Runs once (marker `seedStaffPermsV2`). Records are "roles-only" so rank checks can't be bypassed by Discord perms.
]]
local GUILD_ID = "1522997818330058772"
local MARKER = "2026-10-13-v2"
local G = {
	TM = { "1522997818510278862", "1522997818510278861", "1522997818510278864" },
	MOD = { "1522997818510278860", "1522997818510278859", "1522997818510278858" },
	ADMIN = { "1522997818476855382", "1522997818476855381", "1522997818476855380", "1522997818476855379", "1522997818476855378", "1522997818476855384", "1522997818476855376" },
	IA = { "1522997818447626458", "1522997818447626457", "1522997818447626456", "1522997818447626455", "1522997818447626454", "1522997818447626460" },
	MGMT = { "1522997818426527851", "1522997818426527850", "1522997818426527849", "1522997818426527848", "1522997818426527847", "1522997818426527853",
		"1522997818447626452", "1522997818384580634", "1522997818384580632", "1522997818384580631",
		"1522997818384580629", "1522997818363740169", "1522997818363740168", "1522997818363740167", "1522997818363740166", "1522997818363740165" },
	OWN = { "1522997818363740163", "1522997818363740161", "1522997818363740160", "1522997818330058781" },
}
local C = {
	warn = { "TM", "MOD", "ADMIN", "IA", "MGMT", "OWN" },
	mute = { "MOD", "ADMIN", "IA", "MGMT", "OWN" }, unmute = { "MOD", "ADMIN", "IA", "MGMT", "OWN" },
	case = { "MOD", "ADMIN", "IA", "MGMT", "OWN" }, modlogs = { "MOD", "ADMIN", "IA", "MGMT", "OWN" },
	nick = { "MOD", "ADMIN", "MGMT", "OWN" }, slowmode = { "MOD", "ADMIN", "MGMT", "OWN" }, purge = { "MOD", "ADMIN", "MGMT", "OWN" },
	lock = { "ADMIN", "MGMT", "OWN" }, unlock = { "ADMIN", "MGMT", "OWN" },
	kick = { "IA", "MGMT", "OWN" },
	modstats = { "ADMIN", "MGMT", "OWN" },
	["punishments create"] = { "ADMIN", "MGMT", "OWN" }, ["punishments view"] = { "ADMIN", "MGMT", "OWN" },
	ban = { "MGMT", "OWN" }, unban = { "MGMT", "OWN" }, softban = { "MGMT", "OWN" },
	["role add"] = { "MGMT", "OWN" }, ["role remove"] = { "MGMT", "OWN" }, ["punishments manage"] = { "MGMT", "OWN" },
	infraction = { "MGMT", "OWN" }, promotion = { "MGMT", "OWN" },
	setup = { "OWN" }, setupthree = { "OWN" }, permissions = { "OWN" }, automations = { "OWN" }, syncbans = { "OWN" }, updatemembers = { "OWN" }, message = { "OWN" },
}
_G.SCRP_STAFF_V2 = { groups = G, commands = C }

return function(Client, sqldb)
	local function say(m) print("[seed] staff perms v2: " .. m) end
	local config = sqldb:get(GUILD_ID)
	if type(config) ~= "table" then return say("guild config not loaded, nothing done") end
	if config.seedStaffPermsV2 == MARKER then return say("already applied, nothing done") end
	local existing = sqldb:getCommandPermissions(GUILD_ID, true) or {}
	local written, failed = 0, 0
	for key, groups in pairs(C) do
		local old = existing[key] or {}
		local roles = {}
		for id, allow in pairs(type(old.roles) == "table" and old.roles or {}) do if allow == false then roles[id] = false end end
		for _, g in ipairs(groups) do for _, id in ipairs(G[g]) do roles[id] = true end end
		local ok = sqldb:setCommandPermission(GUILD_ID, key, { mode = (old.mode == "disabled") and "disabled" or "roles-only", roles = roles, users = old.users or {} }, Client.user.id)
		if ok then written = written + 1 else failed = failed + 1 end
	end
	sqldb:set(GUILD_ID, { seedStaffPermsV2 = MARKER }, "SEED_STAFF_PERMS_V2")
	local back = sqldb:getCommandPermissions(GUILD_ID, true) or {}
	local bad = {}
	for key, groups in pairs(C) do
		local want = {}
		for _, g in ipairs(groups) do for _, id in ipairs(G[g]) do want[id] = true end end
		local r = back[key]
		local okk = r and r.mode == "roles-only"
		for id in pairs(want) do if not (r and r.roles[id] == true) then okk = false end end
		for id, v in pairs(r and r.roles or {}) do if v == true and not want[id] then okk = false end end
		if not okk then table.insert(bad, key) end
	end
	say(("written %d, failed %d, readback mismatches: %s"):format(written, failed, (#bad > 0) and table.concat(bad, ",") or "none"))
	if _G.syncSlashCommands then pcall(_G.syncSlashCommands) end
end
