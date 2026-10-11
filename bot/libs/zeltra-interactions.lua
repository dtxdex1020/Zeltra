--[[
	Zeltra interaction timing and auto-defer (added by Zeltra; not part of upstream Ducky V1).

	Discord drops an interaction ("Unknown interaction", 10062, and the user sees "The application did
	not respond") if the bot doesn't send a first response within 3 seconds of Discord creating it.

	  * Timing: every slash command gets one log line when its first response is sent, split into
	      gateway  Discord creating the interaction -> the bot receiving it
	      wait     received -> the first response request starting (permission checks, DB, the command)
	      http     how long the first response request took
	    Slow or failed responses are always logged; component/modal interactions only when slow or failed.
	  * Auto-defer: the slash command dispatcher calls M.autoDefer(). If nothing has been sent by
	    AUTO_DEFER_MS after receiving it (or 2.2s after Discord created it, whichever is sooner), the bot
	    sends "thinking..." so the command can take as long as it needs. Later replies become the
	    follow-up that replaces the thinking message. A command can set `noAutoDefer = true` (for example
	    one that opens a modal) or `deferEphemeral = true` (thinking message only visible to the user).
	  * Responses can't collide: a reply sent while the auto-defer request is in flight waits for it and
	    then goes out as a follow-up. replyDeferred() after an auto-defer is a no-op.
	  * Event loop monitor: logs when the loop was blocked for more than LAG_WARN_MS.

	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local uv = require("uv")
local timer = require("timer")

local M = {
	AUTO_DEFER_MS = 1500,
	DEADLINE_MARGIN_MS = 800, -- defer no later than 3000 - this after Discord created the interaction
	SLOW_MS = 1500,
	LAG_WARN_MS = 500,
	stats = { commands = 0, autoDeferred = 0, failed = 0, slow = 0, maxLagMs = 0 },
	log = print,
}

local function wallMs()
	local s, us = uv.gettimeofday()
	return s * 1000 + us / 1000
end
M.wallMs = wallMs

local function createdMs(ia)
	local ok, t = pcall(function() return ia.createdAt end)
	return ok and type(t) == "number" and t * 1000 or nil
end

local function errText(err)
	err = tostring(err or "")
	return (err:match("HTTP Error %d+ : [^\n]*") or err):sub(1, 140)
end

local function label(ia)
	if ia._zLabel then return ia._zLabel end
	local d = ia._data or ia.data or {}
	if d.name then return "/" .. d.name end
	if d.custom_id then return "component " .. tostring(d.custom_id):sub(1, 40) end
	return "interaction"
end

local function report(ia, kind, startMs, endMs, ok, err)
	local recv = ia._zRecv or startMs
	local created = createdMs(ia) or recv
	local gateway = math.floor(recv - created + 0.5)
	local wait = math.floor(startMs - recv + 0.5)
	local http = math.floor(endMs - startMs + 0.5)
	local total = math.floor(endMs - created + 0.5)
	local isCommand = ia._zCommand
	local slow = total >= M.SLOW_MS or http >= 1000
	if slow then M.stats.slow = M.stats.slow + 1 end
	if not ok then M.stats.failed = M.stats.failed + 1 end
	if not (isCommand or slow or not ok) then return end
	M.log(("[interaction] %s %s gateway=%dms wait=%dms http=%dms total=%dms %s%s"):format(
		label(ia), kind, gateway, wait, http, total,
		ok and "ok" or ("FAILED " .. errText(err)),
		ia._zAutoDeferred and " (auto-deferred)" or ""))
end

local function waitInFlight(ia)
	local n = 0
	while ia._zInFlight and n < 300 do
		timer.sleep(10)
		n = n + 1
	end
end

--- Wraps the first-response methods of an Interaction class. Safe to call more than once.
function M.install(Interaction)
	if not Interaction then
		M.log("[interaction] Interaction class not loaded; timing and auto-defer are off")
		return M
	end
	if rawget(Interaction, "_zInstalled") then return M end
	rawset(Interaction, "_zInstalled", true)

	local init = Interaction.__init
	Interaction.__init = function(self, ...)
		self._zRecv = wallMs()
		return init(self, ...)
	end

	local sendMessage = Interaction._sendMessage
	Interaction._sendMessage = function(self, payload, files, deferred)
		waitInFlight(self)
		if self._initialRes then
			if deferred then return true end -- already acknowledged, nothing to defer
			return self:_sendFollowup(payload, files)
		end
		self._zInFlight = true
		local t0 = wallMs()
		local res, err = sendMessage(self, payload, files, deferred)
		self._zInFlight = false
		if not self._zReported then
			self._zReported = true
			report(self, deferred and "defer" or "reply", t0, wallMs(), res ~= nil and res ~= false, err)
		end
		return res, err
	end

	local sendUpdate = Interaction._sendUpdate
	Interaction._sendUpdate = function(self, payload, files)
		waitInFlight(self)
		if self._initialRes then
			if not payload then return true end
			return self:update(payload)
		end
		self._zInFlight = true
		local t0 = wallMs()
		local ok, err = sendUpdate(self, payload, files)
		self._zInFlight = false
		if not self._zReported then
			self._zReported = true
			report(self, payload and "update" or "defer-update", t0, wallMs(), ok, err)
		end
		return ok, err
	end

	local sendModal = Interaction._sendModal
	Interaction._sendModal = function(self, payload)
		waitInFlight(self)
		if self._initialRes then
			M.log(("[interaction] %s tried to open a modal after it was already answered%s"):format(
				label(self), self._zAutoDeferred and " (auto-deferred; set noAutoDefer on this command)" or ""))
			return false, "interaction already acknowledged"
		end
		self._zInFlight = true
		local t0 = wallMs()
		local ok, err = sendModal(self, payload)
		self._zInFlight = false
		if ok then self._initialRes = true end
		if not self._zReported then
			self._zReported = true
			report(self, "modal", t0, wallMs(), ok, err)
		end
		return ok, err
	end

	Interaction.replyDeferred = function(self, isEphemeral)
		waitInFlight(self)
		if self._initialRes then return true end
		return self:_sendMessage(isEphemeral and { flags = 64 } or nil, nil, true)
	end

	Interaction.updateDeferred = function(self)
		assert(self._message, "DEFERRED_UPDATE_MESSAGE is only supported by components-based interactions!")
		waitInFlight(self)
		if self._initialRes then return true end
		return self:_sendUpdate()
	end

	return M
end

--- Called by the slash command dispatcher as soon as a command arrives.
function M.track(ia, name)
	ia._zCommand = true
	ia._zLabel = name and ("/" .. tostring(name)) or nil
	ia._zRecv = ia._zRecv or wallMs()
	M.stats.commands = M.stats.commands + 1
end

--- Milliseconds until the auto-defer should fire for this interaction.
function M.deferDelay(ia, nowMs)
	nowMs = nowMs or wallMs()
	local recv = ia._zRecv or nowMs
	local byRecv = recv + M.AUTO_DEFER_MS - nowMs
	local created = createdMs(ia)
	local byDeadline = created and (created + 3000 - M.DEADLINE_MARGIN_MS - nowMs) or byRecv
	return math.max(0, math.floor(math.min(byRecv, byDeadline)))
end

--- Sends "thinking..." if the command hasn't responded in time. opts: {noAutoDefer, deferEphemeral}
function M.autoDefer(ia, opts)
	opts = opts or {}
	ia._zDeferOpts = opts
	local delay = M.deferDelay(ia)
	local function fire()
		local o = ia._zDeferOpts or {}
		if ia._initialRes or ia._zInFlight or o.noAutoDefer or ia._zNoAutoDefer then return end
		coroutine.wrap(function()
			if ia._initialRes or ia._zInFlight then return end
			ia._zAutoDeferred = true
			local res, err = ia:replyDeferred(o.deferEphemeral and true or false)
			if res then
				M.stats.autoDeferred = M.stats.autoDeferred + 1
			else
				M.log("[interaction] auto-defer failed for " .. label(ia) .. ": " .. errText(err))
			end
		end)()
	end
	if delay <= 0 then
		fire()
		return 0
	end
	timer.setTimeout(delay, fire)
	return delay
end

--- Logs whenever the event loop was blocked (a timer fired much later than scheduled).
function M.startLagMonitor(intervalMs)
	intervalMs = intervalMs or 500
	local last = uv.hrtime()
	local t = uv.new_timer()
	t:start(intervalMs, intervalMs, function()
		local nowNs = uv.hrtime()
		local lag = (nowNs - last) / 1e6 - intervalMs
		last = nowNs
		if lag > M.stats.maxLagMs then M.stats.maxLagMs = math.floor(lag) end
		if lag >= M.LAG_WARN_MS then
			M.log(("[interaction] event loop was blocked for about %dms"):format(math.floor(lag)))
		end
	end)
	t:unref()
	return t
end

return M
