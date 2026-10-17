--[[
	SCRP command kit. Hand-coded by Dex.

	One definition per command gives both the slash command and the "-" prefix command:
	  /erlc information   and   -erlc info
	The prefix parser reads the same option list the slash command uses, so arguments line up.
	Staff gating is done here by staff rank for both styles.

	The parsing and rank helpers are pure (no Discord calls) so tests/scrp_kit_test.lua can run them.
]]

local K = {}

K.COLOR = 0xFF6A00
K.FOOTER = "Hand-coded by Dex"
K.PREFIX = "-"
K.GUILD_ID = "1522997818330058772"
K.COMMUNITY_ROLE = "1522997818774782013"
K.BASE_STAFF_ROLE = "1522997818531512542"
K.NOT_SET_UP = "not set up yet"
K.DENIED = "You don't have permission to use this command."
K.BANNER_NAME = "scrp-banner.png"
K.BANNER_PATH = "images/scrp/strip.png"

-- Staff rank tiers, lowest to highest.
K.TIER = { PUBLIC = 0, STAFF = 1, MOD = 2, ADMIN = 3, IA = 4, MGMT = 5, OWN = 6, OWNER = 7 }
K.TIER_NAMES = {
	[0] = "Member", [1] = "Staff Team", [2] = "Moderation Team", [3] = "Administration Team",
	[4] = "Internal Affairs", [5] = "Management", [6] = "Ownership", [7] = "Bot Owner"
}

-- Rank roles per tier (same groups as seeds/staff_permissions_v2.lua). The Community Member role is not here on purpose.
K.RANK_ROLES = {
	[1] = { "1522997818531512542", "1522997818510278862", "1522997818510278861", "1522997818510278864" },
	[2] = { "1522997818510278860", "1522997818510278859", "1522997818510278858" },
	[3] = { "1522997818476855382", "1522997818476855381", "1522997818476855380", "1522997818476855379", "1522997818476855378", "1522997818476855384", "1522997818476855376" },
	[4] = { "1522997818447626458", "1522997818447626457", "1522997818447626456", "1522997818447626455", "1522997818447626454", "1522997818447626460" },
	[5] = { "1522997818426527851", "1522997818426527850", "1522997818426527849", "1522997818426527848", "1522997818426527847", "1522997818426527853",
		"1522997818447626452", "1522997818384580634", "1522997818384580632", "1522997818384580631",
		"1522997818384580629", "1522997818363740169", "1522997818363740168", "1522997818363740167", "1522997818363740166", "1522997818363740165" },
	[6] = { "1522997818363740163", "1522997818363740161", "1522997818363740160", "1522997818330058781" },
}

---------------------------------------------------------------- rank (pure)

local function cmdperms()
	return _G.cmdperms or require("../utils/cmdperms")
end

--- Tier for a user from a set of role IDs. Owners and the server owner are top tier, except IDs in TEST_DEMOTED_IDS.
function K.tierFrom(userId, roleSet, guildOwnerId, devIds)
	userId = tostring(userId or "")
	local cp = cmdperms()
	if not cp.TEST_DEMOTED_IDS[userId] then
		if cp.isBotOwner(userId, devIds) then return 7 end
		if guildOwnerId and tostring(guildOwnerId) == userId then return 7 end
	end
	local best = 0
	for tier, list in pairs(K.RANK_ROLES) do
		if tier > best then
			for _, id in ipairs(list) do
				if roleSet[id] then best = tier break end
			end
		end
	end
	return best
end

function K.roleSetOf(member)
	local set = {}
	pcall(function()
		for role in member.roles:iter() do set[tostring(role.id)] = true end
	end)
	return set
end

function K.tier(member)
	if type(member) ~= "table" or not member.id then return 0 end
	local ownerId
	pcall(function() ownerId = member.guild and member.guild.ownerId end)
	local devIds = _G.SECRETS and _G.SECRETS.DEV_ACCESS_IDS or {}
	return K.tierFrom(member.id, K.roleSetOf(member), ownerId, devIds)
end

function K.isStaff(member) return K.tier(member) >= K.TIER.STAFF end

---------------------------------------------------------------- prefix parsing (pure)

