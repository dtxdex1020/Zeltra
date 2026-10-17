-- Run from bot/: ./luvit tests/scrp_kit_test.lua
-- SCRP command kit: prefix parsing, staff tiers, and a load check of every command's slash payload.
local fs = require("fs")
_G.fs = fs
_G.json = require("json")
_G.cmdperms = require("../utils/cmdperms")
_G.prettyLog = function() end
_G.discordia = require("discordia")
string.truncate = string.truncate or function(s, n) s = tostring(s) return #s > n and s:sub(1, n) or s end

local K = require("../libs/scrp-kit")
_G.scrpKit = K
_G.scrpApi = require("../libs/scrp-api")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 print("PASS  " .. name)
	else failed = failed + 1 print("FAIL  " .. name) end
end

---------------------------------------------------------------- tokenize / prefix
local t = K.tokenize('say "hello there" world')
check("tokenize keeps quoted text together", t[2] == "hello there" and t[3] == "world")
check("stripPrefix -", K.stripPrefix("-erlc info") == "erlc info")
check("stripPrefix ignores d!", K.stripPrefix("d!erlc info") == nil)
check("stripPrefix bot mention", K.stripPrefix("<@123> erlc info", "123") == "erlc info")
check("parseId mention", K.parseId("<@!1514313618827510011>", "user") == "1514313618827510011")
check("parseId raw id", K.parseId("1514313618827510011", "user") == "1514313618827510011")
check("parseId rejects words", K.parseId("hello", "user") == nil)

local function loadCmd(file)
	local fn = assert(load(fs.readFileSync("commands/" .. file), "@" .. file))
	return fn()
end

local erlc = loadCmd("erlc.lua")
local sub, args, err = K.parsePrefix(erlc.scrpDef, "erlc info")
check("-erlc info picks information", sub and sub.name == "information" and err == nil)
sub = K.parsePrefix(erlc.scrpDef, "erlc information")
check("-erlc information", sub and sub.name == "information")
sub, args, err = K.parsePrefix(erlc.scrpDef, "erlc")
check("-erlc with no sub gives help", sub == nil and err and err:find("Pick one") ~= nil)

local role = loadCmd("role.lua")
sub, args, err = K.parsePrefix(role.scrpDef, "role 1514313618827510011 Staff Team remove")
check("-role id multiword role + action", args and args.user.id == "1514313618827510011" and args.role.name == "Staff Team" and args.action == "remove")
sub, args = K.parsePrefix(role.scrpDef, "role <@1514313618827510011> <@&1522997818531512542>")
check("-role mention + role mention", args and args.user.id == "1514313618827510011" and args.role.id == "1522997818531512542" and args.action == nil)
sub, args, err = K.parsePrefix(role.scrpDef, "role notanid Staff")
check("-role bad user errors with usage", args == nil and err:find("Usage") ~= nil)

local ticket = loadCmd("ticket.lua")
sub, args = K.parsePrefix(ticket.scrpDef, "ticket close done here thanks")
check("-ticket close reason", sub and sub.name == "close" and args.reason == "done here thanks")
sub = K.parsePrefix(ticket.scrpDef, "ticket cr")
check("-ticket cr alias", sub and sub.name == "closerequest")

local session = loadCmd("session.lua")
sub = K.parsePrefix(session.scrpDef, "session start")
check("-session start", sub and sub.name == "start")

local tm = loadCmd("time.lua")
sub, args = K.parsePrefix(tm.scrpDef, "time PST")
check("-time choice match is case-insensitive", args and args.zone == "pst")

local tr = loadCmd("training.lua")
sub, args = K.parsePrefix(tr.scrpDef, "training results 1514313618827510011 passed 9 good job")
check("-training results parses all", args and args.result == "Passed" and args.score == 9 and args.notes == "good job")

---------------------------------------------------------------- tiers
local OWNER = "1514313618827510011"
local DEMOTED = "1307878235383795732"
check("community member is tier 0", K.tierFrom("5", { [K.COMMUNITY_ROLE] = true }, "999", {}) == 0)
check("base staff role is staff", K.tierFrom("5", { [K.BASE_STAFF_ROLE] = true }, "999", {}) == K.TIER.STAFF)
check("bot owner is top tier", K.tierFrom(OWNER, {}, "999", {}) == K.TIER.OWNER)
check("guild owner is top tier", K.tierFrom("42", {}, "42", {}) == K.TIER.OWNER)
check("test-demoted id stays a normal member even as guild owner and dev", K.tierFrom(DEMOTED, { [K.COMMUNITY_ROLE] = true }, DEMOTED, { DEMOTED }) == 0)
check("management role", K.tierFrom("5", { ["1522997818426527851"] = true }, "999", {}) == K.TIER.MGMT)

---------------------------------------------------------------- load every command
local expected = { "afk", "backgroundcheck", "chat", "erlc", "escalate", "funds", "getinfo", "giveaway", "global", "group", "joinvc",
	"jurisdiction", "leaderboard", "leavevc", "membercount", "queue", "restart", "role", "roleplay", "say", "server", "session",
	"sponsored", "staff", "suggest", "ticket", "time", "training", "update", "verify" }
local found = {}
local BAD = { "\226\128\148", "Ducky", "ducky" } -- em dash, old brand
local function checkOptions(where, opts)
	local seenOptional = false
	for _, o in ipairs(opts or {}) do
		if o.type == 1 then
			check(where .. " " .. o.name .. " sub description <= 100", #o.description <= 100)
			checkOptions(where .. " " .. o.name, o.options)
		else
			if not o.required then seenOptional = true end
			if o.required and seenOptional then check(where .. " required option " .. o.name .. " after optional", false) end
			if not o.name:match("^[a-z0-9_%-]+$") or #o.name > 32 then check(where .. " option name " .. o.name, false) end
			if #o.description > 100 then check(where .. " option " .. o.name .. " description too long", false) end
			if o.choices and #o.choices > 25 then check(where .. " too many choices", false) end
			for _, c in ipairs(o.choices or {}) do
				if type(c) ~= "table" or c.name == nil or c.value == nil then check(where .. " bad choice", false) end
			end
		end
	end
end
for _, file in ipairs(fs.readdirSync("commands")) do
	if file:match("%.lua$") and file ~= "backgroundcheck.lua" then
		local ok, cmd = pcall(loadCmd, file)
		check("loads " .. file, ok and type(cmd) == "table")
		if ok and type(cmd) == "table" then
			local s = cmd.slashCommand
			found[cmd.name] = true
			check(file .. " is a kit command", cmd.scrpKit == true and type(cmd.hybridCallback) == "function")
			check(file .. " slash name matches", s and s.name == cmd.name and s.name:match("^[a-z0-9_%-]+$"))
			check(file .. " description <= 100", s and #s.description <= 100)
			checkOptions(file, s and s.options)
		end
		local src = fs.readFileSync("commands/" .. file)
		for _, b in ipairs(BAD) do
			if src:find(b, 1, true) then check(file .. " has no " .. b, false) end
		end
		check(file .. " has no emoji bytes", not src:find("[\240-\244][\128-\191][\128-\191][\128-\191]"))
	end
end
found.backgroundcheck = fs.existsSync("commands/backgroundcheck.lua")
for _, name in ipairs(expected) do check("command present: " .. name, found[name]) end
local count = 0
for _ in pairs(found) do count = count + 1 end
check("exactly " .. #expected .. " commands", count == #expected)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then process:exit(1) end
