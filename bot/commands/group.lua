-- group.lua (SCRP). Roblox group through Open Cloud. Hand-coded by Dex.
local K = _G.scrpKit
local R = _G.scrpApi.roblox
local T = K.TIER

local function notReady(ctx)
	if not R.ready() then
		ctx:fail("The Roblox group is not set up yet.")
		return true
	end
end

local function apiFail(ctx, err) return ctx:fail(tostring(err or "Roblox did not answer.")) end

return K.command({
	name = "group",
	description = "Roblox group commands.",
	subs = {
		{
			name = "info", description = "Show the Roblox group info.",
			run = function(ctx)
				if notReady(ctx) then return end
				local g, err = R.info()
				if not g then return apiFail(ctx, err) end
				local ownerId = tostring(g.owner or ""):match("(%d+)$")
				local owner = ownerId and R.user(ownerId)
				local pending = R.joinRequests(20)
				local pendingCount = pending and pending.groupJoinRequests and #pending.groupJoinRequests or nil
				return ctx:card({
					title = "SCRP Roblox Group",
					blocks = {
						{ { "Group Name", g.displayName }, { "Group ID", g.id or R.groupId() }, { "Owner", owner and owner.name or "Unknown" } },
						{ { "Members", g.memberCount and K.commas(g.memberCount) or "Unknown" }, { "Pending Requests", pendingCount and (pendingCount >= 20 and "20+" or tostring(pendingCount)) }, { "Open To Join", g.publicEntryAllowed and "Yes" or "Request only" } },
					},
					components = { { type = 1, components = { { type = 2, style = 5, label = "Open Group", url = R.groupLink() } } } },
				})
			end
		},
		{
			name = "request", description = "Send your Roblox join request to staff.",
			options = { { type = "string", name = "username", description = "Your Roblox username (defaults to your verified account)." } },
			run = function(ctx, args)
				if notReady(ctx) then return end
				local user
				if args.username then
					user = R.userByName(args.username)
				else
					local link = sqldb:getLink(ctx.user.id)
					user = link and link.roblox and R.user(link.roblox)
				end
				if not user then return ctx:fail(args.username and "I could not find that Roblox user." or "You are not verified. Run -verify me first, or give your Roblox username.") end
				local member = R.membership(user.id)
				if member then return ctx:fail("**" .. user.name .. "** is already in the group.") end
				local pending, err = R.pendingRequest(user.id)
				if pending == nil then return apiFail(ctx, err) end
				if not pending then
					return ctx:card({
						title = "Group Request",
						intro = "I don't see a join request from **" .. user.name .. "**. Press Open Group, send a join request on Roblox, then run this again.",
						components = { { type = 1, components = { { type = 2, style = 5, label = "Open Group", url = R.groupLink() } } } },
						banner = false,
					})
				end
				local config = K.config(ctx.guild)
				local list = config.scrp_grouprequests or {}
				list[tostring(user.id)] = { discord = ctx.user.id, name = user.name, at = os.time() }
				K.save(ctx.guild, { scrp_grouprequests = list }, "SCRP_GROUP_REQUEST")
				return ctx:card({
					title = "Group Request Sent",
					intro = "Your join request is on file. Staff will accept it soon.",
					blocks = { { { "Roblox Account", user.name }, { "Discord", ctx.user.mentionString, true } } },
					note = "Staff: run -group accept " .. user.name,
					banner = false,
				})
			end
		},
		{
			name = "accept", description = "Accept a pending join request.", tier = T.MOD,
			options = { { type = "string", name = "username", description = "Roblox username or ID.", required = true } },
			run = function(ctx, args)
				if notReady(ctx) then return end
				local user = R.userByName(args.username)
				if not user then return ctx:fail("I could not find that Roblox user.") end
				local ok, err = R.accept(user.id)
				if not ok then return apiFail(ctx, err) end
				local config = K.config(ctx.guild)
				local list = config.scrp_grouprequests or {}
				local req = list[tostring(user.id)]
				list[tostring(user.id)] = nil
				K.save(ctx.guild, { scrp_grouprequests = list }, "SCRP_GROUP_ACCEPT")
				return ctx:card({
					title = "Join Request Accepted",
					blocks = { { { "Roblox Account", user.name }, { "Discord", req and K.mention(req.discord) or "Unknown", req and true }, { "Accepted By", ctx.user.mentionString, true } } },
					banner = false,
				})
			end
		},
		{
			name = "kick", description = "Remove someone from the Roblox group.", tier = T.MGMT,
			options = {
				{ type = "string", name = "username", description = "Roblox username or ID.", required = true },
				{ type = "string", name = "reason", description = "Why.", rest = true },
			},
			run = function(ctx, args)
				if notReady(ctx) then return end
				local user = R.userByName(args.username)
				if not user then return ctx:fail("I could not find that Roblox user.") end
				local ok, err = R.kick(user.id)
				if not ok then return apiFail(ctx, err) end
				print("[scrp] group kick " .. user.id .. " by " .. ctx.user.id)
				return ctx:card({
					title = "Removed From Group",
					blocks = { { { "Roblox Account", user.name }, { "Reason", args.reason or "No reason given" }, { "Removed By", ctx.user.mentionString, true } } },
					banner = false,
				})
			end
		},
	}
})
