--[[
	Mock test for modules/discord_moderation/security.lua (Zeltra). No network, no Discord.
	Run: ./luvit tests/security_module_test.lua
	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]
package.path = "./libs/?.lua;" .. package.path
local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. name) end
end

_G.securityCore = dofile("libs/zeltra-security-core.lua")
local posts = {}
_G.sqldb = { store = {} }
function sqldb:get(id) return self.store[id] end
function sqldb:set(id, changes) self.store[id] = self.store[id] or {} for k, v in pairs(changes) do self.store[id][k] = v end return true end
_G.json = require("json")
_G.dmStyle = dofile("libs/zeltra-dmstyle.lua") or _G.dmStyle
dmStyle.post = function(channel, opts) table.insert(posts, opts) return true end
_G.discordia = { enums = { permission = { sendMessages = 2048 } } }
_G.isBotOwner = function() return false end
_G.timer = { setInterval = function() return 1 end, clearInterval = function() end }

local handlers = {}
local function iter(list) local i = 0 return { iter = function() return function() i = i + 1 return list[i] end end } end
local function iterOf(list) return { iter = function() local i = 0 return function() i = i + 1 return list[i] end end } end

local function perms(set) return { has = function(_, p) return set[p] == true end } end
local channelState = {}
local function makeChannel(id, everyoneSend)
	local ow = { allow = {}, deny = {} }
	channelState[id] = ow
	return {
		id = id, name = "general-" .. id, send = function() end, mentionString = "<#" .. id .. ">",
		getPermissionOverwriteFor = function()
			return {
				getAllowedPermissions = function() return perms({ sendMessages = ow.allow.send }) end,
				getDeniedPermissions = function() return perms({ sendMessages = ow.deny.send }) end,
				denyPermissions = function() ow.deny.send = true ow.allow.send = nil return true end,
				allowPermissions = function() ow.allow.send = true ow.deny.send = nil return true end,
				clearPermissions = function() ow.allow.send = nil ow.deny.send = nil return true end,
			}
		end,
	}
end
local chans = { makeChannel("c1"), makeChannel("c2") }
local logChannel = makeChannel("log")
local timeouts, removedRoles = {}, {}

local function makeMember(id, rolesList, extra)
	local m = {
		id = id, user = { id = id, bot = false, avatar = "abc", username = "user" .. id, createdAt = os.time() - 86400 * 400, mentionString = "<@" .. id .. ">" },
		roles = iterOf(rolesList or {}),
		timeoutFor = function(_, s) timeouts[id] = s return true end,
		removeTimeout = function() timeouts[id] = nil return true end,
		kick = function() return true end,
		removeRole = function(_, rid) table.insert(removedRoles, rid) return true end,
		hasPermission = function() return false end,
	}
	m.guild = _G.__testGuild
	for k, v in pairs(extra or {}) do m[k] = v end
	return m
end

local adminRole = { id = "r1", name = "Admin", _permissions = "8", position = 10, managed = false }
local highRole = { id = "r2", name = "Above Bot", _permissions = "8", position = 200, managed = false }
local plainRole = { id = "r3", name = "Member", _permissions = "1024", position = 2, managed = false }
local nuker = makeMember("999", { adminRole, highRole, plainRole })

local guild = {
	id = "g1", name = "Tennessee State Roleplay", ownerId = "owner", verificationLevel = 1,
	setVerificationLevel = function(self, l) self.verificationLevel = l return true end,
	defaultRole = { getPermissions = function() return perms({ viewChannel = true, sendMessages = true }) end },
	textChannels = iterOf(chans),
	me = { highestRole = { position = 153 } },
	getChannel = function(_, id) if id == "log" then return logChannel end for _, c in ipairs(chans) do if c.id == id then return c end end end,
	getMember = function(_, id) if id == "999" then return nuker end return makeMember(id) end,
	getRole = function(_, id) if id == "r1" then return adminRole end end,
}
_G.__testGuild = guild
nuker.guild = guild
_G.Client = {
	user = { id = "bot" },
	on = function(_, ev, fn) handlers[ev] = fn return fn end,
	removeListener = function() end,
	getGuild = function() return guild end,
	guilds = iterOf({ guild }),
	_api = { modifyGuildRole = function(_, g, r, p) _G.lastRoleEdit = p return true end },
}
sqldb.store.g1 = { security = { logchannel = "log", antiraid = { lockchannels = true } } }

local mod = assert(loadfile("modules/discord_moderation/security.lua"))()
mod.Start()
local api = _G.zeltraSecurity
check("api exposed", api and api.startRaid and api.endRaid)

