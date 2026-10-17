-- sponsored.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit

return K.command({
	name = "sponsored",
	description = "Sponsored events.",
	tier = K.TIER.MGMT,
	subs = {
		{
			name = "giveaway", description = "Start a giveaway paid for by a sponsor.",
			options = {
				{ type = "user", name = "sponsor", description = "Who is sponsoring it.", required = true },
				{ type = "string", name = "duration", description = "How long it runs, like 30m, 6h, 2d.", required = true },
				{ type = "integer", name = "winners", description = "How many winners.", required = true, min = 1, max = 50 },
				{ type = "string", name = "prize", description = "What they win.", required = true, rest = true, maxLength = 180 },
				{ type = "role", name = "ping", description = "Role to ping." },
			},
			run = function(ctx, args)
				local sponsor = K.memberOf(ctx.guild, args.sponsor) or args.sponsor
				local msg, err = _G.scrpGiveawayCreate(ctx, args.prize .. " (Sponsored)", args.duration, args.winners, sponsor, args.ping)
				if not msg then return ctx:fail(err) end
				ctx.channel:send(K.notice("This giveaway is sponsored by " .. sponsor.mentionString .. ". Thank you for supporting South Carolina Roleplay."))
				return ctx:ok("The sponsored giveaway is live: " .. msg.link)
			end
		},
	}
})
