-- getinfo.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit
local R = _G.scrpApi.roblox

return K.command({
	name = "getinfo",
	description = "Get info on a member: account, Roblox link, and staff records.",
	aliases = { "whois", "userinfo" },
	tier = K.TIER.STAFF,
	options = { { type = "user", name = "user", description = "Member (ID or mention). Defaults to you." } },
	run = function(ctx, args)
		local user = args.user or ctx.user
		local member = K.memberOf(ctx.guild, user)
		user = (member and member.user) or user
		local config = K.config(ctx.guild)

		local infractions, active = 0, 0
		for _, inf in pairs(config.infractions or {}) do
			if tostring(inf.user) == tostring(user.id) then
				infractions = infractions + 1
				if not inf.revoked and not (inf.expires and inf.expires < os.time()) then active = active + 1 end
			end
		end
		local promotions = 0
		for _, p in pairs(config.promotions or {}) do
			if tostring(p.user) == tostring(user.id) then promotions = promotions + 1 end
		end

		local link = sqldb:getLink(user.id)
		local rblx = link and link.roblox and R.user(link.roblox)
		local rank = member and K.tier(member) or 0
		local created = math.floor(user.createdAt or os.time())

		return ctx:card({
			title = "Member Info",
			thumbnail = user.avatarURL,
			blocks = {
				{ { "Member", user.mentionString, true }, { "Username", user.username }, { "User ID", user.id } },
				{
					{ "Account Created", "<t:" .. created .. ":D>", true },
					{ "Joined Server", member and member.joinedAt and ("<t:" .. math.floor(discordia.Date.parseISO(member.joinedAt)) .. ":D>") or "Not in the server", member and member.joinedAt and true },
					{ "Top Role", member and member.highestRole and member.highestRole.mentionString or "None", member ~= nil },
					{ "Staff Rank", K.TIER_NAMES[math.min(rank, 7)] or "Member" },
				},
				{ { "Roblox", rblx and (rblx.name .. " (" .. rblx.id .. ")") or "Not verified" } },
				{ { "Infractions", infractions .. " total, " .. active .. " active" }, { "Promotions", tostring(promotions) } },
			},
		})
	end
})
