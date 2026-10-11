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
	keywords = {
		enabled = true,        -- watch messages for raid/nuke commands and words (applies to everyone)
		lock = true,           -- start a full lockdown on a match
		timeoutminutes = 60,   -- time out the sender (0 = off); skipped where Discord doesn't allow it
		cooldown = 60,         -- seconds after a lockdown before another match can lock again
		custom = {},           -- extra keywords added with /security config keyword
		-- ticket channels (any channel in a ticket category, or an open ticket) skip word matches so reports that
		-- mention "raid" don't lock the server; prefix commands like .nuke at the start of a message still count
		ignoretickets = true,
		ticketcommands = true,
		ignorecategories = {}, -- extra category ids treated like ticket categories
		pingusers = { "1307878235383795732", "1514313618827510011" }, -- pinged 3 times once per lockdown
		-- ownership roles pinged too: Owner, Co-Owner, Assistant Owner, Ownership Board
		pingroles = { "1522997818330058781", "1522997818363740160", "1522997818363740161", "1522997818363740163" },
	},
	whitelist = { users = {}, roles = {} },
	raid = { active = false },
	lockdown = { active = false },
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

---------------------------------------------------------------- lockdown bits
-- Send Messages, Send Messages in Threads, Add Reactions, Create Public Threads
M.LOCK_BITS = { 11, 38, 6, 35 }

local function setBits(dec, list, on)
	local bits = toBits(dec)
	local n = bits.n or 0
	for _, b in ipairs(list) do
		bits[b] = on and 1 or 0
		if on and b + 1 > n then n = b + 1 end
	end
	for i = 0, n - 1 do bits[i] = bits[i] or 0 end
	bits.n = n
	local out = fromBits(bits):gsub("^0+(%d)", "%1")
	return out
end

--- New (allow, deny) with the lock permissions removed from allow and added to deny.
function M.lockOverwrite(allow, deny)
	return setBits(allow or "0", M.LOCK_BITS, false), setBits(deny or "0", M.LOCK_BITS, true)
end

function M.allowsAnyLockBit(allow)
	local bits = toBits(allow)
	for _, b in ipairs(M.LOCK_BITS) do if (bits[b] or 0) == 1 then return true end end
	return false
end

function M.isLocked(deny)
	local bits = toBits(deny)
	for _, b in ipairs(M.LOCK_BITS) do if (bits[b] or 0) ~= 1 then return false end end
	return true
end

---------------------------------------------------------------- raid keyword detection
local LEET = { ["4"] = "a", ["@"] = "a", ["3"] = "e", ["1"] = "i", ["!"] = "i", ["0"] = "o", ["5"] = "s", ["$"] = "s", ["7"] = "t" }

-- prefix commands (compared after leet mapping and collapsing repeated letters)
M.RAID_COMMANDS = { "nuke", "nuk", "raid", "massban", "massdm", "spam", "destroy", "wipe", "purgeall", "banall",
	"kickall", "lockall", "webhookspam" }
M.COMMAND_PREFIXES = "[%.!%?%-/;>,%$%+]"
-- whole words that always count
M.RAID_WORDS = { "raid", "raids", "raided", "raiding", "nuke", "nukes", "nuked", "nuking", "nuker" }
-- real words within one typo of "raid"/"nuke" that must not count
M.FUZZY_STOPLIST = { "paid", "said", "maid", "laid", "braid", "rapid", "rabid", "rain", "rail", "rand", "reid", "arid",
	"rais", "raie", "nude", "duke", "luke", "juke", "puke", "nike", "nuka", "nuked", "rid", "ride", "rad" }

--- "raidddd" -> "raid" (any letter repeated in a row becomes one)
local function collapse(word)
	local out, last = {}, nil
	for c in word:gmatch(".") do
		if c ~= last then table.insert(out, c) end
		last = c
	end
	return table.concat(out)
end
M.collapse = collapse

local function setOf(list, fn)
	local out = {}
	for _, w in ipairs(list) do out[fn and fn(w) or w] = w end
	return out
end
local COMMANDS = setOf(M.RAID_COMMANDS, collapse)
local WORDS = setOf(M.RAID_WORDS, collapse)
local STOP = setOf(M.FUZZY_STOPLIST, collapse)

