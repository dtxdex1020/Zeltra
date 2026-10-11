-- Run from bot/: ./luvit tests/cmdperms_test.lua
local cp = require("../utils/cmdperms")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then
		passed = passed + 1
		print("PASS  " .. name)
	else
		failed = failed + 1
		print("FAIL  " .. name)
	end
end

local OWNER = "1307878235383795732"
local GOWNER = "111"
local MOD_ROLE, MEMBER_ROLE, BAD_ROLE = "900", "901", "902"

local function run(userId, roleIds, overrides, name, subcmd)
	return cp.resolve({
		userId = userId,
		guildOwnerId = GOWNER,
		roleIds = roleIds or {},
		devIds = { "222" },
		overrides = overrides or {},
		keys = cp.keysFor(name or "warn", subcmd)
	})
end

-- owner bypass
local r = run(OWNER, {}, { warn = { mode = "disabled" } })
check("bot owner allowed even when disabled", r.decision == "allow" and r.privileged == "bot_owner")
r = run("222", {}, { warn = { mode = "disabled" } })
check("DEV_ACCESS_IDS user is bot owner", r.decision == "allow" and r.privileged == "bot_owner")
r = run(GOWNER, {}, { warn = { mode = "roles-only" } })
check("server owner allowed in roles-only", r.decision == "allow" and r.privileged == "guild_owner")
check("owner id constant", cp.isBotOwner(OWNER, {}) and not cp.isBotOwner("5", {}))

-- no override
r = run("333", { MOD_ROLE }, {})
check("no override -> default", r.decision == "default" and not r.granted)

-- role allow
local ov = { warn = { mode = "default", roles = { [MOD_ROLE] = true } } }
r = run("333", { MOD_ROLE }, ov)
check("allowed role -> allow + granted", r.decision == "allow" and r.granted and r.role == MOD_ROLE)
r = run("334", { MEMBER_ROLE }, ov)
check("other role in default mode -> default", r.decision == "default")

-- roles-only
ov = { warn = { mode = "roles-only", roles = { [MOD_ROLE] = true } } }
check("roles-only: role allowed", run("333", { MOD_ROLE }, ov).decision == "allow")
check("roles-only: others denied", run("334", { MEMBER_ROLE }, ov).decision == "deny")

-- role deny + allow precedence
ov = { warn = { mode = "everyone", roles = { [BAD_ROLE] = false, [MOD_ROLE] = true } } }
check("everyone: plain member allowed", run("335", {}, ov).decision == "allow")
check("everyone: denied role blocked", run("336", { BAD_ROLE }, ov).decision == "deny")
check("allow role wins over deny role", run("337", { BAD_ROLE, MOD_ROLE }, ov).decision == "allow")

-- user overrides
ov = { warn = { mode = "roles-only", roles = { [MOD_ROLE] = true }, users = { ["444"] = true, ["445"] = false } } }
check("user allow beats roles-only", run("444", {}, ov).decision == "allow")
check("user deny beats role allow", run("445", { MOD_ROLE }, ov).decision == "deny")

-- disabled mode
ov = { warn = { mode = "disabled", users = { ["444"] = true }, roles = { [MOD_ROLE] = true } } }
check("disabled: allowed user still denied", run("444", { MOD_ROLE }, ov).decision == "deny")
check("disabled: owner still allowed", run(OWNER, {}, ov).decision == "allow")

-- subcommand specificity
ov = { shift = { mode = "roles-only", roles = { [MOD_ROLE] = true } }, ["shift manage"] = { mode = "everyone" } }
check("subcommand override beats parent", run("500", {}, ov, "shift", "manage").decision == "allow")
check("parent override applies to other subcommand", run("500", {}, ov, "shift", "void").decision == "deny")
check("keysFor order", table.concat(cp.keysFor("shift", "wave view"), "|") == "shift wave view|shift wave|shift")

-- visibility
check("needsVisible everyone", cp.needsVisible({ mode = "everyone" }))
check("needsVisible roles-only", cp.needsVisible({ mode = "roles-only" }))
check("needsVisible default+allow role", cp.needsVisible({ roles = { ["1"] = true } }))
check("not visible: disabled", not cp.needsVisible({ mode = "disabled", roles = { ["1"] = true } }))
check("not visible: default+deny only", not cp.needsVisible({ roles = { ["1"] = false } }))
check("isEmpty", cp.isEmpty({ mode = "default", roles = {}, users = {} }) and not cp.isEmpty({ mode = "everyone" }))
check("normalize bad mode -> default", cp.normalize({ mode = "bogus" }).mode == "default")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exitCode = 1
	os.exit(1)
end
