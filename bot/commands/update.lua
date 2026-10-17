-- update.lua (SCRP). Posts or refreshes the live queue board. Hand-coded by Dex.
local K = _G.scrpKit
local E = _G.scrpApi.erlc

return K.command({
	name = "update",
	description = "Update live boards.",
	subs = {
		{
			name = "queue", description = "Post or refresh the live queue board in this channel.", tier = K.TIER.MOD,
			run = function(ctx)
				local card, err = _G.scrpErlcCard and _G.scrpErlcCard(true)
				if not card then
					return ctx:fail(err == K.NOT_SET_UP and "The ER:LC API is not set up yet." or tostring(err or "The ER:LC API did not answer."))
				end
				card.title = "Live Server Queue"
				card.note = "Updated by " .. K.userName(ctx.user) .. ". Staff can run -update queue to refresh."
				local config = K.config(ctx.guild)
				local board = config.scrp_queueboard
				if board and board.channel then
					local channel = ctx.guild:getChannel(board.channel)
					local msg = channel and channel:getMessage(board.message)
					if msg then
						local payload = K.card(card)
						payload.files = nil
						payload.embeds[1].image = msg.embed and msg.embed.image or payload.embeds[1].image
						local ok = msg:update({ embeds = payload.embeds, components = payload.components })
						if ok then return ctx:ok("The queue board was updated: " .. msg.link) end
					end
				end
				local msg, e = ctx.channel:send(K.card(card))
				if not msg then return ctx:fail("I could not post the queue board. " .. tostring(e or "")) end
				K.save(ctx.guild, { scrp_queueboard = { channel = ctx.channel.id, message = msg.id } }, "SCRP_QUEUEBOARD")
				return ctx:ok("The queue board was posted. Run this again to refresh it.")
			end
		},
	}
})
