-- Run from bot/: ./luvit tests/security_test.lua
-- Zeltra: checks the security core (libs/zeltra-security-core.lua) without touching Discord.
local S = require("../libs/zeltra-security-core")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 print("PASS  " .. name) else failed = failed + 1 print("FAIL  " .. name) end
end

-- defaults
local c = S.withDefaults({ antiraid = { joins = 12 }, whitelist = { users = { "1" } } })
check("defaults keep stored values", c.antiraid.joins == 12 and c.whitelist.users[1] == "1")
check("defaults fill missing", c.antiraid.window == 30 and c.antinuke.count == 3 and c.flagged.revertperms == false)
check("defaults do not mutate DEFAULTS", S.DEFAULTS.antiraid.joins == 8)
check("raid off by default", c.raid.active == false and c.antiraid.lockchannels == false)

-- join rate: 8 joins in 30s
local w = S.newWindow()
local n
for i = 1, 7 do n = w:hit("g", 1000 + i, 30) end
check("7 joins is not a raid", n == 7 and n < c.antiraid.joins)
n = w:hit("g", 1010, 30)
check("8th join within 30s hits threshold", n >= 8)
check("old joins fall out of the window", w:hit("g", 1100, 30) == 1)

-- anti-nuke: 3 in 60s per executor
local nk = S.newWindow()
nk:hit("u1:ban", 0, 60) nk:hit("u2:ban", 1, 60)
check("different executors counted separately", nk:hit("u1:ban", 2, 60) == 2)
check("third ban by same executor", nk:hit("u1:ban", 3, 60) == 3)

-- cooldown
local cd = S.newCooldown()
check("cooldown fires once", cd("k", 0, 60) and not cd("k", 30, 60) and cd("k", 61, 60))

-- accounts
check("snowflake time", S.snowflakeTime("1307878235383795732") > 1700000000)
check("account age", math.floor(S.accountAgeDays(0, 86400 * 3)) == 3)
check("suspicious names", S.suspiciousName("Free Nitro Here") ~= nil and S.suspiciousName("user123456789") ~= nil and S.suspiciousName("Shark") == nil)

-- permission bits
check("admin bit", S.hasBit("8", 3) and not S.hasBit("16", 3))
check("timeout bit 40", S.hasBit("1099511627776", 40))
check("bit above 2^53 is exact", S.hasBit("18014398509481992", 3) and S.hasBit("18014398509481992", 54))
local added = S.addedDangerous("1024", "1032")
check("granting admin detected", #added == 1 and added[1] == "Administrator")
check("no change, nothing added", #S.addedDangerous("268435464", "268435464") == 0)
check("removing perms is not flagged", #S.addedDangerous("8", "0") == 0)
check("dangerousIn", #S.dangerousIn("268435464") == 2)
check("withoutDangerous clears admin+roles keeps view", S.withoutDangerous(tostring(8 + 268435456 + 1024)) == "1024")
check("withoutDangerous large value", S.withoutDangerous("18014398509481992") == "18014398509481984")

check("severeIn ignores kick/timeout/mention everyone", #S.severeIn(tostring(2 + 131072 + 1099511627776)) == 0 and #S.severeIn("8") == 1)

-- misc
check("owners protected", S.isProtectedId("1307878235383795732") and S.isProtectedId("1514313618827510011") and not S.isProtectedId("5"))
check("extra protected", S.isProtectedId("5", { "5" }))
check("mention count unique", S.countMentions("<@1> <@!1> <@2> <@&3> hi") == 3)

-- raid keywords
local should = { ".nuk", ".raid", "Raidddd", ".nuke", "!raid", "!nuke", "?nuke", "-nuke", "/nuke", ".massban", ".massdm", ".spam",
	".destroy", ".wipe", ".purgeall", ".banall", ".kickall", ".lockall", ".webhookspam", "raid", "nuke", "nuking", "raiding",
	"we got nuked lol", "r4id", "nuk3", "R41D", "r a i d", "n.u.k.e", "N U K E", "r-a-i-d", "nuuuuke", "RAID NOW", "riad", "nuek", "raod", "the raids" }
for _, text in ipairs(should) do
	check("detects " .. text, S.detectRaidKeyword(text) ~= nil)
end
local shouldNot = { "Numere", "braid", "afraid", "I paid", "raider", "Raiders won the game", "rapid", "arid", "nude", "duke", "said what",
	"rainy day", "the maid laid it down", "2024 4 1 3", "hello <@123456789012345678>", "i need help", "good morning",
	"bookkeeper", "nuance", "I like peanuts", "paradise", "Rapid response", "aid the team", "nucleus" }
for _, text in ipairs(shouldNot) do
	check("ignores " .. text, S.detectRaidKeyword(text) == nil)
end
check("command kind", S.detectRaidKeyword(".nuk").kind == "command")
check("typo kind", S.detectRaidKeyword("riad").kind == "typo")
check("custom keyword", S.detectRaidKeyword("Numere", { "numere" }).kind == "custom")
check("custom phrase", S.detectRaidKeyword("time to wipe the server", { "wipe the server" }) ~= nil)
check("collapse", S.collapse("raidddd") == "raid")
check("edit distance swap", S.editDistance("riad", "raid") == 1)

-- lockdown bits
local la, ld = S.lockOverwrite("3072", "0")
check("lock removes send from allow, keeps view", la == "1024")
check("lock denies send, send in threads, reactions, create public threads", ld == "309237647424")
local _, ld2 = S.lockOverwrite("0", "1024")
check("lock keeps existing denies", ld2 == "309237648448")
check("isLocked", S.isLocked("309237647424") and not S.isLocked("2048"))
check("allowsAnyLockBit", S.allowsAnyLockBit("2048") and S.allowsAnyLockBit("64") and not S.allowsAnyLockBit("1024"))

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
