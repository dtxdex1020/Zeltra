-- permissions.lua
-- Zeltra: owner-only per-server command permission overrides + interactive role panel.
-- Data: sqldb command_permissions table (guild_id, command key, mode, roles{id=bool}, users{id=bool}).
-- Enforcement lives in main.lua (checkCommandAccess) so it applies to every slash/prefix command.

local slashCommand = tools.slashCommand("permissions", "Owner-only: configure who can use each bot command in this server.")

local function commandOption(name, description)
	return tools.string(name or "command", description or "The command (or subcommand)."):setRequired(true):setAutocomplete(true)
end

local subcmd = tools.subCommand("set", "Allow or deny a role for a command.")
subcmd = subcmd:addOption(commandOption())
subcmd = subcmd:addOption(tools.role("role", "The role."):setRequired(true))
subcmd = subcmd:addOption(tools.boolean("allow", "True = allow, false = deny."):setRequired(true))
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("remove-role", "Remove a role's allow/deny rule from a command.")
subcmd = subcmd:addOption(commandOption())
subcmd = subcmd:addOption(tools.role("role", "The role."):setRequired(true))
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("add-user", "Add a per-user override for a command.")
subcmd = subcmd:addOption(commandOption())
subcmd = subcmd:addOption(tools.user("user", "The user."):setRequired(true))
subcmd = subcmd:addOption(tools.boolean("allow", "True = allow (default), false = deny."):setRequired(false))
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("remove-user", "Remove a per-user override from a command.")
subcmd = subcmd:addOption(commandOption())
subcmd = subcmd:addOption(tools.user("user", "The user."):setRequired(true))
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("mode", "Set how a command's access is decided.")
subcmd = subcmd:addOption(commandOption())
subcmd = subcmd:addOption(tools.string("mode", "The mode."):setRequired(true)
	:addChoice(tools.choice("default (Discord permissions / staff roles + allowed roles)", "default"))
	:addChoice(tools.choice("roles-only (only listed roles/users)", "roles-only"))
	:addChoice(tools.choice("everyone (any member)", "everyone"))
	:addChoice(tools.choice("disabled (nobody except the owners)", "disabled")))
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("reset", "Reset a command back to its defaults.")
subcmd = subcmd:addOption(commandOption())
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("view", "Show who can use a command.")
subcmd = subcmd:addOption(commandOption())
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("list", "Overview of every command and its allowed roles.")
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("copy", "Copy one command's permission rules to another.")
subcmd = subcmd:addOption(commandOption("from", "Copy rules from this command."))
subcmd = subcmd:addOption(commandOption("to", "Copy rules to this command."))
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("preset", "Allow a role on a bundle of commands.")
subcmd = subcmd:addOption(tools.string("preset", "The preset."):setRequired(true)
	:addChoice(tools.choice("moderator (warn, kick, mute, unmute, infraction, case, modlogs, punishments)", "moderator"))
	:addChoice(tools.choice("shift (shift, session, loa)", "shift")))
subcmd = subcmd:addOption(tools.role("role", "The role to allow."):setRequired(true))
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("panel", "Open the interactive role permission panel.")
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("role", "Open the permission panel for a role.")
subcmd = subcmd:addOption(tools.role("role", "The role."):setRequired(true))
slashCommand:addOption(subcmd)

------------------------------------------------------------------------------------------------------------------
-- helpers

local OWNER_ID = cmdperms.OWNER_ID
local DENIED = _G.COMMAND_DENIED_MESSAGE or "You don't have permission to use this command."

-- Commands gated by bot-team permissions; /permissions grants never bypass those, so they're not configurable.
local DEV_PERMS = {
	BOT_DEVELOPER = true, FOUNDER = true, EXECUTIVE = true, SUPPORT = true, WEB_DEVELOPER = true,
	MANAGEMENT = true, DUCKY_STAFF = true, QUALITY_ASSURANCE = true, DOCWRITER = true
}

