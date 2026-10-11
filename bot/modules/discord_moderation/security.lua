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
local function alert(guild, sec, opts)
	if not sec.enabled or not sec.logchannel then return end
	local channel = guild:getChannel(sec.logchannel)
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

	alert(guild, sec, {
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

	alert(guild, sec, {
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
			alert(guild, sec, {
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

	alert(guild, sec, {
		icon = "⚠️", title = "Unusual staff activity",
		intro = mention(executor) .. " made " .. count .. " " .. label .. " in under " .. sec.antinuke.window .. "s.",
		fields = {
			{ "Staff Member", mention(executor) .. " (`" .. tostring(executor) .. "`)" },
			{ "Activity", count .. " " .. label },
			{ "Action", action },
			{ "Latest reason", entry.reason },
		},
		note = (member and member.user and member.user.bot) and "This is a bot. Its own role can't be removed, so consider kicking it." or nil,
	})
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
	elseif at == 28 then -- bot added
		alert(guild, sec, {
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

local function sendPings(guild, channel, kw)
	local users, roles = pingTargets(guild, kw)
	if #users == 0 and #roles == 0 then return 0 end
	local parts = {}
	for _, id in ipairs(users) do table.insert(parts, "<@" .. id .. ">") end
	for _, id in ipairs(roles) do table.insert(parts, "<@&" .. id .. ">") end
	local sent = 0
	for i = 1, 3 do
		local ok, msg = pcall(function()
			return channel:send({
				content = "🚨 Raid command detected, check the alert above. " .. table.concat(parts, " "),
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
	local channel = sec.logchannel and guild:getChannel(sec.logchannel)
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

---------------------------------------------------------------- alert buttons
local function canRemoveTimeout(member)
	if isOwnerId(member.id) or member.guild.ownerId == member.id then return true end
	if member:hasPermission("administrator") or member:hasPermission("moderateMembers") then return true end
	return _G.hasPermission and hasPermission(member, "ADMIN", nil, nil, false) == true
end

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
			alert(guild, getSec(guild), { icon = "🔓", title = "Lockdown lifted", intro = interaction.user.mentionString .. " unlocked the server.",
				fields = { { "Restored", resL.restored .. " overwrites" }, { "Failed", (resL.failed > 0) and tostring(resL.failed) or nil } } })
		end
		return interaction:reply({ content = (#lines > 0 and table.concat(lines, ". ") .. ".") or "Nothing to unlock." }, true)
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

	-- raid/nuke keywords apply to everyone, owners and whitelisted users included
	if sec.keywords.enabled then
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
		fullLockdown = fullLockdown, endLockdown = endLockdown, isOwnerId = isOwnerId }
	connections.join = { "memberJoin", Client:on("memberJoin", safe("join", onJoin)) }
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
