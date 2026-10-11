-- Run from bot/: ./luvit tests/interactions_test.lua
-- Zeltra: checks libs/zeltra-interactions.lua (timing, auto-defer, no double responses) with a fake Interaction.
local timer = require("timer")
local I = require("../libs/zeltra-interactions")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 print("PASS  " .. name) else failed = failed + 1 print("FAIL  " .. name) end
end

local logs = {}
I.log = function(s) table.insert(logs, s) end
local function lastLog() return logs[#logs] or "" end

-- fake Interaction class mirroring discordia-interactions' first-response rules
local Fake = {}
Fake.__index = function(self, k)
	if k == "createdAt" then return rawget(self, "_created") end
	return Fake[k]
end
function Fake.__init(self, data)
	self._data = data
	self._created = data.created
	self._initialRes, self._deferred = false, false
	self.calls = {}
	self.httpDelay = data.httpDelay or 0
end
function Fake._sendMessage(self, payload, files, deferred)
	assert(not self._initialRes, "double initial response")
	if self.httpDelay > 0 then timer.sleep(self.httpDelay) end
	if self.fail then return nil, "404 Not Found : x | HTTP Error 10062 : Unknown interaction" end
	self._initialRes, self._deferred = true, deferred or false
	table.insert(self.calls, deferred and "defer" or "reply")
	return { id = "m" }
end
function Fake._sendFollowup(self, payload)
	table.insert(self.calls, "followup")
	return { id = "f" }
end
function Fake._sendUpdate(self, payload)
	assert(not self._initialRes, "double initial response")
	self._initialRes = true
	table.insert(self.calls, payload and "update" or "defer-update")
	return true
end
function Fake._sendModal(self)
	table.insert(self.calls, "modal")
	return true
end
function Fake.update(self) table.insert(self.calls, "edit") return true end
function Fake.reply(self, payload, eph)
	if self._initialRes or self._deferred then return self:_sendFollowup(payload) end
	return self:_sendMessage(payload)
end
Fake.replyDeferred = function(self) assert(not self._initialRes, "only the initial response can be deferred") return self:_sendMessage(nil, nil, true) end
I.install(Fake)
local function new(data)
	local o = setmetatable({}, Fake)
	o:__init(data)
	return o
end
local function nowS() return I.wallMs() / 1000 end

coroutine.wrap(function()
	-- quick command: no auto-defer, one timing line
	local ia = new({ name = "ping", created = nowS() - 0.1 })
	I.track(ia, "ping")
	I.AUTO_DEFER_MS = 150
	I.autoDefer(ia)
	ia:reply({ content = "pong" })
	timer.sleep(250)
	check("fast reply is not deferred", #ia.calls == 1 and ia.calls[1] == "reply" and not ia._zAutoDeferred)
	check("timing line logged", lastLog():find("[interaction] /ping reply gateway=", 1, true) ~= nil and lastLog():find(" ok", 1, true) ~= nil)
	check("gateway delay measured", tonumber(lastLog():match("gateway=(%d+)ms")) >= 90)

	-- slow command: auto-defer fires, later reply becomes the follow-up
	logs = {}
	ia = new({ name = "purge", created = nowS() })
	I.track(ia, "purge")
	I.autoDefer(ia)
	timer.sleep(250)
	check("slow command auto-deferred", ia.calls[1] == "defer" and ia._zAutoDeferred == true)
	ia:reply({ content = "done" })
	check("reply after auto-defer is a follow-up", ia.calls[2] == "followup")
	check("log marks auto-deferred", lastLog():find("(auto-deferred)", 1, true) ~= nil)
	local ok = pcall(ia.replyDeferred, ia, true)
	check("command's own replyDeferred after auto-defer is a no-op", ok and #ia.calls == 2)

	-- reply while the auto-defer is still in flight waits and does not double-respond
	ia = new({ name = "slowhttp", created = nowS(), httpDelay = 200 })
	I.track(ia, "slowhttp")
	I.AUTO_DEFER_MS = 0
	I.autoDefer(ia)
	ok = pcall(ia.reply, ia, { content = "x" })
	check("no double initial response during in-flight defer", ok and ia.calls[1] == "defer" and ia.calls[2] == "followup")
	I.AUTO_DEFER_MS = 150

	-- noAutoDefer and modal commands
	ia = new({ name = "form", created = nowS() })
	I.track(ia, "form")
	I.autoDefer(ia, { noAutoDefer = true })
	timer.sleep(250)
	check("noAutoDefer respected", #ia.calls == 0)
	ia:_sendModal({})
	check("modal still works when not deferred", ia.calls[1] == "modal")
	ia = new({ name = "form2", created = nowS() })
	I.track(ia, "form2")
	I.autoDefer(ia)
	timer.sleep(250)
	local mok = ia:_sendModal({})
	check("modal after auto-defer refused with a log", mok == false and lastLog():find("noAutoDefer", 1, true) ~= nil)

	-- deadline: an interaction that arrived late is deferred sooner
	ia = new({ name = "late", created = nowS() - 2.0 })
	I.track(ia, "late")
	local d = I.deferDelay(ia)
	check("late interaction deferred within the 3s window (" .. d .. "ms)", d <= 250)
	ia = new({ name = "verylate", created = nowS() - 5 })
	check("already-expired interaction defers immediately", I.deferDelay(ia) == 0)

	-- failures are logged
	logs = {}
	ia = new({ name = "broken", created = nowS() - 4 })
	ia.fail = true
	I.track(ia, "broken")
	ia:reply({ content = "x" })
	check("failed first response logged", lastLog():find("FAILED HTTP Error 10062", 1, true) ~= nil)

	-- components only logged when slow or failed
	logs = {}
	ia = new({ custom_id = "sec:unlock", created = nowS() })
	ia:_sendUpdate(nil)
	check("fast component not logged", #logs == 0)
	local ok2 = ia:_sendUpdate(nil)
	check("second updateDeferred is a no-op", ok2 == true and #ia.calls == 1)

	-- lag monitor detects a blocked loop
	logs = {}
	local t = I.startLagMonitor(50)
	timer.sleep(120)
	local s = os.clock()
	while os.clock() - s < 0.7 do end -- block the loop ~700ms
	timer.sleep(120)
	t:stop() t:close()
	check("blocked event loop is logged", (logs[1] or ""):find("event loop was blocked", 1, true) ~= nil)

	print(("\n%d passed, %d failed"):format(passed, failed))
	os.exit(failed > 0 and 1 or 0)
end)()
