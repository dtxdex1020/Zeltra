-- roleplay.lua (SCRP). Roleplay requests and logs. Hand-coded by Dex.
local K = _G.scrpKit
local T = K.TIER

return K.command({
	name = "roleplay",
	aliases = { "rp" },
	description = "Roleplay requests and logs.",
	subs = {
		{
			name = "request", description = "Ask staff to approve a roleplay scene.",
			options = {
				{ type = "string", name = "type", description = "Kind of roleplay.", required = true, choices = { "Pursuit", "Robbery", "Hostage", "Event", "Other" } },
				{ type = "string", name = "details", description = "What you have planned.", required = true, rest = true, maxLength = 800 },
			},
			run = function(ctx, args)
				local id = tostring(ctx.source.id)
				local card = K.card({
					title = "Roleplay Request",
					intro = "A member wants to run a roleplay. Staff can approve or deny it below.",
					blocks = {
						{ { "Requested By", ctx.user.mentionString, true }, { "Type", args.type } },
						{ { "Details", args.details } },
						{ { "Status", "Waiting for staff" } },
					},
				})
				card.components = { { type = 1, components = {
					{ type = 2, style = 3, label = "Approve", custom_id = "scrprp_approve_" .. id },
					{ type = 2, style = 4, label = "Deny", custom_id = "scrprp_deny_" .. id },
				} } }
				local msg, e = ctx.channel:send(card)
				if not msg then return ctx:fail("I could not post the request. " .. tostring(e or "")) end
				local list = K.config(ctx.guild).scrp_rprequests or {}
				list[id] = { user = ctx.user.id, type = args.type, details = args.details, channel = ctx.channel.id, message = msg.id, at = os.time() }
				K.save(ctx.guild, { scrp_rprequests = list }, "SCRP_RP_REQUEST")
				if ctx.isSlash then return ctx:send(K.notice("Your roleplay request is up."), true) end
			end
		},
		{
			name = "log", description = "Log a roleplay that happened.", tier = T.STAFF,
			options = {
				{ type = "string", name = "type", description = "Kind of roleplay.", required = true, choices = { "Pursuit", "Robbery", "Hostage", "Event", "Traffic Stop", "Other" } },
				{ type = "string", name = "summary", description = "What happened.", required = true, rest = true, maxLength = 1000 },
				{ type = "string", name = "players", description = "Who was involved." },
				{ type = "string", name = "outcome", description = "How it ended." },
			},
			run = function(ctx, args)
				local list = K.config(ctx.guild).scrp_rplogs or {}
				table.insert(list, { type = args.type, summary = args.summary, players = args.players, outcome = args.outcome, by = ctx.user.id, at = os.time() })
				K.save(ctx.guild, { scrp_rplogs = list }, "SCRP_RP_LOG")
				return ctx:card({
					title = "Roleplay Log #" .. #list,
					blocks = {
						{ { "Type", args.type }, { "Players", args.players }, { "Outcome", args.outcome } },
						{ { "Summary", args.summary } },
						{ { "Logged By", ctx.user.mentionString, true }, { "Date", "<t:" .. os.time() .. ":F>", true } },
					},
				})
			end
		},
	}
})