local CATEGORIES = {
	{ name = "Moderation", emoji = "🔨", commands = { "warn", "kick", "ban", "unban", "softban", "mute", "unmute", "purge", "lock", "unlock", "slowmode", "nick", "role", "case", "modlogs", "modstats", "punishments" } },
	{ name = "Staff", emoji = "🛡️", commands = { "infraction", "promotion", "shift", "session", "loa", "bolo", "bounty", "feedback", "erlc" } },
	{ name = "Tickets", emoji = "🎫", commands = { "ticket" } },
	{ name = "Giveaways", emoji = "🎉", commands = { "giveaway" } },
	{ name = "Economy / Fun", emoji = "💰", commands = { "balance", "beg", "blackjack", "collect", "crime", "daily", "deposit", "donate", "item", "leaderboard", "rob", "slotmachine", "withdraw", "work", "tax", "coinflip", "rockpaperscissors", "wordle" } },
	{ name = "Admin / Config", emoji = "⚙️", commands = { "setup", "config", "automations", "prefix", "syncbans", "updatemembers", "plus", "exportables", "message", "say", "diagnose", "emoji", "suggestion" } },
	{ name = "Utility / Other", emoji = "🧰", commands = {} } -- everything not listed above
}

local function isOwner(user)
	return user and cmdperms.isBotOwner(tostring(user.id), SECRETS.DEV_ACCESS_IDS) and true or false
end

local function isConfigurableCommand(command)
	if type(command.slashCommand) ~= "table" then
		return false
	end
	local name = slashNameOf(command)
	if name == "permissions" then
		return false
	end
	for _, perm in pairs(command.requiredPermissions or {}) do
		if DEV_PERMS[perm] then
			return false
		end
	end
	return true
end

--- All configurable keys: { key, base, sub, command } ordered by base name then declaration order.
local function getEntries()
	local entries = {}
	local cmds = {}
	for _, command in ipairs(_G.commands or {}) do
		if isConfigurableCommand(command) then
			table.insert(cmds, command)
		end
	end
	table.sort(cmds, function(a, b) return slashNameOf(a) < slashNameOf(b) end)

	for _, command in ipairs(cmds) do
		local base = slashNameOf(command)
		table.insert(entries, { key = base, base = base, command = command })
		for _, opt in ipairs(command.slashCommand.options or {}) do
			if opt.type == 1 then
				table.insert(entries, { key = base .. " " .. opt.name, base = base, sub = opt.name, command = command })
			elseif opt.type == 2 then
				for _, sopt in ipairs(opt.options or {}) do
					if sopt.type == 1 then
						local sub = opt.name .. " " .. sopt.name
						table.insert(entries, { key = base .. " " .. sub, base = base, sub = sub, command = command })
					end
				end
			end
		end
	end
	return entries
end

