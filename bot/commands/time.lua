-- time.lua (SCRP). Hand-coded by Dex.
local K = _G.scrpKit

local ZONES = {
	{ key = "est", name = "Eastern", offset = -5, dst = true },
	{ key = "cst", name = "Central", offset = -6, dst = true },
	{ key = "mst", name = "Mountain", offset = -7, dst = true },
	{ key = "pst", name = "Pacific", offset = -8, dst = true },
	{ key = "utc", name = "UTC", offset = 0 },
	{ key = "gmt", name = "London", offset = 0, eudst = true },
	{ key = "cet", name = "Central Europe", offset = 1, eudst = true },
	{ key = "aest", name = "Sydney", offset = 10 },
}

-- US daylight time: second Sunday of March 2:00 to first Sunday of November 2:00 (local).
local function usDst(t)
	local d = os.date("!*t", t)
	local function nthSunday(month, n)
		local first = os.time({ year = d.year, month = month, day = 1, hour = 12 })
		local wday = tonumber(os.date("!%w", first))
		return 1 + ((7 - wday) % 7) + (n - 1) * 7
	end
	local m, day = d.month, d.day
	if m > 3 and m < 11 then return true end
	if m == 3 then return day >= nthSunday(3, 2) end
	if m == 11 then return day < nthSunday(11, 1) end
	return false
end

local function euDst(t)
	local d = os.date("!*t", t)
	local function lastSunday(month)
		local days = os.date("!*t", os.time({ year = d.year, month = month + 1, day = 0, hour = 12 })).day
		local last = os.time({ year = d.year, month = month, day = days, hour = 12 })
		return days - tonumber(os.date("!%w", last))
	end
	local m, day = d.month, d.day
	if m > 3 and m < 10 then return true end
	if m == 3 then return day >= lastSunday(3) end
	if m == 10 then return day < lastSunday(10) end
	return false
end

local function zoneTime(z, now)
	local off = z.offset + (((z.dst and usDst(now)) or (z.eudst and euDst(now))) and 1 or 0)
	return os.date("!%I:%M %p", now + off * 3600):gsub("^0", ""), off
end

local choices = {}
for _, z in ipairs(ZONES) do table.insert(choices, { name = z.name, value = z.key }) end

return K.command({
	name = "time",
	description = "Show the current time.",
	options = {
		{ type = "string", name = "zone", description = "Time zone to show.", choices = choices },
	},
	run = function(ctx, args)
		local now = os.time()
		local lines = {}
		for _, z in ipairs(ZONES) do
			if not args.zone or args.zone == z.key then
				local t, off = zoneTime(z, now)
				table.insert(lines, { z.name, t .. " (UTC" .. (off >= 0 and "+" or "") .. off .. ")" })
			end
		end
		return ctx:card({
			title = "Current Time",
			blocks = { lines, { { "Your Time", "<t:" .. now .. ":F>", true } } },
			banner = false,
		})
	end
})
