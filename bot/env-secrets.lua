-- Zeltra: environment-variable version of secrets.lua, for containers (Docker / Railway).
-- scripts/docker-start.sh copies this file to secrets.lua at container start, so no secret is ever
-- stored in the repository or the image. Each key of example.secrets.lua maps to an environment
-- variable of the same name (the bot token may be given as DISCORD_TOKEN or TOKEN).
--   Lists (DEV_ACCESS_IDS): comma- or space-separated IDs.  Booleans: true/false (or 1/0, yes/no).

local function str(name, default)
	local value = os.getenv(name)
	if value == nil then return default end
	return value
end

local function num(name, default)
	return tonumber(os.getenv(name) or "") or default
end

local function bool(name, default)
	local value = os.getenv(name)
	if value == nil or value == "" then return default end
	value = value:lower()
	return value == "true" or value == "1" or value == "yes" or value == "on"
end

local function list(name)
	local result = {}
	for id in (os.getenv(name) or ""):gmatch("[^%s,]+") do
		table.insert(result, id)
	end
	return result
end

local token = str("DISCORD_TOKEN")
if token == nil or token == "" then token = str("TOKEN", "") end

local apiHost = str("API_HOST")
if apiHost == "" then apiHost = nil end

return {
	TOKEN = token,
	DEV_ACCESS_IDS = list("DEV_ACCESS_IDS"),
	DUCKY_CLIENT_SECRET = str("DUCKY_CLIENT_SECRET", ""),
	ROBLOX_CLIENT_ID = str("ROBLOX_CLIENT_ID", ""),
	ROBLOX_CLIENT_SECRET = str("ROBLOX_CLIENT_SECRET", ""),
	DUCKY_API_KEY = str("DUCKY_API_KEY", ""),
	ERLC_GLOBAL_API_KEY = str("ERLC_GLOBAL_API_KEY", ""),
	ROBLOSECURITY = str("ROBLOSECURITY", ""),
	TOP_GG_VOTE_AUTH = str("TOP_GG_VOTE_AUTH", ""),
	TOP_GG_API_KEY = str("TOP_GG_API_KEY", ""),
	DISCORD_BOT_LIST_API_KEY = str("DISCORD_BOT_LIST_API_KEY", ""),
	DISCORD_BOTS_GG_API_KEY = str("DISCORD_BOTS_GG_API_KEY", ""),
	ADERLC_API_KEY = str("ADERLC_API_KEY", ""),
	POSTGRES_HOST = str("POSTGRES_HOST", ""),
	POSTGRES_PORT = num("POSTGRES_PORT", 0),
	POSTGRES_USER = str("POSTGRES_USER", ""),
	POSTGRES_DB = str("POSTGRES_DB", ""),
	POSTGRES_PASSWORD = str("POSTGRES_PASSWORD", ""),
	HOME_GUILD_ID = str("HOME_GUILD_ID", ""),
	LOG_CHANNEL_ID = str("LOG_CHANNEL_ID", ""),
	WEB_BASE_URL = str("WEB_BASE_URL", ""),
	API_HOST = apiHost,
	KEEP_CUSTOM_EMOJIS = bool("KEEP_CUSTOM_EMOJIS", false),
	PLUS_PURCHASES_ENABLED = bool("PLUS_PURCHASES_ENABLED", false),
}
