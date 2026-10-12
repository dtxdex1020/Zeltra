--[[
	Zeltra one-time seed (added by Zeltra; not part of upstream Ducky V1).

	Posts the server shop panel (libs/zeltra-shop-scrp.lua) in #marketplace and registers it as a ticket panel
	(config.panels[<message id>]), so picking an item opens a ticket. If the panel is already registered and its
	message still exists, the message is edited in place (images uploaded again) and the items are refreshed,
	keeping open tickets and counters. Only runs when SEED_SHOP=1.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local fs = require("fs")

return function(Client, sqldb, timer)
	local S = require("zeltra-shop-scrp")
	local function say(msg) print("[seed] shop: " .. msg) end

	local guild = Client:getGuild(S.GUILD_ID)
	if not guild then return say("guild not found, nothing done") end
	if type(sqldb:get(S.GUILD_ID)) ~= "table" then return say("guild config is not loaded, nothing done") end
	local channel = guild:getChannel(S.PANEL_CHANNEL)
	if not channel then return say("marketplace channel not found, nothing done") end
	if not guild:getCategory(S.CATEGORY) then return say("ticket category " .. S.CATEGORY .. " not found, nothing done") end

	local banner = fs.readFileSync("images/shop/" .. S.BANNER)
	local strip = fs.readFileSync("images/shop/" .. S.STRIP)
	if not banner or not strip then return say("images missing in images/shop, nothing done") end
	local files = { { S.BANNER, banner }, { S.STRIP, strip } }

	local stored = sqldb:get(S.GUILD_ID, true) or {}
	local panels = stored.panels or {}
	local existingId, existing
	for id, p in pairs(panels) do
		if type(p) == "table" and p.key == S.PANEL_KEY then existingId, existing = id, p end
	end

	local subjects = S.subjects()
	local payload = S.panelPayload()
	local messageId
	if existingId and channel:getMessage(existingId) then
		messageId = existingId
		S.mergeSubjects(subjects, existing.subjects)
		local data, err = Client._api:editMessage(channel.id, existingId,
			{ flags = payload.flags, components = payload.components, allowed_mentions = payload.allowed_mentions }, files)
		say(data and ("edited panel " .. existingId) or ("warning: could not edit panel: " .. tostring(err)))
	else
		if existingId then panels[existingId] = nil end
		payload.files = files
		local msg, err = channel:send(payload)
		if not msg then return say("could not post the panel: " .. tostring(err)) end
		messageId = msg.id
		say("posted panel " .. msg.id .. " in #" .. channel.name)
	end

	panels[messageId] = { key = S.PANEL_KEY, channel = S.PANEL_CHANNEL, subjects = subjects, escalation = S.escalation() }
	local ok, err = sqldb:set(S.GUILD_ID, { panels = panels }, "SEED_SHOP")
	if not ok then return say("could not save panels: " .. tostring(err)) end
	if timer then timer.sleep(2000) end
	local fresh = sqldb:get(S.GUILD_ID, true) or {}
	local saved = fresh.panels and fresh.panels[messageId]
	if saved and saved.subjects and #saved.subjects == #S.ITEMS and saved.escalation then
		say("verified panel " .. messageId .. " with " .. #saved.subjects .. " items")
	else
		say("warning: panel not found in the database after saving")
	end
end
