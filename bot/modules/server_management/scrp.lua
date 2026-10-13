-- modules/server_management/scrp.lua
-- Zeltra (AGPL-3.0, see NOTICE.md): South Carolina Roleplay extras, not part of upstream Ducky V1.
--   * join roles: Community Member and Unverified for everyone who joins
--   * verification: once a member has the Verified role (Bloxlink), Unverified is removed right away
--   * staff applications: Apply button -> two modals -> review card with Accept / Deny -> DM and results post
-- Settings and questions: libs/zeltra-staffapp-scrp.lua
local A = _G.scrpStaffApp

local scrp = {
	name = "scrp",
	description = "South Carolina Roleplay join roles, verification cleanup and staff applications."
}

local connections = {}
local partial = {} -- [userId] = { at = os.time(), answers = {...} } between the two modals

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

---------------------------------------------------------------- staff applications
local function state(guildId)
	local config = sqldb:get(guildId) or {}
	local s = type(config.scrpapps) == "table" and config.scrpapps or {}
	s.cooldowns = s.cooldowns or {}
	s.pending = s.pending or {}
	return s
end

local function saveState(guildId, s, user)
	sqldb:set(guildId, { scrpapps = s }, "SCRP_STAFF_APP", user)
end

local function isReviewer(member)
	if not member then return false end
	if member:hasPermission("administrator") then return true end
	local role = member.guild:getRole(A.REVIEWER_ROLE)
	return role and member.highestRole and member.highestRole.position >= role.position
end

local function short(s, n)
	s = tostring(s or ""):gsub("\r", "")
	if #s > n then return s:sub(1, n - 3) .. "..." end
	return s
end

