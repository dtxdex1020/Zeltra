-- leavevc.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit

return K.command({
	name = "leavevc",
	description = "Make the bot leave voice.",
	tier = K.TIER.ADMIN,
	run = function(ctx)
		local shard = Client._shards[ctx.guild.shardId or 0]
		local ok, err = shard and shard:updateVoice(ctx.guild.id, nil)
		if not ok then return ctx:fail("I could not leave voice. " .. tostring(err or "")) end
		return ctx:ok("Left voice.")
	end
})
