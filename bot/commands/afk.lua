-- afk.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit

return K.command({
	name = "afk",
	description = "Set yourself as AFK. You come back the next time you talk.",
	options = {
		{ type = "string", name = "reason", description = "Why you are away.", maxLength = 300 },
	},
	run = function(ctx, args)
		local config = K.config(ctx.guild)
		local settings = sqldb:getUserSettings(ctx.user.id) or {}
		for _, a in pairs(config.afks or {}) do
			if a.id == ctx.user.id then return ctx:fail("You are already AFK.") end
		end
		if settings.afk then return ctx:fail("You are already AFK.") end

		local reason = args.reason
		if not reason or reason:match("^%s*$") then reason = settings.defaultafkreason or "AFK" end
		reason = sanitize(string.truncate(reason, 300), ctx.guild)

		local entry = { id = ctx.user.id, timestamp = os.time(), reason = reason }
		local ok, err
		if settings.globalafk then
			settings.afk = entry
			ok, err = sqldb:setUserSettings(ctx.user.id, settings)
		else
			config.afks = config.afks or {}
			table.insert(config.afks, entry)
			ok, err = K.save(ctx.guild, { afks = config.afks }, "AFK_SET")
		end
		if not ok then return ctx:fail("I could not set your AFK. " .. tostring(err or "")) end

		return ctx:card({
			title = "AFK Set",
			blocks = { { { "Member", ctx.user.mentionString, true }, { "Reason", reason } } },
			note = "Send a message to remove your AFK.",
			banner = false,
		})
	end
})
