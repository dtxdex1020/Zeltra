-- tickets.lua
-- Zeltra changes (AGPL-3.0, see NOTICE.md): ticket channels are created with their permissions in one call
-- (category overwrites + @everyone hidden + support roles/users + opener), {ticket.number} gives zero padded
-- names like general-0001, pings are limited to the opener and the subject's mentionables, and the Web
-- Transcript button is only shown when a web URL is configured.

local tickets = {
	name = "tickets",
	description = "Powers tickets.",
}

local connections = {}

tickets.Start = function()
	local function isSubjectSupport(member, subject)
		local isSupport = false

		for i, v in pairs(subject.support or {}) do
			if (member:hasPermission("manageGuild") == true) or (member:hasRole(v)) then
				isSupport = true
				break
			end
		end

		return isSupport
	end

	_G.isSubjectSupport = isSubjectSupport

	-- Zeltra: view, send, embed links, attach files, read history, add reactions
	local TICKET_ACCESS = 1024 + 2048 + 16384 + 32768 + 65536 + 64
	local VIEW = 1024

	-- permission values can be above 2^32 and LuaJIT's bit ops are 32-bit, so only touch the low 20 bits
	-- (every bit we set is below 2^17) and keep the rest as plain arithmetic
	local LOW = 2 ^ 20
	local function setLow(v, on, off)
		v = tonumber(v) or 0
		local hi, lo = math.floor(v / LOW), v % LOW
		if on then lo = bit.bor(lo, on) end
		if off then lo = bit.band(lo, bit.bnot(off)) % LOW end
		return hi * LOW + lo
	end
	local function hasWebTranscripts()
		return not tostring(_G.ZELTRA_WEB_URL or ""):find("#web-features", 1, true)
	end
	local function ticketNumber(n)
		return string.format("%04d", tonumber(n) or 0)
	end

	--- Overwrites for a new ticket channel: the category's, then @everyone hidden, support roles/users and the opener allowed.
	local function ticketOverwrites(guild, category, subject, member)
		local list, index = {}, {}
		local function put(id, t, allow, deny)
			id = tostring(id)
			local o = index[id]
			if not o then
				o = { id = id, type = t, allow = "0", deny = "0" }
				index[id] = o
				table.insert(list, o)
			end
			local a, d = tonumber(o.allow) or 0, tonumber(o.deny) or 0
			if allow then a = setLow(a, allow) d = setLow(d, nil, allow) end
			if deny then d = setLow(d, deny) a = setLow(a, nil, deny) end
			o.allow, o.deny = string.format("%.0f", a), string.format("%.0f", d)
		end
		local raw = Client._api:getChannel(category.id)
		for _, o in ipairs((raw and raw.permission_overwrites) or {}) do
			local io = { id = o.id, type = o.type, allow = o.allow, deny = o.deny }
			index[o.id] = io
			table.insert(list, io)
		end
		put(guild.id, 0, nil, VIEW)
		for _, roleId in pairs(subject.support or {}) do put(roleId, 0, TICKET_ACCESS) end
		for _, userId in pairs(subject.supportusers or {}) do put(userId, 1, TICKET_ACCESS) end
		put(member.id, 1, TICKET_ACCESS)
		return list
	end
	_G.ticketOverwrites = ticketOverwrites

	--------------------------------------------------

	local ticketActions = discordia.Components()
	local claimButton = discordia.Button({
		id = "ticketclaim",
		label = "Claim",
		emoji = resolvedEmojis.ticket,
		style = "success",
		actionRow = 1,
	})

	ticketActions:button(claimButton)

	local closeButton = discordia.Button({
		id = "ticketclose",
		label = "Close",
		emoji = resolvedEmojis.nowhite,
		style = "danger",
		actionRow = 1,
	})

	ticketActions:button(closeButton)

	------------------------------------------------------

	local closedActions = discordia.Components()

	local transcriptButton = discordia.Button({
		id = "tickettranscript",
		label = "Transcript",
		style = "blurple",
		emoji = resolvedEmojis.document,
		actionRow = 1,
	})

	closedActions:button(transcriptButton)

	local deleteButton = discordia.Button({
		id = "ticketdelete",
		label = "Delete",
		style = "danger",
		emoji = resolvedEmojis.delete,
		actionRow = 1,
	})

	closedActions:button(deleteButton)

	table.insert(
		connections,
		{
			"interactionCreate",
			Client:on("interactionCreate", function(interaction)
				coroutine.wrap(function()
					if
						not interaction.guild
						or not interaction.data
						or not interaction.message
						or not interaction.message.id
						or not interaction.user
						or not interaction.member
						or not interaction.id
						or not interaction.data.custom_id
						or blacklisted(interaction.guild, interaction)
					then
						return
					end

					local id = interaction.data.custom_id
					local selection = interaction.data.values and interaction.data.values[1]

					if id == "subjectselect" then
						if selection then
							local status, updStat = nil, nil
							local config = sqldb:get(interaction.guild.id)
							if config then
								local panels = config.panels

								if panels then
									local panel = panels[interaction.message.id]

									if panel then
										if panel.disabled then
											return interaction:fail("This ticket panel has been disabled by server management.", nil, true)
										end

										local subject = panel.subjects[tonumber(selection)]

										if subject then
											for _, id in pairs(subject.blacklistedroles or {}) do
												if interaction.member:hasRole(id) then
													return interaction:fail("You are blacklisted from this ticket subject.", nil, true)
												end
											end

											local category = interaction.guild:getCategory(subject.category)

											if category then
												local responseMap = nil
												if
													subject.form
													and subject.form.questions
													and table.count(subject.form.questions) > 0
												then
													responseMap = {}

													local formData = {
														title = subject.name .. " Ticket",
														id = "preopenform" .. _G.junkStr(10),
													}

													for qid, q in pairs(subject.form.questions) do
														table.insert(
															formData,
															discordia.TextInput({
																id = tostring(qid),
																label = string.truncate(sanitizeUTF8(q.title), 45),
																style = q.style,
																required = q.required,
																min_length = q.min,
																max_length = q.max,
																placeholder = q.placeholder
																	and string.truncate(sanitizeUTF8(q.placeholder), 100),
															})
														)
														responseMap[q.title] = "N/A"
													end

													local preopenForm = discordia.Modal(formData)
													interaction:modal(preopenForm)

													local _, fia = Client:waitModal(formData.id, interaction.user.id)

													if not fia then
														return interaction:fail(
															"This form has timed out because you took to long.",
															nil,
															true
														)
													end

													if fia.data and fia.data.components then
														if
															fia.data.components[1]
															and fia.data.components[1].components
															and fia.data.components[1].components[1]
														then
															responseMap[subject.form.questions[1].title] =
																fia.data.components[1].components[1].value
														end
														if
															fia.data.components[2]
															and fia.data.components[2].components
															and fia.data.components[2].components[1]
														then
															responseMap[subject.form.questions[2].title] =
																fia.data.components[2].components[1].value
														end
														if
															fia.data.components[3]
															and fia.data.components[3].components
															and fia.data.components[3].components[1]
														then
															responseMap[subject.form.questions[3].title] =
																fia.data.components[3].components[1].value
														end
														if
															fia.data.components[4]
															and fia.data.components[4].components
															and fia.data.components[4].components[1]
														then
															responseMap[subject.form.questions[4].title] =
																fia.data.components[4].components[1].value
														end
														if
															fia.data.components[5]
															and fia.data.components[5].components
															and fia.data.components[5].components[1]
														then
															responseMap[subject.form.questions[5].title] =
																fia.data.components[5].components[1].value
														end
													end

													status = fia:reply({
														embed = {
															description = emojis.loading
																.. " Creating ticket channel...",
															color = colors.blank,
														},
													}, true)

													updStat = function(stat, state)
														if
															not status
															or (type(status) ~= "table")
															or not status.id
														then
															return
														end
														if state == "loading" then
															return fia:editReply({
																embed = {
																	description = emojis.loading .. " " .. stat,
																	color = colors.blank,
																},
															}, status.id)
														elseif state == "success" then
															return fia:editReply({
																embed = {
																	description = emojis.success .. " " .. stat,
																	color = colors.success,
																},
															}, status.id)
														elseif state == "fail" then
															return fia:editReply({
																embed = {
																	description = emojis.fail .. " " .. stat,
																	color = colors.fail,
																},
															}, status.id)
														else
															return fia:editReply({
																embed = {
																	description = stat,
																	color = colors.blank,
																},
															}, status.id)
														end
													end
												else
													status = interaction:reply({
														embed = {
															description = emojis.loading
																.. " Creating ticket channel...",
															color = colors.blank,
														},
													}, true)

													updStat = function(stat, state)
														if
															not status
															or (type(status) ~= "table")
															or not status.id
														then
															return
														end
														if state == "loading" then
															return interaction:editReply({
																embed = {
																	description = emojis.loading .. " " .. stat,
																	color = colors.blank,
																},
															}, status.id)
														elseif state == "success" then
															return interaction:editReply({
																embed = {
																	description = emojis.success .. " " .. stat,
																	color = colors.success,
																},
															}, status.id)
														elseif state == "fail" then
															return interaction:editReply({
																embed = {
																	description = emojis.fail .. " " .. stat,
																	color = colors.fail,
																},
															}, status.id)
														else
															return interaction:editReply({
																embed = {
																	description = stat,
																	color = colors.blank,
																},
															}, status.id)
														end
													end
												end

												local ticketid = config.panels[interaction.message.id].subjects[tonumber(
													selection
												)].nextticketid or 1
												local keys = {
													["member.name"] = interaction.member.name,
													["member.id"] = interaction.member.id,
													["member.username"] = interaction.user.username,
													["ticket.id"] = ticketid,
													["ticket.number"] = ticketNumber(ticketid),
												}
												config.panels[interaction.message.id].subjects[tonumber(selection)].nextticketid = ticketid
													+ 1

												-- Zeltra: create the channel with its permissions in one call so it is never visible to the wrong people
												local ticket, e
												do
													local ok, data, err = pcall(function()
														return Client._api:createGuildChannel(interaction.guild.id, {
															name = parseTable({ subject.ticketname }, keys)[1],
															type = 0,
															parent_id = category.id,
															permission_overwrites = ticketOverwrites(interaction.guild, category, subject, interaction.member),
														})
													end)
													if ok and data then
														ticket = interaction.guild._text_channels:_insert(data)
													else
														e = tostring((ok and err) or data or "unknown error")
													end
												end

												if ticket then
													updStat("Setting ticket data...", "loading")
													config.panels[interaction.message.id].subjects[tonumber(selection)].tickets = config.panels[interaction.message.id].subjects[tonumber(
														selection
													)].tickets or {}
													table.insert(
														config.panels[interaction.message.id].subjects[tonumber(
															selection
														)].tickets,
														{
															owner = interaction.user.id,
															channel = ticket.id,
															claimer = nil,
															id = ticketid,
														}
													)
													sqldb:set(
														interaction.guild.id,
														{ panels = config.panels },
														"TICKET_CREATE"
													)

													local mentionablestr = interaction.user.mentionString .. " "
													local pingUsers, pingRoles = { interaction.user.id }, {}

													for i, v in pairs(subject.mentionables or {}) do
														local isMember = interaction.guild:getMember(v)

														if isMember then
															mentionablestr = mentionablestr
																.. isMember.mentionString
																.. " "
															table.insert(pingUsers, isMember.id)
														else
															mentionablestr = mentionablestr .. "<@&" .. v .. "> "
															table.insert(pingRoles, tostring(v))
														end
													end

													local link = sqldb:getLink(interaction.member.id)
													local roblox = {
														name = emojis.fail,
														display = emojis.fail,
														id = emojis.fail,
														profile = emojis.fail,
														hyperlink = emojis.fail,
													}
													if link and link.roblox then
														local robloxUser = ropi.GetUser(link.roblox)
														if robloxUser then
															roblox = {
																name = robloxUser.name,
																display = robloxUser.displayName,
																id = tostring(robloxUser.id),
																profile = robloxUser.profile,
																hyperlink = robloxUser.hyperlink,
															}
														end
													end

													local tosend = parseTable(subject.embeds.open, {
														["opener.id"] = interaction.member.id,
														["opener.name"] = interaction.member.name,
														["opener.username"] = interaction.user.username,
														["opener.mention"] = interaction.member.mentionString,
														["roblox.name"] = roblox.name,
														["roblox.display"] = roblox.display,
														["roblox.id"] = roblox.id,
														["roblox.profile"] = roblox.profile,
														["roblox.hyperlink"] = roblox.hyperlink,
														["ticket.id"] = ticketid,
														["ticket.number"] = ticketNumber(ticketid),
														["timestamp"] = tostring(os.time()),
													})

													if responseMap and next(responseMap) then
														local emb = {
															color = colors.blank,
															fields = {},
															author = {
																name = interaction.member.name,
																icon_url = interaction.member.avatarURL,
															},
														}

														for question, response in pairs(responseMap) do
															table.insert(emb.fields, {
																name = string.truncate(question, 256),
																value = string.truncate(">>> ```" .. response:gsub("`", "") .. "```", 1024),
															})
														end

														table.insert(tosend, emb)
													end

													local openingmessage, err = ticket:send({
														content = "-# " .. emojis.pings .. " " .. mentionablestr,
														embeds = tosend,
														components = ticketActions:raw(),
														allowed_mentions = { parse = {}, users = pingUsers, roles = pingRoles },
													})

													if openingmessage then
														openingmessage:pin()
													else
														ticket:fail("Failed to send opening message: ```" .. err .. "```")
														Client:error("Failed to send ticket opening message:" .. err)
													end

													updStat(
														"Opened ticket successfully!\n-# "
															.. emojis.ticket
															.. " "
															.. ticket.mentionString,
														"success"
													)
												else

													local code = tostring(e):match("(%d+)")
													updStat(
														"Failed to create ticket channel.\n-# " .. emojis.right .. " " .. (code and errCodes[tonumber(code)]) or e,
														"fail"
													)
												end
											else
												interaction:fail("Could not find ticket category.", nil, true)
											end
										else
											interaction:fail("Could not find ticket subject.", nil, true)
										end
									else
										interaction:fail("Could not find ticket panel.", nil, true)
									end
								else
									interaction:fail("No panels exist in this server.", nil, true)
								end
							else
								interaction:fail("Server is not configured.", nil, true)
							end
						else
							interaction:updateDeferred(true)
						end
					elseif id == "ticketclose" then
						interaction.channel._delete_protection = true
						local config = sqldb:get(interaction.guild.id) or {}

						local panel = nil
						local panelindex = nil
						local subject = nil
						local subjectindex = nil
						local ticket = nil
						local ticketindex = nil

						for pi, v in pairs(config.panels or {}) do
							for si, s in pairs(v.subjects or {}) do
								for ti, t in pairs(s.tickets or {}) do
									if t.channel == interaction.channel.id then
										panel = config.panels[pi]
										panelindex = pi
										subject = panel.subjects[si]
										subjectindex = si
										ticket = subject.tickets[ti]
										ticketindex = ti
									end
								end
							end
						end

						if panel and subject and ticket then
							prompt(interaction, "Close Reason", {
								{
									question = "Why are you closing this ticket?",
									placeholder = "Enter an optional reason...",
									required = false,
									max_length = 500,
									style = "paragraph"
								}
							}, function(mia, responses)
								if mia then
									local ticketOwner = interaction.guild:getMember(ticket.owner) or Client:getUser(ticket.owner)
									local ticketClaimer = (ticket.claimer and (interaction.guild:getMember(ticket.claimer) or Client:getUser(ticket.claimer))) or nil
									local ticketID = (ticket.id and (tonumber(ticket.id) + 0)) or 0
									table.remove(config.panels[panelindex].subjects[subjectindex].tickets, ticketindex)
									sqldb:set(interaction.guild.id, { panels = config.panels }, "TICKET_CLOSE")

									local cs = table.deepcopy(interaction.message.components)
									cs[1].components[2].disabled = true
									mia:update({
										embeds = interaction.message.embeds,
										components = cs,
									})

									local reason = (responses and responses["Why are you closing this ticket?"] and string.truncate(responses["Why are you closing this ticket?"], 500)) or nil

									interaction.channel:send({
										embeds = parseTable(subject.embeds.close, {
											["closer.mention"] = interaction.member.mentionString,
											["closer.id"] = interaction.member.id,
											["closer.name"] = interaction.member.name,
											["closer.username"] = interaction.user.username,
											["owner.mention"] = "<@" .. ticket.owner .. ">",
											["owner.id"] = ticket.owner,
											["owner.name"] = (ticketOwner and ticketOwner.name) or emojis.fail,
											["owner.username"] = (ticketOwner and ticketOwner.username) or emojis.fail,
											["timestamp"] = tostring(os.time()),
											["reason"] = (reason or "N/A")
										}),
										components = closedActions:raw(),
									})

									coroutine.wrap(function()
										local ownerOverwrite = interaction.channel:getPermissionOverwriteFor(
											interaction.guild:getMember(ticket.owner)
										)
										if ownerOverwrite then
											ownerOverwrite:denyPermissions(discordia.enums.permission.readMessages)
										end
										for i, v in pairs(subject.support) do
											local overwrite =
												interaction.channel:getPermissionOverwriteFor(interaction.guild:getRole(v))
											if overwrite then
												overwrite:denyPermissions(discordia.enums.permission.sendMessages)
											end
										end

										local transcript, webTranscriptLink, transcriptCount = transcriptChannel(interaction.channel)
										local embed = {
											title = emojis.document .. " Ticket Transcript",
											description = emojis.right
												.. " **Ticket ID:** `"
												.. ticketID
												.. "`\n"
												.. emojis.right
												.. " **Ticket Subject:** "
												.. subject.name
												.. "\n"
												.. emojis.right
												.. " **Ticket Opener:** <@"
												.. ticket.owner
												.. ">\n"
												.. emojis.right
												.. " **Ticket Claimer:** "
												.. ((ticketClaimer and ticketClaimer.mentionString) or "N/A")
												.. "\n"
												.. emojis.right
												.. " **Ticket Closer:** "
												.. interaction.user.mentionString
												.. "\n"
												.. emojis.right
												.. " **Ticket Close Reason:** "
												.. (reason or emojis.fail),
											color = colors.info,
										}
										local comps = hasWebTranscripts() and discordia.Components()
										:button({
											url = webTranscriptLink,
											style = "link",
											label = "Web Transcript",
											emoji = resolvedEmojis.web,
										}) or nil

										local settings = sqldb:getUserSettings(ticket.owner)
										if settings and settings.ticketnotifications ~= false then
											dmStyle.ticketClosed(Client:getUser(ticket.owner), {
												guild = interaction.guild,
												channel = interaction.channel,
												id = ticketID,
												subject = subject.name,
												closer = interaction.user,
												claimer = ticketClaimer,
												messages = transcriptCount,
												reason = reason,
												url = hasWebTranscripts() and webTranscriptLink or nil,
												transcript = transcript,
											})
										end
										if subject.transcriptschannel then
											local ts = interaction.guild:getChannel(subject.transcriptschannel)
											if ts then
												ts:send({
													embed = embed,
													files = {
														{
															"transcript.txt",
															tostring(transcript),
														},
													},
													components = comps and comps:raw() or nil,
												})
											end
										end
									end)()
								end
							end, true)
						else
							interaction.channel._delete_protection = false
							interaction:fail("This ticket is already closed.", nil, true)
						end
					elseif id == "ticketclaim" then
						local s, e = pcall(function()
							local config = sqldb:get(interaction.guild.id) or {}

							local panel = nil
							local panelindex = nil
							local subject = nil
							local subjectindex = nil
							local ticket = nil
							local ticketindex = nil

							for pi, v in pairs(config.panels or {}) do
								for si, s in pairs(v.subjects or {}) do
									for ti, t in pairs(s.tickets or {}) do
										if t.channel == interaction.channel.id then
											panel = config.panels[pi]
											panelindex = pi
											subject = panel.subjects[si]
											subjectindex = si
											ticket = subject.tickets[ti]
											ticketindex = ti
										end
									end
								end
							end

							if panel and subject and ticket then
								if not isSubjectSupport(interaction.member, subject) then
									return interaction:fail(
										"You do not have permissions to claim this ticket.",
										nil,
										true
									)
								end
								local ticketOwner = interaction.guild:getMember(ticket.owner)
									or Client:getUser(ticket.owner)
								if not ticket.claimer then
									config.panels[panelindex].subjects[subjectindex].tickets[ticketindex].claimer =
										interaction.user.id
									sqldb:set(interaction.guild.id, { panels = config.panels }, "TICKET_CLAIM")

									local cs = table.deepcopy(interaction.message.components)
									cs[1].components[1].label = "Unclaim"
									cs[1].components[1].emoji = resolvedEmojis.unlock
									cs[1].components[1].style = 4
									interaction:update({
										embeds = interaction.message.embeds,
										components = cs,
									})

									interaction.channel:send({
										embeds = parseTable(subject.embeds.claim, {
											["claimer.mention"] = interaction.member.mentionString,
											["claimer.id"] = interaction.member.id,
											["claimer.name"] = interaction.member.name,
											["claimer.username"] = interaction.user.username,
											["owner.mention"] = "<@" .. ticket.owner .. ">",
											["owner.id"] = ticket.owner,
											["owner.name"] = (ticketOwner and ticketOwner.name) or emojis.fail,
											["owner.username"] = (ticketOwner and ticketOwner.username) or emojis.fail,
											["timestamp"] = tostring(os.time()),
										}),
									})

									if subject.claimedticketname then
										coroutine.wrap(function()
											interaction.channel:setName(parseTable({ subject.claimedticketname }, {
												["claimer.name"] = interaction.member.name,
												["claimer.username"] = interaction.user.username,
												["claimer.id"] = interaction.user.id,
												["member.name"] = (ticketOwner and ticketOwner.name) or "0",
												["member.username"] = (ticketOwner and ticketOwner.username) or "0",
												["member.id"] = (ticketOwner and ticketOwner.id) or "0",
												["ticket.id"] = ticket.id or "0",
												["ticket.number"] = ticketNumber(ticket.id),
											})[1])
										end)()
									end

									coroutine.wrap(function()
										local claimerOverwrite = interaction.channel:getPermissionOverwriteFor(interaction.guild:getMember(interaction.member.id))
										if claimerOverwrite then
											claimerOverwrite:allowPermissions(discordia.enums.permission.readMessages, discordia.enums.permission.sendMessages, discordia.enums.permission.addReactions, discordia.enums.permission.embedLinks, discordia.enums.permission.attachFiles)
										end
										if (not subject.ticketclaimmode) or subject.ticketclaimmode == "hide" then
											for i, v in pairs(subject.support) do
												local overwrite = interaction.channel:getPermissionOverwriteFor(interaction.guild:getRole(v))
												if overwrite then
													overwrite:denyPermissions(discordia.enums.permission.readMessages)
												end
											end
										elseif subject.ticketclaimmode == "lock" then
											for i, v in pairs(subject.support) do
												local overwrite = interaction.channel:getPermissionOverwriteFor(interaction.guild:getRole(v))
												if overwrite then
													overwrite:setPermissions(discordia.enums.permission.readMessages, discordia.enums.permission.sendMessages)
												end
											end
										end
									end)()
								elseif ticket.claimer == interaction.user.id then
									config.panels[panelindex].subjects[subjectindex].tickets[ticketindex].claimer = nil
									sqldb:set(interaction.guild.id, { panels = config.panels }, "TICKET_UNCLAIM")
									local cs = table.deepcopy(interaction.message.components)
									cs[1].components[1].label = "Claim"
									cs[1].components[1].emoji = resolvedEmojis.ticket
									cs[1].components[1].style = 3
									interaction:update({
										embeds = interaction.message.embeds,
										components = cs,
									})

									interaction.channel:send({
										embeds = parseTable(subject.embeds.unclaim, {
											["unclaimer.mention"] = interaction.member.mentionString,
											["unclaimer.id"] = interaction.member.id,
											["unclaimer.name"] = interaction.member.name,
											["unclaimer.username"] = interaction.user.username,
											["owner.mention"] = "<@" .. ticket.owner .. ">",
											["owner.id"] = ticket.owner,
											["owner.name"] = (ticketOwner and ticketOwner.name) or emojis.fail,
											["owner.username"] = (ticketOwner and ticketOwner.username) or emojis.fail,
											["timestamp"] = tostring(os.time()),
										}),
									})

									interaction.channel:setName(parseTable({ subject.ticketname }, {
										["member.name"] = (ticketOwner and ticketOwner.name) or "0",
										["member.username"] = (ticketOwner and ticketOwner.username) or "0",
										["member.id"] = (ticketOwner and ticketOwner.id) or "0",
										["ticket.id"] = ticket.id or "0",
										["ticket.number"] = ticketNumber(ticket.id),
									})[1])

									coroutine.wrap(function()
										local unclaimerOverwrite = interaction.channel:getPermissionOverwriteFor(
											interaction.guild:getMember(interaction.member.id)
										)
										if unclaimerOverwrite then
											unclaimerOverwrite:delete()
										end
										for i, v in pairs(subject.support) do
											local overwrite = interaction.channel:getPermissionOverwriteFor(
												interaction.guild:getRole(v)
											)
											if overwrite then
												overwrite:allowPermissions(
													discordia.enums.permission.readMessages,
													discordia.enums.permission.sendMessages,
													discordia.enums.permission.addReactions,
													discordia.enums.permission.embedLinks,
													discordia.enums.permission.attachFiles
												)
											end
										end
									end)()
								elseif ticket.claimer ~= interaction.user.id then
									interaction:fail(
										"This ticket has already been claimed by <@" .. tostring(ticket.claimer) .. ">.",
										nil,
										true
									)
								end
							else
								interaction:fail("Failed to fetch ticket data.", nil, true)
							end
						end)

						if not s then
							interaction:fail(tostring(e))
						end
					elseif id == "ticketdelete" then
						if interaction.channel._delete_protection then
                            return interaction:fail("A transcript of this ticket is currently being generated. Please try again in a few seconds.", nil, true)
                        end
						interaction:updateDeferred(true)
						interaction.channel:delete()
					elseif id == "tickettranscript" then
						local r = interaction:reply({
							embed = {
								description = emojis.loading,
								color = colors.blank,
							},
						}, true)

						local st = realtime()
						local transcript, webTranscriptLink = transcriptChannel(interaction.channel)
						local en = realtime()

						local content = {
							embed = {
								description = emojis.success .. " Your transcript was generated in " .. math.round(
									en - st,
									2
								) .. " seconds:",
								color = colors.success,
							},
							files = {
								{
									"transcript.txt",
									tostring(transcript),
								},
							},
							components = hasWebTranscripts() and discordia
								.Components()
								:button({
									url = webTranscriptLink,
									style = "link",
									label = "Web Transcript",
									emoji = resolvedEmojis.web,
								})
								:raw() or nil,
						}

						if type(r) == "table" then
							interaction:editReply(content, r.id)
						else
							interaction:reply(content, true)
						end
					end
				end)()
			end),
		}
	)
end

tickets.Stop = function()
	for _, con in pairs(connections) do
		Client:removeListener(con[1], con[2])
	end

	connections = nil
end

return tickets