-- leaderboard.lua (SCRP). Donation totals. Hand-coded by Dex.
local K = _G.scrpKit
local T = K.TIER

local function totals(guild)
	local config = K.config(guild)
	return config.scrp_donations or {}
end

local function sorted(guild)
	local list = {}
	for id, amount in pairs(totals(guild)) do
		if tonumber(amount) and tonumber(amount) > 0 then table.insert(list, { id = id, amount = tonumber(amount) }) end
	end
	table.sort(list, function(a, b) return a.amount > b.amount end)
	return list
end
_G.scrpDonationTotals = sorted

local function boardCard(guild, title)
	local list = sorted(guild)
	local lines, sum = {}, 0
	for i, e in ipairs(list) do
		sum = sum + e.amount
		if i <= 10 then
			table.insert(lines, "> **" .. i .. ".** " .. K.mention(e.id) .. " `" .. K.commas(e.amount) .. " Robux`")
		end
	end
	return {
		title = title or "Donation Leaderboard",
		intro = "Thank you to everyone who supports South Carolina Roleplay.",
		body = (#lines > 0) and table.concat(lines, "\n") or "> No donations logged yet.",
		blocks = { { { "Total Donated", K.commas(sum) .. " Robux" }, { "Donors", tostring(#list) } } },
		thumbnail = guild.iconURL,
	}
end

local function change(ctx, args, sign)
	local amount = math.floor(tonumber(args.amount) or 0)
	if amount <= 0 then return ctx:fail("The amount has to be more than 0.") end
	local config = K.config(ctx.guild)
	local data = config.scrp_donations or {}
	local id = tostring(args.user.id)
	local before = tonumber(data[id]) or 0
	local after = math.max(0, before + sign * amount)
	data[id] = (after > 0) and after or nil
	K.save(ctx.guild, { scrp_donations = data }, sign > 0 and "SCRP_DONATION_ADD" or "SCRP_DONATION_REMOVE")
	return ctx:card({
		title = sign > 0 and "Donation Added" or "Donation Removed",
		blocks = {
			{ { "Member", args.user.mentionString, true }, { sign > 0 and "Added" or "Removed", K.commas(amount) .. " Robux" } },
			{ { "Before", K.commas(before) .. " Robux" }, { "Now", K.commas(after) .. " Robux" } },
			{ { "Note", args.note } },
		},
		banner = false,
	})
end

local changeOptions = {
	{ type = "user", name = "user", description = "The donor.", required = true },
	{ type = "integer", name = "amount", description = "Robux amount.", required = true, min = 1 },
	{ type = "string", name = "note", description = "Optional note.", rest = true },
}

return K.command({
	name = "leaderboard",
	description = "Donation leaderboard.",
	aliases = { "lb" },
	subs = {
		{ name = "view", description = "View the donation leaderboard.", run = function(ctx) return ctx:card(boardCard(ctx.guild)) end },
		{ name = "increase", aliases = { "add" }, description = "Add to a member's donation total.", tier = T.MGMT, options = changeOptions,
			run = function(ctx, args) return change(ctx, args, 1) end },
		{ name = "decrease", aliases = { "remove" }, description = "Take away from a member's donation total.", tier = T.MGMT, options = changeOptions,
			run = function(ctx, args) return change(ctx, args, -1) end },
		{
			name = "post", description = "Post the leaderboard in a channel.", tier = T.MGMT,
			options = { { type = "channel", name = "channel", description = "Where to post it (defaults to here)." } },
			run = function(ctx, args)
				local channel = args.channel or ctx.channel
				if not channel or not channel.send then return ctx:fail("I could not find that channel.") end
				local msg, err = channel:send(K.card(boardCard(ctx.guild)))
				if not msg then return ctx:fail("I could not post the leaderboard. " .. tostring(err or "")) end
				return ctx:ok("The leaderboard was posted in " .. channel.mentionString .. ".")
			end
		},
	}
})
