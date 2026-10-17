-- training.lua (SCRP). Staff training requests and results. Hand-coded by Dex.
local K = _G.scrpKit
local T = K.TIER

return K.command({
	name = "training",
	description = "Staff training.",
	tier = T.STAFF,
	subs = {
		{
			name = "request", description = "Ask for a staff training.",
			options = {
				{ type = "string", name = "type", description = "What training you need.", choices = { "Moderation", "Server Commands", "Tickets", "Sessions", "Other" } },
				{ type = "string", name = "availability", description = "When you are free, like 6pm to 9pm EST.", rest = true, maxLength = 200 },
			},
			run = function(ctx, args)
				local id = tostring(ctx.source.id)
				local card = K.card({
					title = "Training Request",
					intro = "A staff member is asking for training. A trainer can claim it below.",
					blocks = {
						{ { "Staff Member", ctx.user.mentionString, true }, { "Training", args.type or "General" }, { "Availability", args.availability or "Any time" } },
						{ { "Status", "Waiting for a trainer" } },
					},
				})
				card.components = { { type = 1, components = { { type = 2, style = 1, label = "Claim", custom_id = "scrptraining_claim_" .. id } } } }
				local msg, e = ctx.channel:send(card)
				if not msg then return ctx:fail("I could not post the request. " .. tostring(e or "")) end
				local list = K.config(ctx.guild).scrp_trainings or {}
				list[id] = { user = ctx.user.id, type = args.type or "General", availability = args.availability, channel = ctx.channel.id, message = msg.id, at = os.time() }
				K.save(ctx.guild, { scrp_trainings = list }, "SCRP_TRAINING_REQUEST")
				if ctx.isSlash then return ctx:send(K.notice("Your training request is up."), true) end
			end
		},
		{
			name = "results", description = "Post the results of a training.", tier = T.ADMIN,
			options = {
				{ type = "user", name = "user", description = "Trainee (ID or mention).", required = true },
				{ type = "string", name = "result", description = "Passed or failed.", required = true, choices = { "Passed", "Failed" } },
				{ type = "integer", name = "score", description = "Score out of 10.", min = 0, max = 10 },
				{ type = "string", name = "notes", description = "Notes for the trainee.", rest = true, maxLength = 1000 },
			},
			run = function(ctx, args)
				local member = K.memberOf(ctx.guild, args.user)
				if not member then return ctx:fail("That user is not in the server.") end
				local list = K.config(ctx.guild).scrp_trainingresults or {}
				table.insert(list, { user = member.id, result = args.result, score = args.score, notes = args.notes, by = ctx.user.id, at = os.time() })
				K.save(ctx.guild, { scrp_trainingresults = list }, "SCRP_TRAINING_RESULT")
				pcall(dmStyle.send, member, {
					guild = ctx.guild, title = "Training " .. args.result:lower(),
					intro = args.result == "Passed" and "Nice work. You passed your training in **" .. dmStyle.serverName(ctx.guild) .. "**." or "You did not pass your training this time in **" .. dmStyle.serverName(ctx.guild) .. "**. You can request another one.",
					fields = { { "Score", args.score and (args.score .. " out of 10") or "N/A" }, { "Notes", args.notes or "None" }, { "Trainer", ctx.user.username } },
					footer = "Staff Training",
				})
				local card = K.card({
					title = "Training Results",
					blocks = {
						{ { "Trainee", member.mentionString, true }, { "Result", args.result }, { "Score", args.score and (args.score .. " out of 10") } },
						{ { "Notes", args.notes }, { "Trainer", ctx.user.mentionString, true } },
					},
				})
				card.content = member.mentionString
				card.allowed_mentions = { users = { member.id } }
				return ctx:send(card)
			end
		},
	}
})
