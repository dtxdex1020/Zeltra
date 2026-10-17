-- staff.lua (SCRP). Staff management. Reuses db:infract and the promotion card. Hand-coded by Dex.
local K = _G.scrpKit
local T = K.TIER

local requestCooldown = {}

local function infractionTypes(guild)
	return K.config(guild).infractiontypes or {}
end

local function findType(guild, input)
	input = tostring(input or "")
	local types = infractionTypes(guild)
	local n = tonumber(input)
	if n and types[n] then return types[n] end
	local partial
	for _, t in ipairs(types) do
		local name = tostring(t.name or ""):lower()
		if name == input:lower() then return t end
		if not partial and name:find(input:lower(), 1, true) then partial = t end
	end
	return partial
end

local function staffTarget(ctx, user)
	local member = K.memberOf(ctx.guild, user)
	if not member then return nil, "That user is not in the server." end
	if member.id == ctx.member.id then return nil, "You can't do that to yourself." end
	if K.tier(ctx.member) < T.OWNER and K.tier(member) >= K.tier(ctx.member) then return nil, "That member is at or above your rank." end
	return member
end

local function promote(ctx, member, rank, reason, notes)
	local ok, err = canManageRole(rank, ctx.member)
	if not ok then return ctx:fail(err or "I can't give that role.") end
	local config = K.config(ctx.guild)
	local promotion = { id = table.count(config.promotions or {}) + 1, user = member.id, rank = rank.id, reason = reason, notes = notes or "N/A", promoter = ctx.user.id, timestamp = os.time() }
	local added, aerr = member:addRole(rank.id, "promotion " .. promotion.id .. " by " .. ctx.user.username)
	if not added then return ctx:fail("Discord would not let me add that role. " .. tostring(aerr or "")) end

	local card = K.card({
		title = "Staff Promotion",
		intro = "Congratulations " .. member.mentionString .. " on the promotion. Keep up the good work.",
		blocks = {
			{ { "Staff Member", member.mentionString, true }, { "New Rank", rank.mentionString, true } },
			{ { "Reason", reason }, { "Notes", notes } },
			{ { "Promoted By", ctx.user.mentionString, true }, { "Promotion ID", tostring(promotion.id) } },
		},
	})
	card.content = member.mentionString
	card.allowed_mentions = { users = { member.id } }
	local msg = config.promotionschannel and db:send(ctx.guild.id, "promotionschannel", card, nil, true)
	if not msg then msg = ctx.channel:send(card) end
	promotion.msg = type(msg) == "table" and msg.id or nil
	pcall(dmStyle.send, member, {
		guild = ctx.guild, title = "You were promoted",
		intro = "You were promoted to **" .. rank.name .. "** in **" .. dmStyle.serverName(ctx.guild) .. "**. Congrats, and thanks for the work you put in.",
		fields = { { "New Rank", rank.name }, { "Reason", reason }, { "Promoted By", ctx.user.username }, { "Date", dmStyle.time(os.time()) } },
		footer = "Staff Management",
	})
	config = K.config(ctx.guild)
	config.promotions = config.promotions or {}
	table.insert(config.promotions, promotion)
	K.save(ctx.guild, { promotions = config.promotions }, "PROMOTION_ISSUE")
	return ctx:ok(member.mentionString .. " was promoted to " .. rank.mentionString .. ".")
end

local function voteRow(id, yes, no, closed)
	return { { type = 1, components = {
		{ type = 2, style = 3, label = "Yes (" .. yes .. ")", custom_id = "scrpvote_yes_" .. id, disabled = closed },
		{ type = 2, style = 4, label = "No (" .. no .. ")", custom_id = "scrpvote_no_" .. id, disabled = closed },
	} } }
end
_G.scrpVoteRow = voteRow

