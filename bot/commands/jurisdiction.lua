-- jurisdiction.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit

local MAPS = {
	fall = "https://api.erlc.gg/maps/fall_postals.png",
	winter = "https://api.erlc.gg/maps/snow_postals.png",
	spring = "https://api.erlc.gg/maps/spring_postals.png",
	summer = "https://api.erlc.gg/maps/summer_postals.png",
}

local function season()
	local m = tonumber(os.date("!%m"))
	if m == 12 or m <= 2 then return "winter" elseif m <= 5 then return "spring" elseif m <= 8 then return "summer" end
	return "fall"
end

return K.command({
	name = "jurisdiction",
	description = "Department jurisdiction info.",
	subs = {
		{
			name = "map", description = "Show the map and which department covers what.",
			options = {
				{ type = "string", name = "season", description = "Which map to show.", choices = {
					{ name = "Fall", value = "fall" }, { name = "Winter", value = "winter" },
					{ name = "Spring", value = "spring" }, { name = "Summer", value = "summer" },
				} },
			},
			run = function(ctx, args)
				local s = args.season or season()
				return ctx:card({
					title = "SCRP Jurisdiction Map",
					intro = "Stay in your area unless you are called for backup or are in a pursuit that crosses over.",
					blocks = {
						{ { "SC Highway Patrol", "Highways, interstates, and pursuits anywhere" } },
						{ { "York County Sheriff", "County roads and everything outside city limits" } },
						{ { "Fort Mill Police", "Inside Fort Mill city limits" } },
						{ { "Fort Mill Fire", "Fires, medical calls, and rescues everywhere" } },
						{ { "Fort Mill DOT", "Towing, road work, and traffic control everywhere" } },
					},
					note = "Map: " .. s:sub(1, 1):upper() .. s:sub(2) .. " with postals.",
					image = MAPS[s],
				})
			end
		},
	}
})
