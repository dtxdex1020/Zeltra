-- say.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit

return K.command({
	name = "say",
	description = "Make the bot send a message.",
	tier = K.TIER.ADMIN,
	options = {
		{ type = "string", name = "message", description = "What to send.", required = true, rest = true, maxLength = 2000 },
		{ type = "channel", name = "channel", description = "Where to send it (defaults to here)." },
	},
	run = function(ctx, args)
		local channel = args.channel or ctx.channel
		if not channel or not channel.send then return ctx:fail("I could not find that channel.") end
		local text = tostring(args.message):gsub("\\n", "\n")
		local msg, err = channel:send({ content = string.truncate(text, 2000), allowed_mentions = { parse = {} } })
		if not msg then return ctx:fail("I could not send that. " .. tostring(err or "")) end
		print("[scrp] say by " .. ctx.user.id .. " in " .. channel.id)
		if ctx.isSlash then return ctx:send(K.notice("Sent."), true) end
		pcall(function() ctx.source:delete() end)
	end
})
