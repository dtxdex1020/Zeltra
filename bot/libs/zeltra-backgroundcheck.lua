--[[
	Zeltra: /backgroundcheck helpers (pure logic, no Discord calls) so they can be unit tested.
	Access is hard-locked to the IDs below. Nothing else (/permissions, Administrator, server owner,
	roles, TEST_DEMOTED_IDS) changes that.
]]
local M = {}

M.ALLOWED_IDS = {
	["1514313618827510011"] = true, -- dtxdex1
	["1307878235383795732"] = true, -- dtxdex
}
M.COLOR = 0xFF6A00
M.DENY_MESSAGE = "You can't use this"
M.YONLE_URL = "https://yonle.github.io/discorduser-globalban/list"

function M.isAllowed(userId)
	return userId ~= nil and M.ALLOWED_IDS[tostring(userId)] == true
end

--- Accepts a mention, a raw ID or nil; returns the ID string or nil.
function M.parseId(input)
	if input == nil then return nil end
	local s = tostring(input)
	local id = s:match("^%s*<@!?(%d+)>%s*$") or s:match("^%s*(%d+)%s*$")
	if id and #id >= 15 and #id <= 21 then return id end
	return nil
end

--- Unix seconds the snowflake was created.
function M.snowflakeTime(id)
	local n = tonumber(id)
	if not n then return nil end
	return math.floor((math.floor(n / 4194304) + 1420070400000) / 1000)
end

local SPAM_WORDS = { "nitro", "free", "giveaway", "airdrop", "steam", "gift", "crypto", "support", "admin", "moderator", "official", "discord", "bot", "promo", "onlyfans" }

--- Returns a reason string if the username looks like a spam or throwaway account, else nil.
function M.spamName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local n = name:lower()
	for _, w in ipairs(SPAM_WORDS) do
		if n:find(w, 1, true) then return "contains \"" .. w .. "\"" end
	end
	if n:match("%d%d%d%d%d?$") then return "ends in a long number" end
	local digits = select(2, n:gsub("%d", ""))
	if #n >= 8 and digits / #n >= 0.4 then return "mostly digits" end
	if n:match("(.)%1%1%1") then return "repeated characters" end
	local letters = n:gsub("[^a-z]", "")
	if #letters >= 10 and not letters:find("[aeiouy]") then return "random letters" end
	return nil
end

--- Parse the Yonle global ban list ("<id> <reason>" per line). Returns reason or nil.
function M.yonleLookup(body, userId)
	if type(body) ~= "string" then return nil end
	for line in body:gmatch("[^\r\n]+") do
		local id, reason = line:match("^%s*(%d+)%s*(.*)$")
		if id == tostring(userId) then
			return (reason ~= "" and reason) or "Listed"
		end
	end
	return nil
end

--[[ facts:
	accountAgeDays, defaultAvatar, noBanner, spamName (reason|nil), robloxLinked (true|false|nil=unknown),
	isBot, inGuild, currentlyBanned, banCount, kickCount, timeoutCount, caseCount, warnCount,
	infractionCount, punishmentCount, securityHits, botBlacklisted, otherServerHits
]]
function M.score(f)
	local pts, reasons = 0, {}
	local function add(p, r) pts = pts + p; table.insert(reasons, r) end
	if f.accountAgeDays and f.accountAgeDays < 7 then add(3, "Account is under 7 days old")
	elseif f.accountAgeDays and f.accountAgeDays < 30 then add(2, "Account is under 30 days old") end
	if f.defaultAvatar then add(1, "Default avatar") end
	if f.noBanner and f.defaultAvatar then add(0, "No banner") end
	if f.spamName then add(1, "Username looks like spam (" .. f.spamName .. ")") end
	if f.robloxLinked == false then add(1, "No Roblox account linked") end
	if f.currentlyBanned then add(4, "Currently banned here") end
	if (f.banCount or 0) > 0 and not f.currentlyBanned then add(2, "Banned here before") end
	if (f.kickCount or 0) > 0 then add(1, "Kicked here before") end
	if (f.timeoutCount or 0) > 0 then add(math.min(f.timeoutCount, 3), f.timeoutCount .. " timeout(s)") end
	local mod = (f.caseCount or 0) + (f.punishmentCount or 0)
	if mod > 0 then add(math.min(mod, 4), mod .. " moderation record(s)") end
	if (f.infractionCount or 0) > 0 then add(math.min(f.infractionCount, 3), f.infractionCount .. " staff infraction(s)") end
	if (f.securityHits or 0) > 0 then add(math.min(f.securityHits * 2, 6), f.securityHits .. " security alert(s)") end
	if f.botBlacklisted then add(4, "Blacklisted from the bot") end
	if (f.otherServerHits or 0) > 0 then add(4, "Listed in a public ban list") end
	local level = (pts >= 7 and "High") or (pts >= 3 and "Medium") or "Low"
	if #reasons == 0 then reasons = { "Nothing notable found" } end
	return level, reasons, pts
end

--- Clean text: drop em/en dashes and non-ASCII symbols (emojis) from free text going on the card.
function M.clean(s)
	s = tostring(s or "")
	s = s:gsub("\226\128\148", "-"):gsub("\226\128\147", "-")
	s = s:gsub("[\240-\247][\128-\191][\128-\191][\128-\191]", "")
	s = s:gsub("\226[\152-\157][\128-\191]", "")
	return s
end

function M.trim(s, n)
	s = M.clean(s)
	if #s > n then s = s:sub(1, n - 3) .. "..." end
	if s == "" then s = "None" end
	return s
end

return M