--- Splits text into words. "double quotes" keep spaces together.
function K.tokenize(text)
	local out = {}
	text = tostring(text or "")
	local i, n = 1, #text
	while i <= n do
		local c = text:sub(i, i)
		if c:match("%s") then
			i = i + 1
		elseif c == '"' then
			local j = text:find('"', i + 1, true)
			if j then
				table.insert(out, text:sub(i + 1, j - 1))
				i = j + 1
			else
				table.insert(out, text:sub(i + 1))
				break
			end
		else
			local j = text:find("%s", i) or (n + 1)
			table.insert(out, text:sub(i, j - 1))
			i = j
		end
	end
	return out
end

local SNOWFLAKE = "^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d?%d?%d?%d?%d?$"

--- Pulls an ID out of a mention or a raw ID. kind: "user", "role", "channel".
function K.parseId(token, kind)
	token = tostring(token or "")
	local id
	if kind == "user" then
		id = token:match("^<@!?(%d+)>$")
	elseif kind == "role" then
		id = token:match("^<@&(%d+)>$")
	elseif kind == "channel" then
		id = token:match("^<#(%d+)>$")
	end
	if id then return id end
	if token:match(SNOWFLAKE) then return token end
end

local TRUE = { ["true"] = true, yes = true, y = true, on = true, ["1"] = true }
local FALSE = { ["false"] = true, no = true, n = true, off = true, ["0"] = true }

local function normalizeChoices(opt)
	if type(opt.choices) ~= "table" then return end
	for i, c in ipairs(opt.choices) do
		if type(c) ~= "table" then opt.choices[i] = { name = tostring(c), value = tostring(c) } end
	end
end
K.normalizeChoices = normalizeChoices

local function matchChoice(opt, token)
	normalizeChoices(opt)
	if not opt.choices then return token end
	local t = tostring(token):lower()
	for _, c in ipairs(opt.choices) do
		if tostring(c.value):lower() == t or tostring(c.name):lower() == t then return c.value end
	end
end

--- Finds a subcommand by name or alias.
function K.findSub(def, word)
	if not word then return nil end
	word = tostring(word):lower()
	for _, sub in ipairs(def.subs or {}) do
		if sub.name == word then return sub end
		for _, a in ipairs(sub.aliases or {}) do
			if a == word then return sub end
		end
	end
end

