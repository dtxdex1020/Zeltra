-- modules/server_management/scrp_panels.lua
-- Zeltra (AGPL-3.0, see NOTICE.md): South Carolina Roleplay panel menus and the free ticket helper.
--   * #dashboard rulebook menu (scrp_rules) and #departments directory menu (scrp_dept): private replies
--   * session buttons (scrp_sess_players / scrp_sess_staff)
--   * ticket helper: greeting + Roblox lookup + keyword FAQ answers + "Talk to staff" hand-off
--   * ticket case log: "New case" / "Case closed" cards in the ticket log channel
-- Preset answers only, no paid AI.
local P = {
	name = "scrp_panels",
	description = "SCRP panel menus, session buttons and the ticket helper."
}

local GUILD = "1522997818330058772"
local LOG = "1522997828127948838" -- ticket-logs
local ACCENT = 0xFF6A00
local LOGO = "<:scrp_logo:1559269062490587307>"
local DEX = "1307878235383795732"
local FOOTER = "-# South Carolina Roleplay"

-- ticket category -> { name, team role to ping }
local CATS = {
	["1522997826462810194"] = { "General Support", "1522997818510278864" },
	["1558873090098864289"] = { "Internal Affairs Support", "1522997818447626460" },
	["1558873091650883657"] = { "Department Support", "1522997818560741473" },
	["1522997826953412698"] = { "Leadership Support", "1522997818476855376" },
	["1522997827662512339"] = { "Leadership Support", "1522997818447626452" },
	["1558873093647245415"] = { "Ownership Support", "1522997818363740163" },
}

local connections = {}
local tickets = {} -- [channelId] = { opener, cat, opened, human, staff = {[id]=n}, details, faq = {} }

local function safe(name, fn)
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then print("[scrp_panels] " .. name .. " error: " .. tostring(err)) end
	end
end

local function text(s) return { type = 10, content = s } end
local function sep() return { type = 14 } end
local function card(blocks, extra)
	local comps = {}
	for _, b in ipairs(blocks) do table.insert(comps, type(b) == "string" and text(b) or b) end
	table.insert(comps, text(FOOTER))
	local out = { { type = 17, accent_color = ACCENT, components = comps } }
	for _, e in ipairs(extra or {}) do table.insert(out, e) end
	return out
end

local function respond(interaction, components, ephemeral)
	return Client._api:request("POST", "/interactions/" .. interaction.id .. "/" .. interaction.token .. "/callback", {
		type = 4,
		data = { flags = 32768 + ((ephemeral ~= false) and 64 or 0), components = components, allowed_mentions = { parse = {} } },
	})
end

---------------------------------------------------------------- rulebooks
local RULES = {
	community = { "Community Rules", {
		"**1. Be respectful.** No harassment, hate speech, bullying or discrimination.",
		"**2. Follow Discord ToS.** You have to meet Discord's age requirement.",
		"**3. Keep it clean.** No NSFW, gore, politics or religion arguments.",
		"**4. No spam or ads.** Ads only in <#1522997821811327137> or through a partnership.",
		"**5. Right channel, right topic.** Bot commands go in <#1522997821043773525>.",
		"**6. Don't ping without a reason.** Open a ticket if you need staff.",
		"**7. Privacy.** No doxxing, threats or impersonating anyone.",
		"**8. Staff calls.** Disagree with one? Open a ticket, don't argue in chat.",
		"**9. No alts** to get around a punishment.",
	} },
	roleplay = { "Roleplay Rules", {
		"**1. Stay in character.** Keep out-of-character talk short and in game chat only when needed.",
		"**2. No FRP.** Don't do things that couldn't happen in real life, like driving off a cliff and walking it off.",
		"**3. Value your life.** If someone has a weapon on you, act like it matters.",
		"**4. No RDM or VDM.** Don't kill or run people over without a roleplay reason.",
		"**5. No cop baiting.** Don't commit crimes just to get a chase going.",
		"**6. Follow staff.** If staff tell you to stop or change something, do it and open a ticket later if you disagree.",
		"**7. Civilians stay civilian.** No police lights, uniforms or roles you aren't in.",
		"The full in-game list is in <#1522997820775469131>.",
	} },
	department = { "Department Rules", {
		"**1. Be in the department.** Only use a department's cars, uniforms and radio if you're in it.",
		"**2. Follow your chain of command.** Supervisors and High Command have the final say on scene.",
		"**3. Use the radio right.** Codes are in <#1522997820116697223>. Keep the channel clear for calls.",
		"**4. Patrol where you belong.** Fort Mill PD in town, York County Sheriff's Office in the county, Highway Patrol on the highways.",
		"**5. Fire and DOT on scene.** Fort Mill FD and DOT take the lead on fires, crashes and road work.",
		"**6. No power abuse.** Don't arrest, tow or fine people without a reason.",
		"**7. Stay active.** Inactive members can be removed. Put in an LOA if you need a break.",
	} },
}

