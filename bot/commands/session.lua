-- session.lua (SCRP). Uses the existing session system (db:session*). Hand-coded by Dex.
local K = _G.scrpKit
local E = _G.scrpApi.erlc
local T = K.TIER

local function sessionsChannel(ctx)
	local config = K.config(ctx.guild)
	local ch = config.sessionschannel and ctx.guild:getChannel(config.sessionschannel)
	return ch, config
end

local function done(ctx, ok, err, text)
	if ok then return ctx:ok(text) end
	return ctx:fail(tostring(err or "Something went wrong."))
end

local function needChannel(ctx)
	local ch = sessionsChannel(ctx)
	if not ch then
		ctx:fail("The sessions channel is not set up yet.")
		return nil
	end
	return ch
end

return K.command({
	name = "session",
	description = "Run in-game sessions.",
	tier = T.MOD,
	subs = {
		{
			name = "start", aliases = { "ssu" }, description = "Start a session and post the start-up card.",
			run = function(ctx)
				local ch = needChannel(ctx) if not ch then return end
				local ok, err = db:sessionStart(ctx.member)
				return done(ctx, ok, err, "The session was started in " .. ch.mentionString .. ".")
			end
		},
		{
			name = "shutdown", aliases = { "end", "ssd" }, description = "Shut the session down.",
			run = function(ctx)
				local ch = needChannel(ctx) if not ch then return end
				local ok, err = db:sessionEnd(ctx.member)
				return done(ctx, ok, err, "The session was shut down.")
			end
		},
		{
			name = "vote", description = "Post a session vote.",
			options = {
				{ type = "integer", name = "votes", description = "Votes needed to start.", required = true, min = 1, max = 100 },
				{ type = "boolean", name = "manual", description = "Start it yourself instead of starting at the vote goal." },
			},
			run = function(ctx, args)
				local ch = needChannel(ctx) if not ch then return end
				local auto = not args.manual
				local ok, err = db:sessionVote(ctx.member, math.floor(args.votes), auto)
				return done(ctx, ok, err, "The session vote was posted. " .. (auto and ("It starts at " .. math.floor(args.votes) .. " votes.") or "Start it with -session start."))
			end
		},
		{
			name = "boost", aliases = { "low" }, description = "Ask for more players when the server is low.",
			run = function(ctx)
				local ch = needChannel(ctx) if not ch then return end
				local ok, err = db:sessionLow(ctx.member)
				return done(ctx, ok, err, "The session boost was posted.")
			end
		},
		{
			name = "full", description = "Let everyone know the server is full.",
			run = function(ctx)
				local ch = needChannel(ctx) if not ch then return end
				local ok, err = db:sessionFull(ctx.member)
				return done(ctx, ok, err, "The server full notice was posted.")
			end
		},
		{
			name = "update", description = "Post a session update with live server stats.",
			options = { { type = "string", name = "message", description = "What to tell everyone.", rest = true } },
			run = function(ctx, args)
				local ch, config = sessionsChannel(ctx)
				ch = ch or ctx.channel
				local blocks = {}
				local server, err = E.server(true)
				if server then
					local players = E.players(true) or {}
					local queue = E.queue(true) or {}
					table.insert(blocks, { { "Server Name", server.Name }, { "Server Code", server.JoinKey } })
					table.insert(blocks, {
						{ "In-game Players", tostring(server.CurrentPlayers or #players) .. "/" .. tostring(server.MaxPlayers or "?") },
						{ "Currently Moderating", tostring(E.staffCount(players)) },
						{ "In-Queue Players", tostring(#queue) },
					})
				elseif err == K.NOT_SET_UP then
					table.insert(blocks, { { "In-game Stats", "ER:LC API not set up yet" } })
				end
				local session = config.session or {}
				table.insert(blocks, { { "Status", session.status == "active" and "Session running" or "No session running" }, { "Posted By", ctx.user.mentionString, true } })
				local msg, e = ch:send(K.card({
					title = "Session Update",
					intro = args.message,
					blocks = blocks,
					components = server and server.JoinKey and { { type = 1, components = { { type = 2, style = 5, label = "Join Server", url = "https://erlc.gg/join/" .. server.JoinKey } } } } or nil,
				}))
				if not msg then return ctx:fail("I could not post the update. " .. tostring(e or "")) end
				return ctx:ok("The session update was posted in " .. ch.mentionString .. ".")
			end
		},
	}
})
