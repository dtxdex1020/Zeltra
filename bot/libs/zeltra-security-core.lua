--[[
	Zeltra security core (added by Zeltra; not part of upstream Ducky V1).

	Pure, Discord-free helpers used by the security module (modules/discord_moderation/security.lua)
	and /security: default settings, sliding-window counters, account heuristics and
	big-number permission bit math. Kept free of Discordia so it can be unit-tested with
	`./luvit tests/security_test.lua`.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local M = {}

-- Bot owners: the security system never acts against these accounts.
M.PROTECTED_USERS = { "1307878235383795732", "1514313618827510011" }

M.DEFAULTS = {
	enabled = true,
	logchannel = nil,
	antiraid = {
		enabled = true,
		joins = 8,             -- joins ...
		window = 30,           -- ... within this many seconds = raid
		autoraid = true,       -- start raid mode automatically when a raid is detected
		raidminutes = 10,      -- raid mode length (auto-ends)
		raidaction = "timeout", -- what happens to people who join during raid mode: none, timeout, kick
		raiseverification = true, -- raise the server verification level to High during raid mode
		lockchannels = false,  -- deny Send Messages for @everyone in public channels during raid mode
		accountage = 7,        -- days; younger accounts are flagged when they join
		flagnew = true,
		heuristics = true,     -- flag default avatars on new accounts and suspicious names
	},
	antinuke = {
		enabled = true,
		count = 3,             -- same destructive action by one person ...
		window = 60,           -- ... within this many seconds
		strip = true,          -- remove that person's dangerous roles (only below the bot's role)
	},
	flagged = {
		enabled = true,
		revertperms = false,   -- undo dangerous permission grants by non-whitelisted users
		mentions = true,       -- flag @everyone/@here pings, mass mentions and message bursts
		mentionlimit = 6,      -- unique user/role mentions in one message
		burst = 7,             -- messages ...
		burstwindow = 5,       -- ... within this many seconds from one person
	},
	whitelist = { users = {}, roles = {} },
	raid = { active = false },
}

local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = deepcopy(v) end
	return out
end
M.deepcopy = deepcopy

--- Fill any missing settings with defaults (never overwrites what is stored).
function M.withDefaults(stored)
	local out = deepcopy(type(stored) == "table" and stored or {})
	local function fill(dst, src)
		for k, v in pairs(src) do
			if dst[k] == nil then
				dst[k] = deepcopy(v)
			elseif type(v) == "table" and type(dst[k]) == "table" and next(v) ~= nil then
				fill(dst[k], v)
			end
		end
	end
	fill(out, M.DEFAULTS)
	out.whitelist.users = out.whitelist.users or {}
	out.whitelist.roles = out.whitelist.roles or {}
	return out
end

---------------------------------------------------------------- sliding windows
local Window = {}
Window.__index = Window

function M.newWindow()
	return setmetatable({ events = {} }, Window)
end

--- Record an event for key at time now; returns how many events for key fall inside the window.
function Window:hit(key, now, window)
	local list = self.events[key] or {}
	self.events[key] = list
	table.insert(list, now)
	local cutoff = now - window
	while list[1] and list[1] <= cutoff do table.remove(list, 1) end
	return #list
end

function Window:reset(key)
	self.events[key] = nil
end

--- Cooldown helper: true if key may fire now (and starts the cooldown), false otherwise.
function M.newCooldown()
	local last = {}
	return function(key, now, seconds)
		if last[key] and now - last[key] < seconds then return false end
		last[key] = now
		return true
	end
end

---------------------------------------------------------------- accounts
local DISCORD_EPOCH = 1420070400000

--- Unix seconds a snowflake was created at.
function M.snowflakeTime(id)
	local n = tonumber(id)
	if not n then return nil end
	return math.floor((math.floor(n / 4194304) + DISCORD_EPOCH) / 1000)
end

function M.accountAgeDays(createdAt, now)
	if not createdAt then return nil end
	return (now - createdAt) / 86400
end

local SUSPICIOUS = {
	{ "discord%.gg", "invite link in name" },
	{ "discord%.com/invite", "invite link in name" },
	{ "nitro", "mentions Nitro" },
	{ "free", "\"free\" in name" },
	{ "giveaway", "\"giveaway\" in name" },
	{ "airdrop", "\"airdrop\" in name" },
	{ "steam", "\"steam\" in name" },
	{ "http", "link in name" },
	{ "%d%d%d%d%d%d", "long run of digits" },
}

--- Reason string if a username/display name looks like a raid or scam account, else nil.
function M.suspiciousName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local lower = name:lower()
	for _, p in ipairs(SUSPICIOUS) do
		if lower:find(p[1]) then return p[2] end
	end
	return nil
end

---------------------------------------------------------------- permission bits (decimal strings, any size)
M.DANGEROUS = {
	{ 3, "Administrator" },
	{ 5, "Manage Server" },
	{ 28, "Manage Roles" },
	{ 4, "Manage Channels" },
	{ 2, "Ban Members" },
	{ 1, "Kick Members" },
	{ 29, "Manage Webhooks" },
	{ 30, "Manage Expressions" },
	{ 40, "Timeout Members" },
	{ 17, "Mention Everyone" },
}

-- decimal string -> array of bits (index 0 = least significant)
local function toBits(dec)
	dec = tostring(dec or "0"):match("^%d+") or "0"
	local digits = {}
	for i = 1, #dec do digits[i] = tonumber(dec:sub(i, i)) end
	local bits, b = {}, 0
	local function isZero()
		for _, d in ipairs(digits) do if d ~= 0 then return false end end
		return true
	end
	while not isZero() do
		local rem = 0
		for i = 1, #digits do
			local cur = rem * 10 + digits[i]
			digits[i] = math.floor(cur / 2)
			rem = cur % 2
		end
		bits[b] = rem
		b = b + 1
	end
	bits.n = b
	return bits
end

local function fromBits(bits)
	local digits = { 0 }
	for b = (bits.n or 0) - 1, 0, -1 do
		local carry = bits[b] or 0
		for i = #digits, 1, -1 do
			local cur = digits[i] * 2 + carry
			digits[i] = cur % 10
			carry = math.floor(cur / 10)
		end
		if carry > 0 then table.insert(digits, 1, carry) end
	end
	return table.concat(digits)
end

function M.hasBit(dec, bit)
	return (toBits(dec)[bit] or 0) == 1
end

--- Names of dangerous permissions present in dec.
function M.dangerousIn(dec)
	local bits, out = toBits(dec), {}
	for _, d in ipairs(M.DANGEROUS) do
		if (bits[d[1]] or 0) == 1 then table.insert(out, d[2]) end
	end
	return out
end

--- Names of dangerous permissions that are in new but were not in old.
function M.addedDangerous(old, new)
	local o, n, out = toBits(old), toBits(new), {}
	for _, d in ipairs(M.DANGEROUS) do
		if (n[d[1]] or 0) == 1 and (o[d[1]] or 0) == 0 then table.insert(out, d[2]) end
	end
	return out
end

--- dec with every dangerous permission bit cleared (decimal string).
function M.withoutDangerous(dec)
	local bits = toBits(dec)
	for _, d in ipairs(M.DANGEROUS) do
		if d[1] < (bits.n or 0) then bits[d[1]] = 0 end
	end
	return fromBits(bits)
end

--- The most powerful permissions only (used for member role grants, so normal staff
--- promotions with Kick/Timeout/Mention Everyone don't raise alerts).
M.SEVERE = { [3] = true, [5] = true, [28] = true, [4] = true, [2] = true, [29] = true }

function M.severeIn(dec)
	local bits, out = toBits(dec), {}
	for _, d in ipairs(M.DANGEROUS) do
		if M.SEVERE[d[1]] and (bits[d[1]] or 0) == 1 then table.insert(out, d[2]) end
	end
	return out
end

---------------------------------------------------------------- misc
function M.isProtectedId(id, extra)
	id = tostring(id or "")
	for _, p in ipairs(M.PROTECTED_USERS) do if p == id then return true end end
	for _, p in ipairs(extra or {}) do if tostring(p) == id then return true end end
	return false
end

--- Count unique user and role mentions in message content.
function M.countMentions(content)
	local seen, n = {}, 0
	for id in tostring(content or ""):gmatch("<@[!&]?(%d+)>") do
		if not seen[id] then seen[id] = true n = n + 1 end
	end
	return n
end

return M
