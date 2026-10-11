--[[
	/security (added by Zeltra; not part of upstream Ducky V1).
	Front end for modules/discord_moderation/security.lua. Owner/admin only by default
	(default_member_permissions = Administrator); can be opened up with /permissions.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

-- setting key -> kind, min, max
local SETTINGS = {
	{ "enabled", "bool", label = "Security system" },
	{ "antiraid.enabled", "bool", label = "Anti-raid" },
	{ "antiraid.joins", "int", 2, 100, label = "Raid joins" },
	{ "antiraid.window", "int", 5, 600, label = "Raid window (seconds)" },
	{ "antiraid.autoraid", "bool", label = "Auto raid mode" },
	{ "antiraid.raidminutes", "int", 1, 1440, label = "Raid mode length (minutes)" },
	{ "antiraid.raidaction", "enum", { "timeout", "kick", "none" }, label = "Raid joiner action" },
	{ "antiraid.raiseverification", "bool", label = "Raise verification in raid mode" },
	{ "antiraid.lockchannels", "bool", label = "Lock public channels in raid mode" },
	{ "antiraid.accountage", "int", 0, 365, label = "New account age (days)" },
	{ "antiraid.flagnew", "bool", label = "Flag new accounts" },
	{ "antiraid.heuristics", "bool", label = "Avatar and name checks" },
	{ "antinuke.enabled", "bool", label = "Anti-nuke" },
	{ "antinuke.count", "int", 2, 50, label = "Anti-nuke actions" },
	{ "antinuke.window", "int", 10, 600, label = "Anti-nuke window (seconds)" },
	{ "antinuke.strip", "bool", label = "Remove dangerous roles" },
	{ "flagged.enabled", "bool", label = "Flagged actions" },
	{ "flagged.revertperms", "bool", label = "Revert permission grants" },
	{ "flagged.mentions", "bool", label = "Mention and spam checks" },
	{ "flagged.mentionlimit", "int", 3, 50, label = "Mass mention limit" },
	{ "flagged.burst", "int", 3, 50, label = "Spam burst messages" },
	{ "flagged.burstwindow", "int", 2, 60, label = "Spam burst window (seconds)" },
	{ "keywords.enabled", "bool", label = "Keyword detection" },
	{ "keywords.lock", "bool", label = "Lock on keyword" },
	{ "keywords.timeoutminutes", "int", 0, 40320, label = "Keyword timeout (minutes, 0 = off)" },
}
local BY_KEY = {}
for _, s in ipairs(SETTINGS) do BY_KEY[s[1]] = s end

local slashCommand = tools.slashCommand("security", "Anti-raid and anti-nuke settings.")

local subcmd = tools.subCommand("status", "Show the security settings and raid mode state.")
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("lockdown", "Turn on raid mode now.")
subcmd = subcmd:addOption(tools.string("reason", "Why the server is being locked down."):setRequired(false))
subcmd = subcmd:addOption(tools.integer("minutes", "How long raid mode lasts (default from config)."):setRequired(false))
subcmd = subcmd:addOption(tools.boolean("lock_channels", "Stop @everyone from talking in public channels."):setRequired(false))
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("unlock", "Bot owners only: end raid mode and lift a keyword lockdown.")
slashCommand:addOption(subcmd)

local group = tools.subCommandGroup("config", "Change the security settings.")
subcmd = tools.subCommand("set", "Change a setting.")
local settingOption = tools.string("setting", "The setting to change."):setRequired(true)
for _, s in ipairs(SETTINGS) do
	settingOption = settingOption:addChoice(tools.choice(s.label, s[1]))
end
subcmd = subcmd:addOption(settingOption)
subcmd = subcmd:addOption(tools.string("value", "on/off, a number, or timeout/kick/none."):setRequired(true))
group:addOption(subcmd)

subcmd = tools.subCommand("whitelist", "Add or remove a trusted user or role.")
subcmd = subcmd:addOption(tools.string("action", "Add or remove."):setRequired(true)
	:addChoice(tools.choice("add", "add")):addChoice(tools.choice("remove", "remove")))
subcmd = subcmd:addOption(tools.user("user", "The user."):setRequired(false))
subcmd = subcmd:addOption(tools.role("role", "The role."):setRequired(false))
group:addOption(subcmd)

subcmd = tools.subCommand("keyword", "Add or remove a custom raid keyword.")
subcmd = subcmd:addOption(tools.string("action", "Add, remove or list."):setRequired(true)
	:addChoice(tools.choice("add", "add")):addChoice(tools.choice("remove", "remove")):addChoice(tools.choice("list", "list")))
subcmd = subcmd:addOption(tools.string("word", "The word or phrase."):setRequired(false))
group:addOption(subcmd)

subcmd = tools.subCommand("ping", "Choose who gets pinged when a raid keyword is detected.")
subcmd = subcmd:addOption(tools.string("action", "Add, remove or list."):setRequired(true)
	:addChoice(tools.choice("add", "add")):addChoice(tools.choice("remove", "remove")):addChoice(tools.choice("list", "list")))
subcmd = subcmd:addOption(tools.user("user", "The user."):setRequired(false))
subcmd = subcmd:addOption(tools.role("role", "The role."):setRequired(false))
group:addOption(subcmd)

subcmd = tools.subCommand("logchannel", "Set where security alerts are posted.")
subcmd = subcmd:addOption(tools.channel("channel", "The alert channel."):setRequired(true))
group:addOption(subcmd)
slashCommand:addOption(group)

local function getPath(t, path)
	for part in path:gmatch("[^%.]+") do
		if type(t) ~= "table" then return nil end
		t = t[part]
	end
	return t
end

local function setPath(t, path, value)
	local parts = {}
	for part in path:gmatch("[^%.]+") do table.insert(parts, part) end
	for i = 1, #parts - 1 do
		t[parts[i]] = t[parts[i]] or {}
		t = t[parts[i]]
	end
	t[parts[#parts]] = value
end

local function showValue(v)
	if v == true then return "On" elseif v == false then return "Off" end
	return tostring(v)
end

local function parseValue(setting, raw)
	raw = tostring(raw or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local kind = setting[2]
	if kind == "bool" then
		if raw == "on" or raw == "true" or raw == "yes" or raw == "enable" or raw == "enabled" or raw == "1" then return true end
		if raw == "off" or raw == "false" or raw == "no" or raw == "disable" or raw == "disabled" or raw == "0" then return false end
		return nil, "Use **on** or **off** for this setting."
	elseif kind == "int" then
		local n = tonumber(raw)
		if not n or n % 1 ~= 0 or n < setting[3] or n > setting[4] then
			return nil, "Use a whole number from **" .. setting[3] .. "** to **" .. setting[4] .. "**."
		end
		return n
	elseif kind == "enum" then
		for _, v in ipairs(setting[3]) do
			if v == raw then return v end
		end
		return nil, "Use one of: **" .. table.concat(setting[3], "**, **") .. "**."
	end
end

local function statusCard(guild, sec)
	local raid = sec.raid or {}
	local wl = {}
	for _, id in ipairs(sec.whitelist.users) do table.insert(wl, "<@" .. id .. ">") end
	for _, id in ipairs(sec.whitelist.roles) do table.insert(wl, "<@&" .. id .. ">") end
	local a, n, f = sec.antiraid, sec.antinuke, sec.flagged
	return dmStyle.buildEmbed({
		guild = guild, icon = "🛡️", title = "Security status",
		fields = {
			{ "System", showValue(sec.enabled) },
			{ "Log channel", (sec.logchannel and ("<#" .. sec.logchannel .. ">")) or "Not set" },
			{ "Raid mode", (raid.active and ("On, ends " .. dmStyle.time(raid.ends, "R"))) or "Off" },
			{ "Keyword lockdown", (sec.lockdown and sec.lockdown.active) and ("On since " .. dmStyle.time(sec.lockdown.started, "R") .. " · " .. #(sec.lockdown.entries or {}) .. " overwrites saved") or "Off" },
			{ "Keyword detection", showValue(sec.keywords.enabled) .. " · lock " .. showValue(sec.keywords.lock):lower() .. " · timeout " .. ((sec.keywords.timeoutminutes > 0) and (sec.keywords.timeoutminutes .. "m") or "off") .. " · " .. #sec.keywords.custom .. " custom" },
			{ "Anti-raid", showValue(a.enabled) .. " · " .. a.joins .. " joins in " .. a.window .. "s · auto raid " .. showValue(a.autoraid):lower() .. " · " .. a.raidminutes .. "m · joiners: " .. a.raidaction },
			{ "Raid mode changes", "verification " .. showValue(a.raiseverification):lower() .. " · channel lock " .. showValue(a.lockchannels):lower() },
			{ "Join flags", "new accounts " .. showValue(a.flagnew):lower() .. " (under " .. a.accountage .. "d) · avatar and name checks " .. showValue(a.heuristics):lower() },
			{ "Anti-nuke", showValue(n.enabled) .. " · " .. n.count .. " actions in " .. n.window .. "s · remove roles " .. showValue(n.strip):lower() },
			{ "Flagged actions", showValue(f.enabled) .. " · revert grants " .. showValue(f.revertperms):lower() },
			{ "Mentions and spam", showValue(f.mentions) .. " · " .. f.mentionlimit .. " mentions · " .. f.burst .. " messages in " .. f.burstwindow .. "s" },
			{ "Whitelist", (#wl > 0 and table.concat(wl, ", ")) or "Nobody (owners are always trusted)" },
		},
		footer = "Security",
	}).embed
end

return {
	name = "security",
	description = "Anti-raid and anti-nuke settings.",
	aliases = {},
	category = "Moderation",
	slashCommand = slashCommand,
	subcommands = { "status", "lockdown", "unlock", "config set", "config whitelist", "config keyword", "config ping", "config logchannel" },
	requiredPermissions = {
		"ADMIN"
	},
	hybridCallback = function(interaction, args, slash, subcmd)
		if not slash then
			return interaction:fail("Use the `/security` slash command.", nil, true)
		end
		local api = _G.zeltraSecurity
		if not api then
			return interaction:fail("The security module is not loaded.", nil, true)
		end
		local guild = interaction.guild
		local sec = api.getSec(guild)
		args = args or {}

		if subcmd == "status" then
			return interaction:reply({ embed = statusCard(guild, sec) }, true)

		elseif subcmd == "lockdown" then
			local ok, res, results = api.startRaid(guild, {
				by = interaction.user.id,
				reason = args.reason or "Manual lockdown",
				minutes = args.minutes,
				lockChannels = args.lock_channels,
			})
			if not ok then return interaction:fail(res, nil, true) end
			return interaction:success("Raid mode is on until " .. dmStyle.time(res.ends, "t") .. ((results and #results > 0) and (": " .. table.concat(results, ", ") .. ".") or "."))

		elseif subcmd == "unlock" then
			-- bot owners only, by user ID; admins and /permissions grants can't unlock
			if not api.isOwnerId(interaction.user.id) then
				return interaction:fail("Only the bot owners can unlock the server.", nil, true)
			end
			interaction:replyDeferred(true)
			local lines = {}
			local okL, resL = api.endLockdown(guild)
			if okL then
				table.insert(lines, "Lockdown lifted: " .. resL.restored .. " overwrites restored" .. ((resL.failed > 0) and (", " .. resL.failed .. " failed") or ""))
			end
			if sec.raid and sec.raid.active then
				local okR, resR = api.endRaid(guild, interaction.user.id)
				if okR then table.insert(lines, "Raid mode ended" .. ((#resR > 0) and (": " .. table.concat(resR, ", ")) or "")) end
			end
			if #lines == 0 then return interaction:fail("Raid mode and the keyword lockdown are both off.", nil, true) end
			return interaction:success(table.concat(lines, ". ") .. ".")

		elseif subcmd == "config set" then
			local setting = BY_KEY[args.setting]
			if not setting then return interaction:fail("Unknown setting.", nil, true) end
			local value, err = parseValue(setting, args.value)
			if value == nil then return interaction:fail(err, nil, true) end
			local old = getPath(sec, setting[1])
			setPath(sec, setting[1], value)
			api.saveSec(guild, sec, "SECURITY_CONFIG")
			return interaction:success("**" .. setting.label .. "** changed from **" .. showValue(old) .. "** to **" .. showValue(value) .. "**.")

		elseif subcmd == "config whitelist" then
			if not args.user and not args.role then
				return interaction:fail("Pick a user or a role.", nil, true)
			end
			local changed = {}
			local function apply(list, id, text)
				local index
				for i, v in ipairs(list) do if tostring(v) == id then index = i end end
				if args.action == "add" and not index then
					table.insert(list, id); table.insert(changed, text)
				elseif args.action == "remove" and index then
					table.remove(list, index); table.insert(changed, text)
				end
			end
			if args.user then apply(sec.whitelist.users, args.user.id, "<@" .. args.user.id .. ">") end
			if args.role then apply(sec.whitelist.roles, args.role.id, args.role.mentionString) end
			if #changed == 0 then
				return interaction:fail("Nothing changed. " .. ((args.action == "add") and "Already on the whitelist." or "Not on the whitelist."), nil, true)
			end
			api.saveSec(guild, sec, "SECURITY_WHITELIST")
			return interaction:success(((args.action == "add") and "Added " or "Removed ") .. table.concat(changed, " and ") .. ((args.action == "add") and " to" or " from") .. " the security whitelist.")

		elseif subcmd == "config keyword" then
			local list = sec.keywords.custom
			if args.action == "list" then
				return interaction:reply({ content = (#list > 0) and ("Custom keywords: " .. table.concat(list, ", ")) or "No custom keywords yet.", allowed_mentions = { parse = {} } }, true)
			end
			local word = args.word and args.word:lower():gsub("^%s+", ""):gsub("%s+$", "")
			if not word or word == "" or #word > 50 then
				return interaction:fail("Give a word or phrase up to 50 characters.", nil, true)
			end
			local index
			for i, v in ipairs(list) do if v == word then index = i end end
			if args.action == "add" then
				if index then return interaction:fail("That keyword is already on the list.", nil, true) end
				if #list >= 50 then return interaction:fail("The list is full (50 keywords).", nil, true) end
				table.insert(list, word)
			else
				if not index then return interaction:fail("That keyword isn't on the list.", nil, true) end
				table.remove(list, index)
			end
			api.saveSec(guild, sec, "SECURITY_KEYWORDS")
			return interaction:success(((args.action == "add") and "Added" or "Removed") .. " the keyword **" .. word:gsub("[*_`~|]", "") .. "**.")

		elseif subcmd == "config ping" then
			local kw = sec.keywords
			if args.action == "list" then
				local list = {}
				for _, id in ipairs(kw.pingusers) do table.insert(list, "<@" .. id .. ">") end
				for _, id in ipairs(kw.pingroles) do table.insert(list, "<@&" .. id .. ">") end
				return interaction:reply({ content = "Pinged 3 times on a raid keyword: " .. ((#list > 0) and table.concat(list, ", ") or "nobody")
					.. ".", allowed_mentions = { parse = {} } }, true)
			end
			if not args.user and not args.role then return interaction:fail("Pick a user or a role.", nil, true) end
			local changed = {}
			local function apply(list, id, text)
				local index
				for i, v in ipairs(list) do if tostring(v) == id then index = i end end
				if args.action == "add" and not index then table.insert(list, id) table.insert(changed, text)
				elseif args.action == "remove" and index then table.remove(list, index) table.insert(changed, text) end
			end
			if args.user then apply(kw.pingusers, args.user.id, "<@" .. args.user.id .. ">") end
			if args.role then apply(kw.pingroles, args.role.id, args.role.mentionString) end
			if #changed == 0 then return interaction:fail("Nothing changed.", nil, true) end
			api.saveSec(guild, sec, "SECURITY_PINGS")
			return interaction:success(((args.action == "add") and "Added " or "Removed ") .. table.concat(changed, " and ") .. ((args.action == "add") and " to" or " from") .. " the raid keyword pings.")

		elseif subcmd == "config logchannel" then
			local channel = args.channel
			if not channel or not channel.send then
				return interaction:fail("Pick a text channel.", nil, true)
			end
			sec.logchannel = channel.id
			api.saveSec(guild, sec, "SECURITY_LOGCHANNEL")
			return interaction:success("Security alerts will be posted in " .. channel.mentionString .. ".")
		end

		return interaction:fail("Unknown subcommand.", nil, true)
	end
}
