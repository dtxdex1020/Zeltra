-- Run from bot/: ./luvit tests/tickets_test.lua
-- Zeltra: checks the SCRP ticket hub data (libs/zeltra-tickets-scrp.lua) and drives Ducky's ticket handler
-- (modules/server_management/tickets.lua) with fake Discord objects: open every ticket type, claim, escalate, close.
-- Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
local T = require("../libs/zeltra-tickets-scrp")

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
check("general pings only the Administration Team", #subjects[1].mentionables == 1 and subjects[1].mentionables[1] == "1522997818476855384")
check("general gives access to the Administration Team, not the Staff Team", #subjects[1].support == 1 and subjects[1].support[1] == "1522997818476855384")
check("member reports go to Moderation + Administration, ping Moderation", subjects[2].support[1] == "1522997818510278864" and subjects[2].support[2] == "1522997818476855384" and #subjects[2].mentionables == 1 and subjects[2].mentionables[1] == "1522997818510278864")
check("staff reports go to High Rank only", #subjects[3].support == 1 and subjects[3].support[1] == "1522997818476855376" and #subjects[3].mentionables == 1 and subjects[3].mentionables[1] == "1522997818476855376")
check("staff report text no longer names Internal Affairs", not (subjects[3].description .. subjects[3].embeds.open[1].description .. table.concat(T.TYPES[3].bullets, " ")):find("Internal Affairs", 1, true))
check("appeals go to High Rank", #subjects[4].support == 1 and subjects[4].support[1] == "1522997818476855376" and subjects[4].mentionables[1] == "1522997818476855376")
check("departments go to Department Head + 5 High Commands", #subjects[5].support == 6 and subjects[5].mentionables[1] == "1522997818560741473")
check("ads go to SHR + Director of Relations, ping Relations", subjects[6].support[2] == "1522997818363740167" and subjects[6].mentionables[1] == "1522997818363740167")
check("HR reports ping SHR and Community Leadership", subjects[7].mentionables[1] == "1522997818447626452" and subjects[7].mentionables[2] == "1522997818384580634")
check("no type gives the Staff Team access", (function()
	for _, x in ipairs(subjects) do for _, r in ipairs(x.support) do if r == "1522997818531512542" then return false end end end
	return true
end)())
local esc = T.escalation()
check("8 escalation tiers, Ownership last", #esc.tiers == 8 and esc.tiers[8].key == "ownership" and #esc.tiers[8].roles == 4)
check("escalation cooldown and log channel set", esc.cooldown == 120 and esc.logchannel == T.LOG_CHANNEL)
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
check("dropdown placeholder", select and select.placeholder == "Request Assistance")
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
local MOD = "6161"
local HIGHRANK = "7171"
local OWNER = "8181"
local DEPTHEAD = "9191"
local SOTW_MOD = "1212"
local BYPASS_MOD = "1313"
local IA_MEMBER = "1414"
-- live role positions (from the server's role list on 2026-10-11)
local POS = {
	["1522997818330058781"] = 147, ["1522997818363740160"] = 146, ["1522997818363740161"] = 145, ["1522997818363740163"] = 144,
	["1522997818384580629"] = 136, ["1522997818384580634"] = 132, ["1522997818426527846"] = 130, ["1522997818426527853"] = 121,
	["1522997818447626452"] = 119, ["1522997818447626460"] = 112, ["1522997818476855376"] = 110, ["1522997818476855378"] = 108,
	["1522997818476855384"] = 103, ["1522997818510278860"] = 99, ["1522997818510278864"] = 96, ["1522997818531512542"] = 91,
	["1522997818560741473"] = 78, ["1522997818330058775"] = 152, ["1522997818447626456"] = 115,
}

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
local lastMia, beforeModalSubmit
_G.prompt = function(ia, title, questions, cb, defer)
	local mia = { updates = {}, title = title }
	lastMia = mia
	function mia:update(p) table.insert(self.updates, p) return true end
	if beforeModalSubmit then beforeModalSubmit() beforeModalSubmit = nil end
	local q = questions[1].question
	return cb(mia, { [q] = (q == "Reason (optional)") and "Needs a High Rank to look at this" or "Sorted, thanks" })
end
_G.ticketEscalation = require("../libs/zeltra-ticket-escalation")

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
local function role(id) roleObjs[id] = roleObjs[id] or { id = id, position = POS[id] or 1, mentionString = "<@&" .. id .. ">" } return roleObjs[id] end
local function member(id, roles, perms)
	return {
		id = id, name = "user" .. id, mentionString = "<@" .. id .. ">", avatarURL = "",
		user = { id = id, username = "user" .. id, mentionString = "<@" .. id .. ">" },
		hasRole = function(self, r) for _, x in ipairs(roles or {}) do if x == r then return true end end return false end,
		hasPermission = function(self, p) return perms and perms[p] or false end,
		roles = { iter = function()
			local i = 0
			return function() i = i + 1 local r = roles and roles[i] return r and role(r) end
		end },
	}
end
local members = {
	[OPENER] = member(OPENER, {}),
	[STAFF_MEMBER] = member(STAFF_MEMBER, { "1522997818531512542", "1522997818476855384" }), -- Staff Team + Administration Team
	[MOD] = member(MOD, { "1522997818531512542", "1522997818510278864", "1522997818510278860" }), -- Staff Team, Moderation Team, Moderator
	[HIGHRANK] = member(HIGHRANK, { "1522997818531512542", "1522997818476855384", "1522997818476855378", "1522997818476855376" }),
	[OWNER] = member(OWNER, { "1522997818330058781" }),
	[DEPTHEAD] = member(DEPTHEAD, { "1522997818560741473" }),
	[SOTW_MOD] = member(SOTW_MOD, { "1522997818531512542", "1522997818510278860", "1522997818426527846" }), -- Moderator + Staff Of The Week (130)
	[BYPASS_MOD] = member(BYPASS_MOD, { "1522997818531512542", "1522997818510278860", "1522997818330058775" }), -- Moderator + Wick Bypass (152)
	[IA_MEMBER] = member(IA_MEMBER, { "1522997818447626456" }), -- Internal Affairs (115) only
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
function api:getChannel(id)
	if channels[id] and channels[id].data then return { id = id, permission_overwrites = deepcopy(channels[id].data.permission_overwrites) } end
	return { id = id, permission_overwrites = deepcopy(categoryOverwrites[id] or {}) }
end
api.permEdits = {}
function api:editChannelPermissions(cid, oid, payload)
	table.insert(self.permEdits, { cid, oid, payload })
	local ch = channels[cid]
	if ch and ch.data then
		local found
		for _, o in ipairs(ch.data.permission_overwrites) do if o.id == oid then o.allow, o.deny = payload.allow, payload.deny found = true end end
		if not found then table.insert(ch.data.permission_overwrites, { id = oid, type = payload.type, allow = payload.allow, deny = payload.deny }) end
	end
	return true
end
function api:createGuildChannel(gid, payload)
	nextChannelId = nextChannelId + 1
	local data = { id = tostring(nextChannelId), name = payload.name, parent_id = payload.parent_id, permission_overwrites = payload.permission_overwrites, type = payload.type }
	table.insert(self.created, data)
	return data
end

local config = { panels = { [PANEL] = { key = T.PANEL_KEY, channel = T.PANEL_CHANNEL, subjects = T.subjects(), embeds = T.panelEmbeds(), escalation = T.escalation() } } }
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
	check(s.name .. ": Claim, Close and Escalate buttons", btn and btn[1].custom_id == "ticketclaim" and btn[2].custom_id == "ticketclose" and btn[3].custom_id == "ticketescalate")
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
for _, c in ipairs(ticket.overwriteCalls) do if c[1] == "1522997818476855384" and c[2] == "set" then locked = true end end
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


---------------------------------------------------------------- escalation (on the member report ticket)
local report = opened[2]
local reportMsg = { id = "m1", components = deepcopy(report.sent[1].components), embeds = report.sent[1].embeds }
local function press(user, ch)
	local ia = interaction("ticketescalate", { channel = ch or report, message = reportMsg, user = user })
	handler(ia)
	return ia
end
local function offered(ia)
	local r = ia.log[1]
	if not r or r[1] ~= "reply" then return nil end
	local sel = r[2].components[1].components[1]
	local keys = {}
	for _, o in ipairs(sel.options) do keys[#keys + 1] = o.value end
	return table.concat(keys, ","), sel
end
local ia = press(OPENER)
check("non-staff can't escalate", ia.log[1] and ia.log[1][1] == "fail" and ia.log[1][2] == "Only staff can escalate.")
ia = press(MOD)
local keys, sel = offered(ia)
check("moderator gets every tier above Moderator (99)", keys == "admin,highrank,ia,shr,management,leadership,bod,ownership")
check("tier menu is a select on the escalate id", sel and sel.custom_id == "ticketescalatetier" and sel.max_values == 1)
check("high rank only gets tiers above High Rank (110)", offered(press(HIGHRANK)) == "ia,shr,management,leadership,bod,ownership")
check("Staff Of The Week is not counted as a rank", offered(press(SOTW_MOD)) == "admin,highrank,ia,shr,management,leadership,bod,ownership")
check("roles above Owner (bypass/bot roles) are ignored", offered(press(BYPASS_MOD)) == "admin,highrank,ia,shr,management,leadership,bod,ownership")
check("department head (ticket role, below Staff Team) counts as staff", offered(press(DEPTHEAD)) == "admin,highrank,ia,shr,management,leadership,bod,ownership")
check("Internal Affairs member (115) gets SHR and up", offered(press(IA_MEMBER)) == "shr,management,leadership,bod,ownership")
ia = press(OWNER)
check("owner has nothing above them", ia.log[1] and ia.log[1][1] == "fail" and ia.log[1][2]:find("no tier above your rank", 1, true) ~= nil)

-- moderator escalates to High Rank
local before = #report.sent
local logBefore = #logSent
api.permEdits = {}
local pick = interaction("ticketescalatetier", { channel = report, values = { "highrank" }, user = MOD, message = { id = "eph" } })
handler(pick)
check("reason form opened for the tier", lastMia and lastMia.title == "Escalate to High Rank")
check("ephemeral menu updated to confirm", lastMia.updates[1] and lastMia.updates[1].content:find("High Rank", 1, true) and #lastMia.updates[1].components == 0)
local edit = api.permEdits[1]
check("High Rank given view and send in the ticket", #api.permEdits == 1 and edit[2] == "1522997818476855376" and (tonumber(edit[3].allow) % 4096) >= 3072 and edit[3].deny == "0")
local card = report.sent[before + 1]
check("escalation card posted", card and card.embeds[1].title == "Ticket Escalated"
	and card.embeds[1].description:find("Ticket escalated to **High Rank** by <@" .. MOD .. ">.", 1, true)
	and card.embeds[1].description:find("Needs a High Rank to look at this", 1, true) and true)
check("card pings only High Rank", card and card.content:find("<@&1522997818476855376>", 1, true) and #card.allowed_mentions.parse == 0
	and #card.allowed_mentions.roles == 1 and card.allowed_mentions.roles[1] == "1522997818476855376")
local lg = logSent[logBefore + 1]
check("escalation logged to ticket-logs", lg and lg.embed.description:find("High Rank", 1, true) and lg.embed.description:find("<@" .. MOD .. ">", 1, true)
	and lg.embed.description:find("Member Report", 1, true) and #lg.allowed_mentions.parse == 0 and true)
local rt = config.panels[PANEL].subjects[2].tickets[1]
check("escalation saved on the ticket", rt.escalation and rt.escalation.tier == "highrank" and rt.escalation.position == 110 and rt.escalation.by == MOD)
check("saved with its own reason", dbSets[#dbSets] == "TICKET_ESCALATE")

-- cooldown, then only higher tiers
ia = press(HIGHRANK)
check("second escalation inside the cooldown is refused", ia.log[1] and ia.log[1][1] == "fail" and ia.log[1][2]:find("again in", 1, true) ~= nil)
rt.escalation.at = rt.escalation.at - 200
check("after the cooldown only tiers above the current one are offered", offered(press(MOD)) == "ia,shr,management,leadership,bod,ownership")
local low = interaction("ticketescalatetier", { channel = report, values = { "admin" }, user = MOD, message = { id = "eph" } })
handler(low)
check("picking a lower tier is refused", low.log[1] and low.log[1][1] == "fail" and low.log[1][2]:find("can't escalate", 1, true) ~= nil)

-- someone else escalates higher while the form is open
beforeModalSubmit = function()
	rt.escalation = { tier = "leadership", name = "Community Leadership", position = 132, by = HIGHRANK, at = os.time() - 500 }
end
api.permEdits = {}
before = #report.sent
handler(interaction("ticketescalatetier", { channel = report, values = { "shr" }, user = MOD, message = { id = "eph" } }))
check("form submitted after a higher escalation does nothing", #api.permEdits == 0 and #report.sent == before
	and lastMia.updates[1] and lastMia.updates[1].content:find("already escalated", 1, true) ~= nil)

-- ownership escalation adds all four ownership roles, keeps big values on existing overwrites
rt.escalation.at = os.time() - 500
table.insert(report.data.permission_overwrites, { id = "1522997818363740163", type = 0, allow = "309237647424", deny = "1024" })
api.permEdits = {}
handler(interaction("ticketescalatetier", { channel = report, values = { "ownership" }, user = MOD, message = { id = "eph" } }))
local ob
for _, e in ipairs(api.permEdits) do if e[2] == "1522997818363740163" then ob = e[3] end end
check("ownership escalation edits 4 roles", #api.permEdits == 4)
local big = 309237647424
local expectAllow = string.format("%.0f", math.floor(big / 2 ^ 20) * 2 ^ 20 + bit.bor(big % 2 ^ 20, 117824))
check("existing big overwrite kept, access added, view deny removed", ob and ob.allow == expectAllow and ob.deny == "0")
check("ownership card pings Owner and Ownership Board", report.sent[#report.sent].allowed_mentions.roles[1] == "1522997818330058781" and report.sent[#report.sent].allowed_mentions.roles[2] == "1522997818363740163")
rt.escalation.at = os.time() - 500
ia = press(MOD)
check("nothing above Ownership", ia.log[1] and ia.log[1][1] == "fail" and ia.log[1][2]:find("already escalated to Ownership", 1, true) ~= nil)

-- closing removes send from escalated roles
report.overwriteCalls = {}
handler(interaction("ticketclose", { channel = report, message = reportMsg, user = STAFF_MEMBER }))
local hrDenied = false
for _, c in ipairs(report.overwriteCalls) do if c[1] == "1522997818476855376" and c[2] == "deny" and c[3] == "sendMessages" then hrDenied = true end end
check("closing takes send away from escalated roles", hrDenied)
ia = press(MOD)
check("closed ticket can't be escalated", ia.log[1] and ia.log[1][1] == "fail" and ia.log[1][2]:find("closed", 1, true) ~= nil)

-- a panel without escalation settings
local saveEsc = config.panels[PANEL].escalation
config.panels[PANEL].escalation = nil
ia = press(MOD, opened[3])
check("panel without escalation settings says so", ia.log[1] and ia.log[1][2]:find("isn't set up", 1, true) ~= nil)
config.panels[PANEL].escalation = saveEsc

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
