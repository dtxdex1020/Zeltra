--[[
	/ownership (added by Zeltra; not part of upstream Ducky V1).
	Front end for modules/server_management/ownership.lua.
	  apply  - staff only (Staff Team role, Ducky moderator/admin roles, Manage Server, or a /permissions grant)
	  config - owners only: review channel, staff role, minimum role, cooldown, open/closed
	  reset  - owners only: clear someone's application record so they can apply again
	The command is registered visible to everyone (see PUBLIC_SLASH_COMMANDS in main.lua) because the staff
	roles in this server don't have a Discord permission to key on; access is checked by the bot. It can be
	narrowed further in Server Settings > Integrations, or with /permissions.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local slashCommand = tools.slashCommand("ownership", "Apply for ownership.")

local subcmd = tools.subCommand("apply", "Start or continue your ownership application.")
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("config", "Owners only: change ownership application settings.")
subcmd = subcmd:addOption(tools.channel("channel", "Where applications are posted for review."):setRequired(false))
subcmd = subcmd:addOption(tools.role("staff_role", "The role that counts as staff for applying."):setRequired(false))
subcmd = subcmd:addOption(tools.role("minimum_role", "Applicants need this role or higher."):setRequired(false))
subcmd = subcmd:addOption(tools.boolean("clear_minimum_role", "Remove the minimum role."):setRequired(false))
subcmd = subcmd:addOption(tools.integer("cooldown_days", "Days before someone can apply again after a denial."):setRequired(false))
subcmd = subcmd:addOption(tools.boolean("open", "Whether applications are open."):setRequired(false))
slashCommand:addOption(subcmd)

subcmd = tools.subCommand("reset", "Owners only: let someone apply again.")
subcmd = subcmd:addOption(tools.user("user", "The applicant."):setRequired(true))
slashCommand:addOption(subcmd)

local function isOwner(user)
	return _G.ownershipCore.isOwner(user.id) or (_G.isBotOwner and isBotOwner(user))
end

return {
	name = "ownership",
	description = "Apply for ownership.",
	aliases = {},
	category = "Staff Management",
	slashCommand = slashCommand,
	subcommands = { "apply", "config", "reset" },
	hybridCallback = function(interaction, args, slash, subcmd)
		if not slash then
			return interaction:fail("Use the `/ownership` slash command.", nil, true)
		end
		local api = _G.zeltraOwnership
		if not api then
			return interaction:fail("Ownership applications aren't loaded right now.", nil, true)
		end
		local guild = interaction.guild
		args = args or {}

		if subcmd == "apply" then
			return api.start(interaction)
		end

		if not isOwner(interaction.user) then
			return interaction:fail("Only the owners can use this.", nil, true)
		end
		local conf = api.getConf(guild)

		if subcmd == "config" then
			local changes = {}
			if args.channel then
				if not args.channel.send then return interaction:fail("Pick a text channel.", nil, true) end
				conf.channel = args.channel.id
				table.insert(changes, "review channel " .. args.channel.mentionString)
			end
			if args.staff_role then
				conf.staffrole = args.staff_role.id
				table.insert(changes, "staff role " .. args.staff_role.mentionString)
			end
			if args.minimum_role then
				conf.minrole = args.minimum_role.id
				table.insert(changes, "minimum role " .. args.minimum_role.mentionString)
			elseif args.clear_minimum_role then
				conf.minrole = nil
				table.insert(changes, "no minimum role")
			end
			if args.cooldown_days then
				if args.cooldown_days < 0 or args.cooldown_days > 365 then
					return interaction:fail("Use a cooldown from 0 to 365 days.", nil, true)
				end
				conf.cooldowndays = args.cooldown_days
				table.insert(changes, "cooldown " .. args.cooldown_days .. " days")
			end
			if args.open ~= nil then
				conf.enabled = args.open
				table.insert(changes, args.open and "applications open" or "applications closed")
			end

			if #changes == 0 then
				local pending = 0
				for _, r in pairs(conf.apps) do if r.status == "pending" then pending = pending + 1 end end
				return interaction:reply({ embed = dmStyle.buildEmbed({
					guild = guild, icon = "📝", title = "Ownership applications",
					fields = {
						{ "Status", conf.enabled and "Open" or "Closed" },
						{ "Review channel", conf.channel and ("<#" .. conf.channel .. ">") or "Not set" },
						{ "Staff role", conf.staffrole and ("<@&" .. conf.staffrole .. ">") or "Not set" },
						{ "Minimum role", conf.minrole and ("<@&" .. conf.minrole .. ">") or "None" },
						{ "Cooldown after denial", conf.cooldowndays .. " days" },
						{ "Waiting for review", tostring(pending) },
					},
					footer = "Ownership Applications",
				}).embed }, true)
			end
			api.saveConf(guild, conf, "OWNERSHIP_APPS_CONFIG")
			return interaction:success("Updated: " .. table.concat(changes, ", ") .. ".")

		elseif subcmd == "reset" then
			local user = args.user
			if not conf.apps[user.id] then
				return interaction:fail("<@" .. user.id .. "> doesn't have an application on record.", nil, true)
			end
			conf.apps[user.id] = nil
			api.saveConf(guild, conf, "OWNERSHIP_APPS_RESET")
			return interaction:success("<@" .. user.id .. "> can apply again.")
		end

		return interaction:fail("Unknown subcommand.", nil, true)
	end
}
