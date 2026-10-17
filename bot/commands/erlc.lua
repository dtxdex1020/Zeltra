-- erlc.lua (SCRP). ER:LC private server info through the PRC API. Hand-coded by Dex.
local K = _G.scrpKit
local E = _G.scrpApi.erlc
local R = _G.scrpApi.roblox
local T = K.TIER

local function apiFail(ctx, err)
	if err == K.NOT_SET_UP then return ctx:fail("The ER:LC API is not set up yet.") end
	return ctx:fail(tostring(err or "The ER:LC API did not answer."))
end

--- Server info card (shared with /server stats and /queue).
local function serverCard(fresh)
	local server, err = E.server(fresh)
	if not server then return nil, err end
	local players = E.players(fresh) or {}
	local queue = E.queue(fresh) or {}
	local owner = R.user(server.OwnerId)
	return {
		title = "South Carolina Roleplay ER:LC",
		blocks = {
			{ { "Last Updated", "<t:" .. os.time() .. ":R>", true } },
			{
				{ "Server Name", server.Name or "Unknown" },
				{ "Server Owner", owner and owner.name or tostring(server.OwnerId or "Unknown") },
				{ "Server Code", server.JoinKey or "Unknown" },
			},
			{
				{ "In-game Players", tostring(server.CurrentPlayers or #players) .. "/" .. tostring(server.MaxPlayers or "?") },
				{ "Currently Moderating", tostring(E.staffCount(players)) },
				{ "In-Queue Players", tostring(#queue) },
			},
		},
		components = server.JoinKey and { { type = 1, components = { { type = 2, style = 5, label = "Join Server", url = "https://erlc.gg/join/" .. server.JoinKey } } } } or nil,
	}
end
_G.scrpErlcCard = serverCard

local TEAM_ORDER = { "Police", "Sheriff", "Fire", "DOT", "Civilian", "Jail" }

return K.command({
	name = "erlc",
	description = "ER:LC private server commands.",
	subs = {
		{
			name = "information", aliases = { "info", "server" }, description = "Show the in-game server info.",
			run = function(ctx)
				local card, err = serverCard()
				if not card then return apiFail(ctx, err) end
				return ctx:card(card)
			end
		},
		{
			name = "players", description = "List the players in game.",
			run = function(ctx)
				local players, err = E.players()
				if not players then return apiFail(ctx, err) end
				local teams = {}
				for _, p in ipairs(players) do
					local team = p.Team or "Civilian"
					teams[team] = teams[team] or {}
					local name = E.splitPlayer(p.Player)
					local tag = (p.Callsign and p.Callsign ~= "") and (" (" .. p.Callsign .. ")") or ""
					table.insert(teams[team], name .. tag)
				end
				local lines = {}
				local seen = {}
				local function add(team)
					local list = teams[team]
					if list and not seen[team] then
						seen[team] = true
						table.sort(list)
						table.insert(lines, "**" .. team .. " (" .. #list .. ")**\n" .. string.truncate(table.concat(list, ", "), 900))
					end
				end
				for _, t in ipairs(TEAM_ORDER) do add(t) end
				for t in pairs(teams) do add(t) end
				return ctx:card({
					title = "In-game Players",
					blocks = { { { "Players", tostring(#players) }, { "Currently Moderating", tostring(E.staffCount(players)) } } },
					body = (#lines > 0) and table.concat(lines, "\n\n") or "Nobody is in game right now.",
				})
			end
		},
		{
			name = "lookup", description = "Look up a Roblox player and see if they are in game.", tier = T.STAFF,
			options = { { type = "string", name = "username", description = "Roblox username or ID.", required = true } },
			run = function(ctx, args)
				local user = R.userByName(args.username)
				if not user then return ctx:fail("I could not find a Roblox user named `" .. args.username .. "`.") end
				local players, err = E.players()
				if not players and err == K.NOT_SET_UP then return apiFail(ctx, err) end
				local found
				for _, p in ipairs(players or {}) do
					local _, id = E.splitPlayer(p.Player)
					if id == tostring(user.id) then found = p break end
				end
				local link = sqldb:getLink(tostring(user.id))
				return ctx:card({
					title = "Player Lookup",
					thumbnail = R.headshot(user.id),
					blocks = {
						{ { "Username", user.name }, { "Display Name", user.displayName }, { "User ID", tostring(user.id) } },
						{
							{ "In Game", found and "Yes" or (players and "No" or "Unknown") },
							{ "Team", found and found.Team },
							{ "Callsign", found and found.Callsign ~= "" and found.Callsign or nil },
							{ "Permission", found and found.Permission },
						},
						{ { "Discord", link and link.discord and K.mention(link.discord) or "Not linked", link and link.discord and true } },
					},
					components = { { type = 1, components = { { type = 2, style = 5, label = "Roblox Profile", url = R.profile(user.id) } } } },
				})
			end
		},
		{
			name = "command", description = "Run a command in the in-game server.", tier = T.ADMIN,
			options = { { type = "string", name = "command", description = "The command, for example :h Server restart soon", required = true, rest = true } },
			run = function(ctx, args)
				local command = tostring(args.command):gsub("^%s+", "")
				if command:sub(1, 1) ~= ":" then command = ":" .. command end
				local ok, err = E.command(command)
				if not ok then return apiFail(ctx, err) end
				print("[scrp] erlc command by " .. ctx.user.id .. ": " .. command)
				return ctx:card({
					title = "Command Sent",
					blocks = { { { "Command", command }, { "Ran By", ctx.user.mentionString, true } } },
					banner = false,
				})
			end
		},
	}
})