local function findEntry(key)
	key = tostring(key or ""):lower():gsub("^/", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	for _, entry in ipairs(getEntries()) do
		if entry.key == key then
			return entry
		end
	end
end

local function entryLabel(entry)
	if entry.sub then
		return "/" .. entry.base .. " › " .. entry.sub
	end
	local hasSubs = entry.command.slashCommand.options and entry.command.slashCommand.options[1]
		and (entry.command.slashCommand.options[1].type == 1 or entry.command.slashCommand.options[1].type == 2)
	return "/" .. entry.base .. (hasSubs and " (all subcommands)" or "")
end

local function loadRecord(guildId, key)
	local overrides = sqldb:getCommandPermissions(guildId) or {}
	return cmdperms.normalize(overrides[key] and table.deepcopy and table.deepcopy(overrides[key]) or overrides[key])
end

local function syncVisibility()
	coroutine.wrap(function()
		local ok, err = pcall(_G.syncSlashCommands)
		if not ok then
			Client:error("permissions: slash command sync failed: " .. tostring(err))
		end
	end)()
end

local function saveRecord(guild, key, rec, actor)
	local ok, err
	if cmdperms.isEmpty(rec) then
		ok, err = sqldb:deleteCommandPermission(guild.id, key)
	else
		ok, err = sqldb:setCommandPermission(guild.id, key, cmdperms.normalize(rec), actor and actor.id)
	end
	return ok, err
end

local function logChange(guild, actor, text)
	local config = sqldb:get(guild.id) or {}
	local key = (config.configlogchannel and "configlogchannel") or (config.modlogchannel and "modlogchannel")
	if not key then
		return
	end
	pcall(db.send, db, guild, key, {
		embed = {
			title = "🔐 Command Permissions Updated",
			description = text:sub(1, 4000) .. "\n-# Changed by <@" .. actor.id .. "> (`" .. actor.id .. "`) via `/permissions`",
			color = colors.info,
			timestamp = discordia.Date():toISO("T", "Z")
		}
	})
end

local function roleList(map, value)
	local out = {}
	for id, v in pairs(map) do
		if v == value then
			table.insert(out, "<@&" .. id .. ">")
		end
	end
	return out
end

local function userList(map, value)
	local out = {}
	for id, v in pairs(map) do
		if v == value then
			table.insert(out, "<@" .. id .. ">")
		end
	end
	return out
end

local function describeDefault(entry)
	local permName = _G.SLASH_PERMISSION_NAMES and _G.SLASH_PERMISSION_NAMES[entry.command.baseMemberPermissions]
	local req = entry.command.requiredPermissions or {}
	local parts = {}
	table.insert(parts, "Discord permission **" .. tostring(permName or "none") .. "**")
	if req[1] then
		table.insert(parts, "bot permission(s) **" .. table.concat(req, ", ") .. "**")
	end
	return table.concat(parts, " + ")
end

local function summarizeRecord(rec)
	local lines = {}
	table.insert(lines, "**Mode:** `" .. rec.mode .. "` — " .. cmdperms.MODE_DESCRIPTIONS[rec.mode])
	local ar, dr = roleList(rec.roles, true), roleList(rec.roles, false)
	local au, du = userList(rec.users, true), userList(rec.users, false)
	table.insert(lines, "**Allowed roles:** " .. (ar[1] and table.concat(ar, ", ") or "*none*"))
	if dr[1] then table.insert(lines, "**Denied roles:** " .. table.concat(dr, ", ")) end
	table.insert(lines, "**Allowed users:** " .. (au[1] and table.concat(au, ", ") or "*none*"))
	if du[1] then table.insert(lines, "**Denied users:** " .. table.concat(du, ", ")) end
	return table.concat(lines, "\n")
end

local function categoryOf(base)
	for i, cat in ipairs(CATEGORIES) do
		for _, name in ipairs(cat.commands) do
			if name == base then
				return i
			end
		end
	end
	return #CATEGORIES
end

------------------------------------------------------------------------------------------------------------------
-- role panel

local function buildPages()
	local byCat = {}
	for i = 1, #CATEGORIES do byCat[i] = {} end
	for _, entry in ipairs(getEntries()) do
		table.insert(byCat[categoryOf(entry.base)], entry)
	end
	local pages = {}
	for i, cat in ipairs(CATEGORIES) do
		local list = byCat[i]
		local chunks = math.max(1, math.ceil(#list / 25))
		if #list > 0 then
			for c = 1, chunks do
				local chunk = {}
				for j = (c - 1) * 25 + 1, math.min(c * 25, #list) do
					table.insert(chunk, list[j])
				end
				table.insert(pages, { catIndex = i, cat = cat, entries = chunk, chunk = c, chunks = chunks, all = list })
			end
		end
	end
	return pages
end

--- status of a role on a key: "allow", "deny", "inherit" (allowed via parent command), nil
local function roleStatus(overrides, roleId, entry)
	local rec = overrides[entry.key] and cmdperms.normalize(overrides[entry.key])
	if rec and rec.roles[roleId] ~= nil then
		return rec.roles[roleId] and "allow" or "deny"
	end
	if entry.sub and (not rec or cmdperms.isEmpty(rec)) then
		local keys = cmdperms.keysFor(entry.base, entry.sub)
		for i = 2, #keys do
			local parent = overrides[keys[i]] and cmdperms.normalize(overrides[keys[i]])
			if parent and not cmdperms.isEmpty(parent) then
				if parent.roles[roleId] == true then return "inherit" end
				break
			end
		end
	end
	return nil
end

local STATUS_ICON = { allow = "✅", deny = "⛔", inherit = "↳✅" }

local function roleSummary(guild, roleId)
	local overrides = sqldb:getCommandPermissions(guild.id) or {}
	local allowed, denied = {}, {}
	for _, entry in ipairs(getEntries()) do
		local st = roleStatus(overrides, roleId, entry)
		if st == "allow" then
			local cat = CATEGORIES[categoryOf(entry.base)].name
			allowed[cat] = allowed[cat] or {}
			table.insert(allowed[cat], "`" .. entry.key .. "`")
		elseif st == "deny" then
			table.insert(denied, "`" .. entry.key .. "`")
		end
	end
	local lines = {}
	for _, cat in ipairs(CATEGORIES) do
		if allowed[cat.name] then
			table.insert(lines, cat.emoji .. " **" .. cat.name .. ":** " .. table.concat(allowed[cat.name], ", "))
		end
	end
	if not lines[1] then
		table.insert(lines, "*No explicit allows. This role falls back to the default Discord / staff-role permissions.*")
	end
	if denied[1] then
		table.insert(lines, "⛔ **Denied:** " .. table.concat(denied, ", "))
	end
	return table.concat(lines, "\n")
end

local function button(id, label, style, disabled)
	return { type = 2, custom_id = id, label = label, style = style or 2, disabled = disabled or false }
end

local function row(...)
	return { type = 1, components = { ... } }
end

local function openPanel(interaction, initialRoleId)
	local guild = interaction.guild
	local actor = interaction.user
	local prefix = "zperm:" .. junkStr(8) .. ":"
	local state = { roleId = initialRoleId, page = 1, view = initialRoleId and "page" or "pick", notice = nil }

	local function roleMention()
		return state.roleId and ("<@&" .. state.roleId .. ">") or "*no role*"
	end

	local function render()
		local pages = buildPages()
		state.page = math.max(1, math.min(state.page, #pages))

		if state.view == "pick" then
			return {
				embed = {
					title = "🔐 Command Permissions Panel",
					description = "**Step 1:** pick the role you want to configure.\n-# Changes are saved immediately and only apply to this server.",
					color = colors.info
				},
				components = {
					row({ type = 6, custom_id = prefix .. "pick", placeholder = "Select a role...", min_values = 1, max_values = 1 }),
					row(button(prefix .. "done", "Close", 4))
				}
			}
		elseif state.view == "copy" then
			return {
				embed = {
					title = "🔐 Copy Permissions → " .. (guild:getRole(state.roleId) and guild:getRole(state.roleId).name or state.roleId),
					description = "Select the role to copy **all** command rules **from**. " .. roleMention() .. "'s current rules will be replaced.",
					color = colors.warning
				},
				components = {
					row({ type = 6, custom_id = prefix .. "copysrc", placeholder = "Copy from role...", min_values = 1, max_values = 1 }),
					row(button(prefix .. "back", "Back", 2))
				}
			}
		elseif state.view == "reset" then
			return {
				embed = {
					title = "🔐 Reset Role",
					description = "Remove **every** allow/deny rule for " .. roleMention() .. " in this server?",
					color = colors.warning
				},
				components = {
					row(button(prefix .. "resetconfirm", "Yes, reset role", 4), button(prefix .. "back", "Back", 2))
				}
			}
		elseif state.view == "done" then
			return {
				embed = {
					title = "🔐 Summary for " .. (guild:getRole(state.roleId) and guild:getRole(state.roleId).name or state.roleId),
					description = "What " .. roleMention() .. " can use (explicit `/permissions` rules):\n\n" .. roleSummary(guild, state.roleId),
					color = colors.success
				},
				components = {}
			}
		end

		-- category page
		local page = pages[state.page]
		local overrides = sqldb:getCommandPermissions(guild.id) or {}
		local lines, options = {}, {}
		for _, entry in ipairs(page.entries) do
			local st = roleStatus(overrides, state.roleId, entry)
			table.insert(lines, (STATUS_ICON[st] or "▫️") .. " `" .. entry.key .. "`")
			table.insert(options, {
				label = entryLabel(entry):sub(1, 100),
				value = entry.key,
				description = (st == "deny" and "Currently DENIED for this role (check to allow)")
					or (st == "inherit" and "Allowed via parent command")
					or nil,
				default = st == "allow"
			})
		end

		local role = guild:getRole(state.roleId)
		local desc = "**Role:** " .. roleMention() .. "\n**Category:** " .. page.cat.emoji .. " " .. page.cat.name
			.. (page.chunks > 1 and (" (part " .. page.chunk .. "/" .. page.chunks .. ")") or "")
			.. "\n\n" .. table.concat(lines, "\n")
			.. "\n\n-# ✅ allowed · ⛔ denied · ↳✅ allowed via parent command · ▫️ default. Check commands in the menu to allow them; unchecking removes the allow."
			.. "\n-# Allowed roles bypass the bot's staff-role checks for that command, but not role hierarchy."
		if state.notice then
			desc = state.notice .. "\n\n" .. desc
			state.notice = nil
		end

		return {
			embed = {
				title = "🔐 Permissions — " .. (role and role.name or state.roleId),
				description = desc,
				color = (role and role.color and role.color ~= 0 and role.color) or colors.info,
				footer = { text = "Page " .. state.page .. "/" .. #pages }
			},
			components = {
				row({ type = 3, custom_id = prefix .. "sel", placeholder = "Allowed commands in " .. page.cat.name .. "...", min_values = 0, max_values = #options, options = options }),
				row(button(prefix .. "prev", "◀ Prev", 2, state.page <= 1), button(prefix .. "next", "Next ▶", 2, state.page >= #pages),
					button(prefix .. "allowcat", "Allow all in category", 3), button(prefix .. "clearcat", "Clear category", 4)),
				row(button(prefix .. "copy", "Copy from role…", 1), button(prefix .. "reset", "Reset role", 4),
					button(prefix .. "change", "Change role", 2), button(prefix .. "done", "Done", 3))
			}
		}
	end

	-- apply a function(rec) -> changed to many keys and save
	local function mutate(keys, fn)
		local changed = {}
		for _, key in ipairs(keys) do
			local rec = loadRecord(guild.id, key)
			if fn(rec, key) then
				local ok, err = saveRecord(guild, key, rec, actor)
				if ok then
					table.insert(changed, key)
				else
					state.notice = "⚠️ Failed to save `" .. key .. "`: " .. tostring(err)
				end
			end
		end
		if changed[1] then
			syncVisibility()
		end
		return changed
	end

	local function allKeysWithRules()
		local keys = {}
		for key in pairs(sqldb:getCommandPermissions(guild.id) or {}) do
			table.insert(keys, key)
		end
		table.sort(keys)
		return keys
	end

	local first = interaction:reply(render(), true)
	if not first then
		return
	end

	local predicateType = discordia.enums.interactionType and discordia.enums.interactionType.messageComponent or 3

	coroutine.wrap(function()
		while true do
			local ok, cia = Client:waitFor("interactionCreate", 840000, function(ia)
				return ia.type == predicateType and ia.data and type(ia.data.custom_id) == "string"
					and ia.data.custom_id:sub(1, #prefix) == prefix
			end)
			if not ok or not cia then
				pcall(interaction.editReply, interaction, { components = {} })
				return
			end

			local action = cia.data.custom_id:sub(#prefix + 1)

			if not isOwner(cia.user) then
				cia:fail(DENIED, nil, true)
			else
				local okHandler, err = pcall(function()
					local pages = buildPages()
					local page = pages[state.page]
					local roleId = state.roleId

					if action == "pick" then
						state.roleId = cia.data.values and cia.data.values[1]
						state.view, state.page = "page", 1
					elseif action == "sel" and roleId and page then
						local selected = {}
						for _, v in ipairs(cia.data.values or {}) do selected[v] = true end
						local added, removed = {}, {}
						local keys = {}
						for _, entry in ipairs(page.entries) do table.insert(keys, entry.key) end
						mutate(keys, function(rec, key)
							if selected[key] and rec.roles[roleId] ~= true then
								rec.roles[roleId] = true
								table.insert(added, "`" .. key .. "`")
								return true
							elseif (not selected[key]) and rec.roles[roleId] == true then
								rec.roles[roleId] = nil
								table.insert(removed, "`" .. key .. "`")
								return true
							end
						end)
						if added[1] or removed[1] then
							local text = "**Role:** <@&" .. roleId .. ">\n"
								.. (added[1] and ("**Allowed:** " .. table.concat(added, ", ") .. "\n") or "")
								.. (removed[1] and ("**Removed allow:** " .. table.concat(removed, ", ")) or "")
							logChange(guild, actor, text)
							state.notice = "💾 Saved."
						end
					elseif action == "prev" then
						state.page = state.page - 1
					elseif action == "next" then
						state.page = state.page + 1
					elseif (action == "allowcat" or action == "clearcat") and roleId and page then
						local keys = {}
						for _, entry in ipairs(page.all) do table.insert(keys, entry.key) end
						local changed = mutate(keys, function(rec)
							if action == "allowcat" then
								if rec.roles[roleId] ~= true then rec.roles[roleId] = true return true end
							elseif rec.roles[roleId] ~= nil then
								rec.roles[roleId] = nil
								return true
							end
						end)
						if changed[1] then
							logChange(guild, actor, "**Role:** <@&" .. roleId .. ">\n" .. (action == "allowcat" and "**Allowed all in** " or "**Cleared all rules in** ") .. page.cat.name .. " (" .. #changed .. " commands)")
						end
						state.notice = "💾 " .. (action == "allowcat" and "Allowed" or "Cleared") .. " " .. #changed .. " command(s) in " .. page.cat.name .. "."
					elseif action == "copy" then
						state.view = "copy"
					elseif action == "copysrc" and roleId then
						local src = cia.data.values and cia.data.values[1]
						if src and src ~= roleId then
							local changed = mutate(allKeysWithRules(), function(rec)
								if rec.roles[roleId] ~= rec.roles[src] then
									rec.roles[roleId] = rec.roles[src]
									return true
								end
							end)
							logChange(guild, actor, "**Copied all rules** from <@&" .. src .. "> to <@&" .. roleId .. "> (" .. #changed .. " commands changed)")
							state.notice = "💾 Copied rules from <@&" .. src .. "> (" .. #changed .. " command(s) changed)."
						end
						state.view = "page"
					elseif action == "reset" then
						state.view = "reset"
					elseif action == "resetconfirm" and roleId then
						local changed = mutate(allKeysWithRules(), function(rec)
							if rec.roles[roleId] ~= nil then
								rec.roles[roleId] = nil
								return true
							end
						end)
						logChange(guild, actor, "**Reset role** <@&" .. roleId .. "> (" .. #changed .. " command rules removed)")
						state.notice = "💾 Removed " .. #changed .. " rule(s) for this role."
						state.view = "page"
					elseif action == "back" then
						state.view = roleId and "page" or "pick"
					elseif action == "change" then
						state.view = "pick"
					elseif action == "done" then
						if roleId then
							state.view = "done"
						else
							cia:update({ embed = { description = "Panel closed.", color = colors.info }, components = {} })
							state.closed = true
							return
						end
					end

					cia:update(render())
					if state.view == "done" then
						state.closed = true
					end
				end)

				if not okHandler then
					Client:error("permissions panel error: " .. tostring(err))
					pcall(cia.fail, cia, "Something went wrong: `" .. tostring(err):sub(1, 300) .. "`", nil, true)
				end
				if state.closed then
					return
				end
			end
		end
	end)()
end

------------------------------------------------------------------------------------------------------------------

return {
	name = "permissions",
	description = "Owner-only: configure who can use each bot command in this server.",
	aliases = {},
	category = "Admin",
	slashCommand = slashCommand,
	requiredPermissions = {},
	autocomplete = function(interaction, command, focused, args)
		local opts = {}
		if isOwner(interaction.user) and focused and (focused.name == "command" or focused.name == "from" or focused.name == "to") then
			local query = tostring(focused.value or ""):lower():gsub("^/", "")
			local overrides = sqldb:getCommandPermissions(interaction.guild.id) or {}
			for _, entry in ipairs(getEntries()) do
				if query == "" or entry.key:find(query, 1, true) then
					local rec = overrides[entry.key]
					local label = entryLabel(entry) .. ((rec and not cmdperms.isEmpty(rec)) and ("  [" .. cmdperms.normalize(rec).mode .. ", customised]") or "")
					table.insert(opts, { name = label:sub(1, 100), value = entry.key })
					if #opts >= 25 then
						break
					end
				end
			end
		end
		return interaction:autocomplete(opts)
	end,
	callback = function(message)
		return message:fail("Use the **`/permissions`** slash command.")
	end,
	slashCallback = function(interaction, args, slash, subcmd)
		if not isOwner(interaction.user) then
			return interaction:fail(DENIED, nil, true)
		end

		local guild = interaction.guild
		local actor = interaction.user
		args = args or {}

		local function needEntry(value)
			local entry = findEntry(value)
			if not entry then
				interaction:fail("Unknown or non-configurable command `" .. tostring(value) .. "`. Pick one from the autocomplete list.", nil, true)
			end
			return entry
		end

		local function finish(entry, rec, logText)
			local ok, err = saveRecord(guild, entry.key, rec, actor)
			if not ok then
				return interaction:fail("Failed to save: " .. tostring(err), nil, true)
			end
			syncVisibility()
			logChange(guild, actor, "**Command:** `/" .. entry.key .. "`\n" .. logText)
			return interaction:reply({
				embed = {
					title = "🔐 /" .. entry.key,
					description = logText .. "\n\n" .. summarizeRecord(cmdperms.normalize(rec)),
					color = colors.success
				}
			}, true)
		end

		if subcmd == "set" then
			local entry = needEntry(args.command)
			if not entry then return end
			local role = args.role
			local rec = loadRecord(guild.id, entry.key)
			rec.roles[role.id] = args.allow == true
			return finish(entry, rec, (args.allow and "✅ **Allowed** " or "⛔ **Denied** ") .. role.mentionString)
		elseif subcmd == "remove-role" then
			local entry = needEntry(args.command)
			if not entry then return end
			local rec = loadRecord(guild.id, entry.key)
			rec.roles[args.role.id] = nil
			return finish(entry, rec, "🗑️ **Removed rule for** " .. args.role.mentionString)
		elseif subcmd == "add-user" then
			local entry = needEntry(args.command)
			if not entry then return end
			local allow = args.allow ~= false
			local rec = loadRecord(guild.id, entry.key)
			rec.users[args.user.id] = allow
			return finish(entry, rec, (allow and "✅ **Allowed user** " or "⛔ **Denied user** ") .. "<@" .. args.user.id .. ">")
		elseif subcmd == "remove-user" then
			local entry = needEntry(args.command)
			if not entry then return end
			local rec = loadRecord(guild.id, entry.key)
			rec.users[args.user.id] = nil
			return finish(entry, rec, "🗑️ **Removed user override for** <@" .. args.user.id .. ">")
		elseif subcmd == "mode" then
			local entry = needEntry(args.command)
			if not entry then return end
			if not cmdperms.MODE_SET[args.mode or ""] then
				return interaction:fail("Invalid mode.", nil, true)
			end
			local rec = loadRecord(guild.id, entry.key)
			rec.mode = args.mode
			return finish(entry, rec, "⚙️ **Mode set to** `" .. args.mode .. "`")
		elseif subcmd == "reset" then
			local entry = needEntry(args.command)
			if not entry then return end
			local ok, err = sqldb:deleteCommandPermission(guild.id, entry.key)
			if not ok then
				return interaction:fail("Failed to reset: " .. tostring(err), nil, true)
			end
			syncVisibility()
			logChange(guild, actor, "**Command:** `/" .. entry.key .. "`\n♻️ **Reset to defaults**")
			return interaction:success("`/" .. entry.key .. "` was reset to its defaults (" .. describeDefault(entry) .. ").", nil, true)
		elseif subcmd == "view" then
			local entry = needEntry(args.command)
			if not entry then return end
			local overrides = sqldb:getCommandPermissions(guild.id) or {}
			local keys = cmdperms.keysFor(entry.base, entry.sub)
			local effectiveKey
			for _, k in ipairs(keys) do
				if overrides[k] and not cmdperms.isEmpty(overrides[k]) then
					effectiveKey = k
					break
				end
			end
			local lines = {}
			if effectiveKey then
				if effectiveKey ~= entry.key then
					table.insert(lines, "-# No rules of its own; inherits from `/" .. effectiveKey .. "`.")
				end
				table.insert(lines, summarizeRecord(cmdperms.normalize(overrides[effectiveKey])))
			else
				table.insert(lines, "**Mode:** `default` (no overrides)")
			end
			table.insert(lines, "\n**Default fallback:** " .. describeDefault(entry) .. ". The bot owner and the server owner can always use it.")
			table.insert(lines, "**Visibility:** " .. ((_G.visibleCommands and _G.visibleCommands[entry.base]) and "visible to everyone in the command picker; the bot enforces access" or "hidden by Discord from members without the default permission"))
			return interaction:reply({
				embed = {
					title = "🔐 /" .. entry.key,
					description = table.concat(lines, "\n"),
					color = colors.info
				}
			}, true)
		elseif subcmd == "list" then
			local overrides = sqldb:getCommandPermissions(guild.id) or {}
			local lines = {}
			for _, entry in ipairs(getEntries()) do
				local rec = overrides[entry.key] and cmdperms.normalize(overrides[entry.key])
				if not entry.sub or (rec and not cmdperms.isEmpty(rec)) then
					local line = "`/" .. entry.key .. "` — "
					if rec and not cmdperms.isEmpty(rec) then
						local ar = roleList(rec.roles, true)
						local au = userList(rec.users, true)
						line = line .. "**" .. rec.mode .. "**"
						if ar[1] then line = line .. " · ✅ " .. table.concat(ar, " ") end
						if au[1] then line = line .. " · 👤 " .. table.concat(au, " ") end
						local dr = roleList(rec.roles, false)
						if dr[1] then line = line .. " · ⛔ " .. table.concat(dr, " ") end
					else
						local permName = _G.SLASH_PERMISSION_NAMES and _G.SLASH_PERMISSION_NAMES[entry.command.baseMemberPermissions]
						line = line .. "default (" .. tostring(permName or "?") .. ")"
					end
					table.insert(lines, line)
				end
			end
			local pages = {}
			local perPage = 15
			for i = 1, #lines, perPage do
				table.insert(pages, {
					title = "🔐 Command Permissions — " .. guild.name,
					description = table.concat(lines, "\n", i, math.min(i + perPage - 1, #lines)) .. "\n\n-# Subcommands are listed only when they have their own rules. Owners always bypass.",
					color = colors.info
				})
			end
			return paginate(interaction, pages, interaction.user, { ephemeral = true })
		elseif subcmd == "copy" then
			local from = needEntry(args.from)
			if not from then return end
			local to = needEntry(args.to)
			if not to then return end
			local rec = loadRecord(guild.id, from.key)
			return finish(to, rec, "📋 **Copied rules from** `/" .. from.key .. "`")
		elseif subcmd == "preset" then
			local list = cmdperms.PRESETS[args.preset or ""]
			if not list then
				return interaction:fail("Unknown preset.", nil, true)
			end
			local role = args.role
			local applied = {}
			for _, name in ipairs(list) do
				local entry = findEntry(name)
				if entry then
					local rec = loadRecord(guild.id, entry.key)
					rec.roles[role.id] = true
					if saveRecord(guild, entry.key, rec, actor) then
						table.insert(applied, "`/" .. entry.key .. "`")
					end
				end
			end
			syncVisibility()
			local text = "✅ **Preset `" .. args.preset .. "`:** allowed " .. role.mentionString .. " on " .. (applied[1] and table.concat(applied, ", ") or "*nothing*")
			logChange(guild, actor, text)
			return interaction:success(text, nil, true)
		elseif subcmd == "panel" then
			return openPanel(interaction, nil)
		elseif subcmd == "role" then
			return openPanel(interaction, args.role and args.role.id)
		end

		return interaction:fail("Unknown subcommand.", nil, true)
	end
}