return K.command({
	name = "staff",
	description = "Staff management.",
	tier = T.STAFF,
	subs = {
		{
			name = "infraction", aliases = { "infract", "warn" }, description = "Give a staff member an infraction.", tier = T.MGMT,
			options = {
				{ type = "user", name = "user", description = "Staff member (ID or mention).", required = true },
				{ type = "string", name = "type", description = "Infraction type.", required = true, autocomplete = function(ia, value)
					local out = {}
					for i, t in ipairs(infractionTypes(ia.guild)) do
						if value == "" or tostring(t.name):lower():find(value:lower(), 1, true) then
							table.insert(out, { name = string.truncate(tostring(t.name), 100), value = tostring(i) })
						end
						if #out >= 25 then break end
					end
					return out
				end },
				{ type = "string", name = "reason", description = "Why.", required = true, rest = true, maxLength = 1000 },
				{ type = "string", name = "expires", description = "When it expires, like 2w or 30d." },
			},
			run = function(ctx, args)
				if #infractionTypes(ctx.guild) == 0 then return ctx:fail("Infraction types are not set up yet.") end
				local member, err = staffTarget(ctx, args.user)
				if not member then return ctx:fail(err) end
				local itype = findType(ctx.guild, args.type)
				if not itype then
					local names = {}
					for _, t in ipairs(infractionTypes(ctx.guild)) do table.insert(names, t.name) end
					return ctx:fail("I could not find that infraction type. Types: " .. table.concat(names, ", ") .. ".")
				end
				local expires = args.expires and convert(args.expires) or nil
				local ok, res = db:infract(member, itype, args.reason, ctx.member, nil, expires, ctx.isSlash and ctx.source or nil)
				if not ok then return ctx:fail(tostring(res or "I could not give that infraction.")) end
				return ctx:card({
					title = "Infraction Issued",
					blocks = {
						{ { "Staff Member", member.mentionString, true }, { "Type", itype.name }, { "Reason", args.reason } },
						{ { "Expires", expires and ("<t:" .. (os.time() + expires) .. ":R>") or "Never", expires and true }, { "Issued By", ctx.user.mentionString, true } },
					},
					banner = false,
				})
			end
		},
		{
			name = "promote", description = "Promote a staff member.", tier = T.MGMT,
			options = {
				{ type = "user", name = "user", description = "Staff member (ID or mention).", required = true },
				{ type = "role", name = "rank", description = "New rank role.", required = true },
				{ type = "string", name = "reason", description = "Why.", required = true, rest = true, maxLength = 1000 },
				{ type = "string", name = "notes", description = "Extra notes." },
			},
			run = function(ctx, args)
				local member, err = staffTarget(ctx, args.user)
				if not member then return ctx:fail(err) end
				return promote(ctx, member, args.rank, args.reason, args.notes)
			end
		},
		{
			name = "request", description = "Ask for more staff in game.",
			options = { { type = "string", name = "reason", description = "What is going on.", rest = true, maxLength = 300 } },
			run = function(ctx, args)
				local last = requestCooldown[ctx.guild.id]
				if last and os.time() - last < 300 then
					return ctx:fail("Staff were just requested. Try again <t:" .. (last + 300) .. ":R>.")
				end
				requestCooldown[ctx.guild.id] = os.time()
				local server = _G.scrpApi.erlc.server()
				local players = server and _G.scrpApi.erlc.players() or nil
				local card = K.card({
					title = "Staff Needed In Game",
					intro = "We need more staff in the server. If you are free, please hop on.",
					blocks = {
						{ { "Reason", args.reason or "Not enough staff online" }, { "Requested By", ctx.user.mentionString, true } },
						server and { { "In-game Players", tostring(server.CurrentPlayers) .. "/" .. tostring(server.MaxPlayers) }, { "Currently Moderating", tostring(_G.scrpApi.erlc.staffCount(players)) }, { "Server Code", server.JoinKey } } or {},
					},
				})
				card.content = "<@&" .. K.BASE_STAFF_ROLE .. ">"
				card.allowed_mentions = { roles = { K.BASE_STAFF_ROLE } }
				local msg, e = ctx.channel:send(card)
				if not msg then return ctx:fail("I could not send the request. " .. tostring(e or "")) end
				if ctx.isSlash then return ctx:send(K.notice("Staff request sent."), true) end
			end
		},
		{
			name = "review", description = "Write a performance review for a staff member.", tier = T.IA,
			options = {
				{ type = "user", name = "user", description = "Staff member (ID or mention).", required = true },
				{ type = "integer", name = "rating", description = "1 to 5.", required = true, min = 1, max = 5 },
				{ type = "string", name = "notes", description = "What went well and what to work on.", required = true, rest = true, maxLength = 1500 },
			},
			run = function(ctx, args)
				local member, err = staffTarget(ctx, args.user)
				if not member then return ctx:fail(err) end
				local rating = math.max(1, math.min(5, math.floor(args.rating)))
				local config = K.config(ctx.guild)
				local reviews = config.scrp_reviews or {}
				table.insert(reviews, { user = member.id, rating = rating, notes = args.notes, by = ctx.user.id, at = os.time() })
				K.save(ctx.guild, { scrp_reviews = reviews }, "SCRP_STAFF_REVIEW")
				local count, total = 0, 0
				for _, r in ipairs(reviews) do if r.user == member.id then count = count + 1 total = total + r.rating end end
				pcall(dmStyle.send, member, {
					guild = ctx.guild, title = "You got a staff review",
					intro = "Internal Affairs wrote a review for you in **" .. dmStyle.serverName(ctx.guild) .. "**.",
					fields = { { "Rating", rating .. " out of 5" }, { "Notes", args.notes } }, footer = "Staff Management",
				})
				return ctx:card({
					title = "Staff Review",
					blocks = {
						{ { "Staff Member", member.mentionString, true }, { "Rating", rating .. " out of 5" } },
						{ { "Notes", args.notes } },
						{ { "Average", string.format("%.1f", total / count) .. " over " .. count .. " review" .. (count == 1 and "" or "s") }, { "Reviewed By", ctx.user.mentionString, true } },
					},
				})
			end
		},
		{
			name = "vote", description = "Start a staff vote about a staff member.", tier = T.MGMT,
			options = {
				{ type = "user", name = "user", description = "Staff member (ID or mention).", required = true },
				{ type = "string", name = "topic", description = "What the vote is for, like Promotion to Moderator.", required = true, rest = true, maxLength = 200 },
			},
			run = function(ctx, args)
				local member = K.memberOf(ctx.guild, args.user)
				if not member then return ctx:fail("That user is not in the server.") end
				local id = tostring(ctx.source.id)
				local card = K.card({
					title = "Staff Vote",
					intro = "Staff, vote below. Only staff votes count.",
					blocks = { { { "Staff Member", member.mentionString, true }, { "Vote For", args.topic } }, { { "Started By", ctx.user.mentionString, true } } },
				})
				card.components = voteRow(id, 0, 0)
				local msg, e = ctx.channel:send(card)
				if not msg then return ctx:fail("I could not start the vote. " .. tostring(e or "")) end
				local config = K.config(ctx.guild)
				local votes = config.scrp_votes or {}
				votes[id] = { channel = ctx.channel.id, message = msg.id, user = member.id, topic = args.topic, yes = {}, no = {}, by = ctx.user.id, at = os.time(), minTier = T.STAFF }
				K.save(ctx.guild, { scrp_votes = votes }, "SCRP_STAFF_VOTE")
				if ctx.isSlash then return ctx:send(K.notice("The vote is up."), true) end
			end
		},
	}
})
