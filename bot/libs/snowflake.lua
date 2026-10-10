--[[
	Zeltra compatibility module (added by Zeltra; not part of upstream Ducky V1).
	Minimal Twitter/Discord-style snowflake ID generator used by Ducky code as
	`snowflake.new(datacenterId, workerId):next()`. Returns IDs as decimal strings.
	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1).
]]
local ffi = require("ffi")
local bit = require("bit")

local EPOCH = 1420070400000ULL -- 2015-01-01, same epoch Discord uses

local Snowflake = {}
Snowflake.__index = Snowflake

local function nowMs()
	local uv = require("uv")
	local s, us = uv.gettimeofday()
	return ffi.new("uint64_t", s) * 1000ULL + ffi.new("uint64_t", math.floor(us / 1000))
end

function Snowflake.new(datacenter, worker)
	return setmetatable({
		dc = ffi.new("uint64_t", (datacenter or 0) % 32),
		worker = ffi.new("uint64_t", (worker or 0) % 32),
		seq = 0,
		last = 0ULL,
	}, Snowflake)
end

function Snowflake:next()
	local t = nowMs()
	if t == self.last then
		self.seq = (self.seq + 1) % 4096
		if self.seq == 0 then
			while t <= self.last do t = nowMs() end
		end
	else
		self.seq = 0
	end
	self.last = t
	local id = bit.bor(bit.lshift(t - EPOCH, 22), bit.lshift(self.dc, 17), bit.lshift(self.worker, 12), ffi.new("uint64_t", self.seq))
	return (tostring(ffi.cast("uint64_t", id)):gsub("ULL$", ""))
end

return Snowflake
