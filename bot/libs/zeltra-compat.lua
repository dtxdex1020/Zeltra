--[[
	Zeltra compatibility layer (added by Zeltra; not part of upstream Ducky V1).

	The open-source Ducky V1 release does not ship its (gitignored) `deps/` folder, and
	the code relies on a few helpers that only existed in Ducky's private, patched copies
	of Discordia and its extensions. This file re-implements those helpers on top of the
	public libraries (see bot/package.lua and scripts/install-deps.sh) so the bot runs:

	  * Interaction/Message/User/Member/TextChannel :success/:fail/:warning/:loading/:info/:heavyred
	  * Client:waitModal(customId, userId?, timeout?)
	  * typed select menus (role/user/channel/mentionable) + SelectMenu:defaultValues()
	  * Client:waitComponent that matches every select-menu type
	  * Guild:getCategory, Guild:setProfile, GuildTextChannel:startThread
	  * string:usub (UTF-8 aware sub) and string:capitalize

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]
local discordia = require("discordia")
local classes = discordia.class.classes
local enums = discordia.enums

-- only fill in helpers that Quackscordia (Ducky's Discordia fork) does not already provide
local function define(t, k, f)
	if t[k] == nil then t[k] = f end
end

---------------------------------------------------------------- strings
local function utf8offsets(s)
	local offs, i, n = {}, 1, #s
	while i <= n do
		offs[#offs + 1] = i
		local c = s:byte(i)
		if c < 0x80 then i = i + 1
		elseif c < 0xE0 then i = i + 2
		elseif c < 0xF0 then i = i + 3
		else i = i + 4 end
	end
	return offs
end

define(string, "usub", function(s, i, j)
	s = tostring(s)
	local offs = utf8offsets(s)
	local len = #offs
	i = i or 1
	j = j or len
	if i < 0 then i = len + i + 1 end
	if j < 0 then j = len + j + 1 end
	if i < 1 then i = 1 end
	if j > len then j = len end
	if i > j then return "" end
	local startByte = offs[i]
	local endByte = (offs[j + 1] or (#s + 1)) - 1
	return s:sub(startByte, endByte)
end)

define(string, "ulen", function(s)
	return #utf8offsets(tostring(s))
end)

define(string, "capitalize", function(s)
	s = tostring(s)
	return (s:gsub("^%l", string.upper))
end)


---------------------------------------------------------------- table/string extensions
-- (these existed in Ducky's patched copy of Discordia's extensions)
define(string, "truncate", function(s, n, suffix)
	s = tostring(s)
	n = n or 100
	suffix = suffix or "..."
	if s:ulen() <= n then return s end
	if n <= #suffix then return s:usub(1, n) end
	return s:usub(1, n - #suffix) .. suffix
end)

define(table, "deeppairs", function(tbl, fn, seen)
	if type(tbl) ~= "table" then return tbl end
	seen = seen or {}
	if seen[tbl] then return tbl end
	seen[tbl] = true
	local keys = {}
	for k in pairs(tbl) do keys[#keys + 1] = k end
	for _, k in ipairs(keys) do
		local nv = fn(tbl, k, tbl[k])
		tbl[k] = nv
		if type(nv) == "table" then table.deeppairs(nv, fn, seen) end
	end
	return tbl
end)

-- table.find(t, value) -> key ; table.find(t, predicate) -> value, key
define(table, "find", function(tbl, needle)
	if type(tbl) ~= "table" then return nil end
	if type(needle) == "function" then
		for k, v in pairs(tbl) do
			if needle(v, k) then return v, k end
		end
		return nil
	end
	for k, v in pairs(tbl) do
		if v == needle then return k end
	end
	return nil
end)

-- remove every occurrence of value from an array (or matching key from a map)
define(table, "delete", function(tbl, value)
	if type(tbl) ~= "table" then return tbl end
	for i = #tbl, 1, -1 do
		if tbl[i] == value then table.remove(tbl, i) end
	end
	for k, v in pairs(tbl) do
		if type(k) ~= "number" and v == value then tbl[k] = nil end
	end
	return tbl
end)

define(table, "merge", function(a, b)
	local out = {}
	for _, t in ipairs({ a or {}, b or {} }) do
		local n = #t
		for i = 1, n do out[#out + 1] = t[i] end
		for k, v in pairs(t) do
			if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then out[k] = v end
		end
	end
	return out
end)

define(table, "chop", function(tbl, n)
	local out = {}
	if type(tbl) ~= "table" then return out end
	for i = 1, math.min(n or #tbl, #tbl) do out[i] = tbl[i] end
	return out
end)

-- elements from index n (inclusive) to the end
define(table, "after", function(tbl, n)
	local out = {}
	if type(tbl) ~= "table" then return out end
	for i = n or 1, #tbl do out[#out + 1] = tbl[i] end
	return out
end)

define(table, "concatFn", function(tbl, sep, fn)
	local parts = {}
	if type(tbl) ~= "table" then return "" end
	for i, v in ipairs(tbl) do
		local r = fn and fn(v, i) or v
		if r ~= nil then parts[#parts + 1] = tostring(r) end
	end
	return table.concat(parts, sep or "")
end)

define(table, "shuffle", function(tbl)
	local out = {}
	for i, v in ipairs(tbl or {}) do out[i] = v end
	for i = #out, 2, -1 do
		local j = math.random(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end)

---------------------------------------------------------------- status replies
local function palette()
	local c = _G.colors or {}
	return {
		success = c.success or 0x66FF66,
		fail = c.fail or 0xFF6666,
		warning = c.warning or 0xFF6A00,
		info = c.info or 0xFF6A00,
		loading = c.info or 0xFF6A00,
		heavyred = c.heavyred or 0xB51A00,
	}
end

local function emojiFor(kind)
	local e = _G.emojis or {}
	if kind == "heavyred" then return e.error or e.fail or "" end
	if kind == "info" then return e.info or "" end
	return e[kind] or ""
end

local function buildPayload(kind, text, emoji)
	local prefix = emoji
	-- error and warning replies are plain text, no emoji in front
	if kind == "fail" or kind == "heavyred" or kind == "warning" then prefix = "" end
	if prefix == nil or type(prefix) ~= "string" then prefix = emojiFor(kind) end
	local desc = tostring(text or "")
	if prefix ~= "" then desc = prefix .. " " .. desc end
	return {
		embed = {
			description = desc:sub(1, 4096),
			color = palette()[kind],
		},
	}
end

-- parse the (text, emojiOrEphemeral, ephemeral) argument styles used throughout Ducky
local function parseArgs(a, b)
	local emoji, ephemeral
	if type(a) == "boolean" then
		ephemeral = a
	elseif type(a) == "string" then
		emoji = a
	end
	if type(b) == "boolean" then ephemeral = b end
	return emoji, ephemeral
end

local kinds = { "success", "fail", "warning", "loading", "info", "heavyred" }

local function install(class, sender)
	if not class then return end
	for _, kind in ipairs(kinds) do
		-- fail/warning/heavyred are always replaced so error replies come out plain (no emoji)
		if rawget(class, kind) == nil or kind == "fail" or kind == "warning" or kind == "heavyred" then
			class[kind] = function(self, text, a, b)
				local emoji, ephemeral = parseArgs(a, b)
				return sender(self, buildPayload(kind, text, emoji), ephemeral)
			end
		end
	end
end

install(classes.Interaction, function(self, payload, ephemeral)
	return self:reply(payload, ephemeral)
end)

install(classes.Message, function(self, payload)
	payload.reference = { message = self, mention = false }
	local msg, err = self:reply(payload)
	if not msg then
		payload.reference = nil
		return self.channel:send(payload)
	end
	return msg, err
end)

local function dm(self, payload)
	local user = self.user or self
	return user:send(payload)
end
install(classes.User, dm)

for _, name in ipairs({ "TextChannel", "GuildTextChannel", "PrivateChannel" }) do
	install(classes[name], function(self, payload) return self:send(payload) end)
end

---------------------------------------------------------------- modals
local Client = classes.Client
local interactionType = enums.interactionType

-- Ducky calls Client:waitModal(customId, userId); upstream discordia-modals uses (id, timeout)
function Client:waitModal(id, userId, timeout)
	if type(userId) == "number" and timeout == nil then
		timeout, userId = userId, nil
	end
	timeout = timeout or 60 * 60 * 1000 -- long forms (staff application) can take a while to write
	return self:waitFor("interactionCreate", timeout, function(ia)
		return ia.type == (interactionType.modalSubmit or 5)
			and ia.data and ia.data.custom_id == id
			and (not userId or (ia.user and ia.user.id == userId))
	end)
end

---------------------------------------------------------------- select menus
local SelectMenu = classes.SelectMenu
if SelectMenu and rawget(SelectMenu, "defaultValues") == nil then
	function SelectMenu:defaultValues(values)
		self._data.default_values = values
		return self
	end
end

---------------------------------------------------------------- guild / channel helpers
local Guild = classes.Guild
if Guild and not rawget(Guild, "getCategory") then
	function Guild:getCategory(id)
		if not id then return nil end
		return self._categories:get(tostring(id))
	end
end

if Guild and not rawget(Guild, "setProfile") then
	-- Per-guild bot profile (nickname/avatar/banner/bio). Call with no args to reset.
	function Guild:setProfile(profile)
		profile = profile or { nick = json and json.null, avatar = json and json.null, banner = json and json.null, bio = json and json.null }
		local data, err = self.client._api:request("PATCH", "/guilds/" .. self.id .. "/members/@me", profile)
		if data then return true end
		return false, err
	end
end

local function startThread(self, name, messageId, autoArchive)
	local endpoint, payload
	if messageId then
		endpoint = "/channels/" .. self.id .. "/messages/" .. tostring(messageId) .. "/threads"
		payload = { name = tostring(name):usub(1, 100), auto_archive_duration = autoArchive or 1440 }
	else
		endpoint = "/channels/" .. self.id .. "/threads"
		payload = { name = tostring(name):usub(1, 100), auto_archive_duration = autoArchive or 1440, type = 11 }
	end
	local data, err = self.client._api:request("POST", endpoint, payload)
	if not data then return nil, err end
	return data
end

for _, name in ipairs({ "GuildTextChannel", "TextChannel" }) do
	local c = classes[name]
	if c and not rawget(c, "startThread") then c.startThread = startThread end
end

return true
