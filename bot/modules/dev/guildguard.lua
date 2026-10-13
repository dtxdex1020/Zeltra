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
		local alerts = main:getChannel("1559377112471965788")
		if alerts then alerts:send(msg) return end
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


-- Main guild self-heal: keep the bot's own security fully on and the server-logs audit webhook present.
local SERVER_LOGS = "1522997828127948837"
local function ensureMain()
	local guild = Client:getGuild(MAIN_GUILD)
	if not guild or not sqldb then return end
	local ok, err = pcall(function()
		local config = sqldb:get(MAIN_GUILD) or {}
		local S = _G.securityCore or require("zeltra-security-core")
		local sec = S.withDefaults(config.security)
		local changed = false
		local function on(t, k) if t[k] ~= true then t[k] = true; changed = true end end
		on(sec, "enabled"); on(sec.antiraid, "enabled"); on(sec.antinuke, "enabled"); on(sec.botguard, "enabled")
		on(sec.keywords, "enabled"); on(sec.flagged, "enabled"); on(sec.antiraid, "autoraid"); on(sec.antinuke, "strip")
		if changed then sqldb:set(MAIN_GUILD, { security = sec }, "SECURITY_ENSURE_ON"); print("[GUILDGUARD] security settings turned back on") end

		local audit = type(config.auditlogchannels) == "table" and config.auditlogchannels or {}
		local primary = audit.primary
		local valid = primary and primary.webhook and primary.webhook.ID and Client:getWebhook(primary.webhook.ID)
		if not valid then
			local channel = guild:getChannel((primary and primary.channel) or SERVER_LOGS)
			local webhook = channel and channel:createWebhook("South Carolina Roleplay", "audit logs for South Carolina Roleplay")
			if webhook then
				pcall(function() webhook:setAvatar("images/scrp-icon.png") end)
				audit.primary = { channel = channel.id, webhook = { ID = webhook.id, TOKEN = webhook.token } }
				sqldb:set(MAIN_GUILD, { auditlogchannels = audit }, "AUDIT_LOG_PRIMARY_ENSURE")
				print("[GUILDGUARD] primary audit log webhook recreated: " .. webhook.id)
			else
				print("[GUILDGUARD] could not create the primary audit log webhook")
			end
		end
	end)
	if not ok then print("[GUILDGUARD] ensureMain failed: " .. tostring(err)) end
end

local function sweep()
	coroutine.wrap(function()
		local list = {}
		for g in Client.guilds:iter() do table.insert(list, g) end
		for _, g in ipairs(list) do check(g) end
		ensureMain()
		local dumpId = os.getenv("DUMP_ERROR_ID")
		if dumpId and dumpId ~= "" and sqldb and sqldb.getError then
			for id in dumpId:gmatch("[^,]+") do
				local ok, e = pcall(function() return sqldb:getError(id) end)
				print("[ERRDUMP] " .. id .. ": " .. (ok and e and _G.json.encode(e) or tostring(e)))
			end
		end
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
