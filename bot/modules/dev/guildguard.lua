-- guildguard.lua: bot may only stay in the main guild or guilds owned by Shark's accounts.
local guard = { name = "guildguard", description = "Leaves unauthorized guilds." }

local MAIN_GUILD = "1522997818330058772"
local ALLOWED_GUILDS = { [MAIN_GUILD] = true }
local ALLOWED_OWNERS = { ["1307878235383795732"] = true, ["1514313618827510011"] = true }

local connections = {}

local function logSecurity(msg)
	pcall(function()
		local main = Client:getGuild(MAIN_GUILD)
		if not main then return end
		for channel in main.textChannels:iter() do
			if channel.name:lower():find("security-logs", 1, true) then
				channel:send(msg)
				return
			end
		end
	end)
end

local function check(guild)
	if not guild or not guild.id then return end
	if ALLOWED_GUILDS[guild.id] or ALLOWED_OWNERS[tostring(guild.ownerId)] then return end
	local name, owner = tostring(guild.name), tostring(guild.ownerId)
	local ok = pcall(function() guild:leave() end)
	print("[GUILDGUARD] Left unauthorized guild " .. name .. " (" .. guild.id .. ") owner " .. owner .. " ok=" .. tostring(ok))
	logSecurity("🛡️ Left unauthorized guild **" .. name .. "**\n-# `" .. guild.id .. "`・owner <@" .. owner .. "> (`" .. owner .. "`)・<t:" .. os.time() .. ":T>")
end

local function sweep()
	coroutine.wrap(function()
		local list = {}
		for g in Client.guilds:iter() do table.insert(list, g) end
		for _, g in ipairs(list) do check(g) end
	end)()
end

guard.Start = function()
	connections.ready = Client:on("ready", sweep)
	connections.guildCreate = Client:on("guildCreate", function(g) coroutine.wrap(check)(g) end)
	if Client.user then sweep() end
end

guard.Stop = function()
	for ev, c in pairs(connections) do Client:removeListener(ev, c) end
	connections = {}
end

return guard
