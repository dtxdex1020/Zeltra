-- funds.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit

return K.command({
	name = "funds",
	description = "Show the server's donation funds.",
	run = function(ctx)
		local list = (_G.scrpDonationTotals and _G.scrpDonationTotals(ctx.guild)) or {}
		local sum, top = 0, list[1]
		for _, e in ipairs(list) do sum = sum + e.amount end
		return ctx:card({
			title = "Server Funds",
			intro = "All donations go back into the server: events, giveaways, and upgrades.",
			blocks = {
				{ { "Total Donated", K.commas(sum) .. " Robux" }, { "Donors", tostring(#list) } },
				{ { "Top Donor", top and (K.mention(top.id) .. " `" .. K.commas(top.amount) .. " Robux`") or "Nobody yet", true } },
			},
			note = "Run -leaderboard view to see the full list.",
		})
	end
})