-- raid via joins
for i = 1, 8 do handlers.memberJoin(makeMember("j" .. i)) end
local sec = api.getSec(guild)
check("8 joins started raid mode", sec.raid.active == true)
check("verification raised", guild.verificationLevel == 3 and sec.raid.prevVerification == 1)
check("public channels locked", #sec.raid.locked == 2 and channelState.c1.deny.send == true)
check("raid alert posted", posts[#posts] and posts[#posts].title == "Raid detected" and posts[#posts].footer == "Security")
handlers.memberJoin(makeMember("late"))
check("joiner during raid timed out", timeouts.late and timeouts.late >= 300)
check("second start refused", api.startRaid(guild, { by = "x" }) == false)

-- end raid
local ok = api.endRaid(guild, "mod")
sec = api.getSec(guild)
check("raid ended", ok and sec.raid.active == false)
check("verification restored", guild.verificationLevel == 1)
check("channels unlocked", channelState.c1.deny.send == nil)
check("timeouts lifted", timeouts.late == nil)
check("end alert posted", posts[#posts].title == "Raid mode ended")

-- anti-nuke: 3 bans by same executor
for i = 1, 3 do handlers.guildAuditLogEntryCreate({ guild_id = "g1", action_type = 22, user_id = "999", target_id = "t" .. i }) end
check("nuke alert posted", posts[#posts].title == "Unusual staff activity")
check("only roles below bot removed", #removedRoles == 1 and removedRoles[1] == "r1")
check("skipped high role mentioned", posts[#posts].fields[3][2]:find("Above Bot", 1, true) ~= nil)

-- owner is never acted on
removedRoles = {}
local ownerMember = makeMember("1307878235383795732", { adminRole })
guild.getMember = function(_, id) if id == "999" then return nuker end if id == "1307878235383795732" then return ownerMember end return makeMember(id) end
for i = 1, 3 do handlers.guildAuditLogEntryCreate({ guild_id = "g1", action_type = 12, user_id = "1307878235383795732", target_id = "c" .. i }) end
check("bot owner not stripped", #removedRoles == 0 and posts[#posts].fields[3][2]:find("Alert only", 1, true))

-- permission grant with revert
sqldb.store.g1.security.flagged = { revertperms = true }
handlers.guildAuditLogEntryCreate({ guild_id = "g1", action_type = 31, user_id = "999", target_id = "r5",
	changes = { { key = "permissions", old_value = "1024", new_value = "1032" } } })
check("grant alert posted", posts[#posts].title == "Dangerous permissions granted")
check("grant reverted to old value", _G.lastRoleEdit and _G.lastRoleEdit.permissions == "1024")

-- bot-made changes ignored
local before = #posts
handlers.guildAuditLogEntryCreate({ guild_id = "g1", action_type = 31, user_id = "bot", target_id = "r5",
	changes = { { key = "permissions", old_value = "0", new_value = "8" } } })
check("bot's own changes ignored", #posts == before)

-- member given admin role
handlers.guildAuditLogEntryCreate({ guild_id = "g1", action_type = 25, user_id = "999", target_id = "555",
	changes = { { key = "$add", new_value = { { id = "r1", name = "Admin" } } } } })
check("powerful role grant alert", posts[#posts].title == "Powerful role given")

-- bot added, settings
handlers.guildAuditLogEntryCreate({ guild_id = "g1", action_type = 28, user_id = "999", target_id = "777" })
check("bot added alert", posts[#posts].title == "Bot added")
handlers.guildAuditLogEntryCreate({ guild_id = "g1", action_type = 1, user_id = "999", target_id = "g1",
	changes = { { key = "vanity_url_code", old_value = "tsrp", new_value = "x" } } })
check("vanity alert", posts[#posts].title == "Server settings changed" and posts[#posts].fields[2][1] == "Vanity URL")

-- messages
local function msg(content, everyone)
	return { guild = guild, author = { id = "123", bot = false, mentionString = "<@123>" }, member = makeMember("123"),
		channel = logChannel, content = content, mentionsEveryone = everyone, link = "https://discord.com/channels/g1/c1/1" }
end
handlers.messageCreate(msg("@everyone hi", true))
check("@everyone flagged", posts[#posts].title == "@everyone ping")
handlers.messageCreate(msg("<@1><@2><@3><@4><@5><@6>"))
check("mass mention flagged", posts[#posts].title == "Mass mention")
for i = 1, 7 do handlers.messageCreate(msg("spam " .. i)) end
check("burst flagged", posts[#posts].title == "Message burst")

-- suspicious join
local sus = makeMember("new1")
sus.user.createdAt = os.time() - 3600
sus.user.avatar = nil
handlers.memberJoin(sus)
check("new account flagged", posts[#posts].title == "Flagged account joined" and posts[#posts].fields[3][2]:find("default avatar", 1, true))

-- every alert builds a valid V2 payload with no em dashes
local allOk = true
for _, p in ipairs(posts) do
	local payload = dmStyle.build(p)
	local text = json.encode(payload)
	if payload.flags ~= 32768 or text:find("\226\128\148") then allOk = false end
end
check("all alerts build V2 payloads without em dashes", allOk)

if os.getenv("SECURITY_PREVIEW_OUT") then
	local want = { ["Raid detected"] = "raid", ["Unusual staff activity"] = "staff-activity", ["Dangerous permissions granted"] = "permission-grant" }
	local out = {}
	for _, p in ipairs(posts) do
		if want[p.title] then
			table.insert(out, { name = want[p.title], payload = dmStyle.build(p) })
			want[p.title] = nil
		end
	end
	local f = io.open(os.getenv("SECURITY_PREVIEW_OUT"), "w") f:write(json.encode(out)) f:close()
end

mod.Stop()
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
