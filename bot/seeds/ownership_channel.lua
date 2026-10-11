--[[
	Zeltra one-time seed (added by Zeltra; not part of upstream Ducky V1).

	Sets up ownership applications for Tennessee State Roleplay. Only runs when SEED_OWNERSHIP_APPS=1.
	  * If no channel named like "ownership-apps" exists, creates a private 「📝」ownership-apps in the
	    Log's category. @everyone is denied; only the two owner accounts and the bot get member overwrites.
	  * Writes the `ownershipapps` config key (defaults + review channel) only if it has no review
	    channel yet, so running it again is harmless. No other key is touched.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local GUILD_ID = "1522997818330058772"
local CATEGORY_ID = "1522997828127948833" -- Log's
local CHANNEL_NAME = "「📝」ownership-apps"
-- view, send, embed links, attach files, read history
local VIEW, SEND, EMBED, ATTACH, HISTORY = 1024, 2048, 16384, 32768, 65536
local MEMBER_ALLOW = VIEW + SEND + EMBED + ATTACH + HISTORY

return function(Client, sqldb, timer)
	local O = _G.ownershipCore
	local function say(msg) print("[seed] ownership apps: " .. msg) end

	local guild = Client:getGuild(GUILD_ID)
	if not guild then
		return say("guild " .. GUILD_ID .. " not found, nothing done")
	end
	if type(sqldb:get(GUILD_ID)) ~= "table" then
		return say("guild config is not loaded, nothing done")
	end
	local stored = sqldb:get(GUILD_ID, true) or {}
	local conf = O.withDefaults(stored.ownershipapps)

	if conf.channel and guild:getChannel(conf.channel) then
		return say("review channel already set to " .. tostring(conf.channel) .. ", left as is")
	end

	local channelId
	for channel in guild.textChannels:iter() do
		if channel.name:lower():find("ownership-apps", 1, true) then
			channelId = channel.id
			say("found existing channel #" .. channel.name .. " (" .. channel.id .. ")")
			break
		end
	end

	if not channelId then
		local overwrites = { { id = GUILD_ID, type = 0, allow = "0", deny = tostring(VIEW) } }
		local who = {}
		for _, id in ipairs(O.OWNERS) do
			table.insert(overwrites, { id = id, type = 1, allow = tostring(MEMBER_ALLOW), deny = "0" })
			table.insert(who, id)
		end
		table.insert(overwrites, { id = Client.user.id, type = 1, allow = tostring(MEMBER_ALLOW), deny = "0" })
		table.insert(who, Client.user.id .. " (bot)")

		local payload = {
			name = CHANNEL_NAME, type = 0,
			topic = "Ownership applications for the owners to review.",
			permission_overwrites = overwrites,
		}
		if guild:getCategory(CATEGORY_ID) then
			payload.parent_id = CATEGORY_ID
		else
			say("Log's category " .. CATEGORY_ID .. " not found, creating the channel without a category")
		end
		local data, err = Client._api:createGuildChannel(GUILD_ID, payload)
		if not data then
			return say("could not create the channel: " .. tostring(err))
		end
		channelId = data.id
		say("created #" .. tostring(data.name) .. " (" .. tostring(data.id) .. ") in category " .. tostring(payload.parent_id or "none")
			.. ", member overwrites for: " .. table.concat(who, ", ") .. "; @everyone denied")
	end

	conf.channel = channelId
	local ok, err = sqldb:set(GUILD_ID, { ownershipapps = conf }, "SEED_OWNERSHIP_APPS")
	if not ok then
		return say("write failed: " .. tostring(err))
	end
	say("ownershipapps config written with review channel " .. channelId)

	timer.setTimeout(5000, coroutine.wrap(function()
		local fresh = sqldb:get(GUILD_ID, true) or {}
		local c = fresh.ownershipapps
		say("read back from database: channel=" .. tostring(c and c.channel) .. ", cooldowndays=" .. tostring(c and c.cooldowndays)
			.. ", staffrole=" .. tostring(c and c.staffrole))
	end))
end
