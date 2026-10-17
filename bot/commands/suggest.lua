-- suggest.lua (SCRP). Uses the existing suggestion module for votes. Hand-coded by Dex.
local K = _G.scrpKit

-- Template the suggestion module also uses when it refreshes votes.
local TEMPLATE = { {
	title = "New Suggestion",
	description = "> **Suggested By:** {submitter.mention}\n> **Suggestion:** {suggestion.suggestion}\n\n> **Upvotes:** `{suggestion.upvotes}`\n> **Downvotes:** `{suggestion.downvotes}`",
	color = K.COLOR,
	thumbnail = { url = "{submitter.avatar}" },
	footer = { text = K.FOOTER .. " | ID {suggestion.id}" },
} }

return K.command({
	name = "suggest",
	description = "Send a suggestion for the server.",
	aliases = { "suggestion" },
	options = { { type = "string", name = "suggestion", description = "Your idea.", required = true, rest = true, maxLength = 1500 } },
	run = function(ctx, args)
		local config = K.config(ctx.guild)
		local channel = config.suggestchannel and ctx.guild:getChannel(config.suggestchannel)
		if not channel or not channel.send then return ctx:fail("The suggestions channel is not set up yet.") end
		if not config.suggestionsubmittedembeds then
			K.save(ctx.guild, { suggestionsubmittedembeds = TEMPLATE }, "SCRP_SUGGESTION_TEMPLATE")
			config = K.config(ctx.guild)
		end
		local text = sanitize(string.truncate(args.suggestion, 1500), ctx.guild)
		local id = tostring(ctx.source.id)
		local suggestion = { id = id, suggestion = text, upvotes = {}, downvotes = {}, submitter = ctx.user.id }
		local keys = {
			["submitter.name"] = ctx.member and ctx.member.name or ctx.user.username, ["submitter.username"] = ctx.user.username,
			["submitter.id"] = ctx.user.id, ["submitter.mention"] = ctx.user.mentionString, ["submitter.avatar"] = ctx.user.avatarURL or "",
			["suggestion.suggestion"] = text, ["suggestion.upvotes"] = "0", ["suggestion.downvotes"] = "0", ["suggestion.id"] = id,
		}
		local msg, err = channel:send({
			embeds = parseTable(config.suggestionsubmittedembeds, keys),
			components = { { type = 1, components = {
				{ type = 2, style = 3, label = "Upvote", custom_id = "upvote_" .. id },
				{ type = 2, style = 4, label = "Downvote", custom_id = "downvote_" .. id },
			} } },
		})
		if not msg then return ctx:fail("I could not post your suggestion. " .. tostring(err or "")) end
		suggestion.message = msg.id
		config = K.config(ctx.guild)
		config.suggestions = config.suggestions or {}
		table.insert(config.suggestions, suggestion)
		K.save(ctx.guild, { suggestions = config.suggestions }, "SUGGESTION_CREATE")
		if config.suggestionthread then
			pcall(function() msg.channel:startThread(string.truncate("Suggestion from " .. ctx.user.username, 100), msg.id) end)
		end
		return ctx:ok("Your suggestion was posted: " .. msg.link)
	end
})
