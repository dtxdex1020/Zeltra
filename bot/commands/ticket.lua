-- ticket.lua (SCRP). Works with the existing ticket panel and module. Hand-coded by Dex.
local K = _G.scrpKit
local T = K.TIER
local perm = discordia.enums.permission

local function findTicket(guild, channelId)
	local config = K.config(guild)
	for pi, p in pairs(config.panels or {}) do
		for si, s in pairs(p.subjects or {}) do
			for ti, t in pairs(s.tickets or {}) do
				if t.channel == channelId then
					return { panel = p, subject = s, ticket = t, pi = pi, si = si, ti = ti }
				end
			end
		end
	end
end
_G.scrpFindTicket = findTicket

local function closedButtons()
	return { { type = 1, components = {
		{ type = 2, style = 1, label = "Transcript", custom_id = "tickettranscript" },
		{ type = 2, style = 4, label = "Delete", custom_id = "ticketdelete" },
	} } }
end

--- Closes the ticket in this channel. closerMember / closerUser close it, reason is optional.
local function closeTicket(guild, channel, st, closerMember, reason)
	channel._delete_protection = true
	local config = K.config(guild)
	local tickets = config.panels[st.pi].subjects[st.si].tickets
	for i, t in pairs(tickets) do
		if t.channel == channel.id then table.remove(tickets, i) break end
	end
	K.save(guild, { panels = config.panels }, "TICKET_CLOSE")

	local ticket, subject = st.ticket, st.subject
	local owner = guild:getMember(ticket.owner) or Client:getUser(ticket.owner)
	local claimer = ticket.claimer and (guild:getMember(ticket.claimer) or Client:getUser(ticket.claimer)) or nil
	channel:send({
		embeds = { K.card({
			title = "Ticket Closed",
			blocks = { { { "Closed By", closerMember.mentionString, true }, { "Reason", reason or "No reason given" } } },
			banner = false,
		}).embeds[1] },
		components = closedButtons(),
	})

	coroutine.wrap(function()
		local ownerMember = guild:getMember(ticket.owner)
		local ow = ownerMember and channel:getPermissionOverwriteFor(ownerMember)
		if ow then ow:denyPermissions(perm.readMessages) end
		for _, v in pairs(subject.support or {}) do
			local role = guild:getRole(v)
			local o = role and channel:getPermissionOverwriteFor(role)
			if o then o:denyPermissions(perm.sendMessages) end
		end
		local transcript, webLink, count = transcriptChannel(channel)
		local settings = sqldb:getUserSettings(ticket.owner)
		if settings == nil or settings.ticketnotifications ~= false then
			pcall(dmStyle.ticketClosed, Client:getUser(ticket.owner), {
				guild = guild, channel = channel, id = ticket.id, subject = subject.name, closer = closerMember.user or closerMember,
				claimer = claimer, messages = count, reason = reason, url = webLink, transcript = transcript
			})
		end
		local ts = subject.transcriptschannel and guild:getChannel(subject.transcriptschannel)
		if ts then
			local payload = K.card({
				title = "Ticket Transcript",
				blocks = {
					{ { "Ticket ID", tostring(ticket.id or 0) }, { "Subject", subject.name } },
					{ { "Opened By", "<@" .. tostring(ticket.owner) .. ">", true }, { "Claimed By", claimer and claimer.mentionString or "Nobody", claimer and true }, { "Closed By", closerMember.mentionString, true } },
					{ { "Reason", reason or "No reason given" } },
				},
				banner = false,
			})
			payload.files = { { "transcript.txt", tostring(transcript) } }
			if webLink then payload.components = { { type = 1, components = { { type = 2, style = 5, label = "Web Transcript", url = webLink } } } } end
			ts:send(payload)
		end
	end)()
	return owner
end

local function getTicket(ctx)
	local st = findTicket(ctx.guild, ctx.channel.id)
	if not st then
		ctx:fail("This channel is not an open ticket.")
		return nil
	end
	if not isSubjectSupport(ctx.member, st.subject) and K.tier(ctx.member) < T.MGMT then
		ctx:fail("You are not support for this ticket type.")
		return nil
	end
	return st
end

