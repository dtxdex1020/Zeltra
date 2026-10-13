-- modules/server_management/scrp.lua
-- Zeltra (AGPL-3.0, see NOTICE.md): South Carolina Roleplay extras, not part of upstream Ducky V1.
--   * join roles: Community Member and Unverified for everyone who joins
--   * verification: once a member has the Verified role (Bloxlink), Unverified is removed right away
--   * staff and High Rank applications: Apply button -> two modals -> review card with Accept / Deny -> DM and results post
-- Settings and questions: libs/zeltra-staffapp-scrp.lua
local A = _G.scrpStaffApp

local scrp = {
	name = "scrp",
	description = "South Carolina Roleplay join roles, verification cleanup and staff applications."
}

local connections = {}
local partial = { staff = {}, hr = {} } -- [kind][userId] = { at = os.time(), answers = {...} } between the two modals

local function safe(name, fn)
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then print("[scrp] " .. name .. " error: " .. tostring(err)) end
	end
end

local function hasRole(member, id)
	return member and member.roles and member.roles:get(id) ~= nil
end

local function isVerified(member)
	if hasRole(member, A.VERIFIED) then return true end
	for role in member.roles:iter() do
		if A.VERIFIED_NAMES[string.lower(role.name)] then return true end
	end
	return false
end

---------------------------------------------------------------- join roles / verification
local function onJoin(member)
	if not member.guild or member.guild.id ~= A.GUILD_ID or (member.user and member.user.bot) then return end
	if not hasRole(member, A.COMMUNITY_MEMBER) then member:addRole(A.COMMUNITY_MEMBER, "join role") end
	if isVerified(member) then return end
	if not hasRole(member, A.UNVERIFIED) then member:addRole(A.UNVERIFIED, "not verified yet") end
end

local function onUpdate(member)
	if not member.guild or member.guild.id ~= A.GUILD_ID or (member.user and member.user.bot) then return end
	if hasRole(member, A.UNVERIFIED) and isVerified(member) then
		member:removeRole(A.UNVERIFIED, "verified")
		print("[scrp] removed Unverified from " .. member.id .. " (verified)")
	end
end

---------------------------------------------------------------- staff and High Rank applications
-- cfg is A.STAFF or A.HR (libs/zeltra-staffapp-scrp.lua); both use the same flow, review card and result format
local function state(guildId, cfg)
	local config = sqldb:get(guildId) or {}
	local s = type(config[cfg.stateKey]) == "table" and config[cfg.stateKey] or {}
	s.cooldowns = s.cooldowns or {}
	s.pending = s.pending or {}
	return s
end

local function saveState(guildId, s, user, cfg)
	sqldb:set(guildId, { [cfg.stateKey] = s }, cfg.kind == "hr" and "SCRP_HR_APP" or "SCRP_STAFF_APP", user)
end

local function isReviewer(member, cfg)
	if not member then return false end
	if member:hasPermission("administrator") then return true end
	local role = member.guild:getRole(cfg.REVIEWER_ROLE)
	return role and member.highestRole and member.highestRole.position >= role.position
end

local function isStaffMember(member, cfg)
	local ids = {}
	for role in member.roles:iter() do ids[role.id] = true end
	local extra = (_G.hasStaffRank and _G.hasStaffRank(member)) or false
	return A.isStaff(cfg, ids, extra)
end

local function short(s, n)
	s = tostring(s or ""):gsub("\r", "")
	if #s > n then return s:sub(1, n - 3) .. "..." end
	return s
end

