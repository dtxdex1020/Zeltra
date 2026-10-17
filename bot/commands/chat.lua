-- chat.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit
local P = discordia.enums.permission

local function setLock(ctx, args, lock)
	local channel = args.channel or ctx.channel
	if not channel or not channel.getPermissionOverwriteFor then return ctx:fail("I can only lock text channels.") end
	local everyone = channel:getPermissionOverwriteFor(ctx.guild.defaultRole)
	if not everyone then return ctx:fail("I could not change that channel.") end
	local locked = everyone:getDeniedPermissions():has(P.sendMessages)
	if lock and locked then return ctx:fail("That channel is already locked.") end
	if not lock and not locked then return ctx:fail("That channel is not locked.") end
	local ok
	if lock then
		local staff = ctx.guild:getRole(K.BASE_STAFF_ROLE)
		local so = staff and channel:getPermissionOverwriteFor(staff)
		if so then so:allowPermissions(P.sendMessages) end
		ok = everyone:denyPermissions(P.sendMessages)
	else
		ok = everyone:clearPermissions(P.sendMessages)
	end
	if not ok then return ctx:fail("I could not change that channel. Check my permissions.") end

	local card = K.card({
		title = lock and "Chat Locked" or "Chat Unlocked",
		intro = lock and "This channel is locked. Only staff can talk right now." or "This channel is open again.",
		blocks = { { { "Reason", args.reason or "No reason given" }, { (lock and "Locked" or "Unlocked") .. " By", ctx.user.mentionString, true } } },
		banner = false,
	})
	if channel.id ~= ctx.channel.id then channel:send(K.card({ title = card.embeds[1].title, intro = card.embeds[1].description, banner = false })) end
	pcall(db.send, db, ctx.guild, "modlogchannel", { embeds = card.embeds })
	return ctx:send(card)
end

local opts = {
	{ type = "channel", name = "channel", description = "Channel to change (defaults to this one)." },
	{ type = "string", name = "reason", description = "Why.", rest = true },
}

return K.command({
	name = "chat",
	description = "Lock or unlock a channel.",
	tier = K.TIER.ADMIN,
	subs = {
		{ name = "lock", description = "Stop members from talking in a channel.", options = opts, run = function(ctx, a) return setLock(ctx, a, true) end },
		{ name = "unlock", description = "Let members talk in a channel again.", options = opts, run = function(ctx, a) return setLock(ctx, a, false) end },
	}
})
