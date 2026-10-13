-- backgroundcheck.lua
-- Zeltra: hard-locked to two Discord IDs (see libs/zeltra-backgroundcheck.lua). /permissions, Administrator,
-- the server owner and roles cannot open it. Reply is always ephemeral.

local BC = _G.backgroundCheck
local slashCommand = tools.slashCommand("backgroundcheck", "Run a background check on a member or user ID.")
slashCommand = slashCommand:addOption(tools.string("user", "A member mention or a Discord user ID."):setRequired(true))

local function ts(t) return t and ("<t:" .. math.floor(t) .. ":D> (<t:" .. math.floor(t) .. ":R>)") or "Unknown" end
local function isoToUnix(s)
	if type(s) ~= "string" then return nil end
	local ok, v = pcall(function() return discordia.Date.parseISO(s) end)
	return ok and v or nil
end

-- Scan recent messages (content + embeds) in a channel for a user ID.
local function scanChannel(channel, id, limit)
	local hits = {}
	if not channel then return hits end
	pcall(function()
		local msgs = channel:getMessages(limit or 100)
		if not msgs then return end
		for m in msgs:iter() do
			local blob = tostring(m.content or "")
			for _, e in ipairs(m.embeds or {}) do
				blob = blob .. " " .. tostring(e.title) .. " " .. tostring(e.description)
				for _, f in ipairs(e.fields or {}) do blob = blob .. " " .. tostring(f.name) .. " " .. tostring(f.value) end
			end
			for _, row in ipairs((m._components or {})) do
				for _, c in ipairs(row.components or {}) do blob = blob .. " " .. tostring(c.custom_id) end
			end
			if blob:find(id, 1, true) then
				local title = (m.embeds and m.embeds[1] and m.embeds[1].title) or blob:sub(1, 60)
				table.insert(hits, { title = BC.trim(title, 60), at = m.createdAt })
			end
		end
	end)
	return hits
end

local function auditFor(guild, actionType, id)
	local out = {}
	pcall(function()
		local logs = guild:getAuditLogs({ type = actionType, limit = 100 })
		if not logs then return end
		for e in logs:iter() do
			if tostring(e.targetId) == id then table.insert(out, e) end
		end
	end)
	return out
end

