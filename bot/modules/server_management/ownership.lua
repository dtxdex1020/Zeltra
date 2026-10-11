--[[
	Zeltra ownership applications (added by Zeltra; not part of upstream Ducky V1, which has no
	application system).

	/ownership apply opens a private (ephemeral) panel. The applicant fills in 5 short forms (modals,
	5 questions max each, chained with Continue buttons). Answers are kept in memory until the last
	form is sent, then posted as cards to the private review channel with Accept / Deny buttons that
	only the owners can use. The applicant gets the decision by DM. Accepting does not give any role.

	Settings: guild config key `ownershipapps` (see libs/zeltra-ownership-core.lua).
	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local ownership = {
	name = "ownership",
	description = "Ownership applications."
}

local O = _G.ownershipCore
local connections = {}
local drafts = {}

local FOOTER = "Ownership Applications"
local SECTION_ICONS = { ["Definitions"] = "📘", ["Scenarios"] = "🧭", ["About you"] = "🙋" }

local function now() return os.time() end

local function getConf(guild)
	local config = sqldb:get(guild.id) or {}
	return O.withDefaults(config.ownershipapps)
end

local function saveConf(guild, conf, reason)
	return sqldb:set(guild.id, { ownershipapps = conf }, reason or "OWNERSHIP_APPS")
end

local function draftKey(guild, user) return guild.id .. ":" .. user.id end

local function getDraft(guild, user)
	local key = draftKey(guild, user)
	local d = drafts[key]
	if d and now() - d.updated > O.DRAFT_TTL then
		drafts[key] = nil
		d = nil
	end
	return d
end

---------------------------------------------------------------- access
local function meetsMinRole(member, conf)
	if not conf.minrole then return true end
	if _G.isPrivileged and isPrivileged(member) then return true end
	local role = member.guild:getRole(conf.minrole)
	if not role then return true end
	local top = member.highestRole
	if top and top.position >= role.position then return true end
	return false, role
end

---------------------------------------------------------------- applicant panel
local function panel(guild, opts)
	opts.guild = guild
	opts.footer = FOOTER
	return dmStyle.build(opts)
end

local function progressPanel(guild, done, nextForm)
	local total = #O.FORMS
	local form = O.FORMS[nextForm]
	return panel(guild, {
		icon = "📝", title = "Saved, " .. done .. " of " .. total .. " done",
		intro = "Next up: **" .. form.title .. "**.",
		note = "Your answers are saved for 2 hours. If this message goes away, run `/ownership apply` again to pick up where you left off.",
		buttons = {
			{ label = "Continue", custom_id = "ownapp:form:" .. nextForm, style = 1, emoji = "➡️" },
			{ label = "Cancel", custom_id = "ownapp:cancel", style = 2 },
		},
	})
end

local function startPanel(guild, resumeAt)
	local fields = {
		{ "Sections", "Definitions · Scenarios · About you" },
		{ "Questions", O.QUESTION_COUNT .. " across " .. #O.FORMS .. " short forms" },
		{ "Time", "About 20 to 30 minutes" },
		{ "Reviewed by", "The owners, in a private channel" },
	}
	return panel(guild, {
		icon = "📝", title = "Ownership Application",
		intro = (resumeAt and ("Welcome back. You've finished **" .. (resumeAt - 1) .. " of " .. #O.FORMS .. "** forms, so you'll pick up at **" .. O.FORMS[resumeAt].title .. "**."))
			or ("Thanks for your interest in ownership at **" .. dmStyle.serverName(guild) .. "**. Answer in your own words; there are no trick questions."),
		fields = fields,
		note = "Each form saves when you press Submit. Copy longer answers somewhere first in case Discord closes the form.",
		buttons = {
			{ label = resumeAt and "Continue" or "Start", custom_id = "ownapp:form:" .. (resumeAt or 1), style = 1, emoji = "📝" },
			{ label = "Cancel", custom_id = "ownapp:cancel", style = 2 },
		},
	})
end

local function updateOrReply(interaction, payload)
	local ok = interaction.message and interaction:update(payload)
	if not ok then
		interaction:reply(payload, true)
	end
end

--- /ownership apply
local function start(interaction)
	local guild, member = interaction.guild, interaction.member
	local conf = getConf(guild)

	if not conf.enabled then
		return interaction:fail("Ownership applications are closed right now.", nil, true)
	end
	if not conf.channel or not guild:getChannel(conf.channel) then
		return interaction:fail("Ownership applications aren't set up yet. Ask an owner to set a review channel.", nil, true)
	end
	local okRole, role = meetsMinRole(member, conf)
	if not okRole then
		return interaction:fail("You need the " .. role.mentionString .. " role or higher to apply for ownership.", nil, true)
	end
	local ok, reason = O.eligibility(conf.apps[member.id], now(), conf.cooldowndays)
	if not ok then
		return interaction:fail(reason, nil, true)
	end

	local d = getDraft(guild, member.user)
	if d then
		return interaction:reply(startPanel(guild, O.nextForm(d.answers) or #O.FORMS), true)
	end
	drafts[draftKey(guild, member.user)] = { answers = {}, started = now(), updated = now() }
	return interaction:reply(startPanel(guild), true)
end

---------------------------------------------------------------- review channel
local function countInfractions(guild, userId)
	local config = sqldb:get(guild.id) or {}
	local total, active = 0, 0
	for _, inf in pairs(config.infractions or {}) do
		if inf.user == userId then
			total = total + 1
			if not inf.expires or inf.expires > now() then active = active + 1 end
		end
	end
	return total, active
end

local function roleList(member)
	local roles = {}
	for role in member.roles:iter() do table.insert(roles, role) end
	table.sort(roles, function(a, b) return a.position > b.position end)
	local out = {}
	for i, role in ipairs(roles) do
		if i > 8 then
			table.insert(out, "+" .. (#roles - 8) .. " more")
			break
		end
		table.insert(out, role.mentionString)
	end
	return (#out > 0 and table.concat(out, " ")) or "No roles yet"
end

local function decisionCard(guild, userId, record)
	local opts = { guild = guild, footer = FOOTER }
	if record.status == "pending" then
		opts.icon = "🗳️"
		opts.title = "Waiting for a decision"
		opts.intro = "Application from <@" .. userId .. ">, sent " .. dmStyle.time(record.submitted, "R") .. "."
		opts.note = "Only the owners can use these buttons. Accepting doesn't give any roles, so give ownership roles by hand."
		opts.buttons = {
			{ label = "Accept", custom_id = "ownapp:decide:accept:" .. userId, style = 3, emoji = "✅" },
			{ label = "Deny", custom_id = "ownapp:decide:deny:" .. userId, style = 4, emoji = "✖️" },
		}
	else
		local accepted = record.status == "accepted"
		opts.icon = accepted and "✅" or "✖️"
		opts.title = accepted and "Application accepted" or "Application denied"
		opts.intro = "<@" .. userId .. ">'s application was " .. (accepted and "accepted" or "denied") .. "."
		opts.fields = {
			{ "Decided by", "<@" .. tostring(record.by) .. ">" },
			{ "Decided", dmStyle.time(record.decided) },
			{ "Reason", record.reason or "No reason given" },
			{ "Applicant DM", record.dm or "Not sent" },
		}
		opts.note = accepted and "No roles were changed. Give ownership roles by hand." or
			("They can apply again " .. dmStyle.time((record.decided or now()) + (record.cooldowndays or 14) * 86400, "R") .. ".")
	end
	return dmStyle.build(opts)
end

local function postApplication(guild, member, answers, conf)
	local channel = guild:getChannel(conf.channel)
	if not channel then return nil, "review channel is missing" end
	local user = member.user
	local created = user.createdAt
	local total, active = countInfractions(guild, member.id)
	local joined = member.joinedAt and math.floor(discordia.Date.parseISO(member.joinedAt))

	local header = dmStyle.post(channel, {
		guild = guild, icon = "📝", title = "Ownership application",
		intro = user.mentionString .. " applied for ownership in **" .. dmStyle.serverName(guild) .. "**.",
		fields = {
			{ "Applicant", user.mentionString .. " · @" .. user.username .. " (`" .. user.id .. "`)" },
			{ "Account created", dmStyle.time(created, "D") .. " (" .. O.humanAge(now() - created) .. " old)" },
			{ "Joined server", joined and (dmStyle.time(joined, "D") .. " (" .. O.humanAge(now() - joined) .. " ago)") or "Unknown" },
			{ "Staff", member:hasRole(O.STAFF_ROLE) and "Yes" or "No, community member" },
			{ "Roles", roleList(member) },
			{ "Infractions", total .. " total · " .. active .. " active" },
			{ "Age", answers.age },
			{ "Timezone", answers.timezone },
			{ "Hours a week", answers.hours },
			{ "Submitted", dmStyle.time(now()) },
		},
		footer = FOOTER,
	})
	if not header then return nil, "could not post to the review channel" end

	for _, card in ipairs(O.answerCards(answers)) do
		dmStyle.post(channel, {
			guild = guild, icon = SECTION_ICONS[card.title:gsub(" %(continued%)", "")] or "📝",
			title = card.title, sections = card.sections, footer = FOOTER,
		})
	end

	local record = { status = "pending", submitted = now() }
	local msg = channel:send(decisionCard(guild, user.id, record))
	if not msg then return nil, "could not post the decision buttons" end
	record.message = msg.id
	record.channel = channel.id
	record.header = header.id
	return record
end

---------------------------------------------------------------- interactions
local function reasonModal(action, userId)
	return {
		custom_id = "ownapp:reason:" .. action .. ":" .. userId,
		title = (action == "accept") and "Accept application" or "Deny application",
		components = {
			{
				type = 18, label = "Reason (optional)",
				description = "The applicant sees this in their DM.",
				component = { type = 4, custom_id = "reason", style = 2, required = false, max_length = 900 },
			},
		},
	}
end

local function decide(interaction, action, userId, reason)
	local guild = interaction.guild
	local conf = getConf(guild)
	local record = conf.apps[userId]
	if not record or record.status ~= "pending" then
		return interaction:reply({ content = "This application was already decided.", allowed_mentions = { parse = {} } }, true)
	end
	-- acknowledge first: the DM and database write can take longer than Discord's 3 second window
	local deferred = interaction.message and interaction:updateDeferred()

	record.status = (action == "accept") and "accepted" or "denied"
	record.decided = now()
	record.by = interaction.user.id
	record.reason = (reason and reason:match("%S")) and reason or nil
	record.cooldowndays = conf.cooldowndays

	local accepted = action == "accept"
	local target = Client:getUser(userId)
	local sent, err = dmStyle.send(target, {
		guild = guild,
		icon = accepted and "✅" or "📝",
		title = accepted and "Your ownership application was accepted" or "Your ownership application was denied",
		intro = accepted and ("Congratulations, your ownership application in **" .. dmStyle.serverName(guild) .. "** was accepted. An owner will reach out about next steps.")
			or ("Thanks for applying for ownership in **" .. dmStyle.serverName(guild) .. "**. This time your application was denied."),
		fields = {
			{ "Reason", record.reason },
			{ "Decided", dmStyle.time(record.decided) },
		},
		note = (not accepted) and ("You can apply again " .. dmStyle.time(record.decided + conf.cooldowndays * 86400, "R") .. ".") or nil,
		footer = FOOTER,
	})
	record.dm = sent and "Sent" or ((tostring(err):find("50007") and "Couldn't DM (their DMs are closed)") or "Couldn't DM")

	conf.apps[userId] = record
	saveConf(guild, conf, accepted and "OWNERSHIP_APP_ACCEPT" or "OWNERSHIP_APP_DENY")
	local card = decisionCard(guild, userId, record)
	local edited = deferred and interaction:editReply(card)
	if not edited and record.channel and record.message then
		edited = Client._api:editMessage(record.channel, record.message, card)
	end
	if not deferred then
		interaction:reply({ content = "Application " .. record.status .. ". Applicant DM: " .. record.dm .. "." }, true)
	end
	print("[ownership] application from " .. userId .. " " .. record.status .. " by " .. interaction.user.id .. " (DM: " .. record.dm .. ")")
end

local function onInteraction(interaction)
	local data = interaction.data
	local id = data and data.custom_id
	if type(id) ~= "string" or id:sub(1, 7) ~= "ownapp:" then return end
	local guild, member = interaction.guild, interaction.member
	if not guild or not member then return end

	local parts = {}
	for p in id:gmatch("[^:]+") do table.insert(parts, p) end
	local action = parts[2]

	if action == "form" then
		local n = tonumber(parts[3])
		local d = getDraft(guild, member.user)
		if not d then
			return interaction:reply({ content = "This application timed out. Run `/ownership apply` to start again." }, true)
		end
		local modal = O.modal(n, d.answers)
		if not modal then return end
		return interaction:modal(modal)

	elseif action == "submit" then
		local n = tonumber(parts[3])
		local d = getDraft(guild, member.user)
		if not d then
			return interaction:reply({ content = "This application timed out. Run `/ownership apply` to start again." }, true)
		end
		for k, v in pairs(O.parseModal(data)) do
			if O.BY_ID[k] then d.answers[k] = v end
		end
		d.updated = now()

		if d.answers.age then
			local age = O.parseAge(d.answers.age)
			if not age then
				d.answers.age = nil
				return updateOrReply(interaction, panel(guild, {
					icon = "📝", title = "Please enter your age as a number",
					buttons = { { label = "Try again", custom_id = "ownapp:form:" .. n, style = 1 } },
				}))
			elseif age < 13 then
				drafts[draftKey(guild, member.user)] = nil
				return updateOrReply(interaction, panel(guild, {
					icon = "📝", title = "Application not sent",
					intro = "You need to be 13 or older to apply for ownership.",
				}))
			end
		end

		local nextForm = O.nextForm(d.answers)
		if nextForm then
			return updateOrReply(interaction, progressPanel(guild, nextForm - 1, nextForm))
		end

		-- all forms done: send it
		local conf = getConf(guild)
		local ok, reason = O.eligibility(conf.apps[member.id], now(), conf.cooldowndays)
		if not ok then
			drafts[draftKey(guild, member.user)] = nil
			return updateOrReply(interaction, panel(guild, { icon = "📝", title = "Application not sent", intro = reason }))
		end
		interaction:updateDeferred()
		local record, err = postApplication(guild, member, d.answers, conf)
		if not record then
			print("[ownership] could not post application for " .. member.id .. ": " .. tostring(err))
			return interaction:editReply(panel(guild, {
				icon = "📝", title = "Something went wrong",
				intro = "Your answers couldn't be sent to the owners. They're still saved for 2 hours, so try again shortly.",
				buttons = { { label = "Try again", custom_id = "ownapp:form:" .. #O.FORMS, style = 1 } },
			}))
		end
		conf.apps[member.id] = record
		saveConf(guild, conf, "OWNERSHIP_APP_SUBMIT")
		drafts[draftKey(guild, member.user)] = nil
		print("[ownership] application from " .. member.id .. " posted to " .. record.channel)
		return interaction:editReply(panel(guild, {
			icon = "✅", title = "Application sent",
			intro = "Thanks for applying. The owners will read your answers and you'll get a DM with their decision.",
			note = "Make sure your DMs from server members are open so the decision reaches you.",
		}))

	elseif action == "cancel" then
		drafts[draftKey(guild, member.user)] = nil
		return updateOrReply(interaction, panel(guild, {
			icon = "📝", title = "Application cancelled",
			intro = "Nothing was sent. You can start again any time with `/ownership apply`.",
		}))

	elseif action == "decide" or action == "reason" then
		if not (O.isOwner(interaction.user.id) or (_G.isBotOwner and isBotOwner(interaction.user))) then
			return interaction:reply({ content = "Only the owners can decide on ownership applications." }, true)
		end
		local verdict, userId = parts[3], parts[4]
		if (verdict ~= "accept" and verdict ~= "deny") or not userId then return end
		if action == "decide" then
			local conf = getConf(guild)
			local record = conf.apps[userId]
			if not record or record.status ~= "pending" then
				return interaction:reply({ content = "This application was already decided." }, true)
			end
			return interaction:modal(reasonModal(verdict, userId))
		end
		local values = O.parseModal(data)
		return decide(interaction, verdict, userId, values.reason)
	end
end

ownership.Start = function()
	_G.zeltraOwnership = {
		start = start, getConf = getConf, saveConf = saveConf, drafts = drafts,
		decisionCard = decisionCard, startPanel = startPanel, progressPanel = progressPanel,
	}
	connections.interaction = { "interactionCreate", Client:on("interactionCreate", function(interaction)
		coroutine.wrap(function()
			local ok, err = pcall(onInteraction, interaction)
			if not ok then print("[ownership] interaction error: " .. tostring(err)) end
		end)()
	end) }
end

ownership.Stop = function()
	for _, con in pairs(connections) do
		Client:removeListener(con[1], con[2])
	end
	connections = {}
end

return ownership
