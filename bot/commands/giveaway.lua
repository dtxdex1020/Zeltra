-- giveaway.lua (SCRP). Uses the existing giveaway module for entries and auto ending. Hand-coded by Dex.
local K = _G.scrpKit
local T = K.TIER

-- Template the giveaway module also uses when it refreshes the entry count.
local TEMPLATE = { {
	title = "{giveaway.prize}",
	description = "> **Prize:** `{giveaway.prize}`\n> **Hosted By:** {host.mention}\n> **Winners:** `{giveaway.winners}`\n\n> **Ends:** <t:{giveaway.ends}:F> (<t:{giveaway.ends}:R>)\n> **Entries:** `{giveaway.entries}`",
	color = K.COLOR,
	footer = { text = K.FOOTER },
} }

local function keys(g)
	return {
		["host.mention"] = g.host.mention, ["host.name"] = g.host.name, ["host.username"] = g.host.username, ["host.id"] = g.host.id,
		["giveaway.id"] = g.id, ["giveaway.entries"] = #g.entries, ["giveaway.winners"] = g.winners, ["giveaway.prize"] = g.prize,
		["giveaway.duration"] = readable(g.duration), ["giveaway.ends"] = g.ends,
	}
end

--- Creates a giveaway in ctx.channel. host is a Member or User. Returns message or nil, error.
local function create(ctx, prize, durationText, winners, host, ping, requiredRole)
	local duration = convert(tostring(durationText or ""))
	if not duration or duration <= 0 then return nil, "That duration is not valid. Use something like 30m, 6h, or 2d." end
	if duration > 60 * 86400 then return nil, "Giveaways can last up to 60 days." end
	winners = math.floor(tonumber(winners) or 1)
	if winners < 1 or winners > 50 then return nil, "Winners has to be between 1 and 50." end

	local config = K.config(ctx.guild)
	if not config.giveawayembeds then
		K.save(ctx.guild, { giveawayembeds = TEMPLATE }, "SCRP_GIVEAWAY_TEMPLATE")
		config = K.config(ctx.guild)
	end

	local id = tostring(ctx.source.id)
	local g = {
		channel = ctx.channel.id, id = id, entries = {}, winners = winners, prize = prize,
		duration = duration, ends = os.time() + duration, started = os.time(),
		requiredrole = requiredRole and requiredRole.id or nil, requiredingame = false,
		host = { name = host.name or host.username, username = host.username, mention = host.mentionString, id = host.id },
	}
	local msg, err = ctx.channel:send({
		content = ping and ping.mentionString or nil,
		embeds = parseTable(config.giveawayembeds or TEMPLATE, keys(g)),
		components = { { type = 1, components = {
			{ type = 2, style = 1, label = "Enter", custom_id = "entergiveaway_" .. id },
			{ type = 2, style = 2, label = "Entries", custom_id = "giveawayentries_" .. id },
		} } },
		allowed_mentions = ping and { roles = { ping.id } } or { parse = {} },
	})
	if not msg then return nil, "I could not post the giveaway. " .. tostring(err or "") end
	g.message = msg.id
	config = K.config(ctx.guild)
	config.giveaways = config.giveaways or {}
	config.giveaways[id] = g
	K.save(ctx.guild, { giveaways = config.giveaways }, "GIVEAWAY_CREATE")
	return msg
end
_G.scrpGiveawayCreate = create

local function endGiveaway(ctx, input)
	local wanted = tostring(input or ""):match("(%d+)%s*$")
	if not wanted then return ctx:fail("Give the giveaway message ID or link.") end
	local config = K.config(ctx.guild)
	local g
	for id, info in pairs(config.giveaways or {}) do
		if id == wanted or info.message == wanted then g = info break end
	end
	if not g then return ctx:fail("I could not find that giveaway.") end
	if g.rolled then return ctx:fail("That giveaway already ended.") end

	local winners, pool = {}, {}
	for _, e in ipairs(g.entries or {}) do table.insert(pool, e) end
	math.randomseed(os.time() + math.floor(math.random() * 10000))
	for _ = 1, g.winners do
		if #pool == 0 then break end
		table.insert(winners, table.remove(pool, math.random(1, #pool)))
	end
	g.rolled = true
	K.save(ctx.guild, { giveaways = config.giveaways }, "GIVEAWAY_UPDATE")

	local channel = ctx.guild:getChannel(g.channel)
	local msg = channel and channel:getMessage(g.message)
	if msg then
		local mentions = {}
		for _, w in ipairs(winners) do table.insert(mentions, "<@" .. w .. ">") end
		msg:reply({
			content = (#winners > 0) and ("Congratulations " .. table.concat(mentions, ", ") .. ", you won **" .. g.prize .. "**.") or ("Nobody entered the **" .. g.prize .. "** giveaway, so there are no winners."),
			allowed_mentions = { users = winners },
		})
		msg:update({
			content = msg.content,
			embeds = msg.embeds,
			components = { { type = 1, components = {
				{ type = 2, style = 2, label = "Reroll", custom_id = "rerollgiveaway_" .. g.id, disabled = #g.entries == 0 },
				{ type = 2, style = 2, label = "Entries", custom_id = "giveawayentries_" .. g.id },
			} } },
		})
	end
	return ctx:ok("The giveaway ended" .. ((#winners > 0) and (" with " .. #winners .. " winner" .. (#winners == 1 and "" or "s") .. ".") or " with no entries."))
end

return K.command({
	name = "giveaway",
	description = "Run giveaways.",
	tier = T.ADMIN,
	subs = {
		{
			name = "create", aliases = { "start" }, description = "Start a giveaway in this channel.",
			options = {
				{ type = "string", name = "duration", description = "How long it runs, like 30m, 6h, 2d.", required = true },
				{ type = "integer", name = "winners", description = "How many winners.", required = true, min = 1, max = 50 },
				{ type = "string", name = "prize", description = "What they win.", required = true, rest = true, maxLength = 200 },
				{ type = "role", name = "ping", description = "Role to ping." },
				{ type = "role", name = "required_role", description = "Role needed to enter." },
			},
			run = function(ctx, args)
				local msg, err = create(ctx, args.prize, args.duration, args.winners, ctx.member, args.ping, args.required_role)
				if not msg then return ctx:fail(err) end
				return ctx:ok("The giveaway is live: " .. msg.link)
			end
		},
		{
			name = "end", description = "End a giveaway now and pick winners.",
			options = { { type = "string", name = "giveaway", description = "Giveaway message ID or link.", required = true } },
			run = function(ctx, args) return endGiveaway(ctx, args.giveaway) end
		},
	}
})
