-- Run from bot/ with the pm2 LUA_CPATH (see ecosystem.config.cjs): ./luvit tests/sqldb_permissions_test.lua
-- Exercises the command_permissions table CRUD in sqldb.lua against a throwaway database in a temp directory.
local uv = require("uv")
_G.uv = uv
_G.fs = require("fs")
_G.cjson = require("cjson")
_G.sqlite3 = require("sqlite3")
_G.p = p or print
local discordia = require("discordia")
_G.discordia = discordia
discordia.extensions()
_G.onFlightSQLDBStart = true -- skip the startup backup copy
_G.prettyLog = function(_, _, msg) print("[log] " .. tostring(msg)) end
local cp = require("../utils/cmdperms")

local botDir = uv.cwd()
local tmp = "/tmp/zeltra-permtest-" .. os.time()
os.execute("mkdir -p " .. tmp)
uv.chdir(tmp)

local sqldb = dofile(botDir .. "/sqldb.lua")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 print("PASS  " .. name) else failed = failed + 1 print("FAIL  " .. name) end
end

local G = "100"
check("empty guild -> {}", next(sqldb:getCommandPermissions(G)) == nil)
check("set warn", sqldb:setCommandPermission(G, "warn", { mode = "roles-only", roles = { ["900"] = true, ["902"] = false }, users = { ["444"] = true } }, "1307878235383795732"))
check("set shift manage", sqldb:setCommandPermission(G, "shift manage", { mode = "everyone" }, "1"))
local map = sqldb:getCommandPermissions(G)
check("roundtrip mode", map.warn and map.warn.mode == "roles-only")
check("roundtrip role allow", map.warn.roles["900"] == true and map.warn.roles["902"] == false)
check("roundtrip user", map.warn.users["444"] == true)
check("subcommand key stored", map["shift manage"] and map["shift manage"].mode == "everyone")
local fresh = sqldb:getCommandPermissions(G, true)
check("uncached read matches", fresh.warn and fresh.warn.roles["900"] == true)

-- resolver against stored data
local r = cp.resolve({ userId = "333", guildOwnerId = "1", roleIds = { "900" }, devIds = {}, overrides = map, keys = cp.keysFor("warn") })
check("stored role allow resolves to allow", r.decision == "allow" and r.granted)
r = cp.resolve({ userId = "334", guildOwnerId = "1", roleIds = {}, devIds = {}, overrides = map, keys = cp.keysFor("warn") })
check("stored roles-only denies others", r.decision == "deny")

local all = sqldb:getAllCommandPermissions()
check("getAllCommandPermissions", all[G] and all[G].warn ~= nil)
check("delete", sqldb:deleteCommandPermission(G, "warn"))
check("deleted", sqldb:getCommandPermissions(G).warn == nil and sqldb:getCommandPermissions(G)["shift manage"] ~= nil)
check("other guild isolated", next(sqldb:getCommandPermissions("200")) == nil)

sqldb:close()
uv.chdir(botDir)
os.execute("rm -rf " .. tmp)
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
