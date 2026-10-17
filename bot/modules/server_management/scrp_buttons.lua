-- scrp_buttons.lua
-- Buttons for the SCRP commands: staff votes, training claims, roleplay approvals. Hand-coded by Dex.
local mod = {
	name = "scrp_buttons",
	description = "Handles the staff vote, training claim and roleplay request buttons."
}

local connection

local function K() return _G.scrpKit end

local function copyEmbed(message)
	local e = message and message.embeds and message.embeds[1]
	if not e then return nil end
	local out = {}
	for k, v in pairs(e) do out[k] = v end
	return out
end

local function setStatus(embed, status)
	local desc = tostring(embed.description or "")
	local new, n = desc:gsub("> %*%*Status:%*%* `[^`]*`", "> **Status:** `" .. status .. "`")
	if n == 0 then new = desc .. "\n\n> **Status:** `" .. status .. "`" end
	embed.description = new
	return embed
end

local function ephemeral(interaction, text)
	return interaction:reply(K().notice(text), true)
end

local function contains(list, id)
	for i, v in ipairs(list) do if v == id then return i end end
end

local function handleVote(interaction, choice, id)
	local kit = K()
	local config = kit.config(interaction.guild)
	local votes = config.scrp_votes or {}
	local vote = votes[id]
	if not vote then return ephemeral(interaction, "This vote is closed.") end
	if kit.tier(interaction.member) < (vote.minTier or kit.TIER.STAFF) then return ephemeral(interaction, "Only staff can vote.") end
	local uid = interaction.user.id
	vote.yes, vote.no = vote.yes or {}, vote.no or {}
	local other = choice == "yes" and vote.no or vote.yes
	local mine = choice == "yes" and vote.yes or vote.no
	local i = contains(other, uid)
	if i then table.remove(other, i) end
	local j = contains(mine, uid)
	local text
	if j then
		table.remove(mine, j)
		text = "Your vote was removed."
	else
		table.insert(mine, uid)
		text = "You voted " .. choice .. "."
	end
	votes[id] = vote
	kit.save(interaction.guild, { scrp_votes = votes }, "SCRP_STAFF_VOTE")
	local embed = copyEmbed(interaction.message)
	local payload = { components = _G.scrpVoteRow and _G.scrpVoteRow(id, #vote.yes, #vote.no) or nil }
	if embed then payload.embeds = { embed } end
	interaction:update(payload)
	interaction:reply(kit.notice(text), true)
end

local function handleTraining(interaction, id)
	local kit = K()
	if kit.tier(interaction.member) < kit.TIER.ADMIN then return ephemeral(interaction, "Only trainers can claim trainings.") end
	local config = kit.config(interaction.guild)
	local list = config.scrp_trainings or {}
	local req = list[id]
	if req and req.claimedBy then return ephemeral(interaction, "This training was already claimed.") end
	if req then
		req.claimedBy = interaction.user.id
		list[id] = req
		kit.save(interaction.guild, { scrp_trainings = list }, "SCRP_TRAINING_CLAIM")
	end
	local embed = copyEmbed(interaction.message)
	if embed then setStatus(embed, "Claimed by " .. interaction.user.username) end
	interaction:update({ embeds = embed and { embed } or nil, components = { { type = 1, components = { { type = 2, style = 2, label = "Claimed", custom_id = "scrptraining_claim_" .. id, disabled = true } } } } })
	if req and req.user then
		local member = interaction.guild:getMember(req.user)
		if member then
			pcall(dmStyle.send, member, {
				guild = interaction.guild, title = "Training claimed",
				intro = interaction.user.username .. " claimed your training request. They will reach out to set up a time.",
				footer = "Staff Training",
			})
		end
	end
end

local function handleRoleplay(interaction, action, id)
	local kit = K()
	if kit.tier(interaction.member) < kit.TIER.STAFF then return ephemeral(interaction, "Only staff can do that.") end
	local config = kit.config(interaction.guild)
	local list = config.scrp_rprequests or {}
	local req = list[id]
	if req and req.status then return ephemeral(interaction, "This request was already handled.") end
	local status = (action == "approve" and "Approved by " or "Denied by ") .. interaction.user.username
	if req then
		req.status = action
		req.by = interaction.user.id
		list[id] = req
		kit.save(interaction.guild, { scrp_rprequests = list }, "SCRP_RP_DECISION")
	end
	local embed = copyEmbed(interaction.message)
	if embed then setStatus(embed, status) end
	interaction:update({ embeds = embed and { embed } or nil, components = { { type = 1, components = { { type = 2, style = action == "approve" and 3 or 4, label = action == "approve" and "Approved" or "Denied", custom_id = "scrprp_done_" .. id, disabled = true } } } } })
	if req and req.user then
		local member = interaction.guild:getMember(req.user)
		if member then
			pcall(dmStyle.send, member, {
				guild = interaction.guild, title = "Roleplay request " .. (action == "approve" and "approved" or "denied"),
				intro = "Your " .. tostring(req.type) .. " roleplay request was " .. (action == "approve" and "approved" or "denied") .. " by " .. interaction.user.username .. ".",
				footer = "Roleplay",
			})
		end
	end
end

mod.Start = function()
	connection = Client:on("interactionCreate", function(interaction)
		coroutine.wrap(function()
			if not interaction.guild or not interaction.message or not interaction.data then return end
			local cid = interaction.data.custom_id
			if type(cid) ~= "string" or cid:sub(1, 4) ~= "scrp" or not _G.scrpKit then return end
			local ok, err = pcall(function()
				local choice, id = cid:match("^scrpvote_(%a+)_(%d+)$")
				if choice then return handleVote(interaction, choice, id) end
				id = cid:match("^scrptraining_claim_(%d+)$")
				if id then return handleTraining(interaction, id) end
				local action
				action, id = cid:match("^scrprp_(%a+)_(%d+)$")
				if action == "approve" or action == "deny" then return handleRoleplay(interaction, action, id) end
			end)
			if not ok then prettyLog("SCRP", "red", "button error: " .. tostring(err)) end
		end)()
	end)
end

mod.Stop = function()
	if connection then Client:removeListener("interactionCreate", connection) end
end

return mod
