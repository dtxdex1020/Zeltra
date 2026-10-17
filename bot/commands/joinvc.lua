-- joinvc.lua (SCRP). The bot sits in a voice channel (no audio). Hand-coded by Dex.
local K = _G.scrpKit

return K.command({
	name = "joinvc",
	description = "Make the bot join a voice channel.",
	tier = K.TIER.ADMIN,
	options = { { type = "channel", name = "channel", description = "Voice channel (defaults to the one you are in)." } },
	run = function(ctx, args)
		local channel = args.channel or (ctx.member and ctx.member.voiceChannel)
		if not channel then return ctx:fail("Join a voice channel first, or give one.") end
		if channel.type ~= discordia.enums.channelType.voice and channel.type ~= 13 then return ctx:fail("That is not a voice channel.") end
		local shard = Client._shards[ctx.guild.shardId or 0]
		local ok, err = shard and shard:updateVoice(ctx.guild.id, channel.id, true, true)
		if not ok then return ctx:fail("I could not join that channel. " .. tostring(err or "")) end
		return ctx:ok("Joined " .. channel.mentionString .. ".")
	end
})
