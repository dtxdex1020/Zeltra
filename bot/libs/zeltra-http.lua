--[[
	Zeltra HTTP client patch (added by Zeltra; not part of upstream Ducky V1).

	Replaces coro-http's request() before Discordia loads, so every Discord REST call goes through it.
	It fixes the cause of the "Unknown interaction" (10062) errors seen on 2026-10-11:

	  coro-http keeps finished connections in a pool and reuses them forever. After a quiet period the
	  network path to Discord can drop an idle connection without telling us. The next request is
	  written into that dead socket and the read waits until the kernel gives up on TCP retransmits
	  (about 15 minutes). Only then does coro-http retry on a new socket, long after the 3 second
	  interaction window, so Discord answers 10062 and the user saw "The application did not respond".

	What this version does differently:
	  * a pooled connection idle for more than MAX_IDLE_MS is closed instead of reused
	  * waiting for a response has a timeout (REUSED_TIMEOUT_MS on a reused connection, TIMEOUT_MS on a
	    new one). A reused connection that times out or closes is retried once on a new connection,
	    the same retry upstream coro-http already does for an immediate close
	  * counters in M.stats for logging

	The request/response code follows luvit coro-http 3.2.4 (MIT, Tim Caswell).
	Licensed under AGPL-3.0 as part of Zeltra (a modified version of Ducky V1 by duckyerlc).
]]

local uv = require("uv")
local net = require("coro-net")
local httpCodec = require("http-codec")
local coroHttp = require("coro-http")
local unpack = unpack or table.unpack

local M = {
	MAX_IDLE_MS = 20000,
	REUSED_TIMEOUT_MS = 10000,
	TIMEOUT_MS = 30000,
	CONNECT_TIMEOUT_MS = 10000,
	stats = { fresh = 0, reused = 0, expired = 0, retried = 0, timeouts = 0 },
}

local pool = {}

local function now()
	uv.update_time()
	return uv.now()
end

local function closeConnection(c)
	if c.close then pcall(c.close) end
	if c.socket and not c.socket:is_closing() then pcall(c.socket.close, c.socket) end
end

local function newConnection(host, port, tls, connectTimeout)
	local read, write, socket, updateDecoder, _, close = assert(net.connect({
		host = host,
		port = port,
		tls = tls,
		timeout = connectTimeout or M.CONNECT_TIMEOUT_MS,
		encoder = httpCodec.encoder,
		decoder = httpCodec.decoder,
	}))
	M.stats.fresh = M.stats.fresh + 1
	return {
		socket = socket, host = host, port = port, tls = tls,
		read = read, write = write, close = close, reused = false,
		reset = function() updateDecoder(httpCodec.decoder()) end,
	}
end

--- Takes a live, recently used connection from the pool, or opens a new one.
function M.getConnection(host, port, tls, forceNew, connectTimeout)
	if not forceNew then
		local t = now()
		for i = #pool, 1, -1 do
			local c = pool[i]
			if c.host == host and c.port == port and c.tls == tls then
				table.remove(pool, i)
				if not c.socket:is_closing() and (t - c.idleSince) <= M.MAX_IDLE_MS then
					c.reused = true
					c.socket:ref()
					M.stats.reused = M.stats.reused + 1
					return c
				end
				M.stats.expired = M.stats.expired + 1
				closeConnection(c)
			end
		end
	end
	return newConnection(host, port, tls, connectTimeout)
end

local function saveConnection(c)
	if c.socket:is_closing() then return end
	c.idleSince = now()
	pool[#pool + 1] = c
	c.socket:unref()
end

--- Closes pooled connections that are too old to reuse. Called on a timer.
function M.sweep()
	local t = now()
	for i = #pool, 1, -1 do
		local c = pool[i]
		if c.socket:is_closing() or (t - c.idleSince) > M.MAX_IDLE_MS then
			table.remove(pool, i)
			closeConnection(c)
		end
	end
	return #pool
end

--- read() with a timeout. On timeout the connection is closed, which makes the pending read return nil.
local function timedRead(c, ms)
	local fired = false
	local t = uv.new_timer()
	t:start(ms, 0, function()
		fired = true
		t:close()
		closeConnection(c)
	end)
	local item = c.read()
	if not fired then
		t:stop()
		t:close()
	end
	return item, fired
end

local function request(method, url, headers, body, customOptions, isRetry)
	local options = {}
	if type(customOptions) == "number" then
		options.timeout = customOptions
	elseif type(customOptions) == "table" then
		for k, v in pairs(customOptions) do options[k] = v end
	end
	if options.followRedirects == nil then options.followRedirects = true end

	local uri = coroHttp.parseUrl(url)
	local c = M.getConnection(uri.hostname, uri.port, uri.tls, isRetry, options.timeout)

	local req = { method = method, path = uri.path }
	local contentLength, chunked, hasHost
	if headers then
		for i = 1, #headers do
			local key, value = unpack(headers[i])
			key = key:lower()
			if key == "content-length" then
				contentLength = value
			elseif key == "content-encoding" and tostring(value):lower() == "chunked" then
				chunked = true
			elseif key == "host" then
				hasHost = true
			end
			req[#req + 1] = headers[i]
		end
	end
	if not hasHost then req[#req + 1] = { "Host", uri.host } end
	if type(body) == "string" and not chunked and not contentLength then
		req[#req + 1] = { "Content-Length", #body }
	end

	-- options.timeout stays a connect timeout, as in upstream coro-http
	local limit = (c.reused and M.REUSED_TIMEOUT_MS) or M.TIMEOUT_MS
	c.write(req)
	if body then c.write(body) end
	local res, timedOut = timedRead(c, limit)
	if not res then
		closeConnection(c)
		if timedOut then M.stats.timeouts = M.stats.timeouts + 1 end
		if c.reused and not isRetry then
			M.stats.retried = M.stats.retried + 1
			return request(method, url, headers, body, customOptions, true)
		end
		error(timedOut and ("HTTP request timed out after " .. limit .. "ms") or "Connection closed")
	end

	local parts = {}
	if method == "HEAD" then
		c.reset()
	else
		while true do
			local item = timedRead(c, M.TIMEOUT_MS)
			if not item then
				res.keepAlive = false
				break
			end
			if #item == 0 then break end
			parts[#parts + 1] = item
		end
	end

	if res.keepAlive then
		saveConnection(c)
	else
		pcall(c.write)
		closeConnection(c)
	end

	if method == "GET" and (res.code == 302 or res.code == 307) and options.followRedirects then
		for i = 1, #res do
			local key, location = unpack(res[i])
			if key:lower() == "location" then
				return request(method, location, headers)
			end
		end
	end

	return res, table.concat(parts)
end

M.request = function(method, url, headers, body, customOptions)
	return request(method, url, headers, body, customOptions, false)
end

--- Swap coro-http's request for this one. Must run before Discordia is required.
function M.install()
	if coroHttp.request == M.request then return M end
	M.original = coroHttp.request
	coroHttp.request = M.request
	coroHttp.getConnection = function(host, port, tls) return M.getConnection(host, port, tls) end
	coroHttp.saveConnection = saveConnection
	local sweeper = uv.new_timer()
	sweeper:start(M.MAX_IDLE_MS, M.MAX_IDLE_MS, function() pcall(M.sweep) end)
	sweeper:unref()
	return M
end

M._pool = pool
return M
