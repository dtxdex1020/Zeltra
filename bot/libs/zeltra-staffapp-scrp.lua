--[[
	SCRP staff application and join roles (added by Zeltra; not part of upstream Ducky V1).
	Settings and question text for modules/server_management/scrp.lua; kept free of Discordia for the tests.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local M = {}

M.GUILD_ID = "1522997818330058772"
M.COLOR = 16738816

-- join roles and verification (Bloxlink assigns VERIFIED, the bot then removes UNVERIFIED)
M.COMMUNITY_MEMBER = "1522997818774782013"
M.UNVERIFIED = "1522997818837700638"
M.VERIFIED = "1559287862367621251"
M.VERIFIED_NAMES = { ["verified"] = true } -- any role with this name counts as verified too

-- staff applications
M.REVIEW_CHANNEL = "1522997820775469129" -- 「📄」app-responses (private)
M.RESULTS_CHANNEL = "1522997820775469127" -- 「✉️」app-results
M.REVIEW_PING = "1522997818476855376" -- SCRP I High Rank
M.REVIEWER_ROLE = "1522997818476855376" -- High Rank or above (by position) can accept or deny
M.PASS_ROLE = "1522997818510278866" -- SCRP | Awaiting Training
M.COOLDOWN = 14 * 24 * 3600 -- after a denial
M.PENDING_COOLDOWN = 7 * 24 * 3600 -- a pending application blocks a new one for up to a week

M.PAGES = {
	{
		title = "Staff Application (1 of 2)",
		questions = {
			{ key = "roblox", question = "Roblox username", placeholder = "Your exact Roblox username", style = "short", required = true, max = 40 },
			{ key = "age", question = "How old are you?", placeholder = "Your age", style = "short", required = true, max = 3 },
			{ key = "activity", question = "Time zone and hours a week", placeholder = "Example: EST, about 10 hours a week", style = "short", required = true, max = 100 },
			{ key = "experience", question = "Past staff experience", placeholder = "Where you staffed before, your rank and how long. Say none if you have none.", style = "paragraph", required = true, max = 800 },
			{ key = "why", question = "Why do you want to be SCRP staff?", placeholder = "In your own words", style = "paragraph", required = true, min = 50, max = 1000 },
		},
	},
	{
		title = "Staff Application (2 of 2)",
		questions = {
			{ key = "rdm", question = "Someone is RDMing in game. What do you do?", placeholder = "Walk us through how you handle it", style = "paragraph", required = true, min = 40, max = 800 },
			{ key = "chat", question = "A member argues with staff in chat. You?", placeholder = "How do you handle a member arguing with staff in general chat?", style = "paragraph", required = true, min = 40, max = 800 },
			{ key = "terms", question = "What do FRP and VDM mean?", placeholder = "Explain both and give an example of each", style = "paragraph", required = true, min = 30, max = 600 },
			{ key = "bring", question = "What would you bring to the team?", placeholder = "Skills, availability, anything that makes you a good fit", style = "paragraph", required = true, min = 30, max = 800 },
			{ key = "extra", question = "Anything else we should know?", placeholder = "Optional", style = "paragraph", required = false, max = 600 },
		},
	},
}

-- High Rank application. Same flow, review buttons and result format as the staff one.
-- Only members who already hold a staff role can send it. Reviews go to the same app-responses channel, labeled HR.
M.HR = {
	kind = "hr",
	name = "High Rank application",
	footer = "High Rank Applications",
	stateKey = "scrphrapps",
	REVIEW_CHANNEL = M.REVIEW_CHANNEL,
	RESULTS_CHANNEL = M.RESULTS_CHANNEL,
	REVIEW_PING = "1522997818447626452", -- SCRP I Senior High Rank
	REVIEWER_ROLE = "1522997818447626452", -- Senior High Rank or above can accept or deny
	STAFF_ROLE = "1522997818531512542", -- SCRP | Staff Team
	PASS_ROLE = nil, -- HR rank is given by hand after acceptance
	COOLDOWN = 14 * 24 * 3600,
	PENDING_COOLDOWN = 7 * 24 * 3600,
	NOT_STAFF = "Thanks for your interest! The High Rank application is only open to current SCRP staff. If you're not on the team yet, you can send a staff application first.",
	PAGES = {
		{
			title = "High Rank Application (1 of 3)",
			questions = {
				{ key = "roblox", question = "Roblox username", placeholder = "Your exact Roblox username", style = "short", required = true, max = 40 },
				{ key = "age", question = "How old are you?", placeholder = "Your age", style = "short", required = true, max = 3 },
				{ key = "rank", question = "Current SCRP rank and how long you've had it", placeholder = "Example: Senior Moderator, about 2 months", style = "short", required = true, max = 100 },
				{ key = "activity", question = "Time zone and weekly availability", placeholder = "Time zone, hours a week and the days and times you're usually on", style = "paragraph", required = true, min = 30, max = 400 },
				{ key = "experience", question = "Leadership experience, with proof", placeholder = "Where, what rank, how long and what you did. Add links or screenshots as proof.", style = "paragraph", required = true, min = 150, max = 1500 },
			},
		},
		{
			title = "High Rank Application (2 of 3)",
			questions = {
				{ key = "interview", question = "How would you interview staff applicants?", placeholder = "What you look for, what you ask and how you decide pass or fail", style = "paragraph", required = true, min = 200, max = 1500 },
				{ key = "discipline", question = "How do you decide promotions and firings?", placeholder = "How you keep promotions, demotions and terminations fair and backed by proof", style = "paragraph", required = true, min = 200, max = 1500 },
				{ key = "friend", question = "A friend of yours breaks the rules. You?", placeholder = "Walk us through it step by step", style = "paragraph", required = true, min = 150, max = 1200 },
				{ key = "abuse", question = "A staff member is abusing powers. You?", placeholder = "From finding proof to the punishment and follow up", style = "paragraph", required = true, min = 200, max = 1500 },
				{ key = "leak", question = "There's a leak or a raid. What do you do?", placeholder = "Your first steps, who you contact and how you stop it from happening again", style = "paragraph", required = true, min = 200, max = 1500 },
			},
		},
		{
			title = "High Rank Application (3 of 3)",
			questions = {
				{ key = "improve", question = "What would you improve about SCRP staff?", placeholder = "Be specific and say how you'd do it", style = "paragraph", required = true, min = 150, max = 1500 },
				{ key = "why", question = "Why should you be High Rank?", placeholder = "In your own words, not a list of ranks", style = "paragraph", required = true, min = 150, max = 1200 },
				{ key = "agree", question = "Do you agree to the HR rules and privacy?", placeholder = "Type I agree. You'll follow the HR rules and keep HR matters confidential.", style = "short", required = true, min = 7, max = 60 },
				{ key = "extra", question = "Anything else we should know?", placeholder = "Optional", style = "paragraph", required = false, max = 800 },
			},
		},
	},
}

-- staff application as a config table too (same fields as M.HR), so scrp.lua can run both with one flow
M.STAFF = {
	kind = "staff",
	name = "staff application",
	footer = "Staff Applications",
	stateKey = "scrpapps",
	REVIEW_CHANNEL = M.REVIEW_CHANNEL,
	RESULTS_CHANNEL = M.RESULTS_CHANNEL,
	REVIEW_PING = M.REVIEW_PING,
	REVIEWER_ROLE = M.REVIEWER_ROLE,
	PASS_ROLE = M.PASS_ROLE,
	COOLDOWN = M.COOLDOWN,
	PENDING_COOLDOWN = M.PENDING_COOLDOWN,
	PAGES = M.PAGES,
}

--- Custom id prefix for an application kind. Staff keeps the old ids so posted panels and review cards still work.
function M.prefix(cfg)
	return (cfg and cfg.kind == "hr") and "scrpapp_hr_" or "scrpapp_"
end

--- Which application and action a button id belongs to: returns cfg, action, userId (action is start, next, acc or deny)
function M.parseId(id)
	if type(id) ~= "string" then return nil end
	local cfg, rest = M.STAFF, id:match("^scrpapp_(.+)$")
	if not rest then return nil end
	local hr = rest:match("^hr_(.+)$")
	if hr then cfg, rest = M.HR, hr end
	if rest == "start" or rest == "next" then return cfg, rest end
	local action, userId = rest:match("^(%a+)_(%d+)$")
	if action == "acc" or action == "deny" then return cfg, action, userId end
	return nil
end

--- Does the member hold a staff role? roleIds is a set {[id]=true}; extra is an optional checker (hasStaffRank).
function M.isStaff(cfg, roleIds, extra)
	if cfg.STAFF_ROLE and roleIds[cfg.STAFF_ROLE] then return true end
	return extra == true
end

--- Copy of a page's questions in the format _G.prompt expects (it adds fields to the tables it gets).
function M.questions(page, cfg)
	local out = {}
	for _, q in ipairs((cfg or M).PAGES[page].questions) do
		out[#out + 1] = { question = q.question, placeholder = q.placeholder, style = q.style, required = q.required, min = q.min, max = q.max, key = q.key }
	end
	return out
end

--- Is the member allowed to apply right now? state = { cooldowns = {[userId]=until}, pending = {[userId]=timestamp} }
function M.canApply(state, userId, now, cfg)
	cfg = cfg or M
	state = state or {}
	local untilTs = state.cooldowns and state.cooldowns[userId]
	if untilTs and now < untilTs then
		return false, "You were denied recently. You can apply again <t:" .. untilTs .. ":R>."
	end
	local pending = state.pending and state.pending[userId]
	if pending and now - pending < cfg.PENDING_COOLDOWN then
		return false, "Your application is still being reviewed. You'll get a DM once there's a decision."
	end
	return true
end

return M
