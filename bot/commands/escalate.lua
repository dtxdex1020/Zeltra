-- escalate.lua (SCRP). Uses the ticket module's escalation rules. Hand-coded by Dex.
local K = _G.scrpKit

-- Tiers come from this ticket's escalation settings, so the list is built live.
local function tierOptions(ia, value)
	local esc = _G.scrpTicketEscalation
	if not esc then return {} end
	local st = esc.state(ia, K.config(ia.guild))
	local out = {}
	for _, o in ipairs((st and st.options) or {}) do
		if value == "" or o.tier.name:lower():find(value:lower(), 1, true) then
			table.insert(out, { name = string.truncate(o.tier.name, 100), value = tostring(o.tier.key) })
		end
	end
	return out
end

return K.command({
	name = "escalate",
	description = "Escalate things to higher staff.",
	tier = K.TIER.STAFF,
	subs = {
		{
			name = "ticket", description = "Escalate this ticket to a higher staff tier.",
			options = {
				{ type = "string", name = "tier", description = "Who to send it to.", required = true, autocomplete = tierOptions },
				{ type = "string", name = "reason", description = "Why it needs them.", rest = true, maxLength = 300 },
			},
			run = function(ctx, args)
				local esc = _G.scrpTicketEscalation
				if not esc then return ctx:fail("Ticket escalation is not loaded yet. Try again in a moment.") end
				local config = K.config(ctx.guild)
				local st, msg = esc.state(ctx.source, config)
				if not st then return ctx:fail(msg) end
				local pick
				for _, o in ipairs(st.options) do
					if o.tier.key == args.tier or o.tier.name:lower() == tostring(args.tier):lower() then pick = o end
				end
				if not pick then
					local names = {}
					for _, o in ipairs(st.options) do table.insert(names, o.tier.name) end
					return ctx:fail("You can't escalate this ticket to that tier. You can pick: " .. table.concat(names, ", ") .. ".")
				end
				local reason = args.reason and string.truncate(tostring(args.reason), 300) or nil
				local t = config.panels[st.pi].subjects[st.si].tickets[st.ti]
				t.escalation = { tier = pick.tier.key, name = pick.tier.name, position = pick.position, by = ctx.user.id, at = os.time(), reason = reason }
				t.escalatedroles = t.escalatedroles or {}
				for _, r in ipairs(pick.tier.roles or {}) do table.insert(t.escalatedroles, r) end
				K.save(ctx.guild, { panels = config.panels }, "TICKET_ESCALATE")
				st.ticket = t
				esc.apply(ctx.guild, ctx.channel, st, pick.tier, ctx.user, reason)
				if ctx.isSlash then return ctx:ok("This ticket was escalated to " .. pick.tier.name .. ".") end
			end
		},
	}
})
