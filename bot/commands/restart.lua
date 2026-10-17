-- restart.lua (SCRP). Railway starts the bot again on exit (restart policy ALWAYS). Hand-coded by Dex.
local K = _G.scrpKit

return K.command({
	name = "restart",
	description = "Restart the bot.",
	tier = K.TIER.OWN,
	options = { { type = "string", name = "reason", description = "Why.", rest = true } },
	run = function(ctx, args)
		ctx:ok("Restarting. I will be back in about a minute.")
		print("[scrp] restart by " .. ctx.user.id .. ": " .. tostring(args.reason or "no reason"))
		timer.setTimeout(1500, function()
			for _, mod in pairs(_G.modules or {}) do
				if mod.Stop then pcall(mod.Stop) end
			end
			os.exit(1)
		end)
	end
})