---------------------------------------------------------------- departments
local DEPTS = {
	fmpd = { "Fort Mill Police Department", "<@&1522997818610942109>", "City patrol, calls for service and investigations inside Fort Mill.", "<@&1522997818610942110>, <@&1522997818648694865>" },
	fmfd = { "Fort Mill Fire Department", "<@&1522997818648694867>", "Fires, rescues and EMS calls across the city.", "<@&1522997818648694868>, <@&1522997818648694869>" },
	fmdot = { "Fort Mill DOT", "<@&1522997818648694871>", "Towing, road work, traffic control and keeping the roads clear.", "<@&1522997818648694873>, <@&1522997818648694872>" },
	ycso = { "York County Sheriff's Office", "<@&1522997818610942104>", "Law enforcement for the county roads and towns outside Fort Mill.", "<@&1522997818610942105>, <@&1522997818610942106>" },
	schp = { "South Carolina Highway Patrol", "<@&1522997818560741475>", "Traffic enforcement and pursuits on the highways.", "<@&1522997818560741476>, <@&1522997818610942101>" },
}

---------------------------------------------------------------- tickets
local FAQ = {
	{ { "how do i join", "how to join", "join code", "server code", "join the server", "private server" },
		"**Joining the server:** open ER:LC on Roblox, go to Servers, then Private Servers, then Join by Code. The code is in every session post in <#1522997820389589124>." },
	{ { "apply", "application", "staff app", "become staff", "join staff" },
		"**Staff applications:** press Start Application in <#1522997820389589131>. Results come by DM and in <#1522997820775469127>. If you were denied, you can apply again after 14 days." },
	{ { "verify", "verification", "bloxlink", "unverified", "link my roblox" },
		"**Verifying:** go to <#1522997820116697220> and follow the steps there to link your Roblox account. Once you're verified the Unverified role goes away by itself." },
	{ { "report", "rule break", "broke the rules", "exploiter", "rdm", "vdm", "clip", "proof" },
		"**Reports:** send the person's Roblox username, what happened, and a clip or screenshot. Reports without proof usually can't be acted on." },
	{ { "pay", "payment", "paypal", "refund", "purchase", "bought", "buy", "price" },
		"**Payments:** everything is PayPal only and Dex is the only person who handles it. Only pay with the details Dex posts in a shop ticket, never through DMs." },
	{ { "department", "police", "sheriff", "fire", "dot", "highway patrol", "fmpd", "ycso", "schp", "fmfd" },
		"**Departments:** see <#1522997820775469134> for every department and how to join." },
	{ { "appeal", "unban", "banned", "warned", "muted" },
		"**Appeals:** tell us what the punishment was, when it happened, and why you think it should be looked at again. Be honest, it helps." },
}

local function teamFor(channel)
	if channel.name and channel.name:find("^shop") then return "Shop & Payments", nil, DEX end
	local c = CATS[channel._parent_id or (channel.category and channel.category.id) or ""]
	if c then return c[1], c[2] end
	return "Support", "1522997818531512542"
end

local function robloxFor(userId)
	local link = sqldb.getLink and sqldb:getLink(userId)
	local rid = link and link.roblox
	if not rid then return nil end
	local http = _G.http
	local okU, resU, bodyU = pcall(http.request, "GET", "https://users.roblox.com/v1/users/" .. tostring(rid), {})
	local user = okU and resU and resU.code == 200 and _G.json.decode(bodyU) or nil
	local okT, resT, bodyT = pcall(http.request, "GET", "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=" .. tostring(rid) .. "&size=150x150&format=Png&isCircular=false", {})
	local thumb = okT and resT and resT.code == 200 and _G.json.decode(bodyT) or nil
	local img = thumb and thumb.data and thumb.data[1] and thumb.data[1].imageUrl
	return { id = tostring(rid), name = user and user.name or "Unknown", display = user and user.displayName, avatar = img }
