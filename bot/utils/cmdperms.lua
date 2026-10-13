-- utils/cmdperms.lua
-- Zeltra: pure (Discord-free) resolver for per-server command permission overrides set via /permissions.
-- Kept free of Discordia/sqldb so it can be unit-tested with `./luvit tests/cmdperms_test.lua`.

local M = {}

-- The bot owner. Always merged with SECRETS.DEV_ACCESS_IDS by callers.
-- TESTING (2026-10-13): dtxdex (1307878235383795732) is treated as a normal member; dtxdex1 is the only owner.
-- UNDO: set OWNER_ID back to "1307878235383795732" and empty TEST_DEMOTED_IDS below (and in libs/zeltra-security-core.lua).
M.OWNER_ID = "1514313618827510011"

-- IDs that are never treated as bot owner / bypass, even if listed in SECRETS.DEV_ACCESS_IDS.
M.TEST_DEMOTED_IDS = { ["1307878235383795732"] = true }

M.MODES = { "default", "roles-only", "everyone", "disabled" }
M.MODE_SET = { ["default"] = true, ["roles-only"] = true, ["everyone"] = true, ["disabled"] = true }

M.MODE_DESCRIPTIONS = {
	["default"] = "Default Discord-permission / bot staff-role behavior (plus any allowed roles/users).",
	["roles-only"] = "Only the listed allowed roles/users (and the owners).",
	["everyone"] = "Any member (except explicitly denied roles/users).",
	["disabled"] = "Nobody except the bot owner and the server owner."
}

-- Bulk presets for /permissions preset. Commands that don't exist are skipped by the caller.
M.PRESETS = {
	moderator = { "warn", "kick", "mute", "unmute", "infraction", "case", "modlogs", "punishments" },
	shift = { "shift", "session", "loa" }
}

local function find(list, value)
	if type(list) ~= "table" then
		return false
	end
	for _, v in pairs(list) do
		if tostring(v) == tostring(value) then
			return true
		end
	end
	return false
end

--- Normalises a stored record into { mode = string, roles = {[id]=bool}, users = {[id]=bool} }.
function M.normalize(rec)
	rec = type(rec) == "table" and rec or {}
	local out = {
		mode = M.MODE_SET[rec.mode or ""] and rec.mode or "default",
		roles = {},
		users = {}
	}
	for id, allow in pairs(type(rec.roles) == "table" and rec.roles or {}) do
		if allow == true or allow == false then
			out.roles[tostring(id)] = allow
		end
	end
	for id, allow in pairs(type(rec.users) == "table" and rec.users or {}) do
		if allow == true or allow == false then
			out.users[tostring(id)] = allow
		end
	end
	return out
end

--- True when a record carries no information (same as having no override at all).
function M.isEmpty(rec)
	if not rec then
		return true
	end
	rec = M.normalize(rec)
	return rec.mode == "default" and next(rec.roles) == nil and next(rec.users) == nil
end

--- True when the record grants access to someone who may lack the Discord default_member_permissions,
--- i.e. the slash command must be registered visible (default_member_permissions unset).
function M.needsVisible(rec)
	if not rec then
		return false
	end
	rec = M.normalize(rec)
	if rec.mode == "disabled" then
		return false
	end
	if rec.mode == "everyone" or rec.mode == "roles-only" then
		return true
	end
	for _, allow in pairs(rec.roles) do
		if allow then return true end
	end
	for _, allow in pairs(rec.users) do
		if allow then return true end
	end
	return false
end

--- "warn" -> {"warn"}; "shift wave view" -> {"shift wave view", "shift wave", "shift"} (most specific first).
function M.keysFor(name, subcmd)
	local parts = { tostring(name or ""):lower() }
	if subcmd and subcmd ~= "" then
		for part in tostring(subcmd):lower():gmatch("%S+") do
			table.insert(parts, part)
		end
	end
	local keys = {}
	for i = #parts, 1, -1 do
		table.insert(keys, table.concat(parts, " ", 1, i))
	end
	return keys
end

--- Is this user the bot owner (hardcoded owner or any SECRETS.DEV_ACCESS_IDS entry)?
function M.isBotOwner(userId, devIds)
	if not userId then
		return false
	end
	userId = tostring(userId)
	if M.TEST_DEMOTED_IDS[userId] then
		return false
	end
	return userId == M.OWNER_ID or find(devIds, userId)
end

--- Resolve whether a member may run a command.
--- ctx = {
---   userId = string, guildOwnerId = string|nil, roleIds = {string...}, devIds = {string...},
---   overrides = { [commandKey] = record }, keys = { most specific key first }
--- }
--- returns { decision = "allow"|"deny"|"default", privileged = false|"bot_owner"|"guild_owner",
---           granted = bool (explicit grant -> bypass internal staff-role checks), key = matched key|nil, reason = string }
function M.resolve(ctx)
	local userId = tostring(ctx.userId or "")

	if M.isBotOwner(userId, ctx.devIds) then
		return { decision = "allow", privileged = "bot_owner", granted = true, reason = "bot owner" }
	end
	if ctx.guildOwnerId and userId == tostring(ctx.guildOwnerId) then
		return { decision = "allow", privileged = "guild_owner", granted = true, reason = "server owner" }
	end

	local overrides = ctx.overrides or {}
	local rec, key
	for _, k in ipairs(ctx.keys or {}) do
		if overrides[k] and not M.isEmpty(overrides[k]) then
			rec, key = M.normalize(overrides[k]), k
			break
		end
	end

	if not rec then
		return { decision = "default", privileged = false, granted = false, reason = "no override" }
	end

	if rec.mode == "disabled" then
		return { decision = "deny", privileged = false, granted = false, key = key, reason = "command disabled" }
	end

	local userRule = rec.users[userId]
	if userRule == true then
		return { decision = "allow", privileged = false, granted = true, key = key, reason = "user allowed" }
	elseif userRule == false then
		return { decision = "deny", privileged = false, granted = false, key = key, reason = "user denied" }
	end

	local roleSet = {}
	for _, id in pairs(ctx.roleIds or {}) do
		roleSet[tostring(id)] = true
	end

	local denied = false
	for roleId, allow in pairs(rec.roles) do
		if roleSet[roleId] then
			if allow then
				return { decision = "allow", privileged = false, granted = true, key = key, reason = "role allowed", role = roleId }
			else
				denied = roleId
			end
		end
	end
	if denied then
		return { decision = "deny", privileged = false, granted = false, key = key, reason = "role denied", role = denied }
	end

	if rec.mode == "everyone" then
		return { decision = "allow", privileged = false, granted = true, key = key, reason = "everyone" }
	elseif rec.mode == "roles-only" then
		return { decision = "deny", privileged = false, granted = false, key = key, reason = "not in allowed roles/users" }
	end

	return { decision = "default", privileged = false, granted = false, key = key, reason = "default mode" }
end

return M
