-- Run from bot/: ./luvit tests/dmstyle_test.lua
-- Zeltra: checks the DM card builder (libs/zeltra-dmstyle.lua) without touching Discord.
local dm = require("../libs/zeltra-dmstyle")
local json = require("json")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 print("PASS  " .. name) else failed = failed + 1 print("FAIL  " .. name) end
end

local guild = { name = "South Carolina Roleplay" }

check("serverName uses guild name", dm.serverName(guild) == "South Carolina Roleplay")
check("serverName falls back", dm.serverName(nil) == "South Carolina Roleplay")
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
check("footer", c.components[5].content == "-# South Carolina Roleplay · Staff Management")
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
check("ticket file + button + footer", tc[4].type == 13 and tc[5].type == 1 and tc[6].content == "-# South Carolina Roleplay · Ticket #0725")
check("ticket file attached", sent[1].files and sent[1].files[1][1] == "transcript.txt")

-- channel post with ping
local posted = {}
local chan = { id = "c1", send = function(self, p) table.insert(posted, p) return { id = "m" } end }
dm.post(chan, { guild = guild, icon = "🎓", title = "Staff promotion", fields = { { "New Rank", "<@&5>" } }, footer = "Staff Management" }, "42")
local pc = posted[1]
check("post ping above the card", pc.components[1].type == 10 and pc.components[1].content == "-# 🔔 <@42>" and pc.components[2].type == 17)
check("post pings only that user", #pc.allowed_mentions.parse == 0 and pc.allowed_mentions.users[1] == "42")
check("post keeps V2 flag", pc.flags == 32768)

posted = {}
local badChan = { id = "c2", send = function(self, p) table.insert(posted, p) if p.flags then return nil, "HTTP 400" end return { id = "m" } end }
dm.post(badChan, { title = "Infraction issued", fields = { { "A", "b" } } }, "42")
check("post falls back to embed with ping", #posted == 2 and posted[2].embed and posted[2].content == "-# 🔔 <@42>")
check("post with no channel is safe", dm.post(nil, { title = "x" }) == nil)

-- Discord Components V2 limits (https://discord.com/developers/docs/components/reference)
local function countText(comps)
	local n, total = 0, 0
	for _, c in ipairs(comps) do
		n = n + 1
		if c.type == 10 then total = total + #c.content end
		if c.components then local a, b = countText(c.components) n = n + a total = total + b end
	end
	return n, total
end
local long = dm.build({ guild = guild, icon = "⚖️", title = "t", intro = string.rep("x", 5000),
	fields = { { "Reason", string.rep("y", 5000) } }, sections = { { title = "Reason", body = string.rep("z", 5000) } } })
local n, total = countText(long.components)
check("component count <= 40", n <= 40)
check("each text display <= 4000 chars", (function() for _, c in ipairs(long.components[1].components) do if c.type == 10 and #c.content > 4000 then return false end end return true end)())
check("accent is an integer color", math.floor(long.components[1].accent_color) == long.components[1].accent_color and long.components[1].accent_color <= 0xFFFFFF)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
