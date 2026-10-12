--[[
	SCRP server shop (added by Zeltra; not part of upstream Ducky V1).

	The #marketplace shop panel and its items. Each item is a ticket subject in Ducky's ticket module
	(config.panels[<message id>].subjects), so picking an item opens a ticket in the Paid Ads & Affiliates
	category. Used by seeds/shop_panel.lua and the tests; kept free of Discordia.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local M = {}

M.GUILD_ID = "1522997818330058772"
M.PANEL_KEY = "scrp-shop-v1"
M.PANEL_CHANNEL = "1522997820116697225" -- 「🛒」marketplace
M.LOG_CHANNEL = "1522997828127948838" -- 「📁」ticket-logs
M.CATEGORY = "1522997827662512339" -- ☰ SHR's Assistance (Paid Ads & Affiliates tickets)
M.COLOR = 16738816
M.LOGO = "<:scrp_logo:1559269062490587307>"
M.BANNER = "banner-shop.jpg"
M.STRIP = "strip.jpg"
M.PAYMENT = "PayPal only"

M.DEX = "1307878235383795732" -- Dex (Shark), the only person who handles shop tickets and payments

M.ROLES = {
	shr = "1522997818447626452", -- SCRP I Senior High Rank
	relations = "1522997818363740167", -- SCRP I Director of Relations
}

M.ITEMS = {
	{ key = "office", name = "Custom Office + Role", price = "5.99", line = "Your own office voice channel and a custom role.", prefix = "shop-office" },
	{ key = "plus", name = "SCRP Plus", price = "4.99", line = "Supporter perks and the SCRP Plus role.", prefix = "shop-plus" },
	{ key = "everyone", name = "Everyone AD", price = "3.99", line = "Your ad posted in our ad channel with an @everyone ping.", prefix = "shop-ad" },
	{ key = "here", name = "Here AD", price = "2.99", line = "Your ad posted with an @here ping.", prefix = "shop-ad" },
	{ key = "noping", name = "No Ping AD", price = "1.99", line = "Your ad posted without a ping.", prefix = "shop-ad" },
}

local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = copy(v) end
	return o
end

function M.price(item)
	return "$" .. item.price .. " USD"
end

function M.openCard(item)
	return { {
		title = "Shop order: " .. item.name,
		description = "Thanks, {opener.mention}. You picked **" .. item.name .. "** for **" .. M.price(item) .. "**.\n\n"
			.. "Payment is **PayPal only**. We don't take Robux, gift cards or crypto for shop items. "
			.. "**Dex (<@" .. M.DEX .. ">) is the only person who handles shop tickets and payments.** He will post the PayPal details in this ticket. "
			.. "Only pay Dex through the details given here, never anyone else and never someone who DMs you.\n\n"
			.. "**Copy this and fill it in:**\n> **Roblox username:**\n> **Item:** " .. item.name .. "\n> **Anything we should know:**"
			.. "\n\n-# Ticket {ticket.number} · Please don't ping staff, someone will be with you soon.",
		color = M.COLOR,
	} }
end

function M.subjects()
	local out = {}
	for _, item in ipairs(M.ITEMS) do
		table.insert(out, {
			name = item.name,
			description = M.price(item) .. " · " .. M.PAYMENT,
			key = "shop-" .. item.key,
			category = M.CATEGORY,
			support = { M.ROLES.shr, M.ROLES.relations },
			mentionables = { M.DEX, M.ROLES.relations },
			supportusers = { M.DEX },
			transcriptschannel = M.LOG_CHANNEL,
			ticketname = item.prefix .. "-{ticket.number}",
			ticketclaimmode = "lock",
			embeds = {
				open = M.openCard(item),
				close = { { title = "Ticket Closed", description = "> This ticket was closed by {closer.mention}.\n> **Reason:** {reason}", color = 0xFF6666 } },
				claim = { { title = "Ticket Claimed", description = "> {claimer.mention} will be handling your order.", color = 0x66FF66 } },
				unclaim = { { title = "Ticket Unclaimed", description = "> {unclaimer.mention} unclaimed this ticket.\n> -# Someone else will be with you soon.", color = 0xFF6A00 } },
				request = { { title = "Close Request", description = "> {requester.mention} would like to close this ticket.\n> **Reason:** {reason}", color = M.COLOR } },
			},
			tickets = {},
		})
	end
	return out
end

-- Escalation for shop tickets: straight to Ownership only.
function M.escalation()
	local T = require("zeltra-tickets-scrp")
	local esc = T.escalation()
	local keep = {}
	for _, t in ipairs(esc.tiers) do if t.key == "ownership" then keep[#keep + 1] = t end end
	esc.tiers = keep
	return esc
end

function M.mergeSubjects(fresh, old)
	local byKey = {}
	for _, s in ipairs(old or {}) do byKey[s.key or s.name] = s end
	for _, s in ipairs(fresh) do
		local o = byKey[s.key] or byKey[s.name]
		if o then s.tickets = o.tickets or {}; s.nextticketid = o.nextticketid end
	end
	return fresh
end

function M.panelPayload()
	local lines = {}
	local options = {}
	for i, item in ipairs(M.ITEMS) do
		table.insert(lines, "**" .. item.name .. "** · " .. M.price(item) .. "\n-# " .. item.line)
		table.insert(options, { label = item.name, value = tostring(i), description = M.price(item) .. " · " .. M.PAYMENT })
	end
	return {
		flags = 32768,
		allowed_mentions = { parse = {} },
		components = { {
			type = 17,
			accent_color = M.COLOR,
			components = {
				{ type = 12, items = { { media = { url = "attachment://" .. M.BANNER } } } },
				{ type = 10, content = "## " .. M.LOGO .. " | Server Shop\n"
					.. "> Want to support the server or get your community seen? Pick an item below and a ticket opens for you. "
					.. "Prices are in USD and payment is **PayPal only**, no Robux." },
				{ type = 10, content = table.concat(lines, "\n\n") },
				{ type = 14, divider = true, spacing = 1 },
				{ type = 1, components = { {
					type = 3,
					custom_id = "subjectselect",
					placeholder = "Choose a shop item",
					min_values = 0,
					max_values = 1,
					options = options,
				} } },
				{ type = 10, content = "-# Purchases help pay for the server and the bot. Refunds are handled case by case through the ticket." },
				{ type = 12, items = { { media = { url = "attachment://" .. M.STRIP } } } },
			},
		} },
	}
end

M._copy = copy
return M
