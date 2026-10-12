-- Run from bot/: ./luvit tests/welcome_test.lua
-- Zeltra: checks the SCRP join message (libs/zeltra-welcome-scrp.lua) through Ducky's welcome module
-- (modules/server_management/welcome.lua) with fake Discord objects. Nothing is sent to Discord.
-- Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
local W = require("../libs/zeltra-welcome-scrp")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 print("PASS  " .. name) else failed = failed + 1 print("FAIL  " .. name) end
end

local listeners = {}
_G.Client = { on = function(self, ev, fn) listeners[ev] = fn return fn end, removeListener = function() end }
_G.realtime = os.time
_G.emojis = setmetatable({}, { __index = function(_, k) return ":" .. k .. ":" end })
_G.resolvedEmojis = setmetatable({}, { __index = function(_, k) return { name = k } end })
_G.colors = setmetatable({}, { __index = function() return 0 end })
_G.formatNumber = function(n) local s = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse() return (s:gsub("^,", "")) end
_G.ordinal = function(n) return tostring(n) .. "th" end
_G.hasPermission = function() return false end
_G.fixCompId = function() end
_G.signature = function() return nil end
string.truncate = string.truncate or function(s, n) return tostring(s):sub(1, n) end
_G.parseTable = function(tbl, keys)
	local function sub(v)
		if type(v) == "string" then
			return (v:gsub("{([%w%.]+)}", function(k) local r = keys[k] if r == nil then return "{" .. k .. "}" end return tostring(r) end))
		elseif type(v) == "table" then
			local o = {}
			for k, x in pairs(v) do o[k] = sub(x) end
			return o
		end
		return v
	end
	return sub(tbl)
end

local sent, dms = {}, {}
local welcomeChannel = { id = W.CHANNEL, send = function(self, p) table.insert(sent, p) return { id = "m" } end }
local guild = { id = W.GUILD_ID, name = "South Carolina Roleplay", totalMemberCount = 1234,
	getChannel = function(self, id) return id == W.CHANNEL and welcomeChannel or nil end }
local function member(id, username)
	return { id = id, name = username, mentionString = "<@" .. id .. ">", guild = guild,
		user = { id = id, username = username, send = function(self, p) table.insert(dms, p) end } }
end

local mod = assert(loadfile("modules/server_management/welcome.lua"))()
mod.Start()
local join = listeners.memberJoinWelcome
check("welcome module listens for joins", type(join) == "function")

local function config(extra)
	local c = { joinchannel = W.CHANNEL, joinmessage = W.message() }
	for k, v in pairs(extra or {}) do c[k] = v end
	return c
end

join(member("42", "newguy"), config())
local m = sent[1]
check("join message posted in the welcome channel", #sent == 1)
check("exact format", m and m.content == "<:scrp_logo:1559269062490587307> **Welcome** <@42> (**newguy**) to **South Carolina**! We are now at **1,234** members.")
check("plain message, no embed or buttons", m and m.embed == nil and m.embeds == nil and m.components == nil)
check("pings only the member who joined", m and m.allowed_mentions and #m.allowed_mentions.parse == 0
	and #m.allowed_mentions.users == 1 and m.allowed_mentions.users[1] == "42" and m.allowedMentions == nil)
check("no DM by default", #dms == 0)

guild.totalMemberCount = 1235
join(member("43", "second"), config())
check("member count is live", sent[2] and sent[2].content:find("We are now at **1,235** members.", 1, true) ~= nil)

local before = #sent
join(member("44", "raider"), config({ security = { raid = { active = true, ends = os.time() + 600 } } }))
check("no welcome while raid mode is on", #sent == before and #dms == 0)
join(member("45", "later"), config({ security = { raid = { active = true, ends = os.time() - 5 } } }))
check("raid mode past its end time doesn't block welcomes", #sent == before + 1)
join(member("46", "calm"), config({ security = { raid = { active = false } } }))
check("welcome when raid mode is off", #sent == before + 2)

join(member("47", "dmtest"), config({ dmjoin = false, dmjoinmessage = { content = "hi" } }))
check("no DM when DM on join is off, even with a DM message saved", #dms == 0)
join(member("48", "dmon"), config({ dmjoin = true, dmjoinmessage = { content = "hi {member.username}" } }))
check("DM only when DM on join is on", #dms == 1 and dms[1].content == "hi dmon")

before = #sent
local ok = pcall(join, member("49", "nomsg"), { joinchannel = W.CHANNEL })
check("join channel without a message doesn't error or post", ok and #sent == before)

local message = W.message().content
check("no em dashes", not message:find("\226\128\148"))
check("uses the scrp_logo app emoji", message:find("<:scrp_logo:1559269062490587307>", 1, true) == 1)

-- bots are skipped before the welcome module is reached
local dispatch = io.open("modules/dispatch.lua"):read("*a")
check("dispatch skips bots on join", dispatch:find("(member.user.bot)", 1, true) ~= nil)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