local function setAccess(ctx, user, allow)
	local member = K.memberOf(ctx.guild, user)
	if not member then return ctx:fail("That user is not in the server.") end
	local ow = ctx.channel:getPermissionOverwriteFor(member)
	if not ow then return ctx:fail("I could not change that member's access.") end
	if allow then
		ow:allowPermissions(perm.readMessages, perm.sendMessages, perm.addReactions, perm.embedLinks, perm.attachFiles, perm.readMessageHistory)
	else
		ow:denyPermissions(perm.readMessages, perm.sendMessages)
	end
	return ctx:ok(member.mentionString .. (allow and " was added to this ticket." or " was removed from this ticket."))
end

return K.command({
	name = "ticket",
	description = "Manage the ticket you are in.",
	tier = T.STAFF,
	subs = {
		{
			name = "add", description = "Add a member to this ticket.",
			options = { { type = "user", name = "user", description = "Member to add.", required = true } },
			run = function(ctx, args)
				if not getTicket(ctx) then return end
				return setAccess(ctx, args.user, true)
			end
		},
		{
			name = "remove", description = "Remove a member from this ticket.",
			options = { { type = "user", name = "user", description = "Member to remove.", required = true } },
			run = function(ctx, args)
				local st = getTicket(ctx) if not st then return end
				if tostring(args.user.id) == tostring(st.ticket.owner) then return ctx:fail("You can't remove the person who opened the ticket.") end
				return setAccess(ctx, args.user, false)
			end
		},
		{
			name = "rename", description = "Rename this ticket.",
			options = { { type = "string", name = "name", description = "New channel name.", required = true, rest = true, maxLength = 90 } },
			run = function(ctx, args)
				if not getTicket(ctx) then return end
				local name = tostring(args.name):lower():gsub("%s+", "-"):gsub("[^%w%-_]", "")
				if name == "" then return ctx:fail("That name is not valid.") end
				local ok, err = ctx.channel:setName(string.truncate(name, 90))
				if not ok then return ctx:fail("I could not rename the ticket. Discord limits renames to 2 every 10 minutes.") end
				return ctx:ok("Ticket renamed to `" .. name .. "`.")
			end
		},
		{
			name = "close", description = "Close this ticket.",
			options = { { type = "string", name = "reason", description = "Why it is being closed.", rest = true, maxLength = 500 } },
			run = function(ctx, args)
				local st = getTicket(ctx) if not st then return end
				if ctx.isSlash then ctx:ok("Closing this ticket.") end
				closeTicket(ctx.guild, ctx.channel, st, ctx.member, args.reason and string.truncate(args.reason, 500))
			end
		},
		{
			name = "closerequest", aliases = { "cr" }, description = "Ask the ticket opener if the ticket can be closed.",
			options = { { type = "string", name = "reason", description = "Why it can be closed.", rest = true, maxLength = 500 } },
			run = function(ctx, args)
				local st = getTicket(ctx) if not st then return end
				local reason = args.reason and string.truncate(args.reason, 500)
				local request = ctx.channel:send({
					content = "<@" .. tostring(st.ticket.owner) .. ">",
					embeds = { K.card({
						title = "Close Request",
						intro = ctx.member.mentionString .. " thinks this ticket can be closed. Press Close if you are all set, or Keep Open if you still need help.",
						blocks = { { { "Reason", reason or "No reason given" } } },
						banner = false,
					}).embeds[1] },
					components = { { type = 1, components = {
						{ type = 2, style = 3, label = "Close", custom_id = "yes" },
						{ type = 2, style = 4, label = "Keep Open", custom_id = "no" },
					} } },
					allowed_mentions = { users = { tostring(st.ticket.owner) } },
				})
				if not request then return ctx:fail("I could not send the close request.") end
				onComp(request, nil, nil, st.ticket.owner, true, function(ia)
					local id = ia.data.custom_id
					ia:updateDeferred(true)
					request:delete()
					if id == "yes" then
						local fresh = findTicket(ctx.guild, ctx.channel.id)
						if fresh then closeTicket(ctx.guild, ctx.channel, fresh, ia.member, reason) end
					else
						ctx.channel:send(K.notice("The ticket opener wants to keep this ticket open."))
					end
				end)
				if ctx.isSlash then return ctx:ok("The close request was sent.") end
			end
		},
	}
})
