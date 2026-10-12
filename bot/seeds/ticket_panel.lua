--[[
	Zeltra one-time seed (added by Zeltra; not part of upstream Ducky V1).

	Sets up the SCRP ticket hub. Only runs when SEED_TICKETS=1 (scripts/docker-start.sh backs the database up first).
	  * Posts the ticket panel (libs/zeltra-tickets-scrp.lua) in #assistance as the bot, unless a panel with the
	    same key is already registered and its message still exists. In that case the message text is edited in place
	    and the ticket types are refreshed (open tickets and ticket counters are kept).
	  * Registers it in the `panels` config key the way /setup's Ticket Panel Builder does
	    (panels[<message id>] = { channel, subjects, embeds }). Other panels are not touched, except bot panels
	    already registered for #assistance, which this one replaces.
	  * Saves the escalation settings (panels[<message id>].escalation) and adds the Escalate button to the
	    welcome card of tickets that were opened before it existed.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local fs = require("fs")

return function(Client, sqldb, timer)
	local T = require("zeltra-tickets-scrp")
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
		say("panel " .. existingId .. " already posted, refreshing its ticket types and text")
		-- edit the text in place; the banner and strip stay as the message's existing attachments
		local payload = T.panelPayload()
		local data, err = Client._api:editMessage(channel.id, existingId, { flags = payload.flags, components = payload.components, allowed_mentions = payload.allowed_mentions })
		if data then say("edited panel " .. existingId .. " text") else say("warning: could not edit panel text, left as is: " .. tostring(err)) end
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
		escalation = T.escalation(),
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
		for i, s in ipairs(saved.subjects) do
			local function names(list)
				local out = {}
				for _, id in ipairs(list or {}) do
					local r = guild:getRole(id)
					table.insert(out, r and r.name or ("missing " .. id))
				end
				return table.concat(out, " + ")
			end
			say(i .. " " .. s.name .. ": access " .. names(s.support) .. "; ping " .. names(s.mentionables) .. "; open tickets " .. #(s.tickets or {}))
		end
		local tiers = {}
		for _, t in ipairs((saved.escalation and saved.escalation.tiers) or {}) do
			local r = guild:getRole(t.role)
			table.insert(tiers, t.name .. "@" .. tostring(r and r.position or "missing"))
		end
		say("escalation tiers: " .. table.concat(tiers, ", "))
	else
		say("warning: panel " .. messageId .. " not found in the database after saving")
		return
	end

	-- add the Escalate button to welcome cards of tickets opened before it existed
	local updated = 0
	for _, s in ipairs(saved.subjects) do
		for _, t in ipairs(s.tickets or {}) do
			local ok2, e2 = pcall(function()
				local ch = guild:getChannel(t.channel)
				local pins = ch and ch:getPinnedMessages()
				if not pins then return end
				for m in pins:iter() do
					local row = m.author and m.author.id == Client.user.id and m.components and m.components[1]
					local btns = row and row.components
					if btns and btns[1] and btns[1].custom_id == "ticketclaim" then
						local has = false
						for _, b in ipairs(btns) do if b.custom_id == "ticketescalate" then has = true end end
						if not has then
							table.insert(btns, { type = 2, custom_id = "ticketescalate", label = "Escalate", style = 1, emoji = { name = "⬆️" } })
							Client._api:editMessage(ch.id, m.id, { components = m.components })
							updated = updated + 1
						end
					end
				end
			end)
			if not ok2 then say("warning: could not update ticket " .. tostring(t.channel) .. ": " .. tostring(e2)) end
		end
	end
	say("added the Escalate button to " .. updated .. " open ticket(s)")
end
