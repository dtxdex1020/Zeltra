-- verify.lua (SCRP). Roblox verification with a phrase in the profile description. Hand-coded by Dex.
local K = _G.scrpKit
local R = _G.scrpApi.roblox

local WORDS = { "Palmetto", "Carolina", "Harbor", "Pine", "River", "Orange", "Sunset", "Patrol", "Highway", "Engine", "Badge", "Coast", "Maple", "Signal" }

local function phrase()
	math.randomseed(os.time() + math.floor(math.random() * 10000))
	local out = {}
	for i = 1, 6 do out[i] = WORDS[math.random(1, #WORDS)] end
	return table.concat(out, " ")
end

local function buttons(profile, disabled)
	return { { type = 1, components = {
		{ type = 2, style = 3, label = "Done", custom_id = "scrpverify_done", disabled = disabled },
		{ type = 2, style = 2, label = "New Phrase", custom_id = "scrpverify_new", disabled = disabled },
		{ type = 2, style = 4, label = "Cancel", custom_id = "scrpverify_cancel", disabled = disabled },
		{ type = 2, style = 5, label = "Open Profile", url = profile },
	} } }
end

local function phraseCard(user, words)
	local p = K.card({
		title = "Roblox Verification",
		intro = "Put this phrase anywhere in your Roblox profile About section, save it, then press Done.",
		blocks = { { { "Roblox Account", user.name }, { "Phrase", words } } },
		note = "You can remove the phrase after you are verified.",
		banner = false,
	})
	p.components = buttons(R.profile(user.id))
	return p
end

return K.command({
	name = "verify",
	description = "Roblox verification.",
	subs = {
		{
			name = "me", description = "Verify your Roblox account or update your roles.",
			options = { { type = "string", name = "username", description = "Your Roblox username (only needed the first time)." } },
			run = function(ctx, args)
				local link = sqldb:getLink(ctx.user.id)
				if link and link.roblox and not args.username then
					local rblx = R.user(link.roblox)
					pcall(updateMember, ctx.member, "user verified themselves")
					return ctx:card({
						title = "You Are Verified",
						intro = "Your roles were updated.",
						thumbnail = rblx and R.headshot(rblx.id),
						blocks = { { { "Roblox Account", rblx and rblx.name or tostring(link.roblox) }, { "Roblox ID", tostring(link.roblox) } } },
						note = "Want to switch accounts? Run -verify me <new username>.",
						banner = false,
					})
				end
				if not args.username then
					return ctx:fail("Tell me your Roblox username. Example: `" .. K.PREFIX .. "verify me Builderman` or `/verify me username:Builderman`.")
				end
				local user = R.userByName(args.username)
				if not user then return ctx:fail("I could not find a Roblox user named `" .. args.username .. "`.") end
				local taken = sqldb:getLink(tostring(user.id))
				if taken and taken.discord and tostring(taken.discord) ~= tostring(ctx.user.id) then
					return ctx:fail("That Roblox account is already linked to another Discord account.")
				end

				local words = phrase()
				local msg = ctx:send(phraseCard(user, words))
				if type(msg) ~= "table" or not msg.components then return end
				onComp(msg, "button", nil, ctx.user.id, false, function(ia)
					local id = ia.data.custom_id
					if id == "scrpverify_new" then
						words = phrase()
						ia:update(phraseCard(user, words))
					elseif id == "scrpverify_cancel" then
						ia:update({ embeds = { K.notice("Verification canceled.").embeds[1] }, components = {} })
						return true
					elseif id == "scrpverify_done" then
						local code, data = _G.scrpApi.request("GET", "https://users.roblox.com/v1/users/" .. user.id, { { "Accept", "application/json" } })
						local desc = (code == 200 and type(data) == "table" and data.description) or ""
						if not desc:find(words, 1, true) then
							ia:reply(K.notice("I don't see the phrase in your profile yet. Save it on Roblox and press Done again."), true)
							return
						end
						if link and link.roblox then pcall(sqldb.unLink, sqldb, ctx.user.id) end
						local ok, err = sqldb:link(ctx.member, user.id)
						if not ok then
							ia:reply(K.notice("I could not save your link. " .. tostring(err or "")), true)
							return
						end
						pcall(updateMember, ctx.member, "user verified themselves")
						ia:update({ embeds = { K.card({
							title = "You Are Verified",
							intro = "You are now linked to **" .. user.name .. "** and your roles were updated.",
							banner = false,
						}).embeds[1] }, components = {} })
						return true
					end
				end)
			end
		},
	}
})
