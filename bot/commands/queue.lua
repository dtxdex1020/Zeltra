-- queue.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit
local E = _G.scrpApi.erlc

return K.command({
	name = "queue",
	description = "Show how many players are waiting to join the in-game server.",
	run = function(ctx)
		local queue, err = E.queue()
		if not queue then
			return ctx:fail(err == K.NOT_SET_UP and "The ER:LC API is not set up yet." or tostring(err))
		end
		local server = E.server() or {}
		return ctx:card({
			title = "Server Queue",
			blocks = {
				{ { "In-Queue Players", tostring(#queue) } },
				{ { "In-game Players", tostring(server.CurrentPlayers or "?") .. "/" .. tostring(server.MaxPlayers or "?") }, { "Server Code", server.JoinKey } },
			},
		})
	end
})
