-- Run from bot/: ./luvit tests/dmstyle_test.lua
-- Zeltra: checks the DM card builder (libs/zeltra-dmstyle.lua) without touching Discord.
local dm = require("../libs/zeltra-dmstyle")
local json = require("json")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 print("PASS  " .. name) else failed = failed + 1 print("FAIL  " .. name) end
end

local guild = { name = "Tennessee State Roleplay" }

check("serverName uses guild name", dm.serverName(guild) == "Tennessee State Roleplay")
check("serverName falls back", dm.serverName(nil) == "Tennessee State Roleplay")
check("serverName escapes markdown", dm.serverName({ name = "a*b" }) == "a\\*b")
check("duration 53m", dm.duration(53 * 60) == "53m")
check("duration 21h 56m", dm.duration(21 * 3600 + 56 * 60 + 10) == "21h 56m")
check("duration 5m 24s", dm.duration(324) == "5m 24s")
check("ticket number padded", dm.ticketNumber(725) == "0725")
check("shiftName adds Shift", dm.shiftName("Normal") == "Normal Shift" and dm.shiftName("Normal Shift") == "Normal Shift")
check("quote multiline", dm.quote("a\nb") == "> a\n> b")

local p = dm.build({
	guild = guild, icon = "⚖️", title = "You received an infraction",
	intro = "Intro **" .. dm.serverName(guild) .. "**.",
	fields = { { "Punishment", "Termination" }, { "Notes", nil }, { "Case ID", "`85UhCj`" } },
	note = "Note", buttons = { { label = "View Transcript", url = "https://example.com" }, { label = "bad", url = "nope" } },
	footer = "Staff Management",
})
local c = p.components[1]
check("V2 flag", p.flags == 32768)
check("container type 17 + accent", c.type == 17 and c.accent_color == dm.accent)
check("heading text", c.components[1].content:find("^# ⚖️ You received an infraction") ~= nil)
check("fields quoted, empty skipped", c.components[2].content == "> **Punishment** · Termination\n> **Case ID** · `85UhCj`")
check("note is subtext", c.components[3].content == "-# Note")
check("only valid link buttons", c.components[4].type == 1 and #c.components[4].components == 1 and c.components[4].components[1].style == 5)
check("footer", c.components[5].content == "-# Tennessee State Roleplay · Staff Management")
check("no content/embeds with V2", p.content == nil and p.embed == nil and p.embeds == nil)
check("encodes to JSON", pcall(json.encode, p))

-- send: V2 accepted
local sent = {}
local okUser = { send = function(self, payload) table.insert(sent, payload) return { id = "1" } end }
local m = dm.send(okUser, { title = "x" })
check("send V2 once", m and #sent == 1 and sent[1].flags == 32768)

-- send: V2 rejected -> embed fallback
sent = {}
local v2Fails = { send = function(self, payload) table.insert(sent, payload) if payload.flags then return nil, "HTTP 400 : Invalid Form Body" end return { id = "2" } end }
m = dm.send(v2Fails, { title = "x", fields = { { "A", "b" } } })
check("fallback to embed", m and #sent == 2 and sent[2].embed and sent[2].embed.description:find("%*%*A%*%*") ~= nil)

-- send: DMs closed -> no retry
sent = {}
local closed = { send = function(self, payload) table.insert(sent, payload) return nil, "HTTP 403 : Cannot send messages to this user (50007)" end }
m = dm.send(closed, { title = "x" })
check("closed DMs not retried", m == nil and #sent == 1)

-- send: throwing user never throws
local ok = pcall(dm.send, { send = function() error("boom") end }, { title = "x" })
check("send never throws", ok)
check("member resolves to .user", dm.send({ user = okUser }, { title = "x" }) ~= nil)

-- ticket closed card
sent = {}
dm.ticketClosed(okUser, { guild = guild, channel = { createdAt = os.time() - 3600 }, id = 725, subject = "General Support",
	closer = { mentionString = "<@1>" }, messages = 26, reason = "Done", url = "https://x.example/t", transcript = "log" })
local tc = sent[1].components[1].components
check("ticket title", tc[1].content:find("# 📋 Ticket #0725 %- General Support") ~= nil)
check("ticket fields", tc[2].content:find("> %*%*Handled by%*%* · Unclaimed") and tc[2].content:find("> %*%*Duration%*%* · 1h"))
check("ticket reason section", tc[3].content == "**Reason**\n> Done")
check("ticket file + button + footer", tc[4].type == 13 and tc[5].type == 1 and tc[6].content == "-# Tennessee State Roleplay · Ticket #0725")
check("ticket file attached", sent[1].files and sent[1].files[1][1] == "transcript.txt")

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
