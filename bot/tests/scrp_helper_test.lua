-- Zeltra: checks the free SCRP ticket helper matching (modules/server_management/scrp_panels.lua)
local f = assert(loadfile("modules/server_management/scrp_panels.lua"))
local P = f()
local H = P._helper
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1; print("PASS  " .. name) else failed = failed + 1; print("FAIL  " .. name) end end
for _, g in ipairs({ "Hi", "Hello??", "yo", "hey", "heyyy", "anyone there", "??", "is anyone there?", "hello anyone here", "helo" }) do
	check("greeting: " .. g, H.isGreeting(g) and #H.matchTopics(g) == 0)
end
local cases = {
	{ "how do i join the server", "join" }, { "whats the join code", "join" }, { "i wanna aply for staff", "staff" },
	{ "how do i become a moderator", "staff" }, { "i cant verfy my account", "verify" }, { "i want to reprot someone for rdm", "report" },
	{ "i paid with paypal and need a refund", "pay" }, { "how do i join the sherif department", "dept" }, { "i want to appeal my ban", "appeal" },
	{ "can i get unbaned", "appeal" }, { "when is the next sesion", "session" }, { "can i do a ride along", "ride" },
	{ "i am missing my role", "roles" }, { "my roblox username is wrong", "roblox" },
}
for _, c in ipairs(cases) do
	local m = H.matchTopics(c[1])
	check("topic " .. c[2] .. ": " .. c[1], m[1] and m[1][1] == c[2])
end
check("nonsense goes to staff", #H.matchTopics("my game crashes when i open the map") == 0 and not H.isGreeting("my game crashes when i open the map"))
local src = io.open("modules/server_management/scrp_panels.lua"):read("*a")
check("no em dashes", not src:find("\226\128\148"))
check("no Ducky", not src:lower():find("ducky"))
print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
