--[[
	TSRP ticket hub (added by Zeltra; not part of upstream Ducky V1).

	The ticket types, categories, staff roles, welcome cards and the #assistance panel for Tennessee State
	Roleplay, in the format of Ducky's ticket module (config.panels[<message id>] = { subjects = {...} }).
	Used by the one-time seed (seeds/ticket_panel.lua) and the tests; kept free of Discordia.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local M = {}

M.GUILD_ID = "1522997818330058772"
M.PANEL_KEY = "tsrp-assistance-v1"
M.PANEL_CHANNEL = "1522997820116697226" -- 「📬」assistance
M.LOG_CHANNEL = "1522997828127948838" -- 「📁」ticket-logs (Log's)
M.COLOR = 3054591 -- sky blue, same as the server's other panels
M.LOGO = "<:tsrp_logo:1558645723527127122>"
M.BANNER = "banner-assistance.jpg"
M.STRIP = "strip.jpg"

M.CATEGORIES = {
	general = "1522997826462810194", -- ☰ General Assistance
	report = "1558873090098864289", -- ☰ Report Assistance (new)
	department = "1558873091650883657", -- ☰ Department Assistance (new)
	hr = "1522997826953412698", -- ☰ HR's Assistance
	shr = "1522997827662512339", -- ☰ SHR's Assistance
	ownership = "1558873093647245415", -- ☰ Ownership Assistance (new)
}

M.ROLES = {
	staff = "1522997818531512542", -- TSRP | Staff Team (base staff role, position 91)
	moderation = "1522997818510278864", -- TSRP I Moderation Team
	admin = "1522997818476855384", -- TSRP I Administration Team
	management = "1522997818426527853", -- TSRP | Management Board
	bod = "1522997818384580629", -- TSRP I Board Of Directors
	highrank = "1522997818476855376", -- TSRP I High Rank
	shr = "1522997818447626452", -- TSRP I Senior High Rank
	leadership = "1522997818384580634", -- TSRP I Community Leadership
	iaboard = "1522997818447626460", -- TSRP | Internal Affairs Board
	relations = "1522997818363740167", -- TSRP I Director of Relations
	depthead = "1522997818560741473", -- TSRP | Department Head
	thp = "1522997818560741476", -- Tennessee Highway Patrol: High Command
	dcso = "1522997818610942105", -- Davidson County Sheriff's Office: High Command
	npd = "1522997818610942110", -- NPD | High Command
	nfd = "1522997818648694868", -- NFD | High Command
	tdot = "1522997818648694873", -- TDOT | High Command
	owner = "1522997818330058781", -- TSRP | Owner
	coowner = "1522997818363740160", -- TSRP | Co-Owner
	aowner = "1522997818363740161", -- TSRP | Assistant Owner
	oboard = "1522997818363740163", -- TSRP I Ownership Board
}

M.OWNER_USERS = { "1307878235383795732", "1514313618827510011" }

local R = M.ROLES

local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = copy(v) end
	return o
end

local function card(title, intro, format, note)
	local lines = {}
	for _, q in ipairs(format) do table.insert(lines, "> **" .. q .. ":**") end
	return {
		{
			title = title,
			description = intro .. "\n\n**Copy this and fill it in:**\n" .. table.concat(lines, "\n")
				.. (note and ("\n\n" .. note) or "") .. "\n\n-# Ticket {ticket.number} · Please don't ping staff, someone will be with you soon.",
			color = M.COLOR,
		},
	}
end

-- name, emoji, short description (dropdown), bullets (panel), category, support roles, pinged roles, ticket prefix, welcome card
M.TYPES = {
	{
		key = "general", name = "General Support", emoji = "❓", prefix = "general",
		description = "Questions, prize redemption and in-game help",
		bullets = {
			"Questions about the server or the Discord",
			"Redeeming giveaway and event prizes",
			"Help with in-game issues in ER:LC",
			"Claiming supporter or booster perks",
		},
		category = "general", support = { R.admin }, mention = { R.admin },
		open = card("❓ General Support", "Thanks for reaching out, {opener.mention}. The Administration Team will help you soon.",
			{ "Roblox username", "What do you need help with", "Screenshots or extra details (if any)" }),
	},
	{
		key = "report", name = "Member Report", emoji = "🛑", prefix = "report",
		description = "Report a member breaking the rules (proof required)",
		bullets = {
			"Report a member breaking the rules in-game or in Discord",
			"Clips or screenshots are required",
			"__No proof means the ticket will be closed__",
		},
		category = "report", support = { R.moderation, R.admin }, mention = { R.moderation },
		open = card("🛑 Member Report", "Thanks for the report, {opener.mention}. The Moderation Team will look into it.",
			{ "Your Roblox username", "Who you are reporting (Roblox or Discord name)", "In-game or Discord", "What rule they broke",
				"Date and time", "Proof (clips or screenshots)" },
			"**No proof means this ticket will be closed.**"),
	},
	{
		key = "staffreport", name = "Staff Report", emoji = "🕵️", prefix = "staff-report",
		description = "Report a staff member to Internal Affairs",
		bullets = {
			"Report a staff member for abuse or breaking the rules",
			"Handled privately by Internal Affairs",
			"Include the staff member's name and your proof",
		},
		category = "hr", support = { R.iaboard }, mention = { R.iaboard },
		open = card("🕵️ Staff Report", "Thanks, {opener.mention}. Internal Affairs will handle this privately.",
			{ "Your Roblox username", "Staff member's name", "What happened", "Date and time", "Proof (clips or screenshots)" }),
	},
	{
		key = "appeal", name = "Appeals", emoji = "📝", prefix = "appeal",
		description = "Appeal an in-game or Discord moderation",
		bullets = {
			"Appeal an in-game or Discord moderation",
			"Include the date and the reason you were given",
			"Media evidence is highly recommended",
		},
		category = "hr", support = { R.highrank }, mention = { R.highrank },
		open = card("📝 Appeal", "Thanks, {opener.mention}. A High Rank will review your appeal.",
			{ "Roblox username", "What you were punished for (warning, kick, ban or Discord action)", "Who punished you (if you know)",
				"Date", "Why it should be removed" }),
	},
	{
		key = "department", name = "Departments", emoji = "🏢", prefix = "dept",
		description = "Department questions and applications",
		bullets = {
			"Questions about THP, DCSO, NPD, NFD or TDOT",
			"Department applications and transfers",
			"Anything else department related",
		},
		category = "department", support = { R.depthead, R.thp, R.dcso, R.npd, R.nfd, R.tdot }, mention = { R.depthead },
		open = card("🏢 Departments", "Thanks, {opener.mention}. Department leadership will be with you soon.",
			{ "Roblox username", "Which department", "Your question or application", "Extra details" }),
	},
	{
		key = "ads", name = "Paid Ads & Affiliates", emoji = "🤝", prefix = "ads",
		description = "Partnerships and paid ad redemption",
		bullets = {
			"Partnership and affiliation requests",
			"Redeeming a paid advertisement or paid giveaway, see <#1522997821811327137>",
		},
		category = "shr", support = { R.shr, R.relations }, mention = { R.relations },
		open = card("🤝 Paid Ads & Affiliates", "Thanks, {opener.mention}. Our relations team will get back to you soon.",
			{ "Server or brand name", "Affiliation or paid ad redemption", "Invite link", "Proof of payment (if redeeming)" }),
	},
	{
		key = "highrank", name = "High Rank Report", emoji = "💼", prefix = "hr-report",
		description = "Report a High Rank or above (proof required)",
		bullets = {
			"Only for reporting High Rank members and above",
			"Must have enough media proof",
			"__No proof means the ticket is closed right away__",
		},
		category = "shr", support = { R.shr, R.leadership }, mention = { R.shr, R.leadership },
		open = card("💼 High Rank Report", "Thanks, {opener.mention}. Senior leadership will handle this privately.",
			{ "Your Roblox username", "Who you are reporting and their rank", "What happened", "Date and time", "Proof (clips or screenshots)" },
			"**No proof means this ticket will be closed right away.**"),
	},
	{
		key = "ownership", name = "Ownership Support", emoji = "👑", prefix = "ownership",
		description = "Important matters for ownership",
		bullets = {
			"Important matters that need ownership",
			"Please use another ticket type if one fits",
		},
		category = "ownership", support = { R.owner, R.coowner, R.aowner, R.oboard }, mention = { R.owner, R.oboard },
		supportusers = M.OWNER_USERS,
		open = card("👑 Ownership Support", "Thanks, {opener.mention}. Ownership will reply as soon as they can.",
			{ "Roblox username", "What this is about", "Why it needs ownership" }),
	},
}

-- Escalation tiers for the Escalate button, lowest to highest. The handler sorts them by the live role position
-- and only offers tiers above the presser's highest staff role and above the ticket's current tier.
-- role: compared by position, roles: given view and send in the ticket, ping: pinged in the escalation card.
M.TIERS = {
	{ key = "admin", name = "Administration Team", role = R.admin, roles = { R.admin }, ping = { R.admin } },
	{ key = "highrank", name = "High Rank", role = R.highrank, roles = { R.highrank }, ping = { R.highrank } },
	{ key = "ia", name = "Internal Affairs Board", role = R.iaboard, roles = { R.iaboard }, ping = { R.iaboard } },
	{ key = "shr", name = "Senior High Rank", role = R.shr, roles = { R.shr }, ping = { R.shr } },
	{ key = "management", name = "Management Board", role = R.management, roles = { R.management }, ping = { R.management } },
	{ key = "leadership", name = "Community Leadership", role = R.leadership, roles = { R.leadership }, ping = { R.leadership } },
	{ key = "bod", name = "Board of Directors", role = R.bod, roles = { R.bod }, ping = { R.bod } },
	{ key = "ownership", name = "Ownership", role = R.oboard, roles = { R.owner, R.coowner, R.aowner, R.oboard }, ping = { R.owner, R.oboard } },
}

-- Escalation settings saved on the panel (config.panels[id].escalation).
function M.escalation()
	local tiers = {}
	for _, t in ipairs(M.TIERS) do
		tiers[#tiers + 1] = { key = t.key, name = t.name, role = t.role, roles = copy(t.roles), ping = copy(t.ping) }
	end
	return {
		tiers = tiers,
		staffrole = R.staff, -- this role or anything above it (by position) counts as staff
		ownerrole = R.owner, -- roles above this one (bots, bypass roles) are ignored when ranking someone
		-- roles that sit high in the list but are not ranks
		ignoreroles = {
			"1522997818426527846", -- Staff Of The Week
			"1522997818384580636", -- Currently Moderating
			"1522997818384580637", -- Currently On Break
			"1522997818531512551", -- Leave of Absence
			"1558858413885100153", -- "-"
			"1522997818330058779", -- Quarantine
		},
		cooldown = 120, -- seconds between escalations of one ticket
		logchannel = M.LOG_CHANNEL,
	}
end

local function shared(t)
	return {
		close = { {
			title = "Ticket Closed",
			description = "> This ticket was closed by {closer.mention}.\n> **Reason:** {reason}",
			color = 0xFF6666,
		} },
		claim = { {
			title = "Ticket Claimed",
			description = "> {claimer.mention} will be helping you with this ticket.\n> -# Thanks for your patience.",
			color = 0x66FF66,
		} },
		unclaim = { {
			title = "Ticket Unclaimed",
			description = "> {unclaimer.mention} unclaimed this ticket.\n> -# Another staff member will be with you soon.",
			color = 0xFFC72B,
		} },
		request = { {
			title = "Close Request",
			description = "> {requester.mention} would like to close this ticket.\n> **Reason:** {reason}",
			color = M.COLOR,
		} },
	}
end

--- Ducky subject tables, in panel order (the dropdown value is the index).
function M.subjects()
	local out = {}
	for _, t in ipairs(M.TYPES) do
		local embeds = shared(t)
		embeds.open = copy(t.open)
		table.insert(out, {
			name = t.name,
			description = t.description,
			emoji = t.emoji,
			key = t.key,
			category = M.CATEGORIES[t.category],
			support = copy(t.support),
			supportusers = t.supportusers and copy(t.supportusers) or nil,
			mentionables = copy(t.mention),
			transcriptschannel = M.LOG_CHANNEL,
			ticketname = t.prefix .. "-{ticket.number}",
			ticketclaimmode = "lock",
			embeds = embeds,
			tickets = {},
		})
	end
	return out
end

--- Keeps open tickets and counters from an existing panel when the subjects are rebuilt.
function M.mergeSubjects(fresh, old)
	local byKey = {}
	for _, s in ipairs(old or {}) do byKey[s.key or s.name] = s end
	for _, s in ipairs(fresh) do
		local o = byKey[s.key] or byKey[s.name]
		if o then
			s.tickets = o.tickets or {}
			s.nextticketid = o.nextticketid
		end
	end
	return fresh
end

--- Zero padded ticket number used in channel names: 1 -> "0001".
function M.number(n)
	return string.format("%04d", tonumber(n) or 0)
end

local function sectionText(t)
	local lines = { "### " .. t.emoji .. " " .. t.name }
	for _, b in ipairs(t.bullets) do table.insert(lines, "- " .. b) end
	return table.concat(lines, "\n")
end

--- The #assistance panel as a Components V2 message (banner and strip are uploaded as attachments).
function M.panelPayload()
	local sections = {}
	for _, t in ipairs(M.TYPES) do table.insert(sections, sectionText(t)) end
	local options = {}
	for i, t in ipairs(M.TYPES) do
		table.insert(options, { label = t.name, value = tostring(i), description = t.description, emoji = { name = t.emoji } })
	end
	local half = math.ceil(#sections / 2)
	return {
		flags = 32768,
		allowed_mentions = { parse = {} },
		components = { {
			type = 17,
			accent_color = M.COLOR,
			components = {
				{ type = 12, items = { { media = { url = "attachment://" .. M.BANNER } } } },
				{ type = 10, content = "## " .. M.LOGO .. " TSRP Ticket Hub\n"
					.. "Please read this before you open a ticket. Tickets that ignore these rules can be closed without warning, and troll tickets will be moderated. "
					.. "Once your ticket opens, follow the format the bot gives you." },
				{ type = 14, divider = true, spacing = 1 },
				{ type = 10, content = table.concat(sections, "\n", 1, half) },
				{ type = 10, content = table.concat(sections, "\n", half + 1) },
				{ type = 14, divider = true, spacing = 1 },
				{ type = 10, content = "### Before you open one\n- One ticket per issue, and explain it clearly.\n- Pick the right type so the right team sees it.\n- Don't ping staff to speed things up." },
				{ type = 1, components = { {
					type = 3,
					custom_id = "subjectselect",
					placeholder = "Click here to find ticket options",
					min_values = 0,
					max_values = 1,
					options = options,
				} } },
				{ type = 14, divider = true, spacing = 1 },
				{ type = 12, items = { { media = { url = "attachment://" .. M.STRIP } } } },
				{ type = 10, content = "-# Tennessee State Roleplay" },
			},
		} },
	}
end

--- Classic embed copy of the panel, stored as panel.embeds so /setup's panel builder can show and resend it.
function M.panelEmbeds()
	local fields = {}
	for _, t in ipairs(M.TYPES) do
		table.insert(fields, { name = t.emoji .. " " .. t.name, value = "- " .. table.concat(t.bullets, "\n- "), inline = false })
	end
	return { {
		title = "TSRP Ticket Hub",
		description = "Please read this before you open a ticket. Tickets that ignore these rules can be closed without warning. Follow the format the bot gives you once your ticket opens.",
		color = M.COLOR,
		fields = fields,
	} }
end

--- Total visible text in the panel (Components V2 limit is 4000).
function M.panelTextLength(payload)
	local n = 0
	local function walk(c)
		if type(c) ~= "table" then return end
		if c.type == 10 and c.content then n = n + #c.content end
		for _, v in pairs(c) do if type(v) == "table" then walk(v) end end
	end
	walk(payload or M.panelPayload())
	return n
end

return M
