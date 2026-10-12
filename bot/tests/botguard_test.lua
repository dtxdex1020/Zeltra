-- Zeltra: bot guard helpers in libs/zeltra-security-core.lua
local S = require("../libs/zeltra-security-core")
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1; print("PASS  " .. name) else failed = failed + 1; print("FAIL  " .. name) end end

local sec = S.withDefaults({})
check("bot guard on by default", sec.botguard.enabled == true and sec.botguard.timeoutminutes == 1440)
check("old configs get bot guard defaults", S.withDefaults({ enabled = true, botguard = { enabled = false } }).botguard.timeoutminutes == 1440)
check("DM wording", S.BOT_DM == "You are not allowed to invite bots to this server. Your roles have been removed and you have been timed out while this is investigated.")
check("no em dash in DM", not S.BOT_DM:find("\226\128\148"))

local allow = { ["111"] = 200, ["222"] = 50 }
check("allowed bot inside window", S.botAllowed(allow, "111", 100) == true)
check("expired allowance removed", S.botAllowed(allow, "222", 100) == false and allow["222"] == nil)
check("unknown bot not allowed", S.botAllowed(allow, "333", 100) == false)
check("nil allow table", S.botAllowed(nil, "1", 1) == false)

local strip, skipped = S.splitRoles({
	{ id = "g", name = "@everyone", position = 0 },
	{ id = "a", name = "Staff", position = 5 },
	{ id = "b", name = "Owner", position = 50 },
	{ id = "c", name = "Booster", position = 3, managed = true },
}, 40, "g")
check("strips roles below the bot", #strip == 1 and strip[1].id == "a")
check("skips roles above the bot and managed ones", #skipped == 2)
check("everyone is never touched", (function() for _, r in ipairs(strip) do if r.id == "g" then return false end end for _, r in ipairs(skipped) do if r.id == "g" then return false end end return true end)())

local e = { { target_id = "9", user_id = "old", action_type = 28, created = 0 }, { target_id = "7", user_id = "u1", action_type = 28, created = 95 } }
check("finds the adder of this bot", S.findBotAdder(e, "7", 100, 120) == "u1")
check("ignores old entries", S.findBotAdder(e, "9", 1000, 120) == nil)
check("no entry -> nil", S.findBotAdder({}, "7", 100, 120) == nil)
check("Shark's accounts are protected", S.isProtectedId("1307878235383795732") and S.isProtectedId("1514313618827510011"))
check("random user is not protected", not S.isProtectedId("42"))

local admin = tostring(8)
check("key perms admin", S.botKeyPerms(admin)[1] == "Administrator")
local lvl, why = S.botRisk({ verified = false, ageDays = 3, perms = admin, description = nil, name = "Nuke Bot" })
check("obvious nuke bot is High", lvl == "High" and #why >= 4)
lvl, why = S.botRisk({ verified = true, ageDays = 900, perms = "0", description = "Music for your server", name = "Tunes" })
check("verified old bot with no perms is Low", lvl == "Low" and why[1] == "nothing stood out")
lvl = S.botRisk({ verified = false, ageDays = 400, perms = tostring(2 ^ 28), description = "Helps with roles", name = "Roley" })
check("unverified with Manage Roles is Medium", lvl == "Medium")
check("wording says it's not a verdict elsewhere, reasons are plain", not table.concat(why, " "):find("\226\128\148"))

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then process:exit(1) end
