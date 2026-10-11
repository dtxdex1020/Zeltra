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
dmStyle.post = function(channel, opts) table.insert(posts, opts) return { id = "post" .. #posts } end
local realSend = dmStyle.send
local dmsSent = {}
dmStyle.send = function(target, opts) table.insert(dmsSent, { target = target, opts = opts }) return true end
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
	_api = {
		modifyGuildRole = function(_, g, r, p) _G.lastRoleEdit = p return true end,
		getGuildChannels = function() return _G.fakeChannels end,
		editChannelPermissions = function(_, c, id, p) table.insert(_G.permCalls, { "edit", c, id, p }) return true end,
		deleteChannelPermission = function(_, c, id) table.insert(_G.permCalls, { "delete", c, id }) return true end,
		editMessage = function(_, c, m, p) _G.lastEdit = { c, m, p } return true end,
	},
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

-- raid keyword detection: applies to owners too, alerts, deletes, DMs, times out, locks everything
_G.permCalls = {}
_G.fakeChannels = {
	{ id = "t1", type = 0, permission_overwrites = {
		{ id = "g1", type = 0, allow = "0", deny = "1024" },
		{ id = "staffrole", type = 0, allow = "3072", deny = "0" },   -- view + send, non-admin: gets locked
		{ id = "adminrole", type = 0, allow = "2048", deny = "0" },   -- admin role: left alone
		{ id = "u5", type = 1, allow = "2048", deny = "0" } } },     -- member overwrite: not a role, left alone
	{ id = "v1", type = 2, permission_overwrites = {} },                -- voice, no @everyone overwrite yet
	{ id = "f1", type = 15, permission_overwrites = {} },               -- forum
	{ id = "cat", type = 4, permission_overwrites = {} },               -- category: skipped
	{ id = "already", type = 0, permission_overwrites = { { id = "g1", type = 0, allow = "0", deny = "309237647424" } } },
}
local roleTable = { adminrole = { id = "adminrole", _permissions = "8" }, staffrole = { id = "staffrole", _permissions = "1024" } }
for _, rid in ipairs({ "1522997818330058781", "1522997818363740160", "1522997818363740161", "1522997818363740163" }) do roleTable[rid] = { id = rid, _permissions = "8" } end
_G.pingMsgs = {}
logChannel.send = function(self, p) table.insert(_G.pingMsgs, p) return { id = "ping" .. #_G.pingMsgs } end
guild.getRole = function(_, id) return roleTable[id] or ((id == "r1") and adminRole) or nil end
guild.ownerId = "1307878235383795732" -- the server owner can't be timed out
local deleted = 0
local function kwMsg(authorId, content, ownerMember)
	local m = ownerMember or makeMember(authorId)
	return { guild = guild, author = { id = authorId, bot = false, username = "dex", mentionString = "<@" .. authorId .. ">" }, member = m,
		channel = { id = "hrcmds", mentionString = "<#hrcmds>" }, content = content, link = "https://discord.com/channels/g1/hrcmds/9",
		delete = function() deleted = deleted + 1 return true end }
end
-- the owner is whitelisted, exempt and the server owner, and still triggers it
sqldb.store.g1.security.whitelist = { users = { "1307878235383795732" }, roles = {} }
local before = #posts
handlers.messageCreate(kwMsg("1307878235383795732", ".nuk", ownerMember))
local kwAlert = posts[before + 1]
check("owner .nuk triggers alert", kwAlert and kwAlert.title == "Raid command detected")
check("alert pings nobody", dmStyle.build(kwAlert).allowed_mentions.parse[1] == nil)
check("alert has jump, remove timeout and unlock buttons", json.encode(dmStyle.build(kwAlert)):find("sec:untimeout:1307878235383795732", 1, true)
	and json.encode(dmStyle.build(kwAlert)):find("sec:unlock", 1, true) and json.encode(dmStyle.build(kwAlert)):find("discord.com/channels", 1, true))
check("3 ping messages after the alert", #_G.pingMsgs == 3)
check("pings only the owners and ownership roles", (function()
	for _, p in ipairs(_G.pingMsgs) do
		local am = p.allowed_mentions
		if #am.parse ~= 0 or #am.users ~= 2 or #am.roles ~= 4 then return false end
		if not p.content:find("<@1307878235383795732>", 1, true) or not p.content:find("<@1514313618827510011>", 1, true) or not p.content:find("<@&1522997818363740163>", 1, true) then return false end
		if p.content:find("\226\128\148") then return false end
	end
	return true
end)())
check("message deleted", deleted == 1)
check("DM sent in card style", #dmsSent == 1 and dmsSent[1].opts.title == "You're suspected of raiding" and dmsSent[1].opts.intro == "Please be patient while we review the report.")
local finalCard = json.encode(_G.lastEdit[3])
check("server owner timeout skipped and noted", finalCard:find("Skipped: Discord can't time out the server owner", 1, true) ~= nil)
check("alert edited with lockdown result", finalCard:find("Lockdown** · On", 1, true) ~= nil)
local ld = api.getSec(guild).lockdown
check("lockdown active and saved", ld.active == true and #ld.entries == 4)
local touched = {}
for _, c in ipairs(_G.permCalls) do touched[c[2] .. ":" .. c[3]] = c[4] end
check("@everyone locked in text, voice and forum", touched["t1:g1"] and touched["v1:g1"] and touched["f1:g1"])
check("non-admin role with allow locked", touched["t1:staffrole"] and touched["t1:staffrole"].allow == "1024")
check("admin role, member overwrite, category untouched", not touched["t1:adminrole"] and not touched["t1:u5"] and not touched["cat:g1"])
check("channel already locked is skipped", not touched["already:g1"])
check("lock denies send, threads, reactions, create threads", touched["v1:g1"].deny == "309237647424" and touched["t1:g1"].deny == "309237648448")
check("previous overwrites saved exactly", (function()
	for _, e in ipairs(ld.entries) do
		if e.c == "t1" and e.id == "g1" then if not (e.e and e.a == "0" and e.d == "1024") then return false end end
		if e.c == "v1" and e.id == "g1" then if e.e then return false end end
		if e.c == "t1" and e.id == "staffrole" then if not (e.a == "3072" and e.d == "0") then return false end end
	end
	return true
end)())

-- a second match inside the cooldown alerts but doesn't lock again
_G.permCalls = {}
local regular = makeMember("4242")
handlers.messageCreate(kwMsg("4242", "we are going to raid lol", regular))
check("second match alerts", posts[#posts].title == "Raid command detected")
check("no relock inside cooldown", #_G.permCalls == 0 and json.encode(_G.lastEdit[3]):find("not locking again", 1, true) ~= nil)
check("regular member timed out 60 minutes", timeouts["4242"] == 3600)
check("no pings on cooldown repeats", #_G.pingMsgs == 3)

-- false positives don't fire
before = #posts
for _, text in ipairs({ "I'm afraid of that braid", "the Raiders won", "I paid for it", "rapid response" }) do
	handlers.messageCreate(kwMsg("4242", text, regular))
end
check("normal words don't trigger", #posts == before)

-- custom keyword
sqldb.store.g1.security.keywords = { custom = { "numere" } }
handlers.messageCreate(kwMsg("4242", "Numere", regular))
check("custom keyword triggers", posts[#posts].title == "Raid command detected" and posts[#posts].fields[3][2]:find("custom", 1, true))

-- detection off
sqldb.store.g1.security.keywords = { enabled = false }
before = #posts
handlers.messageCreate(kwMsg("4242", ".nuke", regular))
check("keyword detection can be turned off", #posts == before)
sqldb.store.g1.security.keywords = nil

-- ticket channels: words like "raid" in a report are ignored, prefix commands still count
sqldb.store.g1.security.flagged.mentions = false -- keep spam burst alerts out of these counts
sqldb.store.g1.panels = { p1 = { subjects = { { category = "ticketcat", tickets = { { channel = "tk2" } } } } } }
local function ticketMsg(content, channelId, parentId)
	local m = kwMsg("4242", content, regular)
	m.channel = { id = channelId, _parent_id = parentId, mentionString = "<#" .. channelId .. ">" }
	return m
end
before = #posts
handlers.messageCreate(ticketMsg("he said he would raid us and nuke the server", "tk1", "ticketcat"))
check("raid words in a ticket category don't trigger", #posts == before)
handlers.messageCreate(ticketMsg("raid", "tk2", nil))
check("raid words in an open ticket channel don't trigger", #posts == before)
handlers.messageCreate(ticketMsg("raid", "general", "othercat"))
check("raid words outside tickets still trigger", #posts == before + 1)
before = #posts
handlers.messageCreate(ticketMsg(".nuke", "tk1", "ticketcat"))
check("prefix commands in tickets still trigger", #posts == before + 1)
sqldb.store.g1.security.keywords = { ignoretickets = false }
before = #posts
handlers.messageCreate(ticketMsg("raid", "tk1", "ticketcat"))
check("ticket exemption can be turned off", #posts == before + 1)
sqldb.store.g1.security.keywords = { ignorecategories = { "extracat" } }
before = #posts
handlers.messageCreate(ticketMsg("raid", "x1", "extracat"))
check("extra ignored categories work", #posts == before)
sqldb.store.g1.security.keywords = nil
sqldb.store.g1.panels = nil
sqldb.store.g1.security.flagged.mentions = nil

-- buttons
local function btn(userId, customId)
	local ia = { guild = guild, member = makeMember(userId), user = { id = userId, mentionString = "<@" .. userId .. ">" }, data = { custom_id = customId }, log = {} }
	function ia:reply(p) table.insert(self.log, p) return true end
	function ia:replyDeferred() table.insert(self.log, "deferred") return true end
	return ia
end
local ia = btn("4242", "sec:unlock")
handlers.interactionCreate(ia)
check("non-owner can't unlock from the alert", json.encode(ia.log):find("Only the bot owners", 1, true) ~= nil and api.getSec(guild).lockdown.active)
ia = btn("4242", "sec:untimeout:4242")
handlers.interactionCreate(ia)
check("can't remove your own timeout", json.encode(ia.log):find("own timeout", 1, true) ~= nil)
local mod2 = makeMember("mod2") mod2.hasPermission = function(_, p) return p == "moderateMembers" end
ia = btn("mod2", "sec:untimeout:4242") ia.member = mod2
handlers.interactionCreate(ia)
check("staff can remove a timeout", timeouts["4242"] == nil and json.encode(ia.log):find("Removed the timeout", 1, true) ~= nil)

-- owner unlock restores exactly
_G.permCalls = {}
ia = btn("1514313618827510011", "sec:unlock")
handlers.interactionCreate(ia)
local restored = {}
for _, c in ipairs(_G.permCalls) do restored[c[2] .. ":" .. c[3]] = c end
check("owner unlock lifts lockdown", api.getSec(guild).lockdown.active == false and posts[#posts].title == "Lockdown lifted")
check("existing overwrite restored exactly", restored["t1:g1"][1] == "edit" and restored["t1:g1"][4].allow == "0" and restored["t1:g1"][4].deny == "1024")
check("role overwrite restored exactly", restored["t1:staffrole"][4].allow == "3072" and restored["t1:staffrole"][4].deny == "0")
check("new overwrites deleted", restored["v1:g1"][1] == "delete" and restored["f1:g1"][1] == "delete")

-- /security unlock is bot-owner only (admins and /permissions grants can't use it)
local stub = {}
stub.__index = function(t, k) return function(self, ...) return self end end
_G.tools = setmetatable({}, { __index = function(_, kind) return function(name) return setmetatable({ kind = kind, name = name }, stub) end end })
local secCmd = assert(loadfile("commands/security.lua"))()
local function cmdIa(userId)
	local ia = { guild = guild, member = makeMember(userId), user = { id = userId }, log = {} }
	function ia:fail(m) table.insert(self.log, { "fail", m }) return true end
	function ia:success(m) table.insert(self.log, { "success", m }) return true end
	function ia:reply(p) table.insert(self.log, { "reply", p }) return true end
	function ia:replyDeferred() table.insert(self.log, { "deferred" }) return true end
	return ia
end
local adminIa = cmdIa("4242") adminIa.member.hasPermission = function() return true end
secCmd.hybridCallback(adminIa, {}, true, "unlock")
check("admin can't use /security unlock", adminIa.log[1][1] == "fail" and adminIa.log[1][2]:find("bot owners", 1, true))
local ownerIa = cmdIa("1307878235383795732")
secCmd.hybridCallback(ownerIa, {}, true, "unlock")
check("owner reaches unlock (nothing to unlock)", ownerIa.log[#ownerIa.log][1] == "fail" and ownerIa.log[#ownerIa.log][2]:find("both off", 1, true))
local kwIa = cmdIa("1307878235383795732")
secCmd.hybridCallback(kwIa, { action = "add", word = "Numere" }, true, "config keyword")
check("custom keyword added via command", kwIa.log[1][1] == "success" and api.getSec(guild).keywords.custom[1] == "numere")

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
