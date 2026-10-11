--[[
	Zeltra one-time seed (added by Zeltra; not part of upstream Ducky V1).

	Sets up the TSRP ticket hub. Only runs when SEED_TICKETS=1 (scripts/docker-start.sh backs the database up first).
	  * Posts the ticket panel (libs/zeltra-tickets-tsrp.lua) in #assistance as the bot, unless a panel with the
	    same key is already registered and its message still exists. In that case the message is left alone and
	    only the ticket types are refreshed (open tickets and ticket counters are kept).
	  * Registers it in the `panels` config key the way /setup's Ticket Panel Builder does
	    (panels[<message id>] = { channel, subjects, embeds }). Other panels are not touched, except bot panels
	    already registered for #assistance, which this one replaces.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local fs = require("fs")

return function(Client, sqldb, timer)
	local T = require("zeltra-tickets-tsrp")
	local function say(msg) print("[seed] tickets: " .. msg) end

	local guild = Client:getGuild(T.GUILD_ID)
	if not guild then return say("guild " .. T.GUILD_ID .. " not found, nothing done") end
	if type(sqldb:get(T.GUILD_ID)) ~= "table" then return say("guild config is not loaded, nothing done") end

	local channel = guild:getChannel(T.PANEL_CHANNEL)
	if not channel then return say("panel channel " .. T.PANEL_CHANNEL .. " not found, nothing done") end
	if not guild:getChannel(T.LOG_CHANNEL) then say("warning: ticket log channel " .. T.LOG_CHANNEL .. " not found") end
	for key, id in pairs(T.CATEGORIES) do
		if not guild:getCategory(id) then return say("category " .. key .. " (" .. id .. ") not found, nothing done") end
	end
	for key, id in pairs(T.ROLES) do
		if not guild:getRole(id) then say("warning: role " .. key .. " (" .. id .. ") not found") end
	end

	local stored = sqldb:get(T.GUILD_ID, true) or {}
	local panels = stored.panels or {}

	local existingId, existing
	for id, p in pairs(panels) do
		if type(p) == "table" and p.key == T.PANEL_KEY then existingId, existing = id, p end
	end

	local subjects = T.subjects()
	local messageId
	if existingId and channel:getMessage(existingId) then
		messageId = existingId
		T.mergeSubjects(subjects, existing.subjects)
		say("panel " .. existingId .. " already posted, refreshing its ticket types only")
	else
		-- replace bot panels already registered for #assistance
		for id, p in pairs(panels) do
			if type(p) == "table" and p.channel == T.PANEL_CHANNEL then
				local old = channel:getMessage(id)
				if old and old.author and old.author.id == Client.user.id then
					old:delete()
					say("deleted old bot panel " .. id)
				end
				if p.subjects then T.mergeSubjects(subjects, p.subjects) end
				panels[id] = nil
			end
		end
		local banner = fs.readFileSync("images/tickets/" .. T.BANNER)
		local strip = fs.readFileSync("images/tickets/" .. T.STRIP)
		if not banner or not strip then return say("panel images missing in images/tickets, nothing done") end
		local payload = T.panelPayload()
		payload.files = { { T.BANNER, banner }, { T.STRIP, strip } }
		local msg, err = channel:send(payload)
		if not msg then return say("could not post the panel: " .. tostring(err)) end
		messageId = msg.id
		say("posted panel " .. msg.id .. " in #" .. channel.name)
	end

	panels[messageId] = {
		key = T.PANEL_KEY,
		channel = T.PANEL_CHANNEL,
		subjects = subjects,
		embeds = T.panelEmbeds(),
	}
	local ok, err = sqldb:set(T.GUILD_ID, { panels = panels }, "SEED_TICKETS")
	if not ok then return say("could not save panels: " .. tostring(err)) end

	local fresh = sqldb:get(T.GUILD_ID, true) or {}
	local saved = fresh.panels and fresh.panels[messageId]
	if saved and saved.subjects and #saved.subjects == #T.TYPES then
		local parts = {}
		for i, s in ipairs(saved.subjects) do
			table.insert(parts, i .. "=" .. s.name .. "->" .. tostring(s.category))
		end
		say("verified panel " .. messageId .. " in the database: " .. table.concat(parts, ", "))
	else
		say("warning: panel " .. messageId .. " not found in the database after saving")
	end
end