end

local function logCase(t, title, closed)
	local ch = Client:getChannel(LOG)
	if not ch then return end
	local handled = {}
	for id in pairs(t.staff) do table.insert(handled, "<@" .. id .. ">") end
	local lines = {
		"## " .. title,
		"> **Applicant** · <@" .. tostring(t.opener) .. "> (`" .. tostring(t.opener) .. "`)",
		"> **Handled by** · " .. ((#handled > 0) and table.concat(handled, ", ") or "Not yet"),
		"> **Category** · " .. t.team,
		"> **Subject** · " .. tostring(t.name),
		"> **Details** · " .. ((t.details and t.details ~= "") and t.details:gsub("\n", " "):sub(1, 300) or "None given yet"),
		"> **" .. (closed and "Closed" or "Opened") .. "** · <t:" .. os.time() .. ":F>",
	}
	ch:send({ flags = 32768, allowed_mentions = { parse = {} }, components = card({ table.concat(lines, "\n") }) })
end

local function openerOf(channel)
	for ow in channel.permissionOverwrites:iter() do
		if ow.type == "member" and not (Client.user and ow.id == Client.user.id) then
			local m = channel.guild:getMember(ow.id)
			if m and not (m.user and m.user.bot) then return ow.id end
		end
	end
end

local function onChannelCreate(channel)
	if not channel.guild or channel.guild.id ~= GUILD then return end
	local team, role, user = teamFor(channel)
	local parent = channel._parent_id or (channel.category and channel.category.id)
	if not CATS[parent or ""] then return end
	timer.sleep(3500)
	local opener = openerOf(channel)
	if not opener then return end
	local t = { opener = opener, team = team, role = role, user = user, name = channel.name, opened = os.time(), staff = {}, faq = {} }
	tickets[channel.id] = t

	local rb = robloxFor(opener)
	local blocks = {
		"## " .. LOGO .. " Hey <@" .. opener .. ">, thanks for opening a ticket",
		"This is the **" .. team .. "** team. While you wait, fill in the questions above as best you can. If your question is a common one I'll answer it right here.",
		sep(),
		"**Common questions**\nHow to join · Applying for staff · Verifying · Reports · Payments · Departments · Appeals\nJust ask in your own words.",
	}
	if rb then
		local s = { type = 9, components = { text("**Roblox account**\n" .. rb.name .. ((rb.display and rb.display ~= rb.name) and (" (" .. rb.display .. ")") or "") .. "\n[Profile](https://www.roblox.com/users/" .. rb.id .. "/profile) · ID `" .. rb.id .. "`") } }
		if rb.avatar then s.accessory = { type = 11, media = { url = rb.avatar } } else s = text(s.components[1].content) end
		table.insert(blocks, 3, s)
	else
		table.insert(blocks, 3, text("-# No linked Roblox account found. Please send your Roblox username."))
	end
	table.insert(blocks, sep())
	table.insert(blocks, "Need a person instead? Press **Talk to staff** and the team will be pinged. Staff will be with you soon either way.")
	table.insert(blocks, { type = 1, components = { { type = 2, style = 2, label = "Talk to staff", custom_id = "scrp_tk_human" } } })
	channel:send({ flags = 32768, allowed_mentions = { parse = {}, users = { opener } }, components = card(blocks) })
	logCase(t, "New case")
end

local function isStaff(member)
	if not member then return false end
	if member:hasPermission("manageMessages") or member:hasPermission("kickMembers") then return true end
	return member.roles:get("1522997818531512542") ~= nil
end

local function onMessage(message)
	local ch = message.channel
	local t = ch and tickets[ch.id]
	if not t or not message.author or message.author.bot then return end
	if message.author.id ~= t.opener then
		if isStaff(message.member) then
			t.staff[message.author.id] = (t.staff[message.author.id] or 0) + 1
			t.human = true
		end
		return
	end
	if not t.details then t.details = message.content end
	if t.human then return end
	local low = " " .. tostring(message.content or ""):lower() .. " "
	local answers = {}
	for i, f in ipairs(FAQ) do
		if not t.faq[i] then
			for _, k in ipairs(f[1]) do
				if low:find(k, 1, true) then table.insert(answers, f[2]); t.faq[i] = true; break end
			end
		end
	end
	if #answers == 0 then return end
	table.insert(answers, "-# If that didn't help, press **Talk to staff** above or just wait, someone will reply soon.")
	ch:send({ flags = 32768, allowed_mentions = { parse = {} }, components = card({ table.concat(answers, "\n\n") }),
		message_reference = { message_id = message.id, fail_if_not_exists = false } })
end

local function onChannelDelete(channel)
	local t = channel and tickets[channel.id]
	if not t then return end
	tickets[channel.id] = nil
	logCase(t, "Case closed", true)
end

---------------------------------------------------------------- sessions
local function sessionList(interaction, staffOnly)
	local config = sqldb:get(GUILD) or {}
	if not config.apikey then
		return respond(interaction, card({ "**" .. (staffOnly and "Staff in-game" or "Players") .. "**\nLive player lists need the ER:LC API key, which isn't set up yet. Check the counts on the session post." }))
	end
	local server = ERLC:getServer(config.apikey)
	local names = {}
	for _, p in ipairs((server and server.players) or {}) do
		local name = tostring(p.Player or p.name or p):match("^([^:]+)") or "?"
		local perm = tostring(p.Permission or p.permission or "")
		if not staffOnly or (perm ~= "" and perm ~= "Normal") then table.insert(names, name) end
	end
	return respond(interaction, card({ "**" .. (staffOnly and "Staff in-game" or "Players") .. " (" .. #names .. ")**\n" .. ((#names > 0) and table.concat(names, ", ") or "Nobody right now.") }))
end

---------------------------------------------------------------- interactions
local function onInteraction(interaction)
	if not interaction.guild or interaction.guild.id ~= GUILD or not interaction.data then return end
	local id = interaction.data.custom_id
	if type(id) ~= "string" or id:sub(1, 5) ~= "scrp_" then return end
	if id == "scrp_rules" then
		local r = RULES[(interaction.data.values or {})[1] or ""]
		if not r then return end
		return respond(interaction, card({ "## " .. LOGO .. " " .. r[1], sep(), table.concat(r[2], "\n") }))
	elseif id == "scrp_dept" then
		local d = DEPTS[(interaction.data.values or {})[1] or ""]
		if not d then return end
		return respond(interaction, card({ "## " .. LOGO .. " " .. d[1], d[2] .. "\n" .. d[3], sep(),
			"**Leadership**\n" .. d[4],
			"**How to join**\nRequest the department in <#1522997820775469135> or open a Department ticket in <#1522997820116697226>. Grab <@&1529009472830177440> in <#1522997820116697224> to hear about openings." }))
	elseif id == "scrp_sess_players" then
		return sessionList(interaction, false)
	elseif id == "scrp_sess_staff" then
		return sessionList(interaction, true)
	elseif id == "scrp_tk_human" then
		local ch = interaction.channel
		local t = ch and tickets[ch.id]
		if not t then
			local team, role, user = teamFor(ch)
			t = { opener = interaction.user.id, team = team, role = role, user = user, name = ch.name, opened = os.time(), staff = {}, faq = {} }
			tickets[ch.id] = t
		end
		if t.human then return respond(interaction, card({ "Staff already know about this ticket. Someone will be with you soon." })) end
		t.human = true
		respond(interaction, card({ "Got it, I've let the **" .. t.team .. "** team know. I'll stop auto replies here." }), false)
		local ping = t.user and ("<@" .. t.user .. ">") or ("<@&" .. tostring(t.role) .. ">")
		ch:send({ content = ping .. " a member asked to talk to staff in this ticket.", allowed_mentions = { parse = {}, users = t.user and { t.user } or {}, roles = t.role and { t.role } or {} } })
	end
end

P.Start = function()
	connections.ia = { "interactionCreate", Client:on("interactionCreate", function(i) coroutine.wrap(safe("interaction", onInteraction))(i) end) }
	connections.cc = { "channelCreate", Client:on("channelCreate", function(c) coroutine.wrap(safe("channelCreate", onChannelCreate))(c) end) }
	connections.cd = { "channelDelete", Client:on("channelDelete", function(c) coroutine.wrap(safe("channelDelete", onChannelDelete))(c) end) }
	connections.msg = { "messageCreate", Client:on("messageCreate", function(m) coroutine.wrap(safe("message", onMessage))(m) end) }
end

P.Stop = function()
	for _, con in pairs(connections) do Client:removeListener(con[1], con[2]) end
	connections = {}
end

return P
