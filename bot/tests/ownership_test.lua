--[[
	Tests for ownership applications (Zeltra): libs/zeltra-ownership-core.lua and a mocked run of
	modules/server_management/ownership.lua + commands/ownership.lua. No network, no Discord.
	Run: ./luvit tests/ownership_test.lua
	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]
local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. name) end
end
_G.json = require("json")
local O = dofile("libs/zeltra-ownership-core.lua")
_G.ownershipCore = O

---------------------------------------------------------------- core
check("9 questions in 2 forms", O.QUESTION_COUNT == 9 and #O.FORMS == 2)
local labelsOk, descOk, perModal, styleOk = true, true, true, true
local allText = {}
for n, form in ipairs(O.FORMS) do
	if #form.questions > 5 or #form.title > 45 then perModal = false end
	for _, q in ipairs(form.questions) do
		if #q.label > 45 then labelsOk = false print("long label: " .. q.label) end
		if q.description and #q.description > 100 then descOk = false print("long description: " .. q.description) end
		if q.max > 4000 or q.min > q.max then styleOk = false end
		table.insert(allText, q.label .. " " .. (q.description or ""))
	end
	table.insert(allText, form.title)
end
check("labels fit 45 chars", labelsOk)
check("descriptions fit 100 chars", descOk)
check("at most 5 inputs per modal", perModal)
check("length limits valid", styleOk)
local blob = table.concat(allText, "\n")
check("no em dashes in questions", not blob:find("\226\128\148"))
local ai = { "delve", "leverage", "tapestry", "furthermore", "in today's", "as an ai", "navigate the", "seamless", "robust" }
local aiFree = true
for _, w in ipairs(ai) do if blob:lower():find(w, 1, true) then aiFree = false print("phrase: " .. w) end end
check("no AI-sounding phrases", aiFree)
check("uses GTA driving, not Erratic driving", not blob:find("Erratic", 1, true))
for _, term in ipairs({ "FRP", "RDM", "Mass RDM", "VDM", "NITRP", "GTA driving" }) do
	check("definition covers " .. term, blob:find(term, 1, true) ~= nil)
end

local m = O.modal(1, { def1 = "saved answer" })
check("modal shape", m.custom_id == "ownapp:submit:1" and #m.components == 5 and m.components[1].type == 18 and m.components[1].component.type == 4)
check("modal prefilled", m.components[1].component.value == "saved answer" and m.components[2].component.value == nil)
check("no modal 3", O.modal(3) == nil)

local parsed = O.parseModal({ components = {
	{ type = 18, component = { type = 4, custom_id = "a", value = "x" } },
	{ type = 1, components = { { type = 4, custom_id = "b", value = "y" } } },
} })
check("parse label + legacy rows", parsed.a == "x" and parsed.b == "y")
check("parse age", O.parseAge("I'm 16") == 16 and O.parseAge("sixteen") == nil)

check("eligible with no record", O.eligibility(nil, 0, 14) == true)
check("pending blocks", O.eligibility({ status = "pending" }, 0, 14) == false)
check("accepted blocks", O.eligibility({ status = "accepted" }, 0, 14) == false)
check("denied in cooldown blocks", O.eligibility({ status = "denied", decided = 0 }, 13 * 86400, 14) == false)
check("denied after cooldown ok", O.eligibility({ status = "denied", decided = 0 }, 15 * 86400, 14) == true)

local full = {}
for id, q in pairs(O.BY_ID) do full[id] = string.rep("a", q.max) end
check("nextForm done", O.nextForm(full) == nil)
check("nextForm first gap", O.nextForm({ def1 = "a", def2 = "a", sc1 = "a", sc2 = "a", sc3 = "a" }) == 2)
local cards = O.answerCards(full)
local cardsOk = true
for _, c in ipairs(cards) do
	local size = 0
	for _, s in ipairs(c.sections) do size = size + #s.title + #s.body end
	if size > 3500 then cardsOk = false end
end
check("max-length answers fit in at most 2 cards under the limit", cardsOk and #cards <= 2)
check("typical answers fit in 1 card", #O.answerCards({ def1 = string.rep("a", 250), def2 = string.rep("a", 250), sc1 = string.rep("a", 200), sc2 = string.rep("a", 200), sc3 = string.rep("a", 200), experience = string.rep("a", 250), why = string.rep("a", 250) }) == 1)
check("about you short answers not repeated in cards", (function()
	for _, c in ipairs(cards) do for _, s in ipairs(c.sections) do if s.title == "How old are you?" then return false end end end
	return true
end)())
check("isOwner", O.isOwner("1307878235383795732") and O.isOwner("1514313618827510011") and not O.isOwner("1"))

---------------------------------------------------------------- mocked module flow
_G.dmStyle = dofile("libs/zeltra-dmstyle.lua") or _G.dmStyle
local channelPosts, dms = {}, {}
_G.sqldb = { store = { g1 = {} } }
function sqldb:get(id) return self.store[id] end
function sqldb:set(id, changes) for k, v in pairs(changes) do self.store[id][k] = v end return true end
_G.discordia = { Date = { parseISO = function() return os.time() - 86400 * 40 end } }
_G.isPrivileged = function() return false end
_G.hasCommandGrant = function() return false end
_G.hasPermission = function() return false end
_G.isBotOwner = function() return false end

local handlers = {}
local function iterOf(list) return { iter = function() local i = 0 return function() i = i + 1 return list[i] end end } end
local review = { id = "rev", send = function(self, p) table.insert(channelPosts, p) return { id = "m" .. #channelPosts } end }
local staffRole = { id = "1522997818531512542", position = 90, mentionString = "<@&1522997818531512542>" }
local highRole = { id = "hr", position = 109, mentionString = "<@&hr>" }
local guild
local function member(id, roles)
	local u = { id = id, username = "user" .. id, mentionString = "<@" .. id .. ">", createdAt = os.time() - 86400 * 500,
		send = function(self, p) table.insert(dms, { to = id, payload = p }) return { id = "dm" } end }
	local rl = roles or {}
	local mem = { id = id, user = u, joinedAt = "2026-01-01T00:00:00Z", roles = iterOf(rl), highestRole = rl[1],
		hasRole = function(_, r) for _, x in ipairs(rl) do if x.id == r then return true end end return false end,
		hasPermission = function() return false end }
	return mem
end
guild = { id = "g1", name = "Tennessee State Roleplay",
	getChannel = function(_, id) if id == "rev" then return review end end,
	getRole = function(_, id) if id == "hr" then return highRole end if id == staffRole.id then return staffRole end end }
_G.Client = { on = function(_, ev, fn) handlers[ev] = fn return fn end, removeListener = function() end,
	getUser = function(_, id) return member(id).user end,
	_api = { editMessage = function() return true end } }

local applicant = member("555", { staffRole })
applicant.guild = guild
local outsider = member("777", {})
outsider.guild = guild

local function newInteraction(mem, data, opts)
	opts = opts or {}
	local ia = { guild = guild, member = mem, user = mem.user, data = data, message = opts.message, log = {} }
	function ia:reply(p, eph) table.insert(self.log, { "reply", p, eph }) return true end
	function ia:fail(msg) table.insert(self.log, { "fail", msg }) return true end
	function ia:success(msg) table.insert(self.log, { "success", msg }) return true end
	function ia:modal(m) table.insert(self.log, { "modal", m }) return true end
	function ia:update(p) table.insert(self.log, { "update", p }) return true end
	function ia:updateDeferred() table.insert(self.log, { "deferred" }) return true end
	function ia:editReply(p) table.insert(self.log, { "edit", p }) return true end
	return ia
end
local function last(ia) return ia.log[#ia.log] end
local function run(ia) handlers.interactionCreate(ia) end -- coroutine.wrap inside runs synchronously here

local stub = {}
stub.__index = function(t, k) return function(self, ...) return self end end
local function opt(kind, name) return setmetatable({ kind = kind, name = name }, stub) end
_G.tools = setmetatable({}, { __index = function(_, kind) return function(name) return opt(kind, name) end end })
local mod = assert(loadfile("modules/server_management/ownership.lua"))()
mod.Start()
local cmd = assert(loadfile("commands/ownership.lua"))()
local api = _G.zeltraOwnership

-- not configured yet
local ia = newInteraction(applicant)
cmd.hybridCallback(ia, {}, true, "apply")
check("needs review channel", last(ia)[1] == "fail" and last(ia)[2]:find("set up", 1, true))

sqldb.store.g1.ownershipapps = { channel = "rev" }
ia = newInteraction(outsider)
cmd.hybridCallback(ia, {}, true, "apply")
check("non-staff member can apply", last(ia)[1] == "reply" and json.encode(last(ia)[2]):find("ownapp:form:1", 1, true))
api.drafts["g1:777"] = nil
-- an old stored staff role is ignored
sqldb.store.g1.ownershipapps.staffrole = "1522997818531512542"
ia = newInteraction(outsider)
cmd.hybridCallback(ia, {}, true, "apply")
check("stored staffrole no longer restricts", last(ia)[1] == "reply" and api.getConf(guild).staffrole == nil)
api.drafts["g1:777"] = nil
sqldb.store.g1.ownershipapps.staffrole = nil

-- /permissions deny is still honoured (checked by main.lua before the callback)
local cp = require("../utils/cmdperms")
local denied = cp.resolve({ userId = "777", guildOwnerId = "1", roleIds = {}, devIds = {}, overrides = { ownership = { mode = "disabled" } }, keys = cp.keysFor("ownership", "apply") })
check("/permissions can deny /ownership apply", denied.decision == "deny")
local deniedUser = cp.resolve({ userId = "777", guildOwnerId = "1", roleIds = {}, devIds = {}, overrides = { ownership = { mode = "default", users = { ["777"] = false } } }, keys = cp.keysFor("ownership", "apply") })
check("/permissions can deny one user", deniedUser.decision == "deny")

ia = newInteraction(outsider)
cmd.hybridCallback(ia, {}, true, "config")
check("config is owners only", last(ia)[1] == "fail" and last(ia)[2]:find("Only the owners", 1, true))

-- minimum role
sqldb.store.g1.ownershipapps.minrole = "hr"
ia = newInteraction(applicant)
cmd.hybridCallback(ia, {}, true, "apply")
check("minimum role enforced", last(ia)[1] == "fail" and last(ia)[2]:find("or higher", 1, true))
sqldb.store.g1.ownershipapps.minrole = nil

ia = newInteraction(applicant)
cmd.hybridCallback(ia, {}, true, "apply")
check("member gets start panel (ephemeral V2)", last(ia)[1] == "reply" and last(ia)[3] == true and last(ia)[2].flags == 32768)
local startJson = json.encode(last(ia)[2])
check("start panel has Start button", startJson:find("ownapp:form:1", 1, true) ~= nil)

-- walk through all forms
local msg = { id = "eph" }
for n = 1, #O.FORMS do
	ia = newInteraction(applicant, { custom_id = "ownapp:form:" .. n }, { message = msg })
	run(ia)
	check("form " .. n .. " opens modal", last(ia)[1] == "modal" and last(ia)[2].custom_id == "ownapp:submit:" .. n)
	local comps = {}
	for _, q in ipairs(O.FORMS[n].questions) do
		local v = (q.id == "age") and "17" or ("Answer for " .. q.id .. " written by the applicant.")
		table.insert(comps, { type = 18, component = { type = 4, custom_id = q.id, value = v } })
	end
	ia = newInteraction(applicant, { custom_id = "ownapp:submit:" .. n, components = comps }, { message = msg })
	run(ia)
	if n < #O.FORMS then
		if n == 1 then _G.__progress = last(ia)[2] end
		check("form " .. n .. " saved, continue offered", last(ia)[1] == "update" and json.encode(last(ia)[2]):find("ownapp:form:" .. (n + 1), 1, true))
	else
		check("final form deferred then edited", ia.log[1][1] == "deferred" and last(ia)[1] == "edit" and json.encode(last(ia)[2]):find("Application sent", 1, true))
	end
end
local rec = sqldb.store.g1.ownershipapps.apps["555"]
check("record pending", rec and rec.status == "pending" and rec.message)
check("review posts: header + 1 answer card + decision", #channelPosts == 3)
local reviewJson = json.encode(channelPosts)
check("header shows age and timezone/hours", reviewJson:find("**Age** · 17", 1, true) and reviewJson:find("**Timezone and hours** · Answer for tzhours", 1, true))
check("review card shows staff status", reviewJson:find("**Staff** · Yes", 1, true) ~= nil)
check("review header has applicant info", reviewJson:find("Account created", 1, true) and reviewJson:find("Infractions", 1, true) and reviewJson:find("Joined server", 1, true))
check("review footer", reviewJson:find("Tennessee State Roleplay · Ownership Applications", 1, true) ~= nil)
check("decision buttons", reviewJson:find("ownapp:decide:accept:555", 1, true) and reviewJson:find("ownapp:decide:deny:555", 1, true))
check("all answers present", (function()
	for id in pairs(O.BY_ID) do if not reviewJson:find("Answer for " .. id, 1, true) and id ~= "age" then return false end end
	return true
end)())
local textOk = true
for _, p in ipairs(channelPosts) do
	local total = 0
	for _, c in ipairs(p.components[#p.components].components or {}) do total = total + #(c.content or "") end
	if total > 4000 then textOk = false end
end
check("each review message under 4000 chars of text", textOk)
check("review posts never ping", (function() for _, p in ipairs(channelPosts) do if not p.allowed_mentions or #(p.allowed_mentions.parse or {}) > 0 then return false end end return true end)())

-- second application blocked
ia = newInteraction(applicant)
cmd.hybridCallback(ia, {}, true, "apply")
check("one active application", last(ia)[1] == "fail" and last(ia)[2]:find("already have", 1, true))

-- non-owner cannot decide
ia = newInteraction(applicant, { custom_id = "ownapp:decide:accept:555" }, { message = { id = rec.message } })
run(ia)
check("non-owner cannot decide", last(ia)[1] == "reply" and json.encode(last(ia)[2]):find("Only the owners", 1, true))

-- owner denies with a reason
local owner = member("1307878235383795732", {})
owner.guild = guild
ia = newInteraction(owner, { custom_id = "ownapp:decide:deny:555" }, { message = { id = rec.message } })
run(ia)
check("owner gets reason modal", last(ia)[1] == "modal" and last(ia)[2].custom_id == "ownapp:reason:deny:555" and last(ia)[2].components[1].component.required == false)
ia = newInteraction(owner, { custom_id = "ownapp:reason:deny:555", components = { { type = 18, component = { type = 4, custom_id = "reason", value = "Needs more experience." } } } }, { message = { id = rec.message } })
run(ia)
rec = sqldb.store.g1.ownershipapps.apps["555"]
check("denied + recorded", rec.status == "denied" and rec.by == "1307878235383795732" and rec.reason == "Needs more experience.")
check("decision card edited with disabled state", ia.log[1][1] == "deferred" and last(ia)[1] == "edit" and json.encode(last(ia)[2]):find("Application denied", 1, true) and not json.encode(last(ia)[2]):find("ownapp:decide", 1, true))
_G.__denied = last(ia)[2]
check("applicant DM'd in card style", #dms == 1 and dms[1].to == "555" and json.encode(dms[1].payload):find("was denied", 1, true) and dms[1].payload.flags == 32768)
check("DM includes reason and reapply time", json.encode(dms[1].payload):find("Needs more experience", 1, true) and json.encode(dms[1].payload):find("apply again", 1, true))

ia = newInteraction(applicant)
cmd.hybridCallback(ia, {}, true, "apply")
check("cooldown after denial", last(ia)[1] == "fail" and last(ia)[2]:find("apply again", 1, true))

-- owner reset, then accept path
ia = newInteraction(owner)
cmd.hybridCallback(ia, { user = { id = "555" } }, true, "reset")
check("reset clears record", last(ia)[1] == "success" and sqldb.store.g1.ownershipapps.apps["555"] == nil)
sqldb.store.g1.ownershipapps.apps["555"] = { status = "pending", submitted = os.time(), message = "mX", channel = "rev" }
ia = newInteraction(owner, { custom_id = "ownapp:reason:accept:555", components = { { type = 18, component = { type = 4, custom_id = "reason", value = "" } } } }, { message = { id = "mX" } })
run(ia)
rec = sqldb.store.g1.ownershipapps.apps["555"]
check("accepted with no reason", rec.status == "accepted" and rec.reason == nil)
check("accept DM sent", json.encode(dms[#dms].payload):find("was accepted", 1, true) ~= nil)
check("accept does not touch roles", not reviewJson:find("addRole", 1, true))

-- under 13
sqldb.store.g1.ownershipapps.apps["555"] = nil
ia = newInteraction(applicant) cmd.hybridCallback(ia, {}, true, "apply")
for n = 1, 1 do
	local comps = {}
	for _, q in ipairs(O.FORMS[n].questions) do table.insert(comps, { type = 18, component = { type = 4, custom_id = q.id, value = "ok answer" } }) end
	run(newInteraction(applicant, { custom_id = "ownapp:submit:" .. n, components = comps }, { message = msg }))
end
ia = newInteraction(applicant, { custom_id = "ownapp:submit:2", components = {
	{ type = 18, component = { type = 4, custom_id = "age", value = "12" } },
	{ type = 18, component = { type = 4, custom_id = "tzhours", value = "EST, 10 hours" } },
	{ type = 18, component = { type = 4, custom_id = "experience", value = "Ran a small server" } },
	{ type = 18, component = { type = 4, custom_id = "why", value = "I want to help it grow" } } } }, { message = msg })
run(ia)
check("under 13 stopped", json.encode(last(ia)[2]):find("13 or older", 1, true) ~= nil and api.drafts["g1:555"] == nil)

-- a community member (no roles) goes all the way through
_G.__firstPosts = channelPosts
channelPosts = {}
for n = 1, #O.FORMS do
	local comps = {}
	for _, q in ipairs(O.FORMS[n].questions) do table.insert(comps, { type = 18, component = { type = 4, custom_id = q.id, value = (q.id == "age") and "15" or "a fair answer here" } }) end
	if n == 1 then run(newInteraction(outsider)) cmd.hybridCallback(newInteraction(outsider), {}, true, "apply") end
	run(newInteraction(outsider, { custom_id = "ownapp:submit:" .. n, components = comps }, { message = msg }))
end
local commJson = json.encode(channelPosts)
check("community member application posted", sqldb.store.g1.ownershipapps.apps["777"] and sqldb.store.g1.ownershipapps.apps["777"].status == "pending")
check("labelled as community member, no roles", commJson:find("No, community member", 1, true) and commJson:find("No roles yet", 1, true))

-- no em dashes anywhere the module or command shows text
local srcOk = true
for _, f in ipairs({ "modules/server_management/ownership.lua", "commands/ownership.lua", "libs/zeltra-ownership-core.lua" }) do
	local fh = io.open(f) local src = fh:read("*a") fh:close()
	if src:find("\226\128\148") then srcOk = false print("em dash in " .. f) end
end
check("no em dashes in source", srcOk)

if os.getenv("OWNERSHIP_PREVIEW_OUT") then
	local out = { { name = "review", payloads = _G.__firstPosts or channelPosts }, { name = "start", payloads = { json.decode(startJson) } },
		{ name = "progress", payloads = { _G.__progress } }, { name = "denied", payloads = { _G.__denied } }, { name = "dm", payloads = { dms[1].payload } } }
	local f = io.open(os.getenv("OWNERSHIP_PREVIEW_OUT"), "w") f:write(json.encode(out)) f:close()
end

mod.Stop()
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
