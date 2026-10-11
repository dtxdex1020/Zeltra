-- Run from bot/: ./luvit tests/tickets_test.lua
-- Zeltra: checks the TSRP ticket hub data (libs/zeltra-tickets-tsrp.lua) and drives Ducky's ticket handler
-- (modules/server_management/tickets.lua) with fake Discord objects: open every ticket type, claim, close.
-- Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
local T = require("../libs/zeltra-tickets-tsrp")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 print("PASS  " .. name) else failed = failed + 1 print("FAIL  " .. name) end
end

---------------------------------------------------------------- data
local subjects = T.subjects()
check("8 ticket types", #subjects == 8)
local expectCat = {
	["General Support"] = "1522997826462810194", ["Member Report"] = "1558873090098864289", ["Staff Report"] = "1522997826953412698",
	["Appeals"] = "1522997826953412698", ["Departments"] = "1558873091650883657", ["Paid Ads & Affiliates"] = "1522997827662512339",
	["High Rank Report"] = "1522997827662512339", ["Ownership Support"] = "1558873093647245415",
}
for _, s in ipairs(subjects) do
	check(s.name .. " goes to the right category", s.category == expectCat[s.name])
	check(s.name .. " has support roles and logs to ticket-logs", #s.support > 0 and s.transcriptschannel == "1522997828127948838")
	check(s.name .. " ticket name is numbered", s.ticketname:find("%-{ticket.number}$") ~= nil)
	check(s.name .. " has open/close/claim/unclaim cards", s.embeds.open and s.embeds.close and s.embeds.claim and s.embeds.unclaim and true)
end
check("ownership tickets include both owners", subjects[8].supportusers and subjects[8].supportusers[1] == "1307878235383795732")
check("general pings Staff Team", subjects[1].mentionables[1] == "1522997818531512542")
check("number pads to 4 digits", T.number(1) == "0001" and T.number(42) == "0042")

local payload = T.panelPayload()
local select
local function find(c)
	if type(c) ~= "table" then return end
	if c.type == 3 then select = c end
	for _, v in pairs(c) do if type(v) == "table" then find(v) end end
end
find(payload)
check("panel is Components V2", payload.flags == 32768 and payload.components[1].type == 17 and payload.components[1].accent_color == T.COLOR)
check("panel select uses the ticket handler id", select and select.custom_id == "subjectselect")
check("dropdown placeholder", select and select.placeholder == "Click here to find ticket options")
check("8 dropdown options with emoji", select and #select.options == 8 and select.options[1].emoji.name == "❓")
local valuesOk = true
for i, o in ipairs(select.options) do
	if o.value ~= tostring(i) or o.label ~= subjects[i].name or #o.label > 100 or #o.description > 100 then valuesOk = false end
end
check("option values match subject indexes", valuesOk)
check("panel text under 4000 (" .. T.panelTextLength(payload) .. ")", T.panelTextLength(payload) < 4000)
check("panel mentions nobody", payload.allowed_mentions and #payload.allowed_mentions.parse == 0)
local function allText(t, acc)
	acc = acc or {}
	if type(t) == "string" then table.insert(acc, t) elseif type(t) == "table" then for _, v in pairs(t) do allText(v, acc) end end
	return acc
end
local dash = false
for _, s in ipairs(allText({ payload, subjects, T.panelEmbeds() })) do if s:find("\226\128\148") then dash = true end end
check("no em dashes anywhere", not dash)
local merged = T.mergeSubjects(T.subjects(), { { key = "general", name = "General Support", nextticketid = 5, tickets = { { channel = "c" } } } })
check("refresh keeps open tickets and counters", merged[1].nextticketid == 5 and merged[1].tickets[1].channel == "c" and merged[2].nextticketid == nil)

---------------------------------------------------------------- fake Discord + bot globals
local GUILD = T.GUILD_ID
local PANEL = "9000000000000000001"
local OPENER = "4242"
local STAFF_MEMBER = "5151"

local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = deepcopy(v) end
	return o
end
table.deepcopy = table.deepcopy or deepcopy
table.count = table.count or function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
string.truncate = string.truncate or function(s, n) return tostring(s):sub(1, n) end

local listeners = {}
local api = { created = {}, }
_G.Client = {
	user = { id = "1485114788534026260" },
	on = function(self, ev, fn) listeners[ev] = fn return fn end,
	removeListener = function() end,
	getUser = function(self, id) return { id = id, mentionString = "<@" .. id .. ">" } end,
	error = function() end,
	_api = api,
}
_G.bit = require("bit")
_G.ZELTRA_WEB_URL = "https://github.com/dtxdex1020/Zeltra#web-features"
_G.emojis = setmetatable({}, { __index = function(_, k) return ":" .. k .. ":" end })
_G.resolvedEmojis = setmetatable({}, { __index = function(_, k) return { name = k } end })
_G.colors = setmetatable({}, { __index = function() return 0 end })
_G.blacklisted = function() return false end
_G.sanitizeUTF8 = function(s) return s end
_G.junkStr = function() return "x" end
_G.errCodes = {}
_G.realtime = os.time
_G.ropi = { GetUser = function() return nil end }
local dms = {}
_G.dmStyle = { ticketClosed = function(user, info) table.insert(dms, info) end }
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
local transcripts = 0
_G.transcriptChannel = function(ch) transcripts = transcripts + 1 return "transcript text", _G.ZELTRA_WEB_URL .. "/transcripts", 3 end
_G.prompt = function(ia, title, questions, cb, defer)
	local mia = { updates = {} }
	function mia:update(p) table.insert(self.updates, p) return true end
	return cb(mia, { ["Why are you closing this ticket?"] = "Sorted, thanks" })
end

local function Components()
	local c = { buttons = {} }
	function c:button(b) table.insert(self.buttons, b) return self end
	function c:raw() return { { type = 1, components = deepcopy(self.buttons) } } end
	return c
end
_G.discordia = {
	Components = Components,
	Button = function(o) return { type = 2, custom_id = o.id, label = o.label, style = o.style, url = o.url } end,
	enums = { permission = { readMessages = "readMessages", sendMessages = "sendMessages", addReactions = "addReactions", embedLinks = "embedLinks", attachFiles = "attachFiles" } },
}

-- guild, roles, members, channels
local roleObjs = {}
local function role(id) roleObjs[id] = roleObjs[id] or { id = id, mentionString = "<@&" .. id .. ">" } return roleObjs[id] end
local function member(id, roles, perms)
	return {
		id = id, name = "user" .. id, mentionString = "<@" .. id .. ">", avatarURL = "",
		user = { id = id, username = "user" .. id, mentionString = "<@" .. id .. ">" },
		hasRole = function(self, r) for _, x in ipairs(roles or {}) do if x == r then return true end end return false end,
		hasPermission = function(self, p) return perms and perms[p] or false end,
	}
end
local members = {
	[OPENER] = member(OPENER, {}),
	[STAFF_MEMBER] = member(STAFF_MEMBER, { "1522997818531512542" }),
}
local categoryOverwrites = {}
for _, id in pairs(T.CATEGORIES) do
	categoryOverwrites[id] = { { id = GUILD, type = 0, allow = "0", deny = "1024" }, { id = "777", type = 0, allow = "309237647424", deny = "0" } }
end
local channels = {}
local logSent = {}
channels[T.LOG_CHANNEL] = { id = T.LOG_CHANNEL, send = function(self, p) table.insert(logSent, p) return { id = "log" } end }

local function makeTicketChannel(data)
	local ch = { id = data.id, name = data.name, mentionString = "<#" .. data.id .. ">", sent = {}, overwriteCalls = {}, data = data }
	function ch:send(p) table.insert(self.sent, p) return { id = "m" .. #self.sent, pin = function() end } end
	function ch:setName(n) self.name = n return true end
	function ch:getPermissionOverwriteFor(obj)
		local calls = self.overwriteCalls
		local id = obj and obj.id
		return {
			allowPermissions = function(_, ...) table.insert(calls, { id, "allow", ... }) end,
			denyPermissions = function(_, ...) table.insert(calls, { id, "deny", ... }) end,
			setPermissions = function(_, ...) table.insert(calls, { id, "set", ... }) end,
			delete = function() table.insert(calls, { id, "delete" }) end,
		}
	end
	function ch:fail() end
	channels[data.id] = ch
	return ch
end

local guild = {
	id = GUILD,
	getCategory = function(self, id) return categoryOverwrites[id] and { id = id } or nil end,
	getMember = function(self, id) return members[id] end,
	getRole = function(self, id) return role(id) end,
	getChannel = function(self, id) return channels[id] end,
	_text_channels = { _insert = function(self, data) return makeTicketChannel(data) end },
}
guild.defaultRole = role(GUILD)

local nextChannelId = 100
function api:getChannel(id) return { id = id, permission_overwrites = deepcopy(categoryOverwrites[id] or {}) } end
function api:createGuildChannel(gid, payload)
	nextChannelId = nextChannelId + 1
	local data = { id = tostring(nextChannelId), name = payload.name, parent_id = payload.parent_id, permission_overwrites = payload.permission_overwrites, type = payload.type }
	table.insert(self.created, data)
	return data
end

local config = { panels = { [PANEL] = { key = T.PANEL_KEY, channel = T.PANEL_CHANNEL, subjects = T.subjects(), embeds = T.panelEmbeds() } } }
local dbSets = {}
_G.sqldb = {
	get = function(self, id) return config end,
	set = function(self, id, changes, reason) table.insert(dbSets, reason) for k, v in pairs(changes) do config[k] = v end return true end,
	getLink = function() return nil end,
	getUserSettings = function() return { ticketnotifications = true } end,
}

local function interaction(custom, opts)
	opts = opts or {}
	local m = members[opts.user or OPENER]
	local ia = {
		guild = guild, id = "ia", user = m.user, member = m, log = {},
		data = { custom_id = custom, values = opts.values },
		message = opts.message or { id = PANEL },
		channel = opts.channel,
	}
	function ia:reply(p, e) table.insert(self.log, { "reply", p }) return { id = "status" } end
	function ia:editReply(p) table.insert(self.log, { "edit", p }) return true end
	function ia:fail(m2) table.insert(self.log, { "fail", m2 }) return true end
	function ia:update(p) table.insert(self.log, { "update", p }) return true end
	function ia:updateDeferred() table.insert(self.log, { "deferred" }) return true end
	return ia
end

local mod = assert(loadfile("modules/server_management/tickets.lua"))()
mod.Start()
local handler = listeners.interactionCreate
check("ticket handler listens for interactions", type(handler) == "function")

---------------------------------------------------------------- open one ticket per type
local function overwriteFor(list, id)
	for _, o in ipairs(list) do if o.id == id then return o end end
end
local opened = {}
for i, s in ipairs(config.panels[PANEL].subjects) do
	local before = #api.created
	handler(interaction("subjectselect", { values = { tostring(i) } }))
	local data = api.created[#api.created]
	check(s.name .. ": channel created", #api.created == before + 1)
	local prefix = T.TYPES[i].prefix
	check(s.name .. ": named " .. prefix .. "-0001", data and data.name == prefix .. "-0001")
	check(s.name .. ": created in its category", data and data.parent_id == s.category)
	local ow = data and data.permission_overwrites or {}
	local everyone = overwriteFor(ow, GUILD)
	check(s.name .. ": @everyone can't see it", everyone and (tonumber(everyone.deny) % 2048) >= 1024 and (tonumber(everyone.allow) % 2048) < 1024)
	local opener = overwriteFor(ow, OPENER)
	check(s.name .. ": opener added", opener and opener.type == 1 and (tonumber(opener.allow) % 2048) >= 1024)
	local supportOk = true
	for _, r in ipairs(s.support) do
		local o = overwriteFor(ow, r)
		if not (o and (tonumber(o.allow) % 4096) >= 3072) then supportOk = false end
	end
	check(s.name .. ": support roles can see and talk", supportOk)
	local kept = overwriteFor(ow, "777")
	check(s.name .. ": big category permission values kept exactly", kept and kept.allow == "309237647424")
	local ch = channels[data.id]
	local welcome = ch and ch.sent[1]
	check(s.name .. ": welcome card posted", welcome and welcome.embeds and welcome.embeds[1].description:find("Copy this and fill it in", 1, true) ~= nil)
	check(s.name .. ": welcome shows ticket 0001", welcome and welcome.embeds[1].description:find("Ticket 0001", 1, true) ~= nil)
	local roleIds = {}
	for _, r in ipairs(welcome and welcome.allowed_mentions.roles or {}) do roleIds[r] = true end
	local pingOk = welcome and #welcome.allowed_mentions.parse == 0 and welcome.allowed_mentions.users[1] == OPENER
	for _, r in ipairs(s.mentionables) do
		if not roleIds[r] or not welcome.content:find("<@&" .. r .. ">", 1, true) then pingOk = false end
	end
	check(s.name .. ": pings only the opener and its staff role", pingOk)
	local btn = welcome and welcome.components[1].components
	check(s.name .. ": Claim and Close buttons", btn and btn[1].custom_id == "ticketclaim" and btn[2].custom_id == "ticketclose")
	check(s.name .. ": saved in the database", s.tickets[#s.tickets].channel == data.id and s.tickets[#s.tickets].owner == OPENER)
	opened[i] = ch
end
handler(interaction("subjectselect", { values = { "1" } }))
check("second general ticket is general-0002", api.created[#api.created].name == "general-0002")

---------------------------------------------------------------- claim and close a general ticket
local ticket = opened[1]
local opening = { id = "m1", components = deepcopy(ticket.sent[1].components), embeds = ticket.sent[1].embeds }
local nonStaff = interaction("ticketclaim", { channel = ticket, message = opening, user = OPENER })
handler(nonStaff)
check("non-staff can't claim", nonStaff.log[1] and nonStaff.log[1][1] == "fail")

local claim = interaction("ticketclaim", { channel = ticket, message = opening, user = STAFF_MEMBER })
handler(claim)
local subj = config.panels[PANEL].subjects[1]
check("staff claim saved", subj.tickets[1].claimer == STAFF_MEMBER)
check("claim button becomes Unclaim", claim.log[1][1] == "update" and claim.log[1][2].components[1].components[1].label == "Unclaim")
check("claim card posted", ticket.sent[2] and ticket.sent[2].embeds[1].description:find("<@" .. STAFF_MEMBER .. ">", 1, true) ~= nil)
local locked = false
for _, c in ipairs(ticket.overwriteCalls) do if c[1] == "1522997818531512542" and c[2] == "set" then locked = true end end
check("claim locks other staff to read only", locked)

local close = interaction("ticketclose", { channel = ticket, message = opening, user = STAFF_MEMBER })
handler(close)
check("ticket removed from the database on close", #subj.tickets == 1 and subj.tickets[1].channel ~= ticket.id)
check("close card posted with reason", ticket.sent[3] and ticket.sent[3].embeds[1].description:find("Sorted, thanks", 1, true) ~= nil)
local logMsg = logSent[#logSent]
check("transcript logged to ticket-logs", transcripts == 1 and logMsg and logMsg.files[1][1] == "transcript.txt")
check("log names subject, opener and claimer", logMsg and logMsg.embed.description:find("General Support", 1, true) and logMsg.embed.description:find("<@" .. OPENER .. ">", 1, true) and logMsg.embed.description:find("<@" .. STAFF_MEMBER .. ">", 1, true) and true)
check("no broken Web Transcript button without a web URL", logMsg and logMsg.components == nil)
check("opener DM'd without a web link", dms[1] and dms[1].subject == "General Support" and dms[1].url == nil)
local closedAgain = interaction("ticketclose", { channel = ticket, message = opening, user = STAFF_MEMBER })
handler(closedAgain)
check("closing twice says it's already closed", closedAgain.log[1] and closedAgain.log[1][2]:find("already closed", 1, true) ~= nil)

---------------------------------------------------------------- disabled panel / unknown subject
config.panels[PANEL].disabled = true
local dis = interaction("subjectselect", { values = { "1" } })
handler(dis)
check("disabled panel refuses", dis.log[1] and dis.log[1][2]:find("disabled", 1, true) ~= nil)
config.panels[PANEL].disabled = nil
local bad = interaction("subjectselect", { values = { "99" } })
handler(bad)
check("unknown subject refused", bad.log[1] and bad.log[1][2]:find("subject", 1, true) ~= nil)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
