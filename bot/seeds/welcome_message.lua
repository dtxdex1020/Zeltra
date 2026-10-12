--[[
	Zeltra one-time seed (added by Zeltra; not part of upstream Ducky V1).

	Sets the SCRP join message (libs/zeltra-welcome-scrp.lua) on Ducky's welcome feature: config.joinchannel and
	config.joinmessage. Only runs when SEED_WELCOME=1 (scripts/docker-start.sh backs the database up first).
	Posts nothing. Join DMs and the auto delete delay are left as they are and reported.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

return function(Client, sqldb, timer)
	local W = require("zeltra-welcome-scrp")
	local function say(msg) print("[seed] welcome: " .. msg) end

	local guild = Client:getGuild(W.GUILD_ID)
	if not guild then return say("guild " .. W.GUILD_ID .. " not found, nothing done") end
	local channel = guild:getChannel(W.CHANNEL)
	if not channel then return say("welcome channel " .. W.CHANNEL .. " not found, nothing done") end
	local stored = sqldb:get(W.GUILD_ID, true)
	if type(stored) ~= "table" then return say("guild config is not loaded, nothing done") end

	say("before: joinchannel=" .. tostring(stored.joinchannel) .. " joinmessage=" .. tostring(stored.joinmessage and stored.joinmessage.content)
		.. " dmjoin=" .. tostring(stored.dmjoin) .. " dmjoinmessage=" .. tostring(stored.dmjoinmessage ~= nil)
		.. " joinmessagedelete=" .. tostring(stored.joinmessagedelete) .. " joingatethreshold=" .. tostring(stored.joingatethreshold))

	local ok, err = sqldb:set(W.GUILD_ID, { joinchannel = W.CHANNEL, joinmessage = W.message() }, "SEED_WELCOME")
	if not ok then return say("could not save: " .. tostring(err)) end

	-- sqldb writes keys one per tick, so give the queue a moment before reading the database back
	if timer then timer.sleep(2000) end
	local fresh = sqldb:get(W.GUILD_ID, true) or {}
	if fresh.joinchannel == W.CHANNEL and fresh.joinmessage and fresh.joinmessage.content == W.message().content then
		say("verified: welcome messages go to #" .. channel.name .. " (" .. W.CHANNEL .. "), member count now " .. tostring(guild.totalMemberCount))
	else
		say("warning: settings not found in the database after saving")
	end
end
