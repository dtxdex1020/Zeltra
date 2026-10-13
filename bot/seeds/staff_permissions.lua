--[[
	Zeltra one-time seed: /permissions setup for every SCRP staff rank (13 Oct 2026).
	Runs once (marker `seedStaffPerms` in the guild config), then never again.
	Writes the same command_permissions records the /permissions panel writes. Higher ranks inherit lower.
	Also removes the separator role "-" (1558858413885100153) from every record.
	Security, dev and owner-only commands are not touched.
]]
local GUILD_ID = "1522997818330058772"
local MARKER = "2026-10-13-v1"
local SEPARATOR = "1558858413885100153"

local TIERS = {
	{ name = "Trainee / Junior staff", roles = {
		"1522997818510278862", "1522997818510278861", "1522997818510278864" } }, -- Trial Mod, Junior Mod, Moderation Team
	{ name = "Moderators", roles = {
		"1522997818510278860", "1522997818510278859", "1522997818510278858" } }, -- Moderator, Senior Mod, Head Mod
	{ name = "Administration / High Rank / IA", roles = {
		"1522997818476855382", "1522997818476855381", "1522997818476855380", "1522997818476855379", "1522997818476855378", "1522997818476855384",
		"1522997818476855376",
		"1522997818447626458", "1522997818447626457", "1522997818447626456", "1522997818447626455", "1522997818447626454", "1522997818447626460" } },
	{ name = "Management / Leadership / Directors", roles = {
		"1522997818426527851", "1522997818426527850", "1522997818426527849", "1522997818426527848", "1522997818426527847", "1522997818426527853",
		"1522997818447626452", "1522997818384580634", "1522997818384580632", "1522997818384580631",
		"1522997818384580629", "1522997818363740169", "1522997818363740168", "1522997818363740167", "1522997818363740166", "1522997818363740165" } },
	{ name = "Ownership", roles = {
		"1522997818363740163", "1522997818363740161", "1522997818363740160", "1522997818330058781" } },
}

-- command key -> lowest tier that may use it
local COMMANDS = {
	warn = 1, case = 1, modlogs = 1, mute = 1, unmute = 1, slowmode = 1, purge = 1,
	kick = 2, lock = 2, unlock = 2, nick = 2, ["punishments create"] = 2, ["punishments view"] = 2,
	ban = 3, unban = 3, softban = 3, ["role add"] = 3, ["role remove"] = 3, ["punishments manage"] = 3, modstats = 3,
	infraction = 4, promotion = 4,
	setup = 5, setupthree = 5, permissions = 5, automations = 5, syncbans = 5, updatemembers = 5, message = 5,
}
_G.SCRP_STAFF_TIERS, _G.SCRP_STAFF_COMMANDS = TIERS, COMMANDS

return function(Client, sqldb)
	local function say(m) print("[seed] staff perms: " .. m) end
	local config = sqldb:get(GUILD_ID)
	if type(config) ~= "table" then return say("guild config not loaded, nothing done") end
	if config.seedStaffPerms == MARKER then return say("already applied (" .. MARKER .. "), nothing done") end

	local existing = sqldb:getCommandPermissions(GUILD_ID, true) or {}
	local cleared = 0
	for key, rec in pairs(existing) do
		if type(rec.roles) == "table" and rec.roles[SEPARATOR] ~= nil and not COMMANDS[key] then
			rec.roles[SEPARATOR] = nil
			if next(rec.roles) == nil and next(rec.users or {}) == nil and (rec.mode or "default") == "default" then
				sqldb:deleteCommandPermission(GUILD_ID, key)
			else
				sqldb:setCommandPermission(GUILD_ID, key, { mode = rec.mode, roles = rec.roles, users = rec.users }, Client.user.id)
			end
			cleared = cleared + 1
		end
	end

	local written, failed = 0, 0
	for key, tier in pairs(COMMANDS) do
		local old = existing[key] or {}
		local roles = {}
		for id, allow in pairs(type(old.roles) == "table" and old.roles or {}) do
			if id ~= SEPARATOR and allow == false then roles[id] = false end -- keep explicit denies
		end
		for t = tier, #TIERS do for _, id in ipairs(TIERS[t].roles) do roles[id] = true end end
		local mode = (old.mode == "disabled") and "disabled" or "default"
		local ok = sqldb:setCommandPermission(GUILD_ID, key, { mode = mode, roles = roles, users = old.users or {} }, Client.user.id)
		if ok then written = written + 1 else failed = failed + 1 end
	end
	sqldb:set(GUILD_ID, { seedStaffPerms = MARKER }, "SEED_STAFF_PERMS")

	-- read back
	local back = sqldb:getCommandPermissions(GUILD_ID, true) or {}
	local bad = {}
	for key, tier in pairs(COMMANDS) do
		local r = back[key]
		local n = 0
		for _, v in pairs(r and r.roles or {}) do if v then n = n + 1 end end
		local want = 0
		for t = tier, #TIERS do want = want + #TIERS[t].roles end
		if n ~= want or (r.roles[SEPARATOR] ~= nil) then table.insert(bad, key) end
	end
	local sepLeft = 0
	for _, r in pairs(back) do if type(r.roles) == "table" and r.roles[SEPARATOR] ~= nil then sepLeft = sepLeft + 1 end end
	say(("written %d, failed %d, separator cleared from %d other records, separator left %d, readback mismatches: %s")
		:format(written, failed, cleared, sepLeft, (#bad > 0) and table.concat(bad, ",") or "none"))
	if _G.syncSlashCommands then pcall(_G.syncSlashCommands) end
end
