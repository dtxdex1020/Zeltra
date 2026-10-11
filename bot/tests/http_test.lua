-- Run from bot/: ./luvit tests/http_test.lua
-- Zeltra: checks libs/zeltra-http.lua against a local test server (no Discord traffic).
local uv = require("uv")
local net = require("net")
local timer = require("timer")
local coroHttp = require("coro-http")
local H = require("../libs/zeltra-http")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 print("PASS  " .. name) else failed = failed + 1 print("FAIL  " .. name) end
end

-- test server: answers every request with keep-alive, except it ignores
--   * the 2nd request on any connection when mode == "dead-reuse" (a silently dropped connection)
--   * every request when mode == "silent"
local mode = "normal"
local connectionsSeen = 0
local server = net.createServer(function(client)
	connectionsSeen = connectionsSeen + 1
	local requests, buf = 0, ""
	client:on("data", function(chunk)
		buf = buf .. chunk
		while buf:find("\r\n\r\n", 1, true) do
			local _, e = buf:find("\r\n\r\n", 1, true)
			buf = buf:sub(e + 1)
			requests = requests + 1
			local ignore = mode == "silent" or (mode == "dead-reuse" and requests >= 2)
			if not ignore then
				client:write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nok")
			end
		end
	end)
	client:on("error", function() end)
end)
server:listen(0, "127.0.0.1")
local port = server:address().port
local url = "http://127.0.0.1:" .. port .. "/x"

local function reset(cfg)
	for k, v in pairs(cfg) do H[k] = v end
	for k in pairs(H.stats) do H.stats[k] = 0 end
	for i = #H._pool, 1, -1 do table.remove(H._pool, i) end
end

coroutine.wrap(function()
	-- 1. normal request, then reuse while fresh
	reset({ MAX_IDLE_MS = 20000, REUSED_TIMEOUT_MS = 300, TIMEOUT_MS = 2000 })
	mode = "normal"
	local res, body = H.request("GET", url)
	check("request works", res and res.code == 200 and body == "ok")
	res, body = H.request("GET", url)
	check("recent connection is reused", body == "ok" and H.stats.reused == 1 and H.stats.fresh == 1)

	-- 2. reused connection that went dead: times out fast and retries on a new connection
	reset({ MAX_IDLE_MS = 20000, REUSED_TIMEOUT_MS = 300, TIMEOUT_MS = 2000 })
	mode = "dead-reuse"
	H.request("GET", url)
	local t0 = uv.hrtime()
	res, body = H.request("GET", url)
	local ms = (uv.hrtime() - t0) / 1e6
	check("dead reused connection is retried on a new one", body == "ok" and H.stats.retried == 1 and H.stats.timeouts == 1)
	check("dead connection costs the short timeout, not minutes (" .. math.floor(ms) .. "ms)", ms < 1500)

	-- 3. idle connections are not reused
	reset({ MAX_IDLE_MS = 100, REUSED_TIMEOUT_MS = 300, TIMEOUT_MS = 2000 })
	mode = "dead-reuse"
	H.request("GET", url)
	timer.sleep(250)
	t0 = uv.hrtime()
	res, body = H.request("GET", url)
	ms = (uv.hrtime() - t0) / 1e6
	check("idle connection is closed instead of reused", body == "ok" and H.stats.expired == 1 and H.stats.reused == 0 and H.stats.fresh == 2)
	check("no timeout wait when the idle connection is skipped (" .. math.floor(ms) .. "ms)", ms < 250 and H.stats.timeouts == 0)

	-- 4. sweep closes old pooled connections
	reset({ MAX_IDLE_MS = 100 })
	mode = "normal"
	H.request("GET", url)
	check("connection pooled", #H._pool == 1)
	timer.sleep(200)
	check("sweep empties stale pool", H.sweep() == 0 and #H._pool == 0)

	-- 5. a new connection that never answers errors after TIMEOUT_MS
	reset({ MAX_IDLE_MS = 20000, REUSED_TIMEOUT_MS = 300, TIMEOUT_MS = 400 })
	mode = "silent"
	t0 = uv.hrtime()
	local ok, err = pcall(H.request, "GET", url)
	ms = (uv.hrtime() - t0) / 1e6
	check("silent server times out with an error", not ok and tostring(err):find("timed out", 1, true) ~= nil)
	check("timeout is honoured (" .. math.floor(ms) .. "ms)", ms >= 350 and ms < 1500)

	-- 6. install swaps coro-http's request (what Discordia's API captures)
	H.install()
	check("coro-http request replaced", coroHttp.request == H.request)
	mode = "normal"
	reset({ MAX_IDLE_MS = 20000, TIMEOUT_MS = 2000 })
	res, body = coroHttp.request("POST", url, { { "Content-Type", "application/json" } }, "{}")
	check("POST through the patched coro-http", body == "ok")

	server:close()
	for _, c in ipairs(H._pool) do pcall(c.close) end
	print(("\n%d passed, %d failed"):format(passed, failed))
	if failed > 0 then os.exit(1) end
	os.exit(0)
end)()
