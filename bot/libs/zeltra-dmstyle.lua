--[[
	Zeltra DM card style (added by Zeltra; not part of upstream Ducky V1).

	Builds the direct messages the bot sends to members (infractions, tickets, shifts,
	moderation, LOAs, ...) as a Components V2 container:

	  # <icon> Title
	  Short sentence naming the server in **bold**.
	  > **Label** · value
	  -# muted note
	  [link buttons]
	  -# Server Name · Footer

	If Discord rejects the V2 payload for any reason other than closed DMs, the same
	content is sent again as a classic embed so the member still gets notified.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local DEFAULT_SERVER_NAME = "South Carolina Roleplay"
local ACCENT = 0xFF6A00 -- orange
local IS_COMPONENTS_V2 = 32768
local MAX_TEXT = 3800

local dm = {}

dm.accent = ACCENT
dm.defaultServerName = DEFAULT_SERVER_NAME

-- escape markdown characters that would break the bold server name
local function escapeMarkdown(s)
	return (tostring(s):gsub("([%*_~|`\\])", "\\%1"))
end

local function truncate(s, n)
	s = tostring(s or "")
	if string.truncate then return string.truncate(s, n) end
	if #s <= n then return s end
	return s:sub(1, n - 3) .. "..."
end

--- The guild's name (falls back to South Carolina Roleplay), safe to wrap in **bold**.
function dm.serverName(guild)
	local name = guild and guild.name
	if type(name) ~= "string" or name == "" then
		name = DEFAULT_SERVER_NAME
	end
	return escapeMarkdown(name)
end

--- Discord timestamp, e.g. dm.time(os.time()) -> <t:1700000000:F>
function dm.time(t, style)
	t = math.floor(tonumber(t) or os.time())
	return "<t:" .. t .. ":" .. (style or "F") .. ">"
end

--- Compact duration: 53m, 21h 56m, 5m 24s, 2d 3h
function dm.duration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local d = math.floor(seconds / 86400)
	local h = math.floor((seconds % 86400) / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	local parts = {}
	if d > 0 then
		parts = { d .. "d", (h > 0 and (h .. "h")) or nil }
	elseif h > 0 then
		parts = { h .. "h", (m > 0 and (m .. "m")) or nil }
	elseif m > 0 then
		parts = { m .. "m", (s > 0 and (s .. "s")) or nil }
	else
		parts = { s .. "s" }
	end
	return table.concat(parts, " ")
end

--- "Normal" -> "Normal Shift", "Normal Shift" stays as is
function dm.shiftName(name)
	name = tostring(name or "Shift")
	if name:lower():find("shift%s*$") then return name end
	return name .. " Shift"
end

--- Zero-padded ticket number: 725 -> 0725
function dm.ticketNumber(id)
	local n = tonumber(id)
	if not n then return tostring(id or "0") end
	return string.format("%04d", math.floor(n))
end

--- Turn any text into a quote block (every line starts with "> ")
function dm.quote(text)
	text = tostring(text or "")
	if text == "" then text = "No reason provided" end
	return "> " .. text:gsub("\r", ""):gsub("\n", "\n> ")
end

local function fieldLines(fields)
	local lines = {}
	for _, f in ipairs(fields or {}) do
		local label, value = f[1], f[2]
		if value ~= nil and value ~= false and tostring(value) ~= "" then
			value = truncate(tostring(value):gsub("\r", ""):gsub("\n", " "), 900)
			table.insert(lines, "> **" .. label .. "** · " .. value)
		end
	end
	return table.concat(lines, "\n")
end

local function footerText(opts)
	if opts.footer == false then return nil end
	local name = opts.serverName or dm.serverName(opts.guild)
	if opts.footer and opts.footer ~= "" then
		return "-# " .. name .. " · " .. opts.footer
	end
	return "-# " .. name
end

--[[
	opts = {
		guild = Guild,               -- used for the server name (or opts.serverName)
		icon = "⚖️", title = "You received an infraction",
		intro = "Sentence with **Server**.",
		fields = { {"Punishment", "Termination"}, {"Reason", "..."} },
		sections = { { title = "Reason", body = "..." } },   -- optional, quoted
		note = "muted line",         -- optional, rendered as -# subtext
		buttons = { { label = "View Transcript", url = "https://...", emoji = "📂" } },
		media = "https://image",     -- optional image (media gallery)
		file = "transcript.txt",     -- optional attached file to show (must also be in opts.files)
		files = { {"transcript.txt", "..."} },
		footer = "Staff Management" | false,
	}
]]
--[[
	Button row contents. Link buttons: { label, url, emoji }.
	Action buttons (handled by a module): { label, custom_id, style = 1 primary / 2 grey / 3 green / 4 red, emoji, disabled }.
]]
function dm.buttons(list)
	local out = {}
	for _, b in ipairs(list or {}) do
		if type(b.url) == "string" and b.url:match("^https?://") then
			table.insert(out, { type = 2, style = 5, label = truncate(b.label, 80), url = b.url, emoji = b.emoji and { name = b.emoji } or nil })
		elseif type(b.custom_id) == "string" and b.custom_id ~= "" then
			table.insert(out, { type = 2, style = b.style or 2, label = truncate(b.label, 80), custom_id = b.custom_id:sub(1, 100),
				emoji = b.emoji and { name = b.emoji } or nil, disabled = b.disabled or nil })
		end
		if #out >= 5 then break end
	end
	return out
end

function dm.build(opts)
	local blocks = {}

	local head = "# " .. ((opts.icon and (opts.icon .. " ")) or "") .. tostring(opts.title or "")
	if opts.intro and opts.intro ~= "" then
		head = head .. "\n" .. opts.intro
	end
	table.insert(blocks, head)

	local fl = fieldLines(opts.fields)
	if fl ~= "" then
		table.insert(blocks, fl)
	end

	for _, section in ipairs(opts.sections or {}) do
		table.insert(blocks, "**" .. section.title .. "**\n" .. dm.quote(truncate(section.body, 1000)))
	end

	if opts.note and opts.note ~= "" then
		table.insert(blocks, "-# " .. tostring(opts.note):gsub("\n", "\n-# "))
	end

	local components = {}
	for _, b in ipairs(blocks) do
		table.insert(components, { type = 10, content = truncate(b, MAX_TEXT) })
	end

	if opts.media then
		table.insert(components, { type = 12, items = { { media = { url = opts.media } } } })
	end

	if opts.file then
		table.insert(components, { type = 13, file = { url = "attachment://" .. opts.file } })
	end

	local buttons = dm.buttons(opts.buttons)
	if #buttons > 0 then
		table.insert(components, { type = 1, components = buttons })
	end

	local footer = footerText(opts)
	if footer then
		table.insert(components, { type = 10, content = footer })
	end

	local payload = {
		flags = IS_COMPONENTS_V2,
		allowed_mentions = { parse = {} },
		components = {
			{
				type = 17,
				accent_color = opts.color or ACCENT,
				components = components
			}
		},
		files = opts.files
	}

	return payload
end

-- classic embed with the same content, used only if the V2 payload is rejected
function dm.buildEmbed(opts)
	local desc = {}
	if opts.intro then table.insert(desc, opts.intro) end
	local fl = fieldLines(opts.fields)
	if fl ~= "" then table.insert(desc, fl) end
	for _, section in ipairs(opts.sections or {}) do
		table.insert(desc, "**" .. section.title .. "**\n" .. dm.quote(truncate(section.body, 1000)))
	end
	if opts.note then table.insert(desc, "-# " .. opts.note) end

	local buttons = dm.buttons(opts.buttons)

	local footer = footerText(opts)
	return {
		allowed_mentions = { parse = {} },
		embed = {
			title = truncate(((opts.icon and (opts.icon .. " ")) or "") .. tostring(opts.title or ""), 256),
			description = truncate(table.concat(desc, "\n\n"), 4000),
			color = opts.color or ACCENT,
			image = opts.media and { url = opts.media } or nil,
			footer = footer and { text = footer:gsub("^%-# ", ""):gsub("\\", "") } or nil
		},
		components = (#buttons > 0 and { { type = 1, components = buttons } }) or nil,
		files = opts.files
	}
end

--- Send a styled DM. Never throws; returns the message or nil, err.
function dm.send(target, opts)
	local ok, msg, err = pcall(function()
		local user = (target and target.user) or target
		if not user or not user.send then
			return nil, "no user to DM"
		end

		local m, e = user:send(dm.build(opts))
		if m then return m end

		-- 50007: the member has DMs closed, a fallback would fail as well
		if tostring(e):find("50007") or tostring(e):find("Cannot send messages to this user") then
			return nil, e
		end

		local m2, e2 = user:send(dm.buildEmbed(opts))
		if m2 then return m2 end
		return nil, tostring(e) .. " / fallback: " .. tostring(e2)
	end)

	if not ok then
		err = msg
		msg = nil
	end
	if not msg then
		print("[dm] could not DM " .. tostring(target and target.id) .. " (" .. tostring(opts.title) .. "): " .. tostring(err))
	end
	return msg, err
end

--[[
	Same card style for a log channel post (e.g. #infractions, #promotions).
	ping = user ID to mention above the card (only that user is pinged, roles are not).
]]
function dm.post(channel, opts, ping)
	if not channel or not channel.send then
		return nil, "no channel"
	end

	local ok, msg, err = pcall(function()
		local payload = dm.build(opts)
		if ping then
			table.insert(payload.components, 1, { type = 10, content = "-# 🔔 <@" .. ping .. ">" })
			payload.allowed_mentions = { parse = {}, users = { tostring(ping) } }
		end

		local m, e = channel:send(payload)
		if m then return m end

		local fallback = dm.buildEmbed(opts)
		if ping then
			fallback.content = "-# 🔔 <@" .. ping .. ">"
			fallback.allowed_mentions = { parse = {}, users = { tostring(ping) } }
		end
		local m2, e2 = channel:send(fallback)
		if m2 then return m2 end
		return nil, tostring(e) .. " / fallback: " .. tostring(e2)
	end)

	if not ok then
		err = msg
		msg = nil
	end
	if not msg then
		print("[dm] could not post " .. tostring(opts.title) .. " to channel " .. tostring(channel.id) .. ": " .. tostring(err))
	end
	return msg, err
end

--- Post a card to the channel stored under a guild config key (e.g. "infractionschannel").
function dm.postTo(guild, key, opts, ping)
	local config = guild and sqldb and sqldb:get(guild.id)
	local channelId = config and config[key]
	local channel = channelId and guild:getChannel(channelId)
	if not channel then
		return nil, "channel not configured"
	end
	return dm.post(channel, opts, ping)
end

--[[
	Ticket closed DM, shared by every place that closes a ticket.
	t = { guild, channel, id, subject, closer, claimer, messages, reason, url, transcript }
]]
function dm.ticketClosed(target, t)
	local number = dm.ticketNumber(t.id)
	local closedAt = os.time()
	local openedAt = t.channel and t.channel.createdAt and math.floor(t.channel.createdAt) or nil

	local files, file
	if t.transcript then
		files = { { "transcript.txt", tostring(t.transcript) } }
		file = "transcript.txt"
	end

	return dm.send(target, {
		guild = t.guild,
		icon = "📋",
		title = "Ticket #" .. number .. " - " .. tostring(t.subject or "Support"),
		intro = "Your ticket in **" .. dm.serverName(t.guild) .. "** has been closed.",
		fields = {
			{ "Type", t.subject or "Support" },
			{ "Closed by", t.closer and t.closer.mentionString },
			{ "Handled by", (t.claimer and t.claimer.mentionString) or "Unclaimed" },
			{ "Messages", t.messages and tostring(t.messages) },
			{ "Opened", openedAt and dm.time(openedAt) },
			{ "Closed", dm.time(closedAt) },
			{ "Duration", openedAt and dm.duration(closedAt - openedAt) }
		},
		sections = { { title = "Reason", body = (t.reason and t.reason ~= "") and t.reason or "No reason provided" } },
		buttons = { { label = "View Transcript", url = t.url, emoji = "📂" } },
		file = file,
		files = files,
		footer = "Ticket #" .. number
	})
end

_G.dmStyle = dm
return dm
