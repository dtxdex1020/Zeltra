-- membercount.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit

return K.command({
	name = "membercount",
	description = "Show how many members are in the server.",
	aliases = { "mc", "members" },
	run = function(ctx)
		local guild = ctx.guild
		loadMembers(guild)
		local total = guild.totalMemberCount or table.count(guild.members)
		local bots = #(guild.bots or {})
		local day = table.count(getMembersJoinedWithin(guild, 86400) or {})
		local week = table.count(getMembersJoinedWithin(guild, 604800) or {})
		return ctx:card({
			title = "South Carolina Roleplay Members",
			thumbnail = guild.iconURL,
			blocks = {
				{ { "Total Members", K.commas(total) }, { "Humans", K.commas(total - bots) }, { "Bots", K.commas(bots) } },
				{ { "Joined Today", K.commas(day) }, { "Joined This Week", K.commas(week) } },
			},
		})
	end
})