--- Parses prefix words for one option list. Returns args (users/roles/channels left as { id = ... } or { name = ... }) or nil, error.
function K.parseOptions(options, tokens)
	local args, pos = {}, 1
	tokens = { unpack(tokens) }
	for i, opt in ipairs(options or {}) do
		local token = tokens[pos]
		local last = (i == #options)
		-- A "rest" option may sit before one option with choices (e.g. role then add/remove): leave a trailing match for it.
		local nextOpt = options[i + 1]
		if opt.rest and nextOpt and nextOpt.choices and #tokens > pos and i + 1 == #options then
			if matchChoice(nextOpt, tokens[#tokens]) ~= nil then
				args[nextOpt.name] = matchChoice(nextOpt, table.remove(tokens))
			end
			last = true
		end
		local value, used = nil, 0
		if opt.type == "string" then
			if (opt.rest or last) and token ~= nil then
				value = table.concat(tokens, " ", pos)
				used = #tokens - pos + 1
				if opt.choices then
					value = matchChoice(opt, value)
					if value == nil then return nil, "That is not a valid " .. opt.name .. "." end
				end
			elseif token ~= nil then
				value = matchChoice(opt, token)
				if value == nil then
					if opt.required then return nil, "That is not a valid " .. opt.name .. "." end
				else
					used = 1
				end
			end
		elseif opt.type == "integer" or opt.type == "number" then
			local num = token and tonumber(token)
			if num and (opt.type == "number" or num == math.floor(num)) then
				value, used = num, 1
			elseif opt.required and token then
				return nil, "The " .. opt.name .. " has to be a number."
			end
		elseif opt.type == "boolean" then
			local t = token and token:lower()
			if t and TRUE[t] then value, used = true, 1
			elseif t and FALSE[t] then value, used = false, 1 end
		elseif opt.type == "user" or opt.type == "channel" then
			local id = token and K.parseId(token, opt.type)
			if id then value, used = { id = id }, 1
			elseif opt.required and token then
				return nil, "Give a " .. (opt.type == "user" and "user ID or mention" or "channel ID or mention") .. " for " .. opt.name .. "."
			end
		elseif opt.type == "role" then
			local id = token and K.parseId(token, "role")
			if id then
				value, used = { id = id }, 1
			elseif token then
				if last then
					value, used = { name = table.concat(tokens, " ", pos) }, #tokens - pos + 1
				else
					value, used = { name = token }, 1
				end
			end
		end
		if value == nil and opt.required then
			return nil, "Missing " .. opt.name .. "."
		end
		if value ~= nil then args[opt.name] = value end
		pos = pos + used
	end
	return args
end

--- Usage line for a subcommand, e.g. "-erlc lookup <username>".
function K.usage(def, sub)
	local parts = { K.PREFIX .. def.name }
	if sub and sub.name then table.insert(parts, sub.name) end
	for _, opt in ipairs((sub and sub.options) or def.options or {}) do
		local label = opt.name
		if opt.type == "user" then label = opt.name .. " id" end
		table.insert(parts, opt.required and ("<" .. label .. ">") or ("[" .. label .. "]"))
	end
	return table.concat(parts, " ")
end

--- Full prefix parse: text after the prefix, e.g. "erlc info". Returns sub (or nil when the command has none), args or nil, error.
function K.parsePrefix(def, text)
	local tokens = K.tokenize(text)
	table.remove(tokens, 1) -- the command word
	if def.subs then
		local sub = K.findSub(def, tokens[1])
		if not sub then
			local names = {}
			for _, s in ipairs(def.subs) do table.insert(names, s.name) end
			return nil, nil, "Pick one: " .. table.concat(names, ", ") .. ". Example: `" .. K.PREFIX .. def.name .. " " .. def.subs[1].name .. "`"
		end
		table.remove(tokens, 1)
		local args, err = K.parseOptions(sub.options, tokens)
		if not args then return sub, nil, err .. "\nUsage: `" .. K.usage(def, sub) .. "`" end
		return sub, args
	end
	local args, err = K.parseOptions(def.options, tokens)
	if not args then return def, nil, err .. "\nUsage: `" .. K.usage(def, nil) .. "`" end
	return def, args
end

--- Strips the prefix (or a bot mention) from a message. Returns the text after it, or nil.
function K.stripPrefix(content, botId)
	content = tostring(content or "")
	if botId then
		local rest = content:match("^<@!?" .. botId .. ">%s+(.*)$")
		if rest then return rest end
	end
	if content:sub(1, #K.PREFIX) == K.PREFIX then
		return content:sub(#K.PREFIX + 1)
	end
end

---------------------------------------------------------------- slash payloads (pure)

local OPTION_TYPES = { subcommand = 1, group = 2, string = 3, integer = 4, boolean = 5, user = 6, channel = 7, role = 8, number = 10 }
K.OPTION_TYPES = OPTION_TYPES

local function optionPayload(opt)
	local o = {
		type = OPTION_TYPES[opt.type],
		name = opt.name,
		description = opt.description or opt.name,
		required = opt.required and true or false,
	}
	if opt.choices then normalizeChoices(opt) o.choices = opt.choices end
	if opt.autocomplete then o.autocomplete = true end
	if opt.min then o.min_value = opt.min end
	if opt.max then o.max_value = opt.max end
	if opt.maxLength then o.max_length = opt.maxLength end
	return o
end

function K.slashPayload(def)
	local payload = { name = def.name, description = def.description, type = 1, options = {} }
	if def.subs then
		for _, sub in ipairs(def.subs) do
			local s = { type = 1, name = sub.name, description = sub.description or sub.name, options = {} }
			for _, opt in ipairs(sub.options or {}) do table.insert(s.options, optionPayload(opt)) end
			table.insert(payload.options, s)
		end
	else
		for _, opt in ipairs(def.options or {}) do table.insert(payload.options, optionPayload(opt)) end
	end
	return payload
end

---------------------------------------------------------------- replies

local bannerData
local function banner()
	if bannerData == nil then
		local ok, data = pcall(function() return _G.fs.readFileSync(K.BANNER_PATH) end)
		bannerData = (ok and data) or false
	end
	return bannerData or nil
end

local function cleanCode(v)
	return (tostring(v):gsub("`", "'"):gsub("\n", " "))
end

--[[
	Builds an SCRP card like the reference layout: bold labels, inline code values, grouped blocks, banner at the bottom.
	o = {
		title = "...", intro = "...",
		blocks = { { {"Label", value}, {"Mention", "<@1>", true} }, ... },  -- third field true = show value as is
		note = "small text", thumbnail = url, banner = false to skip, content = "...", components = {...}
	}
]]
function K.card(o)
	o = o or {}
	local parts = {}
	if o.intro and o.intro ~= "" then table.insert(parts, o.intro) end
	for _, block in ipairs(o.blocks or {}) do
		local lines = {}
		for _, f in ipairs(block) do
			local label, value, raw = f[1], f[2], f[3]
			if value ~= nil and value ~= false and tostring(value) ~= "" then
				value = raw and tostring(value) or ("`" .. cleanCode(value) .. "`")
				table.insert(lines, "> **" .. label .. ":** " .. value)
			end
		end
		if #lines > 0 then table.insert(parts, table.concat(lines, "\n")) end
	end
	if o.body and o.body ~= "" then table.insert(parts, o.body) end
	if o.note and o.note ~= "" then table.insert(parts, "-# " .. o.note) end
	local desc = table.concat(parts, "\n\n")
	if #desc > 4000 then desc = desc:sub(1, 3990) .. "..." end
	local embed = {
		title = o.title,
		description = desc ~= "" and desc or nil,
		color = o.color or K.COLOR,
		footer = { text = K.FOOTER },
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		thumbnail = o.thumbnail and { url = o.thumbnail } or nil,
		image = o.image and { url = o.image } or nil,
	}
	local payload = { embeds = { embed }, content = o.content, components = o.components, allowed_mentions = o.allowed_mentions or { parse = {} } }
	if o.banner ~= false and not o.image then
		local data = banner()
		if data then
			embed.image = { url = "attachment://" .. K.BANNER_NAME }
			payload.files = { { K.BANNER_NAME, data } }
		end
	end
	return payload
end

--- Small plain reply (no banner).
function K.notice(text, title)
	return {
		embeds = { { title = title, description = tostring(text or ""):sub(1, 4000), color = K.COLOR, footer = { text = K.FOOTER } } },
		allowed_mentions = { parse = {} }
	}
end

---------------------------------------------------------------- context

local Ctx = {}
Ctx.__index = Ctx
K.Ctx = Ctx

function K.newCtx(source, isSlash)
	local self = setmetatable({ source = source, isSlash = isSlash and true or false }, Ctx)
	self.guild = source.guild
	self.member = source.member
	self.user = source.user or (source.member and source.member.user) or source.author
	self.channel = source.channel
	return self
end

--- Sends a payload. Slash: interaction reply (follow-ups after the first). Prefix: reply to the message.
function Ctx:send(payload, ephemeral)
	if type(payload) == "string" then payload = K.notice(payload) end
	if self.isSlash then
		return self.source:reply(payload, ephemeral and true or false)
	end
	payload.reference = { message = self.source, mention = false }
	local msg, err = self.source.channel:send(payload)
	if not msg then
		payload.reference = nil
		msg, err = self.source.channel:send(payload)
	end
	return msg, err
end

function Ctx:card(o, ephemeral) return self:send(K.card(o), ephemeral) end
function Ctx:ok(text, title) return self:send(K.notice(text, title)) end
function Ctx:fail(text) return self:send(K.notice(text), true) end
function Ctx:tier() return K.tier(self.member) end

---------------------------------------------------------------- resolving prefix args

local function findRoleByName(guild, name)
	name = tostring(name or ""):lower()
	if name == "" then return nil end
	local exact, partial
	for role in guild.roles:iter() do
		local rn = role.name:lower()
		if rn == name then exact = exact or role
		elseif rn:find(name, 1, true) and not partial then partial = role end
	end
	return exact or partial
end
K.findRoleByName = findRoleByName

--- Turns { id = ... } placeholders from the prefix parser into Discord objects. Returns args or nil, error.
function K.resolveArgs(ctx, options, args)
	for _, opt in ipairs(options or {}) do
		local v = args[opt.name]
		if type(v) == "table" then
			if opt.type == "user" then
				local obj = ctx.guild:getMember(v.id)
				if not obj then obj = _G.Client:getUser(v.id) end
				if not obj then return nil, "I could not find a user with the ID `" .. v.id .. "`." end
				args[opt.name] = obj
			elseif opt.type == "role" then
				local role = (v.id and ctx.guild:getRole(v.id)) or (v.name and findRoleByName(ctx.guild, v.name))
				if not role then return nil, "I could not find that role." end
				args[opt.name] = role
			elseif opt.type == "channel" then
				local ch = ctx.guild:getChannel(v.id)
				if not ch then return nil, "I could not find that channel." end
				args[opt.name] = ch
			end
		end
	end
	return args
end

---------------------------------------------------------------- command builder

--[[
	def = {
		name, description, aliases = {...},
		tier = default tier for the command,
		-- either subcommands:
		subs = { { name, description, aliases, tier, options = {...}, run = function(ctx, args) end }, ... },
		-- or a single command:
		options = {...}, run = function(ctx, args) end,
	}
	option = { type = "string"|"integer"|"number"|"boolean"|"user"|"role"|"channel", name, description, required, choices, rest, autocomplete = fn(ia, value) }
]]
function K.command(def)
	local subcommands
	if def.subs then
		subcommands = {}
		for _, sub in ipairs(def.subs) do
			sub.options = sub.options or {}
			subcommands[sub.name] = sub.aliases or {}
		end
	end

	local cmd = {
		name = def.name,
		description = def.description,
		aliases = def.aliases or {},
		category = "SCRP",
		scrpKit = true,
		scrpDef = def,
		slashCommand = K.slashPayload(def),
		subcommands = subcommands,
		requiredPermissions = nil,
	}

	function cmd.hybridCallback(source, args, slash, subcmd)
		local isSlash = slash ~= nil
		local ctx = K.newCtx(source, isSlash)
		local sub, a
		if isSlash then
			if def.subs then
				sub = K.findSub(def, subcmd and subcmd:match("^(%S+)"))
				if not sub then return ctx:fail("Unknown subcommand.") end
			else
				sub = def
			end
			a = args or {}
		else
			local text = K.stripPrefix(source.content, _G.Client and _G.Client.user and _G.Client.user.id) or ""
			local err
			sub, a, err = K.parsePrefix(def, text)
			if err then return ctx:fail(err) end
			prettyLog("SCRP", "cyan", "prefix parsed: " .. def.name .. (sub ~= def and (" " .. sub.name) or "") .. " by " .. tostring(ctx.user and ctx.user.id))
		end

		local need = sub.tier or def.tier or 0
		if need > 0 and K.tier(ctx.member) < need then
			return ctx:fail(K.DENIED)
		end

		if not isSlash then
			local resolved, err = K.resolveArgs(ctx, sub.options or def.options, a)
			if not resolved then return ctx:fail(err) end
			a = resolved
		end

		return sub.run(ctx, a)
	end

	function cmd.autocomplete(interaction, command, focused, args)
		if not focused then return end
		local opts = (interaction.data and interaction.data.options) or {}
		local sub = def
		if def.subs and opts[1] then sub = K.findSub(def, opts[1].name) or def end
		for _, opt in ipairs(sub.options or {}) do
			if opt.name == focused.name and type(opt.autocomplete) == "function" then
				local ok, list = pcall(opt.autocomplete, interaction, tostring(focused.value or ""))
				return interaction:autocomplete((ok and list) or {})
			end
		end
		return interaction:autocomplete({})
	end

	return cmd
end

---------------------------------------------------------------- small helpers

function K.mention(id) return "<@" .. tostring(id) .. ">" end

function K.userName(u)
	if not u then return "Unknown" end
	return tostring(u.username or u.name or u.id)
end

function K.memberOf(guild, userOrMember)
	if not userOrMember then return nil end
	if userOrMember.guild then return userOrMember end
	return guild:getMember(userOrMember.id)
end

--- Guild config table (never nil).
function K.config(guild)
	return (guild and _G.sqldb:get(guild.id)) or {}
end

function K.save(guild, changes, tag)
	return _G.sqldb:set(guild.id, changes, tag or "SCRP_KIT")
end

--- Number with commas: 12345 -> 12,345
function K.commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local neg = s:sub(1, 1) == "-"
	if neg then s = s:sub(2) end
	s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (neg and "-" or "") .. s
end

return K
