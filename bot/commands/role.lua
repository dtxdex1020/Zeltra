-- role.lua (SCRP). Add or remove a role. Hand-coded by Dex.
local K = _G.scrpKit

return K.command({
	name = "role",
	description = "Add or remove a role from a member.",
	tier = K.TIER.MGMT,
	options = {
		{ type = "user", name = "user", description = "Member (ID or mention).", required = true },
		{ type = "role", name = "role", description = "Role to give or take (ID, mention, or name).", required = true, rest = true },
		{ type = "string", name = "action", description = "Add or remove (defaults to switching it).", choices = {
			{ name = "Add", value = "add" }, { name = "Remove", value = "remove" },
		} },
	},
	run = function(ctx, args)
		local member = K.memberOf(ctx.guild, args.user)
		if not member then return ctx:fail("That user is not in the server.") end
		local role = args.role
		if role.id == ctx.guild.id then return ctx:fail("You can't change the everyone role.") end
		if role.managed then return ctx:fail("That role is managed by an integration.") end
		local me = ctx.guild.me
		local botTop = me and me.highestRole and me.highestRole.position or 0
		if role.position >= botTop then return ctx:fail("That role is at or above my highest role, so I can't touch it.") end
		local privileged = K.tier(ctx.member) >= K.TIER.OWNER
		local callerTop = ctx.member.highestRole and ctx.member.highestRole.position or 0
		if not privileged and role.position >= callerTop then
			return ctx:fail("That role is at or above your highest role, so you can't touch it.")
		end
		if not privileged and member.id ~= ctx.member.id and member.highestRole and member.highestRole.position >= callerTop then
			return ctx:fail("That member is at or above your rank.")
		end
		local has = member:hasRole(role.id)
		local action = args.action or (has and "remove" or "add")
		if action == "add" and has then return ctx:fail(member.mentionString .. " already has " .. role.mentionString .. ".") end
		if action == "remove" and not has then return ctx:fail(member.mentionString .. " does not have " .. role.mentionString .. ".") end
		local ok, err
		local why = "role command by " .. ctx.user.username
		if action == "add" then ok, err = member:addRole(role.id, why) else ok, err = member:removeRole(role.id, why) end
		if not ok then return ctx:fail("Discord would not let me change that role. " .. tostring(err or "")) end
		return ctx:card({
			title = action == "add" and "Role Added" or "Role Removed",
			blocks = { { { "Member", member.mentionString, true }, { "Role", role.mentionString, true }, { "Changed By", ctx.user.mentionString, true } } },
			banner = false,
		})
	end
})
