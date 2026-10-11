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

local function onMessage(message)
	local guild = message.guild
	if not guild or not message.author or message.author.bot or message.webhookId then return end
	local sec = getSec(guild)
	if not sec.enabled or not sec.flagged.enabled or not sec.flagged.mentions then return end
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
	_G.zeltraSecurity = { startRaid = startRaid, endRaid = endRaid, getSec = getSec, saveSec = saveSec }
	connections.join = { "memberJoin", Client:on("memberJoin", safe("join", onJoin)) }
	connections.audit = { "guildAuditLogEntryCreate", Client:on("guildAuditLogEntryCreate", safe("audit", onAudit)) }
	connections.message = { "messageCreate", Client:on("messageCreate", safe("message", onMessage)) }
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
