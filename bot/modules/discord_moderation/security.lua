--[[
	Zeltra security system (added by Zeltra; not part of upstream Ducky V1).

	Builds on Ducky's audit logging (modules/discord_moderation/auditlogs.lua uses the same
	guildAuditLogEntryCreate gateway event) and autoban (known raid bots). Adds:
	  * anti-raid: join-rate detection, new/suspicious account flags, raid mode
	    (verification level, timeout/kick joiners, optional channel lock), auto-ends
	  * anti-nuke: the same destructive action by one person N times in a window -> alert
	    and remove their dangerous roles (below the bot's role only)
	  * flagged actions: dangerous permission grants (optional revert), bots added,
	    server setting edits, @everyone pings, mass mentions and message bursts
	  * raid/nuke keywords (.nuke, !raid, "raid", "nuke" ...) from anyone, owners included: alert,
	    delete the message, DM + time out the sender where Discord allows, and a full lockdown whose
	    exact previous overwrites are saved so /security unlock (bot owners only) restores them; in ticket
	    channels only prefix commands count, so reports that mention "raid" don't lock the server
	Alerts are posted as cards (libs/zeltra-dmstyle.lua) to the security log channel.
	Settings live in the guild config key `security` (see libs/zeltra-security-core.lua).

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local security = {
	name = "security",
	description = "Anti-raid, anti-nuke and flagged action alerts."
}

local S = _G.securityCore
local connections = {}
local interval

local joinWindow = S.newWindow()
local nukeWindow = S.newWindow()
local burstWindow = S.newWindow()
local cooldown = S.newCooldown()
local late = {} -- functions defined further down (fullLockdown, sendPings)
local deleteWindow = S.newWindow()
local SECURITY_LOGS = "1558672726246563962"

local NUKE_ACTIONS = {
	[20] = "kicks", [21] = "member prunes", [22] = "bans",
	[10] = "channel creations", [12] = "channel deletions",
	[32] = "role deletions", [50] = "webhook creations", [62] = "emoji deletions",
	[92] = "sticker deletions",
}

local function now() return os.time() end
local function mention(id) return id and ("<@" .. tostring(id) .. ">") or "Unknown" end

---------------------------------------------------------------- settings
local function getSec(guild)
	local config = sqldb:get(guild.id) or {}
	return S.withDefaults(config.security)
end

local function saveSec(guild, sec, reason)
	return sqldb:set(guild.id, { security = sec }, reason or "SECURITY_UPDATE")
end

local function isExempt(guild, userId, sec, member)
	userId = tostring(userId or "")
	if userId == "" then return true end
	if Client.user and userId == Client.user.id then return true end
	if S.isProtectedId(userId, sec.whitelist.users) then return true end
	if guild.ownerId == userId then return true end
	if _G.isBotOwner and isBotOwner({ id = userId }) then return true end
	member = member or guild:getMember(userId)
	if member and member.roles then
		for role in member.roles:iter() do
			for _, r in ipairs(sec.whitelist.roles) do
				if tostring(r) == role.id then return true end
			end
		end
	end
	return false
end

---------------------------------------------------------------- alerts
-- Zeltra: serious events (raids, anti-nuke, lockdowns, bot adds) go to the private #security-alerts channel;
-- routine flags stay in the normal security log channel.
local SECURITY_ALERTS = "1559377112471965788"
local function alertChannel(guild, sec)
	return guild:getChannel(sec.alertchannel or SECURITY_ALERTS) or (sec.logchannel and guild:getChannel(sec.logchannel)) or guild:getChannel(SECURITY_LOGS)
end
_G.securityAlertChannel = alertChannel

local function alert(guild, sec, opts)
	if not sec.enabled then return end
	local serious = opts.serious; opts.serious = nil
	local channel = serious and alertChannel(guild, sec) or (sec.logchannel and guild:getChannel(sec.logchannel))
	if not channel then return end
	opts.guild = guild
	opts.footer = "Security"
	return dmStyle.post(channel, opts)
end

---------------------------------------------------------------- raid mode
local function publicTextChannels(guild)
	local out = {}
	local everyone = guild.defaultRole
	local baseView = everyone:getPermissions():has("viewChannel")
	local baseSend = everyone:getPermissions():has("sendMessages")
	for channel in guild.textChannels:iter() do
		local ow = channel:getPermissionOverwriteFor(everyone)
		local allowed, denied = ow:getAllowedPermissions(), ow:getDeniedPermissions()
		local canView = (baseView and not denied:has("viewChannel")) or allowed:has("viewChannel")
		local canSend = (baseSend and not denied:has("sendMessages")) or allowed:has("sendMessages")
		if canView and canSend then
			table.insert(out, { channel = channel, overwrite = ow, prev = (allowed:has("sendMessages") and "allow") or "neutral" })
		end
	end
	return out
end

--- Start raid mode. opts = { minutes, lockChannels, reason, by (user id or nil for automatic) }
local function startRaid(guild, opts)
	local sec = getSec(guild)
	if sec.raid and sec.raid.active then
		return false, "Raid mode is already on (ends <t:" .. tostring(sec.raid.ends) .. ":R>)."
	end

	local minutes = math.max(1, math.min(tonumber(opts.minutes) or sec.antiraid.raidminutes, 1440))
	local state = {
		active = true, started = now(), ends = now() + minutes * 60,
		by = opts.by, reason = opts.reason, locked = {}, timedout = {}, joins = 0,
	}
	local results = {}

	if sec.antiraid.raiseverification and (guild.verificationLevel or 0) < 3 then
		local prev = guild.verificationLevel or 0
		if guild:setVerificationLevel(3) then
			state.prevVerification = prev
			table.insert(results, "verification raised to High")
		else
			table.insert(results, "could not raise verification")
		end
	end

	local lock = opts.lockChannels
	if lock == nil then lock = sec.antiraid.lockchannels end
	if lock then
		local count = 0
		for _, item in ipairs(publicTextChannels(guild)) do
			if item.overwrite:denyPermissions(discordia.enums.permission.sendMessages) then
				table.insert(state.locked, { id = item.channel.id, prev = item.prev })
				count = count + 1
			end
		end
		table.insert(results, count .. " public channel(s) locked")
	end

	sec.raid = state
	saveSec(guild, sec, "SECURITY_RAID_START")
	pcall(timer.setTimeout, 1500, coroutine.wrap(function() local ch = alertChannel(guild, sec); if ch and late.sendPings then late.sendPings(guild, ch, sec.keywords, "🚨 Raid detected, check the alert above.") end end))

	alert(guild, sec, { serious = true,
		icon = "🚨",
		title = (opts.by and "Lockdown started") or "Raid detected",
		intro = (opts.by and (mention(opts.by) .. " put **" .. dmStyle.serverName(guild) .. "** into lockdown."))
			or ("Joins spiked in **" .. dmStyle.serverName(guild) .. "**, so raid mode was turned on automatically."),
		fields = {
			{ "Reason", opts.reason },
			{ "Joiners", (sec.antiraid.raidaction == "kick" and "Kicked") or (sec.antiraid.raidaction == "timeout" and "Timed out until it ends") or "No action" },
			{ "Actions", (#results > 0 and table.concat(results, ", ")) or "None" },
			{ "Ends", dmStyle.time(state.ends) .. " (" .. dmStyle.time(state.ends, "R") .. ")" },
		},
		note = "Use `/security unlock` to end it early.",
	})
	return true, state, results
end

local function endRaid(guild, by)
	local sec = getSec(guild)
	local state = sec.raid
	if not state or not state.active then
		return false, "Raid mode is not on."
	end
	local results = {}

	if state.prevVerification then
		if guild:setVerificationLevel(state.prevVerification) then
			table.insert(results, "verification restored")
		else
			table.insert(results, "could not restore verification")
		end
	end

	local unlocked = 0
	for _, item in ipairs(state.locked or {}) do
		local channel = guild:getChannel(item.id)
		if channel then
			local ow = channel:getPermissionOverwriteFor(guild.defaultRole)
			local ok
			if item.prev == "allow" then
				ok = ow:allowPermissions(discordia.enums.permission.sendMessages)
			else
				ok = ow:clearPermissions(discordia.enums.permission.sendMessages)
			end
			if ok then unlocked = unlocked + 1 end
		end
	end
	if #(state.locked or {}) > 0 then table.insert(results, unlocked .. " channel(s) unlocked") end

	local released = 0
	for _, id in ipairs(state.timedout or {}) do
		local member = guild:getMember(id)
		if member and member:removeTimeout() then released = released + 1 end
	end
	if #(state.timedout or {}) > 0 then table.insert(results, released .. " timeout(s) lifted") end

	sec.raid = { active = false, lastStarted = state.started, lastEnded = now() }
	saveSec(guild, sec, "SECURITY_RAID_END")

	alert(guild, sec, { serious = true,
		icon = "🔓",
		title = "Raid mode ended",
		intro = (by and (mention(by) .. " ended raid mode.")) or "Raid mode ended automatically.",
		fields = {
			{ "Lasted", "`" .. dmStyle.duration(now() - (state.started or now())) .. "`" },
			{ "Joins during raid", tostring(state.joins or 0) },
			{ "Actions", (#results > 0 and table.concat(results, ", ")) or "None" },
		},
	})
	return true, results
end

---------------------------------------------------------------- handlers
local function onJoin(member)
	local guild = member.guild
	if not guild or member.user.bot then return end
	local sec = getSec(guild)
	if not sec.enabled or not sec.antiraid.enabled then return end
	local t = now()

	-- already in raid mode: act on the joiner
	if sec.raid and sec.raid.active then
		sec.raid.joins = (sec.raid.joins or 0) + 1
		if not isExempt(guild, member.id, sec, member) then
			if sec.antiraid.raidaction == "timeout" then
				local secs = math.min(math.max(300, (sec.raid.ends or t) - t), 2419200)
				if member:timeoutFor(secs) then table.insert(sec.raid.timedout, member.id) end
			elseif sec.antiraid.raidaction == "kick" then
				member:kick("Security: joined during raid mode")
			end
		end
		saveSec(guild, sec, "SECURITY_RAID_JOIN")
		return
	end

	-- join rate
	local count = joinWindow:hit(guild.id, t, sec.antiraid.window)
	if count >= sec.antiraid.joins then
		joinWindow:reset(guild.id)
		if sec.antiraid.autoraid then
			startRaid(guild, { reason = count .. " joins in " .. sec.antiraid.window .. "s" })
		elseif cooldown("raidalert:" .. guild.id, t, 120) then
			alert(guild, sec, { serious = true,
				icon = "🚨", title = "Possible raid",
				intro = "Joins spiked in **" .. dmStyle.serverName(guild) .. "**. Raid mode is set to manual.",
				fields = { { "Joins", count .. " in " .. sec.antiraid.window .. "s" } },
				note = "Use `/security lockdown` to turn on raid mode.",
			})
		end
		return
	end

	-- suspicious accounts
	local age = S.accountAgeDays(member.user.createdAt, t)
	local reasons = {}
	if sec.antiraid.flagnew and age and age < sec.antiraid.accountage then
		table.insert(reasons, "account is " .. dmStyle.duration(age * 86400) .. " old")
		if sec.antiraid.heuristics and not member.user.avatar then table.insert(reasons, "default avatar") end
	end
	if sec.antiraid.heuristics then
		local why = S.suspiciousName(member.user.username) or S.suspiciousName(member.user.globalName)
		if why then table.insert(reasons, why) end
	end
	if #reasons > 0 then
		alert(guild, sec, {
			icon = "👤", title = "Flagged account joined",
			intro = member.user.mentionString .. " joined and looks unusual.",
			fields = {
				{ "User", member.user.mentionString .. " (`" .. member.id .. "`)" },
				{ "Created", dmStyle.time(member.user.createdAt) },
				{ "Flags", table.concat(reasons, ", ") },
			},
		})
	end
end

local function stripDangerousRoles(guild, member)
	local me = guild.me
	local top = me and me.highestRole and me.highestRole.position or 0
	local removed, skipped = {}, {}
	for role in member.roles:iter() do
		local perms = tostring(role._permissions_new or role._permissions or "0")
		if #S.dangerousIn(perms) > 0 then
			if role.managed or role.position >= top then
				table.insert(skipped, role.name)
			elseif member:removeRole(role.id, "Security: unusual activity") then
				table.insert(removed, role.name)
			else
				table.insert(skipped, role.name)
			end
		end
	end
	return removed, skipped
end

-- Zeltra: role/channel deletions are punished on the FIRST one, for everyone (any rank).
-- Only the bot owners (S.PROTECTED_USERS) and the bot itself are skipped. Mass deletions lock the server.
local DELETE_ACTIONS = { [12] = "channel", [32] = "role" }
local MASS_DELETES = 3
local deleteHandled = {}

local function onDeleteNuke(guild, sec, entry)
	local t = now()
	local executor = tostring(entry.user_id or "")
	local kind = DELETE_ACTIONS[entry.action_type]
	local count = deleteWindow:hit(guild.id .. ":" .. executor, t, 120)
	local member = guild:getMember(executor)
	local exempt = executor == "" or (Client.user and executor == Client.user.id) or S.isProtectedId(executor)
	local status = { removed = {}, skipped = {}, timeout = "Skipped", lockdown = "Not needed" }
	local first = not deleteHandled[guild.id .. ":" .. executor] or (t - deleteHandled[guild.id .. ":" .. executor]) > 300

	if exempt then
		status.timeout = "Skipped: bot owner"
	elseif member and first then
		deleteHandled[guild.id .. ":" .. executor] = t
		local roles, saved = {}, {}
		for role in member.roles:iter() do
			table.insert(roles, { id = role.id, name = role.name, position = role.position, managed = role.managed })
			if role.id ~= guild.id then table.insert(saved, role.id) end
		end
		local cur = getSec(guild)
		cur.botguard.cases[executor] = { roles = saved, at = t, reason = "deleted a " .. tostring(kind) }
		saveSec(guild, cur, "SECURITY_ANTINUKE")
		local me = guild.me
		local top = me and me.highestRole and me.highestRole.position or 0
		local strip, skipped = S.splitRoles(roles, top, guild.id)
		for _, r in ipairs(strip) do
			if member:removeRole(r.id, "Anti-nuke: deleted a " .. tostring(kind)) then table.insert(status.removed, r.name)
			else table.insert(status.skipped, r.name .. " (Discord refused)") end
		end
		for _, r in ipairs(skipped) do table.insert(status.skipped, r.name .. " (" .. r.why .. ")") end
		if member.user and member.user.bot then
			local okK = member:kick("Anti-nuke: bot deleted a " .. tostring(kind))
			status.timeout = okK and "Bot kicked" or "Couldn't kick the bot"
		elseif guild.ownerId == executor then
			status.timeout = "Skipped: Discord can't time out the server owner"
		else
			local okT = member:timeoutFor(7 * 86400)
			status.timeout = okT and ("7 days, ends " .. dmStyle.time(t + 7 * 86400, "R")) or "Discord refused the timeout"
		end
	elseif member then
		status.timeout = "Already handled " .. dmStyle.time(deleteHandled[guild.id .. ":" .. executor], "R")
	else
		status.timeout = "Skipped: not in the server"
	end

	if not exempt and count >= MASS_DELETES and late.fullLockdown and not (sec.lockdown and sec.lockdown.active) then
		local res, err = late.fullLockdown(guild, { by = executor, reason = "Mass " .. tostring(kind) .. " deletion", trigger = { user = executor, text = count .. " deletions" } })
		status.lockdown = res and ("On · " .. res.changed .. " overwrites changed in " .. res.channels .. " channels") or ("Failed: " .. tostring(err))
	elseif sec.lockdown and sec.lockdown.active then
		status.lockdown = "Already on"
	end

	local deletedName
	for _, c in ipairs(entry.changes or {}) do if c.key == "name" then deletedName = c.old_value end end
	local channel = alertChannel(guild, sec)
	if not channel then print("[security] anti-nuke: no security log channel"); return end
	dmStyle.post(channel, {
		guild = guild, icon = "🚨", title = "Anti-nuke: " .. tostring(kind) .. " deleted",
		intro = mention(executor) .. " deleted a " .. tostring(kind) .. " in **" .. dmStyle.serverName(guild) .. "**.",
		fields = {
			{ "Member", mention(executor) .. " (`" .. executor .. "`)" },
			{ "Deleted " .. tostring(kind), (deletedName and ("**" .. tostring(deletedName) .. "**") or "Unknown") .. " (`" .. tostring(entry.target_id) .. "`)" },
			{ "Deletions (2 min)", tostring(count) },
			{ "Roles removed", (#status.removed > 0) and table.concat(status.removed, ", ") or "None" },
			{ "Couldn't remove", (#status.skipped > 0) and table.concat(status.skipped, ", ") or nil },
			{ "Timeout", status.timeout },
			{ "Lockdown", status.lockdown },
			{ "Reason given", entry.reason },
			{ "Time", dmStyle.time(t) },
		},
		note = "Found through the audit log. Restore roles: bot owners only.",
		buttons = (not exempt) and {
			{ label = "Restore roles", custom_id = "sec:botrestore:" .. executor, style = 3, emoji = "↩️" },
			{ label = "Remove timeout", custom_id = "sec:untimeout:" .. executor, style = 2, emoji = "⏱️" },
		} or nil,
		footer = "Security",
	})
	if not exempt and late.sendPings then late.sendPings(guild, channel, sec.keywords, "Anti-nuke triggered, check the report above.") end
end

local function onNuke(guild, sec, entry, label)
	local t = now()
	local executor = entry.user_id
	local key = tostring(executor) .. ":" .. tostring(entry.action_type)
	local count = nukeWindow:hit(guild.id .. ":" .. key, t, sec.antinuke.window)
	if count < sec.antinuke.count then return end
	if not cooldown("nuke:" .. guild.id .. ":" .. key, t, sec.antinuke.window) then return end

	local member = guild:getMember(executor)
	local exempt = isExempt(guild, executor, sec, member)
	local action = "Alert only (whitelisted or owner)"
	if not exempt and sec.antinuke.strip and member then
		local removed, skipped = stripDangerousRoles(guild, member)
		action = ((#removed > 0) and ("Removed " .. table.concat(removed, ", ")) or "No roles removed")
			.. ((#skipped > 0) and (". Could not remove " .. table.concat(skipped, ", ") .. " (above the bot or managed)") or "")
	elseif not exempt then
		action = "Alert only (role removal is off)"
	end

	local activityCard = {
		icon = "⚠️", title = "Unusual staff activity",
		intro = mention(executor) .. " made " .. count .. " " .. label .. " in under " .. sec.antinuke.window .. "s.",
		fields = {
			{ "Staff Member", mention(executor) .. " (`" .. tostring(executor) .. "`)" },
			{ "Activity", count .. " " .. label },
			{ "Action", action },
			{ "Latest reason", entry.reason },
		},
		note = (member and member.user and member.user.bot) and "This is a bot. Its own role can't be removed, so consider kicking it." or nil,
	}
	activityCard.serious = true; alert(guild, sec, activityCard)
	-- Zeltra: a copy goes to the activity alerts channel too (security.activitychannel), if one is set
	if sec.enabled and sec.activitychannel and sec.activitychannel ~= sec.logchannel then
		local ch = guild:getChannel(sec.activitychannel)
		if ch then
			local copy = {}
			for k, v in pairs(activityCard) do copy[k] = v end
			copy.guild = guild; copy.footer = "Activity Alerts"
			dmStyle.post(ch, copy)
		end
	end
end

local function permissionChange(entry, key)
	for _, c in ipairs(entry.changes or {}) do
		if c.key == key then return c end
	end
end

local function onFlaggedAudit(guild, sec, entry)
	local at = entry.action_type
	local executor = entry.user_id
	if Client.user and tostring(executor) == Client.user.id then return end
	local exempt = isExempt(guild, executor, sec)

	if at == 30 or at == 31 then -- role create / update
		local c = permissionChange(entry, "permissions")
		if not c then return end
		local added = S.addedDangerous(c.old_value or "0", c.new_value or "0")
		if #added == 0 then return end
		local reverted = "No (revert is off)"
		if exempt then
			reverted = "No (whitelisted or owner)"
		elseif sec.flagged.revertperms then
			local target = (at == 31 and c.old_value) or S.withoutDangerous(c.new_value)
			local ok = Client._api:modifyGuildRole(guild.id, entry.target_id, { permissions = tostring(target) })
			reverted = (ok and "Yes") or "Tried, but it failed"
		end
		alert(guild, sec, {
			icon = "🚩", title = "Dangerous permissions granted",
			intro = mention(executor) .. " gave a role powerful permissions.",
			fields = {
				{ "Role", "<@&" .. tostring(entry.target_id) .. ">" },
				{ "Added", table.concat(added, ", ") },
				{ "By", mention(executor) },
				{ "Reverted", reverted },
			},
		})
	elseif at == 25 then -- member role update
		local c = permissionChange(entry, "$add")
		if not c or type(c.new_value) ~= "table" then return end
		for _, r in ipairs(c.new_value) do
			local role = guild:getRole(r.id)
			local perms = role and tostring(role._permissions_new or role._permissions or "0") or "0"
			local danger = S.severeIn(perms)
			if #danger > 0 then
				local reverted = "No (revert is off)"
				if exempt then
					reverted = "No (whitelisted or owner)"
				elseif sec.flagged.revertperms then
					local target = guild:getMember(entry.target_id)
					reverted = (target and target:removeRole(r.id, "Security: dangerous role given") and "Yes, role removed") or "Tried, but it failed"
				end
				alert(guild, sec, {
					icon = "🚩", title = "Powerful role given",
					intro = mention(executor) .. " gave " .. mention(entry.target_id) .. " a role with powerful permissions.",
					fields = {
						{ "Member", mention(entry.target_id) },
						{ "Role", "<@&" .. tostring(r.id) .. ">" },
						{ "Permissions", table.concat(danger, ", ") },
						{ "By", mention(executor) },
						{ "Reverted", reverted },
					},
				})
			end
		end
	elseif at == 28 and not sec.botguard.enabled then -- bot added (the bot guard posts its own card when it's on)
		alert(guild, sec, { serious = true,
			icon = "🤖", title = "Bot added",
			intro = mention(executor) .. " added a bot to **" .. dmStyle.serverName(guild) .. "**.",
			fields = { { "Bot", mention(entry.target_id) .. " (`" .. tostring(entry.target_id) .. "`)" }, { "By", mention(executor) } },
			note = (exempt and "Added by a whitelisted user or an owner.") or "Make sure this bot was expected.",
		})
	elseif at == 1 then -- server settings
		local lines = {}
		for _, c in ipairs(entry.changes or {}) do
			if type(c.new_value) ~= "table" and type(c.old_value) ~= "table" then
				table.insert(lines, { (c.key == "vanity_url_code" and "Vanity URL") or tostring(c.key), tostring(c.old_value or "none") .. " → " .. tostring(c.new_value or "none") })
			end
		end
		if #lines == 0 then return end
		table.insert(lines, 1, { "By", mention(executor) })
		alert(guild, sec, {
			icon = "🛠️", title = "Server settings changed",
			intro = mention(executor) .. " changed the server settings.",
			fields = lines,
		})
	end
end

local function onAudit(entry)
	local guild = entry and entry.guild_id and Client:getGuild(entry.guild_id)
	if not guild then return end
	local sec = getSec(guild)
	if not sec.enabled then return end

	local label = NUKE_ACTIONS[entry.action_type]
	if DELETE_ACTIONS[entry.action_type] and not (Client.user and tostring(entry.user_id) == Client.user.id) then
		local okD, errD = pcall(onDeleteNuke, guild, sec, entry)
		if not okD then print("[security] anti-nuke failed: " .. tostring(errD)) end
	end
	if label and sec.antinuke.enabled and not (Client.user and tostring(entry.user_id) == Client.user.id) then
		onNuke(guild, sec, entry, label)
	end
	if sec.flagged.enabled then
		onFlaggedAudit(guild, sec, entry)
	end
end

---------------------------------------------------------------- full lockdown (raid/nuke keywords)
local LOCK_TYPES = { [0] = true, [5] = true, [2] = true, [13] = true, [15] = true, [16] = true }
local keywordCooldown = S.newCooldown()
local lockdownRunning = {}

local function isOwnerId(id)
	return S.isProtectedId(id)
end

local function saveLockdown(guild, ld)
	local cur = getSec(guild)
	cur.lockdown = ld
	return saveSec(guild, cur, "SECURITY_LOCKDOWN")
end

local function rolePerms(guild, id)
	local role = guild:getRole(id)
	return role and tostring(role._permissions_new or role._permissions or "0") or "0"
end

--- Deny Send Messages / Send in Threads / Add Reactions / Create Public Threads for @everyone and for every
--- non-admin role with an explicit allow, in every text, announcement, voice, stage, forum and media channel.
--- The exact previous overwrite is saved first so endLockdown can put it back.
local function fullLockdown(guild, info)
	if lockdownRunning[guild.id] then return nil, "a lockdown is already being applied" end
	lockdownRunning[guild.id] = true
	local ok, res = pcall(function()
		local sec = getSec(guild)
		local ld = sec.lockdown
		if not ld or not ld.active then
			ld = { active = true, started = now(), by = info.by, reason = info.reason, trigger = info.trigger, entries = {} }
		end
		ld.entries = ld.entries or {}
		local done = {}
		for _, e in ipairs(ld.entries) do done[e.c .. ":" .. e.id] = true end
		saveLockdown(guild, ld)

		local channels, err = Client._api:getGuildChannels(guild.id)
		if not channels then error("could not list channels: " .. tostring(err)) end
		local result = { channels = 0, changed = 0, failed = 0, skipped = 0 }
		local sinceSave = 0
		for _, ch in ipairs(channels) do
			if LOCK_TYPES[ch.type] then
				local touched = false
				local targets = {}
				local existing = {}
				for _, ow in ipairs(ch.permission_overwrites or {}) do existing[ow.id] = ow end
				table.insert(targets, guild.id)
				for _, ow in ipairs(ch.permission_overwrites or {}) do
					if ow.type == 0 and ow.id ~= guild.id and S.allowsAnyLockBit(ow.allow) and not S.hasBit(rolePerms(guild, ow.id), 3) then
						table.insert(targets, ow.id)
					end
				end
				for _, id in ipairs(targets) do
					local key = ch.id .. ":" .. id
					local prev = existing[id]
					if done[key] then
						result.skipped = result.skipped + 1
					elseif prev and S.isLocked(prev.deny) and not S.allowsAnyLockBit(prev.allow) then
						result.skipped = result.skipped + 1 -- already locked by someone else, leave it alone
					else
						local allow, deny = S.lockOverwrite(prev and prev.allow or "0", prev and prev.deny or "0")
						local entry = { c = ch.id, id = id, t = 0, e = prev ~= nil, a = prev and tostring(prev.allow) or "0", d = prev and tostring(prev.deny) or "0" }
						table.insert(ld.entries, entry)
						done[key] = true
						local okEdit = Client._api:editChannelPermissions(ch.id, id, { allow = allow, deny = deny, type = 0 })
						if okEdit then
							result.changed = result.changed + 1
							touched = true
							sinceSave = sinceSave + 1
							if sinceSave >= 20 then saveLockdown(guild, ld) sinceSave = 0 end
						else
							table.remove(ld.entries) -- nothing changed, nothing to restore
							done[key] = nil
							result.failed = result.failed + 1
						end
					end
				end
				if touched then result.channels = result.channels + 1 end
			end
		end
		saveLockdown(guild, ld)
		result.total = #ld.entries
		return result
	end)
	lockdownRunning[guild.id] = nil
	if not ok then return nil, res end
	return res
end

local function endLockdown(guild)
	local sec = getSec(guild)
	local ld = sec.lockdown
	if not ld or not ld.active then return false, "There's no keyword lockdown in place." end
	local restored, failed = 0, 0
	local entries = ld.entries or {}
	for i = #entries, 1, -1 do
		local e = entries[i]
		local ok
		if e.e then
			ok = Client._api:editChannelPermissions(e.c, e.id, { allow = e.a, deny = e.d, type = e.t or 0 })
		else
			ok = Client._api:deleteChannelPermission(e.c, e.id)
		end
		if ok then restored = restored + 1 else failed = failed + 1 end
	end
	saveLockdown(guild, { active = false, lastStarted = ld.started, lastEnded = now() })
	return true, { restored = restored, failed = failed }
end

---------------------------------------------------------------- raid keywords
local function timeoutBlocker(guild, member)
	if not member then return "they're not in the server" end
	if guild.ownerId == member.id then return "Discord can't time out the server owner" end
	if member:hasPermission("administrator") then return "Discord can't time out members with Administrator" end
	local me = guild.me
	local top = me and me.highestRole and me.highestRole.position or 0
	if member.highestRole and member.highestRole.position >= top then return "their role is above the bot's" end
	return nil
end

local function keywordCard(guild, message, match, status)
	local content = tostring(message.content or "")
	if #content > 900 then content = content:sub(1, 900) .. "..." end
	return {
		guild = guild, icon = "🚨", title = "Raid command detected",
		intro = message.author.mentionString .. " sent a message that looks like a raid or nuke command.",
		fields = {
			{ "User", message.author.mentionString .. " · @" .. tostring(message.author.username) .. " (`" .. message.author.id .. "`)" },
			{ "Channel", message.channel.mentionString },
			{ "Matched", "`" .. match.text:gsub("`", "") .. "` (" .. match.kind .. ")" },
			{ "Lockdown", status.lockdown },
			{ "Timeout", status.timeout },
			{ "DM", status.dm },
			{ "Message", status.deleted },
		},
		sections = { { title = "Message content", body = (content ~= "" and content) or "(no text)" } },
		note = "Remove timeout: staff with Timeout Members. Unlock server: bot owners only.",
		buttons = {
			{ label = "Jump to message", url = message.link },
			{ label = "Remove timeout", custom_id = "sec:untimeout:" .. message.author.id, style = 2, emoji = "⏱️" },
			{ label = "Unlock server", custom_id = "sec:unlock", style = 4, emoji = "🔓" },
		},
		footer = "Security",
	}
end

--- Users and roles to ping (default: the bot owners and the ownership roles). Deleted roles are skipped.
local function pingTargets(guild, kw)
	local users, roles, seen = {}, {}, {}
	for _, id in ipairs(kw.pingusers or {}) do
		if not seen[id] then seen[id] = true table.insert(users, tostring(id)) end
	end
	for _, id in ipairs(kw.pingroles or {}) do
		if not seen[id] and guild:getRole(id) then seen[id] = true table.insert(roles, tostring(id)) end
	end
	return users, roles
end

local function sendPings(guild, channel, kw, text)
	local users, roles = pingTargets(guild, kw)
	if #users == 0 and #roles == 0 then return 0 end
	local parts = {}
	for _, id in ipairs(users) do table.insert(parts, "<@" .. id .. ">") end
	for _, id in ipairs(roles) do table.insert(parts, "<@&" .. id .. ">") end
	local sent = 0
	for i = 1, 3 do
		local ok, msg = pcall(function()
			return channel:send({
				content = (text or "🚨 Raid command detected, check the alert above.") .. " " .. table.concat(parts, " "),
				allowed_mentions = { parse = {}, users = users, roles = roles },
			})
		end)
		if ok and msg then sent = sent + 1 end
	end
	return sent
end

local function onKeyword(message, sec, match)
	local guild, author = message.guild, message.author
	local member = message.member or guild:getMember(author.id)
	local t = now()
	local kw = sec.keywords
	local channel = alertChannel(guild, sec)
	print("[security] raid keyword from " .. author.id .. " in " .. message.channel.id .. ": " .. match.kind .. " " .. match.text)

	-- first match in the cooldown window: lock (if enabled) and ping; later matches only alert
	local first = keywordCooldown("kwlock:" .. guild.id, t, kw.cooldown or 60)
	local willLock = kw.lock and first
	local status = {
		lockdown = (not kw.lock and "Off (Lock on keyword is disabled)") or (willLock and "Starting...")
			or "Already triggered in the last " .. (kw.cooldown or 60) .. "s, not locking again",
		timeout = "Pending", dm = "Pending", deleted = "Pending",
	}

	local posted = channel and dmStyle.post(channel, keywordCard(guild, message, match, status))
	if not channel then print("[security] no security log channel set, keyword alert not posted") end
	if channel and first then sendPings(guild, channel, kw) end

	-- delete the message first so it stops being visible
	local okDel = pcall(function() return message:delete() end)
	status.deleted = okDel and "Deleted" or "Couldn't delete it"

	-- DM, then time out
	local minutes = tonumber(kw.timeoutminutes) or 0
	local blocker = (minutes > 0) and timeoutBlocker(guild, member) or nil
	local sent = dmStyle.send(member or author, {
		guild = guild, icon = "🛡️", title = "You're suspected of raiding",
		intro = "Please be patient while we review the report.",
		fields = {
			{ "Channel", message.channel.mentionString },
			{ "Timeout", (minutes > 0 and not blocker) and (minutes .. " minutes") or nil },
		},
		footer = "Security",
	})
	status.dm = sent and "Sent" or "Couldn't DM them"
	if minutes <= 0 then
		status.timeout = "Off"
	elseif blocker then
		status.timeout = "Skipped: " .. blocker
	else
		local okT = member and member:timeoutFor(math.min(minutes, 40320) * 60)
		status.timeout = okT and (minutes .. " minutes, ends " .. dmStyle.time(t + minutes * 60, "R")) or "Discord refused the timeout"
	end

	if willLock then
		local res, err = fullLockdown(guild, {
			by = author.id, reason = "Raid keyword: " .. match.text,
			trigger = { user = author.id, channel = message.channel.id, text = match.text },
		})
		if res then
			status.lockdown = "On · " .. res.changed .. " overwrites changed in " .. res.channels .. " channels"
				.. ((res.failed > 0) and (" · " .. res.failed .. " failed") or "")
				.. ((res.skipped > 0) and (" · " .. res.skipped .. " already locked") or "")
		else
			status.lockdown = "Failed: " .. tostring(err)
			print("[security] lockdown failed: " .. tostring(err))
		end
	end

	if posted then
		local ok = Client._api:editMessage(channel.id, posted.id, dmStyle.build(keywordCard(guild, message, match, status)))
		if not ok then dmStyle.post(channel, keywordCard(guild, message, match, status)) end
	end
end

---------------------------------------------------------------- bot guard (anyone adding a bot)
local function snowflakeTime(id)
	local n = tonumber(id)
	return n and (math.floor(n / 4194304) / 1000 + 1420070400) or now()
end

local function findBotAdder(guild, botId)
	for attempt = 1, 4 do
		local data = Client._api:getGuildAuditLog(guild.id, { action_type = 28, limit = 10 })
		local entries = {}
		for _, e in ipairs((data and data.audit_log_entries) or {}) do
			table.insert(entries, { target_id = e.target_id, user_id = e.user_id, action_type = e.action_type, created = snowflakeTime(e.id) })
		end
		local adder = S.findBotAdder(entries, botId, now(), 120)
		if adder then return adder end
		timer.sleep(1500)
	end
	return nil
end

--- What we can learn about a bot before it's kicked (public application info, flags, its role's permissions).
local function botInfo(guild, member)
	local out = { id = member.id, name = member.user.username }
	local okA, app = pcall(function() return Client._api:request("GET", "/applications/" .. member.id .. "/rpc") end)
	app = okA and type(app) == "table" and app or {}
	out.description = (type(app.description) == "string" and app.description ~= "") and app.description or nil
	out.tags = type(app.tags) == "table" and app.tags or nil
	out.terms = app.terms_of_service_url
	out.privacy = app.privacy_policy_url
	out.guilds = app.approximate_guild_count
	local flags = tonumber(member.user._public_flags or member.user.publicFlags or 0) or 0
	out.verified = math.floor(flags / 65536) % 2 == 1
	out.created = snowflakeTime(member.id)
	local perms = "0"
	for role in member.roles:iter() do
		if role.managed then perms = tostring(role._permissions_new or role._permissions or "0") end
	end
	out.perms = perms
	out.keyPerms = S.botKeyPerms(perms)
	out.risk, out.reasons = S.botRisk({ verified = out.verified, ageDays = (now() - out.created) / 86400,
		perms = perms, description = out.description, name = out.name })
	return out
end

local function botInfoFields(b)
	local desc = b.description and b.description:gsub("\n", " ") or "No description"
	if #desc > 300 then desc = desc:sub(1, 297) .. "..." end
	return {
		{ "Name", "@" .. tostring(b.name) },
		{ "ID", "`" .. tostring(b.id) .. "`" },
		{ "What it does", desc },
		{ "Discord verified", b.verified and "Yes" or "No" },
		{ "Account created", dmStyle.time(math.floor(b.created), "D") .. " (" .. dmStyle.time(math.floor(b.created), "R") .. ")" },
		{ "In about", b.guilds and (tostring(b.guilds) .. " servers") or nil },
		{ "Tags", b.tags and #b.tags > 0 and table.concat(b.tags, ", ") or nil },
		{ "Key permissions", (#b.keyPerms > 0) and table.concat(b.keyPerms, ", ") or "None of the risky ones" },
		{ "Links", ((b.terms and ("[Terms](" .. b.terms .. ")")) or "") .. ((b.terms and b.privacy) and " · " or "") .. ((b.privacy and ("[Privacy](" .. b.privacy .. ")")) or "") },
		{ "Risk", b.risk .. ": " .. table.concat(b.reasons, ", ") .. ". This is a rough guide, not a verdict." },
	}
end

local function botGuardCard(guild, info, status)
	local removed = (#status.removed > 0) and table.concat(status.removed, ", ") or "None"
	local skipped = (#status.skipped > 0) and table.concat(status.skipped, ", ") or nil
	return {
		guild = guild, icon = "🤖", title = "Unauthorized bot added",
		intro = (info.adder and mention(info.adder) or "Someone") .. " added a bot to **" .. dmStyle.serverName(guild) .. "** without permission.",
		fields = {
			{ "Added by", info.adder and (mention(info.adder) .. " (`" .. info.adder .. "`)") or "Couldn't find it in the audit log" },
			{ "Bot", "@" .. tostring(info.botName) .. " (`" .. info.botId .. "`)" },
			{ "Bot kicked", status.kick },
			{ "Roles removed", removed },
			{ "Couldn't remove", skipped },
			{ "Timeout", status.timeout },
			{ "DM", status.dm },
		},
		sections = info.bot and { { title = "About the bot", body = (function()
			local lines = {}
			for _, f in ipairs(botInfoFields(info.bot)) do
				if f[2] and f[2] ~= "" then table.insert(lines, "**" .. f[1] .. "** · " .. f[2]) end
			end
			return table.concat(lines, "\n")
		end)() } } or nil,
		note = "Restore roles: bot owners only. Remove timeout: staff with Timeout Members.",
		buttons = info.adder and {
			{ label = "Restore roles", custom_id = "sec:botrestore:" .. info.adder, style = 3, emoji = "↩️" },
			{ label = "Remove timeout", custom_id = "sec:untimeout:" .. info.adder, style = 2, emoji = "⏱️" },
		} or nil,
		footer = "Security",
	}
end

local function onBotJoin(member)
	local guild = member.guild
	if not guild or not member.user or not member.user.bot then return end
	if Client.user and member.id == Client.user.id then return end
	local sec = getSec(guild)
	if not sec.enabled or not sec.botguard.enabled then return end
	local channel = alertChannel(guild, sec)
	local t = now()
	local adder = findBotAdder(guild, member.id)
	local okB, bot = pcall(botInfo, guild, member)
	if not okB then print("[security] bot info failed: " .. tostring(bot)); bot = nil end
	local info = { botId = member.id, botName = member.user.username, adder = adder, bot = bot }

	-- allowed: added by a bot owner, or allowed for a short time with /security allowbot
	local allowedBy = (adder and S.isProtectedId(adder)) and "Added by a bot owner"
		or (S.botAllowed(sec.botguard.allow, member.id, t) and "Allowed with /security allowbot")
	if allowedBy then
		if sec.botguard.allow[member.id] then sec.botguard.allow[member.id] = nil; saveSec(guild, sec, "SECURITY_BOT_ALLOWED") end
		print("[security] bot " .. member.id .. " added by " .. tostring(adder) .. ": " .. allowedBy)
		alert(guild, sec, { serious = true,
			icon = "🤖", title = "Bot added",
			intro = mention(adder) .. " added a bot to **" .. dmStyle.serverName(guild) .. "**.",
			fields = (function()
				local f = { { "By", mention(adder) } }
				for _, x in ipairs(bot and botInfoFields(bot) or { { "Bot", "@" .. tostring(member.user.username) .. " (`" .. member.id .. "`)" } }) do table.insert(f, x) end
				return f
			end)(),
			note = allowedBy .. ", nothing was done.",
		})
		return
	end

	print("[security] unauthorized bot " .. member.id .. " added by " .. tostring(adder))
	local status = { kick = "Pending", removed = {}, skipped = {}, timeout = "Pending", dm = "Pending" }

	local okK = member:kick("Security: bots can't be added to this server")
	status.kick = okK and "Kicked" or "Couldn't kick it"

	local target = adder and guild:getMember(adder)
	if target then
		-- save the roles first so they can be restored
		local roles = {}
		for role in target.roles:iter() do
			table.insert(roles, { id = role.id, name = role.name, position = role.position, managed = role.managed })
		end
		local saved = {}
		for _, r in ipairs(roles) do if r.id ~= guild.id then table.insert(saved, r.id) end end
		sec.botguard.cases[adder] = { roles = saved, bot = member.id, at = t }
		saveSec(guild, sec, "SECURITY_BOT_GUARD")

		local me = guild.me
		local top = me and me.highestRole and me.highestRole.position or 0
		local strip, skipped = S.splitRoles(roles, top, guild.id)
		for _, r in ipairs(strip) do
			if target:removeRole(r.id, "Security: added a bot without permission") then
				table.insert(status.removed, r.name)
			else
				table.insert(status.skipped, r.name .. " (Discord refused)")
			end
		end
		for _, r in ipairs(skipped) do table.insert(status.skipped, r.name .. " (" .. r.why .. ")") end

		local minutes = tonumber(sec.botguard.timeoutminutes) or 1440
		local blocker = timeoutBlocker(guild, target)
		if blocker then
			status.timeout = "Skipped: " .. blocker
		else
			local okT = target:timeoutFor(math.min(minutes, 40320) * 60)
			status.timeout = okT and ("1 day, ends " .. dmStyle.time(t + minutes * 60, "R")) or "Discord refused the timeout"
		end

		local sent = dmStyle.send(target, {
			guild = guild, icon = "🛡️", title = "Bot invite blocked",
			intro = S.BOT_DM,
			fields = { { "Bot", "@" .. tostring(member.user.username) } },
			footer = "Security",
		})
		status.dm = sent and "Sent" or "Couldn't DM them"
	else
		status.timeout = "Skipped: couldn't find who added it"
		status.dm = "Skipped"
	end

	if channel then
		dmStyle.post(channel, botGuardCard(guild, info, status))
		sendPings(guild, channel, sec.keywords, "Unauthorized bot added, check the alert above.")
	else
		print("[security] no security log channel set, bot guard alert not posted")
	end
end

local function restoreRoles(guild, userId)
	local sec = getSec(guild)
	local case = sec.botguard.cases[userId]
	if not case then return nil, "No saved roles for that member." end
	local m = guild:getMember(userId)
	if not m then return nil, "They're not in the server." end
	local ok, failed = 0, 0
	for _, id in ipairs(case.roles or {}) do
		if guild:getRole(id) and not m.roles:get(id) then
			if m:addRole(id, "Security: roles restored") then ok = ok + 1 else failed = failed + 1 end
		end
	end
	sec.botguard.cases[userId] = nil
	saveSec(guild, sec, "SECURITY_BOT_RESTORE")
	return ok, failed
end

---------------------------------------------------------------- alert buttons
local function canRemoveTimeout(member)
	if isOwnerId(member.id) or member.guild.ownerId == member.id then return true end
	if member:hasPermission("administrator") or member:hasPermission("moderateMembers") then return true end
	return _G.hasPermission and hasPermission(member, "ADMIN", nil, nil, false) == true
end

late.fullLockdown = fullLockdown
late.sendPings = sendPings

local function onButton(interaction)
	local data = interaction.data
	local id = data and data.custom_id
	if type(id) ~= "string" or id:sub(1, 4) ~= "sec:" then return end
	local guild, member = interaction.guild, interaction.member
	if not guild or not member then return end

	if id == "sec:unlock" then
		if not isOwnerId(interaction.user.id) then
			return interaction:reply({ content = "Only the bot owners can unlock the server." }, true)
		end
		interaction:replyDeferred(true)
		local lines = {}
		local okL, resL = endLockdown(guild)
		if okL then table.insert(lines, "Lockdown lifted: " .. resL.restored .. " overwrites restored" .. ((resL.failed > 0) and (", " .. resL.failed .. " failed") or "")) end
		local sec = getSec(guild)
		if sec.raid and sec.raid.active then
			local okR, resR = endRaid(guild, interaction.user.id)
			if okR then table.insert(lines, "Raid mode ended" .. ((#resR > 0) and (": " .. table.concat(resR, ", ")) or "")) end
		end
		if okL then
			alert(guild, getSec(guild), { serious = true, icon = "🔓", title = "Lockdown lifted", intro = interaction.user.mentionString .. " unlocked the server.",
				fields = { { "Restored", resL.restored .. " overwrites" }, { "Failed", (resL.failed > 0) and tostring(resL.failed) or nil } } })
		end
		return interaction:reply({ content = (#lines > 0 and table.concat(lines, ". ") .. ".") or "Nothing to unlock." }, true)
	end

	local restoreId = id:match("^sec:botrestore:(%d+)$")
	if restoreId then
		if not isOwnerId(interaction.user.id) then
			return interaction:reply({ content = "Only the bot owners can restore roles." }, true)
		end
		local ok, failed = restoreRoles(guild, restoreId)
		if not ok then return interaction:reply({ content = failed }, true) end
		print("[security] " .. member.id .. " restored roles for " .. restoreId .. ": " .. ok .. " ok, " .. failed .. " failed")
		alert(guild, getSec(guild), { serious = true, icon = "↩️", title = "Roles restored", intro = interaction.user.mentionString .. " restored <@" .. restoreId .. ">'s roles.",
			fields = { { "Restored", tostring(ok) }, { "Failed", (failed > 0) and tostring(failed) or nil } } })
		return interaction:reply({ content = "Restored " .. ok .. " roles to <@" .. restoreId .. ">" .. ((failed > 0) and (", " .. failed .. " failed") or "") .. ". The timeout is separate, use Remove timeout for that.", allowed_mentions = { parse = {} } }, true)
	end

	local target = id:match("^sec:untimeout:(%d+)$")
	if target then
		if target == member.id then
			return interaction:reply({ content = "You can't remove your own timeout." }, true)
		end
		if not canRemoveTimeout(member) then
			return interaction:reply({ content = "You need Timeout Members to remove a timeout." }, true)
		end
		local m = guild:getMember(target)
		local ok = m and m:removeTimeout()
		print("[security] " .. member.id .. " removed timeout from " .. target .. ": " .. tostring(ok))
		return interaction:reply({ content = ok and ("Removed the timeout from <@" .. target .. ">.") or "Couldn't remove the timeout.", allowed_mentions = { parse = {} } }, true)
	end
end

local function onMessage(message)
	local guild = message.guild
	if not guild or not message.author or message.author.bot or message.webhookId then return end
	local sec = getSec(guild)
	if not sec.enabled then return end

	-- Zeltra: threat + raid/nuke word watch apply to every rank; only the two bot owner accounts are skipped
	-- (no role or whitelist exemptions here). The bot's own messages are already skipped above.
	local ownerSkip = S.isProtectedId(message.author.id)

	-- Zeltra: threats to nuke/raid/wipe the server in plain chat -> alert only (no delete, timeout or lockdown).
	-- Prefix commands like .nuke still go through the keyword handler below.
	local threat = S.detectThreat and S.detectThreat(message.content)
	local isCommand = threat and S.detectRaidKeyword(message.content, sec.keywords.custom)
	if threat and sec.keywords.ignoretickets ~= false then
		local ch = message.channel
		local parentId = ch and (ch._parent_id or (ch.category and ch.category.id))
		if S.isTicketChannel(sqldb:get(guild.id), ch and ch.id, parentId, sec.keywords.ignorecategories) then threat = nil end
	end
	if ownerSkip then threat = nil end
	if threat and not (isCommand and isCommand.kind == "command") then
		if cooldown("threat:" .. guild.id .. ":" .. message.author.id, now(), 60) then
			local ch = alertChannel(guild, sec)
			if ch then
				local quote = tostring(message.content or ""):sub(1, 900)
				dmStyle.post(ch, {
					guild = guild, icon = "⚠️", title = "Threat to nuke/raid the server",
					intro = message.author.mentionString .. " posted a message threatening the server. Alert only, nothing was done to them.",
					fields = {
						{ "Member", message.author.mentionString .. " (`" .. message.author.id .. "`)" },
						{ "Channel", "<#" .. message.channel.id .. ">" },
						{ "Matched", "`" .. threat.text .. "`" },
						{ "Time", dmStyle.time(now()) },
					},
					sections = { { title = "Message", body = quote } },
					buttons = { { label = "Jump to message", url = message.link } },
					footer = "Security",
				})
				local users, roles = pingTargets(guild, sec.keywords)
				local parts = {}
				for _, id in ipairs(users) do table.insert(parts, "<@" .. id .. ">") end
				for _, id in ipairs(roles) do table.insert(parts, "<@&" .. id .. ">") end
				if #parts > 0 then
					pcall(function() ch:send({ content = "⚠️ Threat in chat, check the alert above. " .. table.concat(parts, " "), allowed_mentions = { parse = {}, users = users, roles = roles } }) end)
				end
			end
			print("[security] threat alert for " .. message.author.id .. " in " .. message.channel.id .. ": " .. threat.text)
		end
		return
	end

	-- raid/nuke keywords apply to everyone, owners and whitelisted users included
	if sec.keywords.enabled and not ownerSkip then
		local match = S.detectRaidKeyword(message.content, sec.keywords.custom)
		-- ticket channels: reports often mention "raid", so only prefix commands count there
		if match and sec.keywords.ignoretickets ~= false then
			local ch = message.channel
			local parentId = ch and (ch._parent_id or (ch.category and ch.category.id))
			if S.isTicketChannel(sqldb:get(guild.id), ch and ch.id, parentId, sec.keywords.ignorecategories) then
				if match.kind ~= "command" or sec.keywords.ticketcommands == false then
					print("[security] ignored raid keyword in ticket channel " .. tostring(ch and ch.id) .. ": " .. match.kind)
					match = nil
				end
			end
		end
		if match then return onKeyword(message, sec, match) end
	end

	if not sec.flagged.enabled or not sec.flagged.mentions then return end
	local member = message.member
	if isExempt(guild, message.author.id, sec, member) then return end
	if member and member:hasPermission("administrator") then return end
	local t = now()

	local function flag(kind, title, intro, fields)
		if not cooldown(kind .. ":" .. guild.id .. ":" .. message.author.id, t, 120) then return end
		table.insert(fields, 1, { "Member", message.author.mentionString })
		table.insert(fields, { "Channel", message.channel.mentionString })
		alert(guild, sec, { icon = "📢", title = title, intro = intro, fields = fields,
			buttons = { { label = "Jump to message", url = message.link } } })
	end

	if message.mentionsEveryone then
		flag("everyone", "@everyone ping", message.author.mentionString .. " pinged @everyone or @here.", {})
	end
	local mentions = S.countMentions(message.content)
	if mentions >= sec.flagged.mentionlimit then
		flag("mass", "Mass mention", message.author.mentionString .. " mentioned " .. mentions .. " users or roles in one message.", { { "Mentions", tostring(mentions) } })
	end
	local burst = burstWindow:hit(guild.id .. ":" .. message.author.id, t, sec.flagged.burstwindow)
	if burst >= sec.flagged.burst then
		flag("burst", "Message burst", message.author.mentionString .. " sent " .. burst .. " messages in " .. sec.flagged.burstwindow .. "s.", { { "Messages", burst .. " in " .. sec.flagged.burstwindow .. "s" } })
	end
end

local function checkRaidExpiry()
	for guild in Client.guilds:iter() do
		local config = sqldb:get(guild.id)
		local raid = config and config.security and config.security.raid
		if raid and raid.active and raid.ends and now() >= raid.ends then
			local ok, err = pcall(endRaid, guild, nil)
			if not ok then print("[security] could not end raid mode in " .. guild.id .. ": " .. tostring(err)) end
		end
	end
end

local function safe(name, fn)
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then print("[security] " .. name .. " error: " .. tostring(err)) end
	end
end

security.Start = function()
	_G.zeltraSecurity = { startRaid = startRaid, endRaid = endRaid, getSec = getSec, saveSec = saveSec,
		fullLockdown = fullLockdown, endLockdown = endLockdown, isOwnerId = isOwnerId, restoreRoles = restoreRoles }
	local joinSafe, botSafe = safe("join", onJoin), safe("botguard", onBotJoin)
	connections.join = { "memberJoin", Client:on("memberJoin", function(member)
		if member and member.user and member.user.bot then return botSafe(member) end
		return joinSafe(member)
	end) }
	connections.audit = { "guildAuditLogEntryCreate", Client:on("guildAuditLogEntryCreate", safe("audit", onAudit)) }
	connections.message = { "messageCreate", Client:on("messageCreate", safe("message", onMessage)) }
	connections.buttons = { "interactionCreate", Client:on("interactionCreate", function(interaction)
		coroutine.wrap(safe("button", onButton))(interaction)
	end) }
	interval = timer.setInterval(30000, function()
		coroutine.wrap(safe("raid expiry", checkRaidExpiry))()
	end)
end

security.Stop = function()
	for _, con in pairs(connections) do
		Client:removeListener(con[1], con[2])
	end
	if interval then timer.clearInterval(interval) end
	connections = {}
end

return security
