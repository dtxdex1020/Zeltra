--[[
	Zeltra emoji fallbacks (added by Zeltra; not part of upstream Ducky V1).

	Upstream Ducky uses custom *application* emojis that only Ducky's own Discord
	application can display. Any other bot (like Zeltra) would show them as broken
	":name:" text, so this maps every custom emoji to a Unicode equivalent.
	Set SECRETS.KEEP_CUSTOM_EMOJIS = true to skip this (e.g. after uploading your own
	application emojis and updating the IDs in main.lua).

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]
local map = {
	success = "✅", fail = "❌", yeswhite = "✔️", nowhite = "✖️", warning = "⚠️", loading = "⏳",
	beta = "🅱️", alpha = "🅰️", quack = "🪙", duckyplus = "💎", ducky = "⚡", left = "◀️", right = "▶️",
	settings = "⚙️", moderate = "🛡️", support = "🛟", log = "📜", game = "🎮", wave = "👋", roblox = "🟥",
	chat = "💬", role = "🏷️", channel = "#️⃣", member = "👤", emoji = "😀", document = "📄", pong = "🏓",
	pings = "🔔", delete = "🗑️", edit = "✏️", suggestion = "💡", suggester = "🙋", reminder = "⏰",
	pause = "⏸️", play = "▶️", stop = "⏹️", counting = "🔢", timeout = "⏱️", kick = "👢", ban = "🔨",
	clock = "🕒", link = "🔗", unlink = "🔓", blacklist = "🚫", plus = "➕", minus = "➖", add = "➕",
	subtract = "➖", lock = "🔒", unlock = "🔓", guild = "🏠", pin = "📌", protect = "🛡️", text = "🔤",
	image = "🖼️", paintbrush = "🖌️", art = "🎨", json = "🧾", ticket = "🎫", error = "⛔", import = "📥",
	export = "📤", founder = "👑", executive = "💼", developer = "🛠️", inspiration = "✨", contributor = "🤝",
	affiliate = "🔗", partner = "🤝", quickfix = "🩹", search = "🔍", duckyoutline = "⚡", duckyexperimental = "🧪",
	discordStaff = "🛡️", bughunter = "🐛", activeDeveloper = "👨‍💻", chart = "📊", boosting = "🚀", power = "🔌",
	hiya = "👋", skull = "💀", modcall = "🚨", shop = "🛒", mail = "✉️", gift = "🎁", send = "📨", key = "🔑",
	filter = "🧹", reload = "🔄", cloud = "☁️", location = "📍", draft = "📝", network = "🌐", desktop = "🖥️",
	mobile = "📱", folder = "📁", vehicle = "🚗", vehiclelocked = "🚙", eye = "👁️", livery = "🎨", box = "📦",
	bookmark = "🔖", casesensitive = "🔠", person = "🧍", people = "👥", book = "📖", list = "📋",
	competitor = "🥊", board = "📋", robux = "💰", rename = "✏️", DOT = "🚧", Fire = "🚒", Sheriff = "⭐",
	Police = "🚓", Criminal = "🦹", flag = "🚩", avatar = "🖼️", Bloxlink = "🔗", star = "⭐", halfstar = "✴️",
	emptystar = "⭐", web = "🌐", automation = "🤖", info = "ℹ️",
	CardBack = "🂠", backpack = "🎒", smroll = "🎲", smplus = "💎", smexperimental = "🧪", smducky = "⚡",
	smdev = "🛠️", sale = "🏷️", Blank = "⬜", verified = "☑️", equals = "🟰", notequal = "❎",
	lessorequal = "📉", greaterorequal = "📈", less = "⬇️", greater = "⬆️", undo = "↩️", redo = "↪️",
	on = "🟢", off = "🔴", cycle = "🔁", discord = "💬", PRC = "🚔", transfer = "🔀",
	donation = "💸", permission = "🔐", vertuo = "☕", o7 = "🫡", goose = "🪿", music = "🎵", line = "➖",
	swords = "⚔️", qa = "🧪", invis = "⬛", thread = "🧵", merge = "🔀", target = "🎯", map = "🗺️",
	license = "🪪",
}

-- Wordle tiles: Gray letters become regional-indicator letters, Yellow/Green become coloured squares
local function wordleTile(key)
	local colour, letter = key:match("^(%u%l+)(%u)$")
	if not colour then return nil end
	if colour == "Green" then return "🟩" end
	if colour == "Yellow" then return "🟨" end
	if colour == "Gray" then
		local cp = 0x1F1E6 + (letter:byte() - 65)
		-- encode code point as UTF-8, followed by a zero-width space so letters never merge into flags
		local b1 = 0xF0 + math.floor(cp / 0x40000)
		local b2 = 0x80 + math.floor(cp / 0x1000) % 0x40
		local b3 = 0x80 + math.floor(cp / 0x40) % 0x40
		local b4 = 0x80 + cp % 0x40
		return string.char(b1, b2, b3, b4) .. "\226\128\139"
	end
end

local suits = { Hearts = "♥️", Diamonds = "♦️", Spades = "♠️", Clubs = "♣️" }
local ranks = {
	Ace = "A", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8",
	Nine = "9", Ten = "10", Jack = "J", Queen = "Q", King = "K",
}

return function(emojis)
	for key, value in pairs(emojis) do
		if type(value) == "string" and value:find("<a?:[%w_]+:%d+>") then
			local replacement = map[key]
			if not replacement then
				local rank, suit = key:match("^(%u%l+)Of(%u%l+)$")
				if rank and ranks[rank] and suits[suit] then
					replacement = ranks[rank] .. suits[suit]
				else
					replacement = wordleTile(key)
				end
			end
			emojis[key] = replacement or "▫️"
		end
	end
	return emojis
end