--- Optimal string alignment distance (edits + adjacent swaps), stops early above max.
function M.editDistance(a, b, max)
	max = max or 99
	if math.abs(#a - #b) > max then return max + 1 end
	local d = {}
	for i = 0, #a do d[i] = { [0] = i } end
	for j = 0, #b do d[0][j] = j end
	for i = 1, #a do
		for j = 1, #b do
			local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
			d[i][j] = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
			if i > 1 and j > 1 and a:sub(i, i) == b:sub(j - 1, j - 1) and a:sub(i - 1, i - 1) == b:sub(j, j) then
				d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + 1)
			end
		end
	end
	return d[#a][#b]
end

--- Lowercased, leetspeak-mapped words. Single letters in a row ("r a i d", "n.u.k.e") are joined.
function M.raidTokens(content)
	local text = tostring(content or ""):lower()
	text = text:gsub("<a?:[%w_]+:%d+>", " "):gsub("<[@#][!&]?%d+>", " "):gsub("https?://%S+", function(url)
		return " " .. url:gsub("[^%a]", " ") .. " "
	end)
	local tokens = {}
	for chunk in text:gmatch("[%w@%$!]+") do
		local hasLetter = chunk:find("%a") ~= nil
		if hasLetter or (#chunk == 1 and LEET[chunk]) then
			local mapped = chunk:gsub(".", function(c) return LEET[c] or c end):gsub("[^%a]", "")
			if mapped ~= "" then table.insert(tokens, mapped) end
		end
	end
	-- join runs of 3+ single letters
	local out, run = {}, {}
	local function flush()
		if #run >= 3 then table.insert(out, table.concat(run)) else for _, r in ipairs(run) do table.insert(out, r) end end
		run = {}
	end
	for _, t in ipairs(tokens) do
		if #t == 1 then table.insert(run, t) else flush() table.insert(out, t) end
	end
	flush()
	return out
end

--- True when the channel is a ticket: its category is used by a ticket panel subject (or listed in
--- keywords.ignorecategories), or it is an open ticket channel.
function M.isTicketChannel(config, channelId, parentId, extraCategories)
	channelId, parentId = tostring(channelId or ""), parentId and tostring(parentId) or nil
	for _, c in pairs(extraCategories or {}) do
		if parentId and tostring(c) == parentId then return true end
	end
	for _, panel in pairs((config and config.panels) or {}) do
		for _, sub in pairs(panel.subjects or {}) do
			if parentId and sub.category and tostring(sub.category) == parentId then return true end
			for _, t in pairs(sub.tickets or {}) do
				if tostring(t.channel) == channelId then return true end
			end
		end
	end
	return false
end

--- Returns { kind = "command"|"word"|"typo"|"custom", text = what matched } or nil.
function M.detectRaidKeyword(content, custom)
	local raw = tostring(content or "")
	local trimmed = raw:match("^%s*(.-)%s*$")

	-- prefix commands: .nuke, !raid, ?nuke, -nuke, .massban ...
	local prefix, word = trimmed:match("^(" .. M.COMMAND_PREFIXES .. ")%s*([%w@%$!]+)")
	if prefix and word then
		local mapped = collapse(word:lower():gsub(".", function(c) return LEET[c] or c end):gsub("[^%a]", ""))
		if COMMANDS[mapped] then
			return { kind = "command", text = prefix .. word }
		end
	end

	local tokens = M.raidTokens(raw)
	local customWords, customPhrases = {}, {}
	for _, kw in ipairs(custom or {}) do
		local ktoks = M.raidTokens(kw)
		if #ktoks == 1 then customWords[collapse(ktoks[1])] = kw
		elseif #ktoks > 1 then
			for i, t in ipairs(ktoks) do ktoks[i] = collapse(t) end
			table.insert(customPhrases, { " " .. table.concat(ktoks, " ") .. " ", kw })
		end
	end

	local collapsed = {}
	for i, t in ipairs(tokens) do
		local c = collapse(t)
		collapsed[i] = c
		if WORDS[c] then return { kind = "word", text = t } end
		if customWords[c] then return { kind = "custom", text = customWords[c] } end
		if #c >= 4 and #c <= 6 and not STOP[c] and not WORDS[c] then
			if M.editDistance(c, "raid", 1) <= 1 or M.editDistance(c, "nuke", 1) <= 1 then
				return { kind = "typo", text = t }
			end
		end
	end
	if #customPhrases > 0 then
		local joined = " " .. table.concat(collapsed, " ") .. " "
		for _, p in ipairs(customPhrases) do
			if joined:find(p[1], 1, true) then return { kind = "custom", text = p[2] } end
		end
	end
	return nil
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
