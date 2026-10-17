--[[
	SCRP API helpers. Hand-coded by Dex.

	ER:LC private server API (PRC, https://api.erlc.gg/v1), key from env ERLC_API_KEY.
	Roblox group (Open Cloud), group from env ROBLOX_GROUP_ID and key from env ROBLOX_API_KEY.
	Public Roblox lookups (users, thumbnails) need no key.
	When a key is missing, calls return nil, "not set up yet", "nokey".
]]

local A = { erlc = {}, roblox = {} }
local E, R = A.erlc, A.roblox

E.BASE = "https://api.erlc.gg/v1"
R.CLOUD = "https://apis.roblox.com/cloud/v2"
local NOT_SET_UP = "not set up yet"

local function env(name)
	local v = os.getenv(name)
	if v and v ~= "" then return v end
end

local function decode(body)
	if type(body) ~= "string" or body == "" then return nil end
	local ok, data = pcall(_G.json.decode, body)
	if ok then return data end
end

--- Plain HTTP call. Returns code, decoded body (or raw string), raw body.
local function request(method, url, headers, body)
	local payload
	if body ~= nil then
		payload = _G.json.encode(body)
		headers[#headers + 1] = { "Content-Type", "application/json" }
	end
	local ok, res, raw = pcall(_G.http.request, method, url, headers, payload, 15000)
	if not ok then return 0, nil, tostring(res) end
	return (res and res.code) or 0, decode(raw), raw
end
A.request = request

---------------------------------------------------------------- ER:LC

function E.key() return env("ERLC_API_KEY") end
function E.ready() return E.key() ~= nil end

local cache = {}
local TTL = 10

local function erlcError(code, data, raw)
	if type(data) == "table" and data.message then return tostring(data.message) end
	if code == 0 then return "The ER:LC API did not answer. Try again in a bit." end
	if code == 403 then return "The ER:LC API key was rejected." end
	if code == 422 then return "The server has no players right now." end
	if code == 429 then return "The ER:LC API is rate limiting us. Try again in a few seconds." end
	return "The ER:LC API returned HTTP " .. tostring(code) .. "."
end

function E.get(path, fresh)
	local key = E.key()
	if not key then return nil, NOT_SET_UP, "nokey" end
	local hit = cache[path]
	if not fresh and hit and os.time() - hit.at < TTL then return hit.data end
	local code, data, raw = request("GET", E.BASE .. path, { { "Server-Key", key }, { "Accept", "application/json" } })
	if code == 200 and data ~= nil then
		cache[path] = { at = os.time(), data = data }
		return data
	end
	return nil, erlcError(code, data, raw), code
end

function E.server(fresh) return E.get("/server", fresh) end
function E.players(fresh) return E.get("/server/players", fresh) end
function E.queue(fresh) return E.get("/server/queue", fresh) end
function E.staff(fresh) return E.get("/server/staff", fresh) end

function E.command(command)
	local key = E.key()
	if not key then return nil, NOT_SET_UP, "nokey" end
	local code, data, raw = request("POST", E.BASE .. "/server/command", { { "Server-Key", key }, { "Accept", "application/json" } }, { command = command })
	if code == 200 then return true end
	return nil, erlcError(code, data, raw), code
end

--- "Name:123" -> "Name", "123"
function E.splitPlayer(p)
	local name, id = tostring(p or ""):match("^(.-):(%d+)$")
	return name or tostring(p or "Unknown"), id
end

--- Players with a staff permission in game (anything other than Normal).
function E.staffCount(players)
	local n = 0
	for _, p in ipairs(players or {}) do
		local perm = tostring(p.Permission or "")
		if perm ~= "" and perm ~= "Normal" then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------- Roblox (public)

local userCache = {}

function R.user(id)
	id = tostring(id or "")
	if id == "" then return nil end
	if userCache[id] then return userCache[id] end
	local code, data = request("GET", "https://users.roblox.com/v1/users/" .. id, { { "Accept", "application/json" } })
	if code == 200 and type(data) == "table" and data.name then
		userCache[id] = data
		return data
	end
end

function R.userByName(name)
	name = tostring(name or ""):gsub("^@", "")
	if name == "" then return nil end
	if name:match("^%d+$") then
		local u = R.user(name)
		if u then return u end
	end
	local code, data = request("POST", "https://users.roblox.com/v1/usernames/users", { { "Accept", "application/json" } }, { usernames = { name }, excludeBannedUsers = false })
	if code == 200 and type(data) == "table" and data.data and data.data[1] then
		local u = data.data[1]
		userCache[tostring(u.id)] = u
		return u
	end
end

function R.headshot(id)
	local code, data = request("GET", "https://thumbnails.roblox.com/v1/users/avatar-headshot?size=150x150&format=Png&userIds=" .. tostring(id), { { "Accept", "application/json" } })
	if code == 200 and type(data) == "table" and data.data and data.data[1] then
		return data.data[1].imageUrl
	end
end

function R.profile(id) return "https://www.roblox.com/users/" .. tostring(id) .. "/profile" end

---------------------------------------------------------------- Roblox group (Open Cloud)

function R.groupId() return env("ROBLOX_GROUP_ID") end
function R.key() return env("ROBLOX_API_KEY") end
function R.ready() return R.groupId() ~= nil and R.key() ~= nil end
function R.groupLink() return "https://www.roblox.com/communities/" .. tostring(R.groupId() or "0") end

local function robloxError(code, data, raw)
	if type(data) == "table" then
		if data.message then return tostring(data.message) end
		if data.errors and data.errors[1] and data.errors[1].message then return tostring(data.errors[1].message) end
	end
	if code == 0 then return "Roblox did not answer. Try again in a bit." end
	if code == 401 or code == 403 then return "Roblox rejected the API key (check its group permissions)." end
	if code == 404 then return "Roblox could not find that." end
	return "Roblox returned HTTP " .. tostring(code) .. "."
end

local function cloud(method, path, body)
	if not R.ready() then return nil, NOT_SET_UP, "nokey" end
	local code, data, raw = request(method, R.CLOUD .. "/groups/" .. R.groupId() .. path, { { "x-api-key", R.key() }, { "Accept", "application/json" } }, body)
	if code >= 200 and code < 300 then return data or {} end
	return nil, robloxError(code, data, raw), code
end
R.cloud = cloud

function R.info() return cloud("GET", "") end

function R.joinRequests(max)
	return cloud("GET", "/join-requests?maxPageSize=" .. tostring(max or 20))
end

function R.pendingRequest(userId)
	local data, err, code = cloud("GET", "/join-requests?maxPageSize=1&filter=" .. _G.querystring.urlencode("user == 'users/" .. tostring(userId) .. "'"))
	if not data then return nil, err, code end
	return (data.groupJoinRequests or {})[1] or false
end

function R.accept(userId) return cloud("POST", "/join-requests/" .. tostring(userId) .. ":accept", {}) end
function R.decline(userId) return cloud("POST", "/join-requests/" .. tostring(userId) .. ":decline", {}) end

function R.membership(userId)
	local data, err, code = cloud("GET", "/memberships?maxPageSize=1&filter=" .. _G.querystring.urlencode("user == 'users/" .. tostring(userId) .. "'"))
	if not data then return nil, err, code end
	return (data.groupMemberships or {})[1] or false
end

function R.role(roleId)
	local id = tostring(roleId or ""):match("(%d+)$")
	if not id then return nil end
	return cloud("GET", "/roles/" .. id)
end

--- Removes a member from the group (groups.roblox.com, API key auth).
function R.kick(userId)
	if not R.ready() then return nil, NOT_SET_UP, "nokey" end
	local code, data, raw = request("DELETE", "https://groups.roblox.com/v1/groups/" .. R.groupId() .. "/users/" .. tostring(userId), { { "x-api-key", R.key() }, { "Accept", "application/json" } })
	if code >= 200 and code < 300 then return true end
	return nil, robloxError(code, data, raw), code
end

return A
