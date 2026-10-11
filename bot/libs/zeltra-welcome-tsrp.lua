--[[
	TSRP join message (added by Zeltra; not part of upstream Ducky V1).

	The welcome channel and join message for Tennessee State Roleplay, in the format of Ducky's welcome module
	(config.joinchannel / config.joinmessage, placeholders filled by modules/server_management/welcome.lua).
	Used by the one-time seed (seeds/welcome_message.lua) and the tests.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local M = {}

M.GUILD_ID = "1522997818330058772"
M.CHANNEL = "1558956607851864137" -- 「👋」welcome
M.LOGO = "<:tsrp_logo:1558645723527127122>" -- the bot's application emoji (bots can use their own app emojis anywhere)

function M.message()
	return {
		content = M.LOGO .. " **Welcome** {member.mention} (**{member.username}**) to **Tennessee**! We are now at **{guild.membercount}** members.",
	}
end

return M