return {
	name = "backgroundcheck",
	description = "Run a background check on a member or user ID.",
	category = "Utility",
	slashCommand = slashCommand,
	requiredPermissions = {},
	deferEphemeral = true,
	hardLocked = true,
	hybridCallback = function(interaction, args, slash)
		if not (interaction.user and BC.isAllowed(interaction.user.id)) then
			return interaction:reply({ content = BC.DENY_MESSAGE, ephemeral = true }, true)
		end
		if not slash then
			return interaction:reply({ content = "Use /backgroundcheck.", ephemeral = true }, true)
		end
		local id = BC.parseId(args and args.user)
		if not id then
			return interaction:reply({ content = "That is not a valid member or user ID.", ephemeral = true }, true)
		end
		local guild = interaction.guild
		local config = sqldb:get(guild.id) or {}
		local f = {}

		-- Account
		local raw
		pcall(function() raw = Client._api:getUser(id) end)
		if type(raw) ~= "table" or not raw.id then
			return interaction:reply({ content = "No Discord user found with that ID.", ephemeral = true }, true)
		end
		local created = BC.snowflakeTime(id)
		f.accountAgeDays = created and math.floor((os.time() - created) / 86400)
		f.defaultAvatar = raw.avatar == nil or raw.avatar == json.null
		f.noBanner = raw.banner == nil or raw.banner == json.null
		f.isBot = raw.bot == true
		f.spamName = BC.spamName(raw.username) or BC.spamName(raw.global_name ~= json.null and raw.global_name or nil)

		local link
		pcall(function() link = sqldb:getLink(id) end)
		local roblox = link and link.roblox
		local robloxSource = roblox and "Bot link"
		if not roblox and config.bloxlinkServerKey and config.bloxlinkServerKey ~= "nil" then
			pcall(function()
				local _, body = _G.http.request("GET", "https://api.blox.link/v4/public/guilds/" .. guild.id .. "/discord-to-roblox/" .. id, { { "Authorization", config.bloxlinkServerKey } }, nil, { timeout = 5000 })
				local ok, data = pcall(json.decode, body)
				if ok and type(data) == "table" and data.robloxID then roblox, robloxSource = data.robloxID, "Bloxlink" end
			end)
			f.robloxLinked = roblox ~= nil
		elseif roblox then
			f.robloxLinked = true
		else
			f.robloxLinked = false
			robloxSource = "Bot link only (no Bloxlink key)"
		end

		-- Membership
		local member = guild:getMember(id)
		f.inGuild = member ~= nil
		local joined = member and isoToUnix(member.joinedAt)

		-- Bot DB records
		local cases, warns = {}, 0
		for _, c in pairs(config.cases or {}) do
			if tostring(c.member) == id then
				table.insert(cases, c)
				if tostring(c.type):lower():find("warn") then warns = warns + 1 end
			end
		end
		table.sort(cases, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
		f.caseCount, f.warnCount = #cases, warns
		local infr = {}
		for _, i in pairs(config.infractions or {}) do
			if tostring(i.user) == id then table.insert(infr, i) end
		end
		f.infractionCount = #infr
		local puns, robloxBans = {}, 0
		if roblox then
			for _, p in pairs(config.punishments or {}) do
				if tostring(p.player) == tostring(roblox) then
					table.insert(puns, p)
					if tostring(p.type):lower():find("ban") then robloxBans = robloxBans + 1 end
				end
			end
		end
		f.punishmentCount = #puns
		local tickets = 0
		for _, panel in pairs(config.panels or {}) do
			for _, sub in pairs(type(panel) == "table" and panel.subjects or {}) do
				for _, t in pairs(type(sub) == "table" and sub.tickets or {}) do
					if type(t) == "table" and tostring(t.owner) == id then tickets = tickets + 1 end
				end
			end
		end
		local bl
		pcall(function() bl = sqldb:getBlacklist(id) end)
		f.botBlacklisted = bl ~= nil and bl ~= false

		-- Security logs (alert + log channels, last 100 messages each)
		local sec = config.security or {}
		local secHits = {}
		local seen = {}
		for _, ch in ipairs({ _G.securityAlertChannel and _G.securityAlertChannel(guild, sec), sec.logchannel and guild:getChannel(sec.logchannel), guild:getChannel("1558672726246563962") }) do
			if ch and not seen[ch.id] then
				seen[ch.id] = true
				for _, h in ipairs(scanChannel(ch, id, 100)) do table.insert(secHits, h) end
			end
		end
		f.securityHits = #secHits

		-- Audit log + current ban
		local ban
		pcall(function() ban = guild:getBan(id) end)
		f.currentlyBanned = ban ~= nil
		local bans = auditFor(guild, 22, id)
		local unbans = auditFor(guild, 23, id)
		local kicks = auditFor(guild, 20, id)
		local timeouts = {}
		for _, e in ipairs(auditFor(guild, 24, id)) do
			local ch = e.changes and e.changes.communication_disabled_until
			if ch and ch.new and ch.new ~= json.null then table.insert(timeouts, e) end
		end
		f.banCount, f.kickCount, f.timeoutCount = #bans, #kicks, #timeouts

		-- Other servers (public lists, free, no key). Failures are silent.
		local other = {}
		pcall(function()
			local res, body = _G.http.request("GET", BC.YONLE_URL, nil, nil, { timeout = 5000 })
			if res and res.code == 200 then
				local r = BC.yonleLookup(body, id)
				other.yonle = r or false
			end
		end)
		f.otherServerHits = other.yonle and 1 or 0

		local level, reasons = BC.score(f)

		-- Card
		local function yn(b) return b and "Yes" or "No" end
		local flags = {}
		if f.accountAgeDays and f.accountAgeDays < 30 then table.insert(flags, "New account") end
		if f.defaultAvatar then table.insert(flags, "Default avatar") end
		if f.noBanner then table.insert(flags, "No banner") end
		if f.spamName then table.insert(flags, "Spam-like name") end
		if f.robloxLinked == false then table.insert(flags, "No Roblox link") end
		if f.isBot then table.insert(flags, "Bot account") end

		local caseLines = {}
		for i = 1, math.min(#cases, 5) do
			local c = cases[i]
			table.insert(caseLines, "#" .. tostring(c.caseID) .. " " .. BC.trim(c.type, 20) .. ": " .. BC.trim(c.reason, 60) .. " <t:" .. (c.timestamp or 0) .. ":d>")
		end
		local infrLines = {}
		for i = 1, math.min(#infr, 3) do
			local x = infr[i]
			table.insert(infrLines, BC.trim(x.type, 20) .. ": " .. BC.trim(x.reason, 50) .. (x.notes and (" (note: " .. BC.trim(x.notes, 40) .. ")") or ""))
		end
		local secLines = {}
		for i = 1, math.min(#secHits, 4) do table.insert(secLines, secHits[i].title) end
		local function entryLine(e)
			return "<t:" .. math.floor(e.createdAt) .. ":d> by <@" .. tostring(e.userId) .. ">: " .. BC.trim(e.reason or "No reason", 50)
		end
		local banLines = {}
		if ban then table.insert(banLines, "Currently banned: " .. BC.trim(ban.reason or "No reason", 80)) end
		for i = 1, math.min(#bans, 3) do table.insert(banLines, "Ban " .. entryLine(bans[i])) end
		if #unbans > 0 then table.insert(banLines, #unbans .. " unban(s) in audit log") end
		if robloxBans > 0 then table.insert(banLines, robloxBans .. " ERLC ban(s) on linked Roblox account") end
		local toLines = {}
		for i = 1, math.min(#timeouts, 3) do table.insert(toLines, entryLine(timeouts[i])) end

		local otherVal
		if other.yonle == nil then otherVal = "Lookup unavailable right now."
		elseif other.yonle then otherVal = "Listed: " .. BC.trim(other.yonle, 80)
		else otherVal = "Not listed." end
		otherVal = otherVal .. "\nSource: Yonle discorduser-globalban (github.com/yonle/discorduser-globalban)"

		local function list(t, empty) return #t > 0 and table.concat(t, "\n") or empty end
		local name = BC.clean(raw.global_name ~= json.null and raw.global_name or raw.username)

		local embed = {
			title = "Background Check: " .. name,
			description = "<@" .. id .. "> (`" .. id .. "`)\n**Risk: " .. level .. "**\n" .. table.concat(reasons, "\n"),
			color = BC.COLOR,
			thumbnail = { url = (not f.defaultAvatar) and ("https://cdn.discordapp.com/avatars/" .. id .. "/" .. raw.avatar .. ".png") or nil },
			fields = {
				{ name = "Account", value = "Created " .. ts(created) .. "\nUsername: @" .. BC.clean(raw.username) .. "\nFlags: " .. list(flags, "None"):gsub("\n", ", "), inline = false },
				{ name = "Roblox", value = roblox and ("Linked: `" .. tostring(roblox) .. "` (" .. robloxSource .. ")") or ("Not linked. " .. (robloxSource or "")), inline = true },
				{ name = "Server", value = (member and ("Joined " .. ts(joined)) or "Not in the server") .. "\nLeave/rejoin counts: not logged", inline = true },
				{ name = "Moderation (" .. #cases .. " cases, " .. warns .. " warnings)", value = list(caseLines, "None"), inline = false },
				{ name = "Staff infractions (" .. #infr .. ")", value = list(infrLines, "None"), inline = true },
				{ name = "ERLC punishments", value = roblox and (#puns .. " record(s)") or "No Roblox link", inline = true },
				{ name = "Tickets opened", value = tostring(tickets), inline = true },
				{ name = "Security alerts (" .. #secHits .. ")", value = list(secLines, "None in recent security logs"), inline = false },
				{ name = "Bans", value = list(banLines, "No bans found") .. "\nBot blacklist: " .. yn(f.botBlacklisted), inline = false },
				{ name = "Timeouts (" .. #timeouts .. ")", value = list(toLines, "None in audit log") .. (#kicks > 0 and ("\nKicks: " .. #kicks) or ""), inline = false },
				{ name = "Other servers", value = otherVal, inline = false },
			},
			footer = { text = "South Carolina Roleplay | Audit log covers recent entries only" },
		}
		for _, fl in ipairs(embed.fields) do fl.value = BC.clean(fl.value):sub(1, 1024) end
		return interaction:reply({ embed = embed, ephemeral = true }, true)
	end
}
