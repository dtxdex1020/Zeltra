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

--- Copy of a page's questions in the format _G.prompt expects (it adds fields to the tables it gets).
function M.questions(page)
	local out = {}
	for _, q in ipairs(M.PAGES[page].questions) do
		out[#out + 1] = { question = q.question, placeholder = q.placeholder, style = q.style, required = q.required, min = q.min, max = q.max, key = q.key }
	end
	return out
end

--- Is the member allowed to apply right now? state = { cooldowns = {[userId]=until}, pending = {[userId]=timestamp} }
function M.canApply(state, userId, now)
	state = state or {}
	local untilTs = state.cooldowns and state.cooldowns[userId]
	if untilTs and now < untilTs then
		return false, "You were denied recently. You can apply again <t:" .. untilTs .. ":R>."
	end
	local pending = state.pending and state.pending[userId]
	if pending and now - pending < M.PENDING_COOLDOWN then
		return false, "Your application is still being reviewed. You'll get a DM once there's a decision."
	end
	return true
end

return M