local function allQuestions()
	local out = {}
	for _, page in ipairs(A.PAGES) do
		for _, q in ipairs(page.questions) do out[#out + 1] = q end
	end
	return out
end

local function transcript(user, answers)
	local lines = { "Staff application from @" .. user.username .. " (" .. user.id .. ")", "Submitted " .. os.date("!%Y-%m-%d %H:%M UTC"), "" }
	for _, q in ipairs(allQuestions()) do
		lines[#lines + 1] = q.question
		lines[#lines + 1] = tostring(answers[q.key] or "No answer")
		lines[#lines + 1] = ""
	end
	return table.concat(lines, "\n")
end

local function reviewCard(guild, user, answers, decision)
	local sections = {}
	for _, q in ipairs(allQuestions()) do
		if answers[q.key] and answers[q.key] ~= "" then
			sections[#sections + 1] = { title = q.question, body = short(answers[q.key], 300) }
		end
	end
	local opts = {
		guild = guild,
		title = "Staff application",
		intro = "New application from <@" .. user.id .. ">. The full answers are in the attached file.",
		fields = {
			{ "Applicant", "<@" .. user.id .. "> (`" .. user.id .. "`)" },
			{ "Roblox", answers.roblox },
			{ "Account created", user.createdAt and dmStyle.time(math.floor(user.createdAt), "R") },
		},
		sections = sections,
		footer = "Staff Applications",
	}
	if decision then
		opts.note = decision
	else
		opts.buttons = {
			{ label = "Accept", custom_id = "scrpapp_acc_" .. user.id, style = 3 },
			{ label = "Deny", custom_id = "scrpapp_deny_" .. user.id, style = 4 },
		}
	end
	return opts
end

local function onApply(interaction)
	local guild = interaction.guild
	local ok, why = A.canApply(state(guild.id), interaction.user.id, os.time())
	if not ok then return interaction:fail(why, nil, true) end

	prompt(interaction, A.PAGES[1].title, A.questions(1), function(mia, responses)
		local answers = {}
		for _, q in ipairs(A.PAGES[1].questions) do answers[q.key] = responses[q.question] end
		partial[interaction.user.id] = { at = os.time(), answers = answers }
		mia:reply(dmStyle.build({
			guild = guild,
			title = "Part 1 saved",
			intro = "Thanks. Press the button below for the second and last part of the application.",
			buttons = { { label = "Continue to part 2", custom_id = "scrpapp_next", style = 1 } },
			footer = "Staff Applications",
		}), true)
	end)
end

local function onNext(interaction)
	local guild = interaction.guild
	local p = partial[interaction.user.id]
	if not p or os.time() - p.at > 1800 then
		partial[interaction.user.id] = nil
		return interaction:fail("Your first part expired. Press Apply in the applications channel to start again.", nil, true)
	end

	prompt(interaction, A.PAGES[2].title, A.questions(2), function(mia, responses)
		local answers = p.answers
		for _, q in ipairs(A.PAGES[2].questions) do answers[q.key] = responses[q.question] end
		partial[interaction.user.id] = nil
		-- acknowledge within Discord's 3 second limit; posting the review card with its file can take longer
		pcall(function() mia:replyDeferred(true) end)

		local channel = guild:getChannel(A.REVIEW_CHANNEL)
		if not channel then return mia:fail("Applications can't be sent right now. Please tell a staff member.", nil, true) end

		local opts = reviewCard(guild, interaction.user, answers)
		opts.files = { { "application-" .. interaction.user.id .. ".txt", transcript(interaction.user, answers) } }
		opts.file = "application-" .. interaction.user.id .. ".txt"
		local payload = dmStyle.build(opts)
		table.insert(payload.components, 1, { type = 10, content = "-# <@&" .. A.REVIEW_PING .. ">" })
		payload.allowed_mentions = { parse = {}, roles = { A.REVIEW_PING } }
		local okSend, msg, err = pcall(channel.send, channel, payload)
		if not okSend then err, msg = msg, nil end
		if not msg then
			print("[scrp] could not post application card: " .. tostring(err) .. ", trying plain fallback")
			-- fallback: classic embed plus the answers file, so an application is never lost
			local fb = dmStyle.buildEmbed(opts)
			fb.content = "<@&" .. A.REVIEW_PING .. ">"
			fb.allowed_mentions = { parse = {}, roles = { A.REVIEW_PING } }
			fb.files = opts.files
			fb.components = { { type = 1, components = dmStyle.buttons(opts.buttons) } }
			local ok2, m2, e2 = pcall(channel.send, channel, fb)
			if ok2 and m2 then msg = m2 else err = tostring(err) .. " / fallback: " .. tostring(ok2 and e2 or m2) end
		end
		if not msg then
			print("[scrp] could not post application: " .. tostring(err))
			partial[interaction.user.id] = p -- keep the answers so pressing Continue again can retry
			p.at = os.time()
			return mia:reply(dmStyle.build({ guild = guild, title = "Application not sent", intro = "Your application couldn't be sent. Press **Continue to part 2** again in a minute to retry, or tell a staff member.", footer = "Staff Applications" }), true)
		end

		local s = state(guild.id)
		s.pending[interaction.user.id] = os.time()
		s.apps = s.apps or {}
		s.apps[interaction.user.id] = { answers = answers, msg = msg.id, at = os.time() }
		saveState(guild.id, s, interaction.user)

		mia:reply(dmStyle.build({
			guild = guild,
			title = "Application sent",
			intro = "Your application is in. The High Rank team will review it and you'll get a DM with the result. Please don't ask staff about it in the meantime.",
			footer = "Staff Applications",
		}), true)
	end)
end

local function decide(interaction, userId, accepted, reason)
	local guild = interaction.guild
	local s = state(guild.id)
	local app = s.apps and s.apps[userId]
	local user = Client:getUser(userId)
	local member = guild:getMember(userId)
	local answers = (app and app.answers) or {}

	local decision = (accepted and "Accepted" or "Denied") .. " by " .. interaction.member.name .. " on " .. os.date("!%B %d, %Y")
		.. ((not accepted and reason and reason ~= "") and (". Reason: " .. reason) or "")
	if user then
		local card = dmStyle.build(reviewCard(guild, user, answers, decision))
		Client._api:editMessage(interaction.channel.id, interaction.message.id, { flags = card.flags, components = card.components, allowed_mentions = card.allowed_mentions })
	end

	s.pending[userId] = nil
	if s.apps then s.apps[userId] = nil end
	if not accepted then s.cooldowns[userId] = os.time() + A.COOLDOWN end
	saveState(guild.id, s, interaction.user)

	if accepted and member then
		member:addRole(A.PASS_ROLE, "staff application accepted by " .. interaction.user.username)
	end

	if user then
		if accepted then
			dmStyle.send(user, {
				guild = guild,
				title = "Your staff application was accepted",
				intro = "Congrats! Your application for **" .. dmStyle.serverName(guild) .. "** staff was accepted. You now have Awaiting Training, and a trainer will reach out to set up your training. Keep an eye on the trainee channels.",
				footer = "Staff Applications",
			})
		else
			dmStyle.send(user, {
				guild = guild,
				title = "Your staff application was denied",
				intro = "Thanks for applying to **" .. dmStyle.serverName(guild) .. "** staff. This time your application was denied.",
				fields = { { "Reason", (reason and reason ~= "" and reason) or "No reason given" }, { "Apply again", dmStyle.time(s.cooldowns[userId], "R") } },
				footer = "Staff Applications",
			})
		end
	end

	local results = guild:getChannel(A.RESULTS_CHANNEL)
	if results then
		dmStyle.post(results, {
			guild = guild,
			title = accepted and "Application accepted" or "Application denied",
			intro = "<@" .. userId .. ">'s staff application was " .. (accepted and "accepted. Welcome to the team, training is next." or "denied. You can apply again after the cooldown."),
			fields = { { "Reviewed by", interaction.member.mentionString }, { "Date", dmStyle.time(os.time()) } },
			color = accepted and 0x66FF66 or 0xFF6666,
			footer = "Staff Applications",
		}, userId)
	end
end

local function onReview(interaction, userId, accepted)
	if not isReviewer(interaction.member) then
		return interaction:fail("Only High Rank and above can review applications.", nil, true)
	end
	if accepted then
		interaction:updateDeferred()
		decide(interaction, userId, true)
	else
		prompt(interaction, "Deny application", {
			{ question = "Reason (sent to the applicant)", placeholder = "Optional, but it helps them improve", style = "paragraph", required = false, max = 500 },
		}, function(mia, responses)
			mia:updateDeferred(true)
			decide(interaction, userId, false, responses["Reason (sent to the applicant)"])
		end)
	end
end

local function onInteraction(interaction)
	if not interaction.guild or interaction.guild.id ~= A.GUILD_ID or not interaction.data then return end
	local id = interaction.data.custom_id
	if type(id) ~= "string" or id:sub(1, 8) ~= "scrpapp_" then return end
	if not interaction.member then return end
	if id == "scrpapp_start" then return onApply(interaction) end
	if id == "scrpapp_next" then return onNext(interaction) end
	local acc = id:match("^scrpapp_acc_(%d+)$")
	if acc then return onReview(interaction, acc, true) end
	local deny = id:match("^scrpapp_deny_(%d+)$")
	if deny then return onReview(interaction, deny, false) end
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
