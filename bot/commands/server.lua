-- server.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit
local E = _G.scrpApi.erlc

return K.command({
	name = "server",
	description = "Server stats and server swaps.",
	subs = {
		{
			name = "stats", aliases = { "statistics" }, description = "Show Discord and in-game server stats.",
			run = function(ctx)
				local guild = ctx.guild
				local total = guild.totalMemberCount or table.count(guild.members)
				local boosts = guild.premiumSubscriptionCount or 0
				local blocks = {
					{ { "Discord Members", K.commas(total) }, { "Boosts", tostring(boosts) }, { "Channels", tostring(guild.textChannels:count() + guild.voiceChannels:count()) }, { "Roles", tostring(guild.roles:count()) } },
				}
				local server, err = E.server()
				if server then
					local players = E.players() or {}
					local queue = E.queue() or {}
					table.insert(blocks, {
						{ "Server Name", server.Name },
						{ "In-game Players", tostring(server.CurrentPlayers or #players) .. "/" .. tostring(server.MaxPlayers or "?") },
						{ "Currently Moderating", tostring(E.staffCount(players)) },
						{ "In-Queue Players", tostring(#queue) },
					})
				else
					table.insert(blocks, { { "In-game Server", err == K.NOT_SET_UP and "ER:LC API not set up yet" or "Could not reach the ER:LC API" } })
				end
				local config = K.config(guild)
				local session = config.session or {}
				table.insert(blocks, { { "Session", session.status == "active" and ("Active since <t:" .. tostring(session.timestamp or os.time()) .. ":R>") or "No session running", session.status == "active" } })
				return ctx:card({ title = "South Carolina Roleplay Stats", thumbnail = guild.iconURL, blocks = blocks })
			end
		},
		{
			name = "swap", description = "Announce a server swap to a new server code.", tier = K.TIER.MGMT,
			options = {
				{ type = "string", name = "code", description = "The new server code.", required = true },
				{ type = "string", name = "reason", description = "Why the server is swapping.", rest = true },
				{ type = "channel", name = "channel", description = "Where to post it (defaults to the sessions channel or here)." },
			},
			run = function(ctx, args)
				local config = K.config(ctx.guild)
				local channel = args.channel or (config.sessionschannel and ctx.guild:getChannel(config.sessionschannel)) or ctx.channel
				if not channel or not channel.send then return ctx:fail("I could not find that channel.") end
				local code = tostring(args.code):gsub("%s", "")
				local msg, err = channel:send(K.card({
					title = "Server Swap",
					intro = "We are moving to a new server. Leave the old one and join with the code below.",
					blocks = {
						{ { "New Server Code", code }, { "Reason", args.reason or "Server swap" } },
						{ { "Announced By", ctx.user.mentionString, true } },
					},
					components = { { type = 1, components = { { type = 2, style = 5, label = "Join Server", url = "https://erlc.gg/join/" .. code } } } },
				}))
				if not msg then return ctx:fail("I could not post the swap. " .. tostring(err or "")) end
				return ctx:ok("The server swap was posted in " .. channel.mentionString .. ".")
			end
		},
	}
})