local function allQuestions(cfg)
	local out = {}
	for _, page in ipairs(cfg.PAGES) do
		for _, q in ipairs(page.questions) do out[#out + 1] = q end
	end
	return out
end

local function cap(s) return (s:gsub("^%l", string.upper)) end

local function transcript(user, answers, cfg)
	local lines = { cap(cfg.name) .. " from @" .. user.username .. " (" .. user.id .. ")", "Submitted " .. os.date("!%Y-%m-%d %H:%M UTC"), "" }
	for _, q in ipairs(allQuestions(cfg)) do
		lines[#lines + 1] = q.question
		lines[#lines + 1] = tostring(answers[q.key] or "No answer")
		lines[#lines + 1] = ""
	end
	return table.concat(lines, "\n")
end

local function reviewCard(guild, user, answers, cfg, decision)
	local sections = {}
	for _, q in ipairs(allQuestions(cfg)) do
		if answers[q.key] and answers[q.key] ~= "" then
			sections[#sections + 1] = { title = q.question, body = short(answers[q.key], 300) }
		end
	end
	local fields = {
		{ "Applicant", "<@" .. user.id .. "> (`" .. user.id .. "`)" },
		{ "Roblox", answers.roblox },
	}
	if cfg.kind == "hr" then fields[#fields + 1] = { "Current rank", answers.rank } end
	fields[#fields + 1] = { "Account created", user.createdAt and dmStyle.time(math.floor(user.createdAt), "R") }
	local opts = {
		guild = guild,
		title = cfg.kind == "hr" and "HR | High Rank application" or "Staff application",
		intro = "New " .. (cfg.kind == "hr" and "**HR** " or "") .. "application from <@" .. user.id .. ">. The full answers are in the attached file.",
		fields = fields,
		sections = sections,
		footer = cfg.footer,
	}
	local pre = A.prefix(cfg)
	if decision then
		opts.note = decision
	else
		opts.buttons = {
			{ label = "Accept", custom_id = pre .. "acc_" .. user.id, style = 3 },
			{ label = "Deny", custom_id = pre .. "deny_" .. user.id, style = 4 },
		}
	end
	return opts
end

local function onApply(interaction, cfg)
	local guild = interaction.guild
	if cfg.STAFF_ROLE and not isStaffMember(interaction.member, cfg) then
		return interaction:fail(cfg.NOT_STAFF, nil, true)
	end
	local ok, why = A.canApply(state(guild.id, cfg), interaction.user.id, os.time(), cfg)
	if not ok then return interaction:fail(why, nil, true) end

	prompt(interaction, cfg.PAGES[1].title, A.questions(1, cfg), function(mia, responses)
		local answers = {}
		for _, q in ipairs(cfg.PAGES[1].questions) do answers[q.key] = responses[q.question] end
		partial[cfg.kind][interaction.user.id] = { at = os.time(), answers = answers, page = 2 }
		mia:reply(dmStyle.build({
			guild = guild,
			title = "Part 1 saved",
			intro = #cfg.PAGES > 2 and "Thanks. Press the button below for part 2." or "Thanks. Press the button below for the second and last part of the application.",
			buttons = { { label = "Continue to part 2", custom_id = A.prefix(cfg) .. "next", style = 1 } },
			footer = cfg.footer,
		}), true)
	end)
end

local function onNext(interaction, cfg)
	local guild = interaction.guild
	local store = partial[cfg.kind]
	local p = store[interaction.user.id]
	if not p or os.time() - p.at > 1800 then
		store[interaction.user.id] = nil
		return interaction:fail("Your saved answers expired. Press the button in the applications channel to start again.", nil, true)
	end
	local page = p.page or 2

	prompt(interaction, cfg.PAGES[page].title, A.questions(page, cfg), function(mia, responses)
		local answers = p.answers
		for _, q in ipairs(cfg.PAGES[page].questions) do answers[q.key] = responses[q.question] end
		if page < #cfg.PAGES then
			p.page, p.at = page + 1, os.time()
			local last = page + 1 == #cfg.PAGES
			return mia:reply(dmStyle.build({
				guild = guild,
				title = "Part " .. page .. " saved",
				intro = "Thanks. Press the button below for part " .. (page + 1) .. (last and ", the last part." or "."),
				buttons = { { label = "Continue to part " .. (page + 1), custom_id = A.prefix(cfg) .. "next", style = 1 } },
				footer = cfg.footer,
			}), true)
		end
		store[interaction.user.id] = nil
		-- acknowledge within Discord's 3 second limit; posting the review card with its file can take longer
		pcall(function() mia:replyDeferred(true) end)

		local channel = guild:getChannel(cfg.REVIEW_CHANNEL)
		if not channel then return mia:fail("Applications can't be sent right now. Please tell a staff member.", nil, true) end

		local fname = (cfg.kind == "hr" and "hr-application-" or "application-") .. interaction.user.id .. ".txt"
		local opts = reviewCard(guild, interaction.user, answers, cfg)
		opts.files = { { fname, transcript(interaction.user, answers, cfg) } }
		opts.file = fname
		local payload = dmStyle.build(opts)
		table.insert(payload.components, 1, { type = 10, content = "-# <@&" .. cfg.REVIEW_PING .. ">" })
		payload.allowed_mentions = { parse = {}, roles = { cfg.REVIEW_PING } }
		local okSend, msg, err = pcall(channel.send, channel, payload)
		if not okSend then err, msg = msg, nil end
		if not msg then
			print("[scrp] could not post " .. cfg.kind .. " application card: " .. tostring(err) .. ", trying plain fallback")
			-- fallback: classic embed plus the answers file, so an application is never lost
			local fb = dmStyle.buildEmbed(opts)
			fb.content = "<@&" .. cfg.REVIEW_PING .. ">"
			fb.allowed_mentions = { parse = {}, roles = { cfg.REVIEW_PING } }
			fb.files = opts.files
			fb.components = { { type = 1, components = dmStyle.buttons(opts.buttons) } }
			local ok2, m2, e2 = pcall(channel.send, channel, fb)
			if ok2 and m2 then msg = m2 else err = tostring(err) .. " / fallback: " .. tostring(ok2 and e2 or m2) end
		end
		if not msg then
			print("[scrp] could not post " .. cfg.kind .. " application: " .. tostring(err))
			store[interaction.user.id] = p -- keep the answers so pressing Continue again can retry
			p.at = os.time()
			return mia:reply(dmStyle.build({ guild = guild, title = "Application not sent", intro = "Your application couldn't be sent. Press **Continue to part " .. #cfg.PAGES .. "** again in a minute to retry, or tell a staff member.", footer = cfg.footer }), true)
		end

		local s = state(guild.id, cfg)
		s.pending[interaction.user.id] = os.time()
		s.apps = s.apps or {}
		s.apps[interaction.user.id] = { answers = answers, msg = msg.id, at = os.time() }
		saveState(guild.id, s, interaction.user, cfg)

		mia:reply(dmStyle.build({
			guild = guild,
			title = "Application sent",
			intro = cfg.kind == "hr"
				and "Your High Rank application is in. Senior High Rank will review it and you'll get a DM with the result. Please don't ask about it in the meantime."
				or "Your application is in. The High Rank team will review it and you'll get a DM with the result. Please don't ask staff about it in the meantime.",
			footer = cfg.footer,
		}), true)
	end)
end

local function decide(interaction, userId, accepted, reason, cfg)
	local guild = interaction.guild
	local s = state(guild.id, cfg)
	local app = s.apps and s.apps[userId]
	local user = Client:getUser(userId)
	local member = guild:getMember(userId)
	local answers = (app and app.answers) or {}
	local hr = cfg.kind == "hr"

	local decision = (accepted and "Accepted" or "Denied") .. " by " .. interaction.member.name .. " on " .. os.date("!%B %d, %Y")
		.. ((not accepted and reason and reason ~= "") and (". Reason: " .. reason) or "")
	if user then
		local card = dmStyle.build(reviewCard(guild, user, answers, cfg, decision))
		Client._api:editMessage(interaction.channel.id, interaction.message.id, { flags = card.flags, components = card.components, allowed_mentions = card.allowed_mentions })
	end

	s.pending[userId] = nil
	if s.apps then s.apps[userId] = nil end
	if not accepted then s.cooldowns[userId] = os.time() + cfg.COOLDOWN end
	saveState(guild.id, s, interaction.user, cfg)

	if accepted and member and cfg.PASS_ROLE then
		member:addRole(cfg.PASS_ROLE, cfg.name .. " accepted by " .. interaction.user.username)
	end

	if user then
		if accepted then
			dmStyle.send(user, {
				guild = guild,
				title = "Your " .. cfg.name .. " was accepted",
				intro = hr
					and ("Congrats! Your High Rank application for **" .. dmStyle.serverName(guild) .. "** was accepted. Senior High Rank will reach out about your new rank and what comes next.")
					or ("Congrats! Your application for **" .. dmStyle.serverName(guild) .. "** staff was accepted. You now have Awaiting Training, and a trainer will reach out to set up your training. Keep an eye on the trainee channels."),
				footer = cfg.footer,
			})
		else
			dmStyle.send(user, {
				guild = guild,
				title = "Your " .. cfg.name .. " was denied",
				intro = hr
					and ("Thanks for applying for High Rank in **" .. dmStyle.serverName(guild) .. "**. This time your application was denied.")
					or ("Thanks for applying to **" .. dmStyle.serverName(guild) .. "** staff. This time your application was denied."),
				fields = { { "Reason", (reason and reason ~= "" and reason) or "No reason given" }, { "Apply again", dmStyle.time(s.cooldowns[userId], "R") } },
				footer = cfg.footer,
			})
		end
	end

	local results = guild:getChannel(cfg.RESULTS_CHANNEL)
	if results then
		dmStyle.post(results, {
			guild = guild,
			title = (hr and "HR application " or "Application ") .. (accepted and "accepted" or "denied"),
			intro = "<@" .. userId .. ">'s " .. cfg.name .. " was " .. (accepted
				and (hr and "accepted. Congrats on High Rank." or "accepted. Welcome to the team, training is next.")
				or "denied. You can apply again after the cooldown."),
			fields = { { "Reviewed by", interaction.member.mentionString }, { "Date", dmStyle.time(os.time()) } },
			color = accepted and 0x66FF66 or 0xFF6666,
			footer = cfg.footer,
		}, userId)
	end
end

local function onReview(interaction, userId, accepted, cfg)
	if not isReviewer(interaction.member, cfg) then
		return interaction:fail(cfg.kind == "hr" and "Only Senior High Rank and above can review HR applications." or "Only High Rank and above can review applications.", nil, true)
	end
	if accepted then
		interaction:updateDeferred()
		decide(interaction, userId, true, nil, cfg)
	else
		prompt(interaction, "Deny application", {
			{ question = "Reason (sent to the applicant)", placeholder = "Optional, but it helps them improve", style = "paragraph", required = false, max = 500 },
		}, function(mia, responses)
			mia:updateDeferred(true)
			decide(interaction, userId, false, responses["Reason (sent to the applicant)"], cfg)
		end)
	end
end

local function onInteraction(interaction)
	if not interaction.guild or interaction.guild.id ~= A.GUILD_ID or not interaction.data then return end
	local cfg, action, userId = A.parseId(interaction.data.custom_id)
	if not cfg or not interaction.member then return end
	if action == "start" then return onApply(interaction, cfg) end
	if action == "next" then return onNext(interaction, cfg) end
	if action == "acc" then return onReview(interaction, userId, true, cfg) end
	if action == "deny" then return onReview(interaction, userId, false, cfg) end
end

scrp.Start = function()
	connections.join = { "memberJoin", Client:on("memberJoin", safe("join", onJoin)) }
	connections.update = { "memberUpdate", Client:on("memberUpdate", safe("update", onUpdate)) }
	connections.ia = { "interactionCreate", Client:on("interactionCreate", function(interaction)
		coroutine.wrap(safe("interaction", onInteraction))(interaction)
	end) }
end

scrp.Stop = function()
	for _, con in pairs(connections) do Client:removeListener(con[1], con[2]) end
	connections = {}
end

return scrp
