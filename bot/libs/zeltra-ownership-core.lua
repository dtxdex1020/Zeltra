--[[
	Zeltra ownership applications: questions and pure helpers (added by Zeltra; not part of upstream Ducky V1).
	Used by modules/server_management/ownership.lua and commands/ownership.lua. No Discord calls in here,
	so it can be unit tested (tests/ownership_test.lua).

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local M = {}

M.OWNERS = { "1307878235383795732", "1514313618827510011" }
M.DEFAULTS = {
	channel = nil,          -- review channel ID
	staffrole = "1522997818531512542", -- TSRP | Staff Team
	minrole = nil,          -- optional: applicant's top role must be at or above this role
	cooldowndays = 14,      -- after a denial
	enabled = true,
	apps = {},              -- [userId] = { status, submitted, decided, by, reason, message }
}
M.DRAFT_TTL = 2 * 3600

local DEF_HINT = "Explain each term in your own words. A sentence or two each is fine."

-- Each form is one modal (Discord allows 5 inputs per modal).
M.FORMS = {
	{
		section = "Definitions", title = "Definitions",
		questions = {
			{ id = "def1", label = "FRP, RDM and Mass RDM", description = DEF_HINT, style = 2, min = 10, max = 700 },
			{ id = "def2", label = "VDM, NITRP and NLR", description = DEF_HINT, style = 2, min = 10, max = 700 },
			{ id = "def3", label = "Metagaming, Powergaming, Combat logging", description = DEF_HINT, style = 2, min = 10, max = 700 },
			{ id = "def4", label = "Fail RP / LTAP, Cop baiting, Erratic driving", description = DEF_HINT, style = 2, min = 10, max = 700 },
		},
	},
	{
		section = "Scenarios", title = "What would you do? (1 of 2)",
		questions = {
			{ id = "sc1", label = "Mass RDM during a session", description = "Someone starts killing everyone in the middle of a session. Walk us through what you do.", style = 2, min = 10, max = 500 },
			{ id = "sc2", label = "A staff member abusing their powers", description = "You find out a staff member is misusing their permissions. What do you do?", style = 2, min = 10, max = 500 },
			{ id = "sc3", label = "A raid in the Discord", description = "Accounts flood the server with spam and pings. What steps do you take?", style = 2, min = 10, max = 500 },
			{ id = "sc4", label = "A dispute between high ranks", description = "Two high ranks are arguing in front of the staff team. How do you handle it?", style = 2, min = 10, max = 500 },
			{ id = "sc5", label = "A player reports a staff member", description = "A player says a staff member treated them unfairly. How do you look into it?", style = 2, min = 10, max = 500 },
		},
	},
	{
		section = "Scenarios", title = "What would you do? (2 of 2)",
		questions = {
			{ id = "sc6", label = "Server template or bot token leaked", description = "Our server template or a bot token gets posted publicly. What do you do first?", style = 2, min = 10, max = 500 },
			{ id = "sc7", label = "Someone threatens to DDoS us", description = "A user says they will DDoS the server or the game. How do you respond?", style = 2, min = 10, max = 500 },
			{ id = "sc8", label = "Low activity in sessions", description = "Sessions have been quiet for a few weeks. What would you change?", style = 2, min = 10, max = 500 },
			{ id = "sc9", label = "Drama with a partner server", description = "A partner server's staff start drama with ours. How do you handle it?", style = 2, min = 10, max = 500 },
		},
	},
	{
		section = "About you", title = "About you (1 of 2)",
		questions = {
			{ id = "age", label = "How old are you?", description = "Just the number. You need to be 13 or older to apply.", style = 1, min = 1, max = 3 },
			{ id = "timezone", label = "What's your timezone?", description = "For example EST, GMT or UTC-5.", style = 1, min = 2, max = 40 },
			{ id = "hours", label = "Hours a week you can give TSRP", description = "Roughly how many hours a week you can put in.", style = 1, min = 1, max = 40 },
		},
	},
	{
		section = "About you", title = "About you (2 of 2)",
		questions = {
			{ id = "experience", label = "Past ownership or management experience", description = "Servers you've owned or helped run, what you did there and how big they were.", style = 2, min = 10, max = 700 },
			{ id = "why", label = "Why do you want ownership?", description = "Be honest. What makes you want this role?", style = 2, min = 10, max = 700 },
			{ id = "grow", label = "How would you grow the server?", description = "Ideas for getting more players, keeping them, and making sessions better.", style = 2, min = 10, max = 700 },
		},
	},
}

M.QUESTION_COUNT = 0
M.BY_ID = {}
for _, form in ipairs(M.FORMS) do
	for _, q in ipairs(form.questions) do
		M.QUESTION_COUNT = M.QUESTION_COUNT + 1
		M.BY_ID[q.id] = q
		q.section = form.section
	end
end

local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = deepcopy(v) end
	return out
end

function M.withDefaults(stored)
	local out = deepcopy(type(stored) == "table" and stored or {})
	for k, v in pairs(M.DEFAULTS) do
		if out[k] == nil then out[k] = deepcopy(v) end
	end
	if type(out.apps) ~= "table" then out.apps = {} end
	return out
end

function M.isOwner(id)
	id = tostring(id or "")
	for _, o in ipairs(M.OWNERS) do if o == id then return true end end
	return false
end

--- Raw modal payload for form n, pre-filled with any saved answers.
function M.modal(n, answers)
	local form = M.FORMS[n]
	if not form then return nil end
	answers = answers or {}
	local components = {}
	for _, q in ipairs(form.questions) do
		local value = answers[q.id]
		if type(value) == "string" and #value > q.max then value = value:sub(1, q.max) end
		table.insert(components, {
			type = 18,
			label = q.label:sub(1, 45),
			description = q.description and q.description:sub(1, 100) or nil,
			component = {
				type = 4, custom_id = q.id, style = q.style, required = true,
				min_length = q.min, max_length = q.max,
				value = (type(value) == "string" and value ~= "") and value or nil,
			},
		})
	end
	return { custom_id = "ownapp:submit:" .. n, title = form.title:sub(1, 45), components = components }
end

--- { [custom_id] = value } from a modal submission (Label and legacy action-row layouts).
function M.parseModal(data)
	local out = {}
	local function take(c)
		if type(c) == "table" and c.custom_id and c.value ~= nil then out[c.custom_id] = tostring(c.value) end
	end
	for _, row in ipairs((data and data.components) or {}) do
		if row.component then take(row.component) end
		for _, c in ipairs(row.components or {}) do take(c) end
	end
	return out
end

function M.parseAge(text)
	local n = tonumber(tostring(text or ""):match("%d+"))
	return n
end

--- Can this user start an application? Returns true or false, reason.
function M.eligibility(record, now, cooldowndays)
	if type(record) ~= "table" then return true end
	if record.status == "pending" then
		return false, "You already have an application waiting for review. You'll get a DM when there's a decision."
	end
	if record.status == "accepted" then
		return false, "Your ownership application was already accepted."
	end
	if record.status == "denied" then
		local untilTime = (record.decided or 0) + (cooldowndays or 14) * 86400
		if now < untilTime then
			return false, "Your last application was denied. You can apply again <t:" .. math.floor(untilTime) .. ":R>.", untilTime
		end
	end
	return true
end

--- Which form to show next (first form with an unanswered question), or nil when all are done.
function M.nextForm(answers)
	for n, form in ipairs(M.FORMS) do
		for _, q in ipairs(form.questions) do
			if not answers[q.id] or answers[q.id] == "" then return n end
		end
	end
	return nil
end

local function clean(text)
	text = tostring(text or ""):gsub("\r", "")
	return text
end

--- Answer sections grouped into cards that stay under Discord's text limit.
--- Returns { { title = "Definitions", sections = { {title, body}, ... } }, ... }
function M.answerCards(answers, limit)
	limit = limit or 3300
	local cards, current, size = {}, nil, 0
	local lastSection
	for _, form in ipairs(M.FORMS) do
		for _, q in ipairs(form.questions) do
			if q.id ~= "age" and q.id ~= "timezone" and q.id ~= "hours" then
				local body = clean(answers[q.id])
				if body == "" then body = "No answer" end
				local cost = #q.label + #body + 12
				if not current or form.section ~= lastSection or size + cost > limit then
					local part = (current and form.section == lastSection) and " (continued)" or ""
					current = { title = form.section .. part, sections = {} }
					table.insert(cards, current)
					size = 0
					lastSection = form.section
				end
				table.insert(current.sections, { title = q.label, body = body })
				size = size + cost
			end
		end
	end
	return cards
end

function M.humanAge(seconds)
	local days = math.floor((seconds or 0) / 86400)
	if days >= 365 then
		local y = math.floor(days / 365)
		local m = math.floor((days % 365) / 30)
		return y .. "y" .. ((m > 0) and (" " .. m .. "mo") or "")
	elseif days >= 30 then
		return math.floor(days / 30) .. "mo"
	end
	return days .. "d"
end

return M
