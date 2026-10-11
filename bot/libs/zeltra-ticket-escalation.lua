--[[
	Ticket escalation (added by Zeltra; not part of upstream Ducky V1).

	Rules for the Escalate button on ticket welcome cards: who counts as staff, someone's rank (their highest
	staff role by position), which tiers they may escalate to, the cooldown, and permission overwrite math.
	The settings live on the ticket panel (config.panels[id].escalation, see libs/zeltra-tickets-tsrp.lua).
	Kept free of Discordia so it can be tested; the handler is in modules/server_management/tickets.lua.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local E = {}

E.ACCESS = 1024 + 2048 + 16384 + 32768 + 65536 + 64 -- view, send, embed, attach, history, react
local LOW = 2 ^ 20

local function set(list)
	local s = {}
	for _, v in pairs(list or {}) do s[tostring(v)] = true end
	return s
end

--- Highest position among the member's roles that count as ranks (ignored roles and roles above the owner role skipped).
--- roles: list of { id, position }. ownerPos: position of the owner role (nil = no cap).
function E.rank(roles, esc, ownerPos)
	local ignore, best = set(esc and esc.ignoreroles), 0
	for _, r in ipairs(roles or {}) do
		local p = tonumber(r.position) or 0
		if not ignore[tostring(r.id)] and (not ownerPos or p <= ownerPos) and p > best then best = p end
	end
	return best
end

--- Staff: holds a support role of any ticket type or an escalation tier role, or ranks at or above the staff role.
function E.isStaff(roles, esc, subjects, staffPos, ownerPos)
	local support = {}
	for _, s in pairs(subjects or {}) do
		for _, id in pairs(s.support or {}) do support[tostring(id)] = true end
	end
	for _, t in pairs((esc and esc.tiers) or {}) do
		for _, id in pairs(t.roles or {}) do support[tostring(id)] = true end
	end
	for _, r in ipairs(roles or {}) do
		if support[tostring(r.id)] then return true end
	end
	return staffPos ~= nil and E.rank(roles, esc, ownerPos) >= staffPos
end

--- Tiers the presser may pick, lowest first: the tier role must exist and sit above both the presser's rank and the
--- ticket's current escalation. positionOf(roleId) returns the live position or nil when the role is gone.
function E.options(esc, positionOf, presserRank, currentPos)
	local out = {}
	for _, t in ipairs((esc and esc.tiers) or {}) do
		local p = positionOf(t.role)
		if p and p > (presserRank or 0) and p > (currentPos or 0) then
			out[#out + 1] = { tier = t, position = p }
		end
	end
	table.sort(out, function(a, b) return a.position < b.position end)
	return out
end

function E.findTier(esc, key)
	for _, t in ipairs((esc and esc.tiers) or {}) do
		if t.key == key then return t end
	end
end

--- Seconds left before this ticket can be escalated again (0 when it can).
function E.cooldownLeft(ticket, now, cooldown)
	local last = ticket and ticket.escalation and tonumber(ticket.escalation.at)
	if not last then return 0 end
	return math.max(0, (last + (tonumber(cooldown) or 0)) - now)
end

--- The ticket's current escalation position (0 when it was never escalated).
function E.currentPosition(ticket)
	return (ticket and ticket.escalation and tonumber(ticket.escalation.position)) or 0
end

--- New allow/deny strings for an overwrite with `bits` allowed. Values can be above 2^32 and LuaJIT's bit ops are
--- 32-bit, so only the low 20 bits are touched.
function E.allowBits(allow, deny, bits)
	local function low(v, on, off)
		v = tonumber(v) or 0
		local hi, lo = math.floor(v / LOW), v % LOW
		if on then lo = bit.bor(lo, on) end
		if off then lo = bit.band(lo, bit.bnot(off)) % LOW end
		return hi * LOW + lo
	end
	return string.format("%.0f", low(allow, bits)), string.format("%.0f", low(deny, nil, bits))
end

return E
