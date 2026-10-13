-- Zeltra: runs the SCRP staff and High Rank application flow (modules/server_management/scrp.lua) against stubs
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1; print("PASS  " .. name) else failed = failed + 1; print("FAIL  " .. name) end end

_G.scrpStaffApp = require("../libs/zeltra-staffapp-scrp")
local A = _G.scrpStaffApp
local db = {}
_G.sqldb = { get = function(_, g) return db[g] end, set = function(_, g, t) db[g] = db[g] or {}; for k, v in pairs(t) do db[g][k] = v end end }
local sent, dms, posts, prompts = {}, {}, {}, {}
_G.dmStyle = {
	build = function(o) return { flags = 32768, components = { { type = 17, opts = o } }, opts = o } end,
	buildEmbed = function(o) return { opts = o } end,
	buttons = function(b) return b end,
	time = function(t) return "<t:" .. tostring(t) .. ">" end,
	serverName = function() return "South Carolina Roleplay" end,
	send = function(u, o) dms[#dms + 1] = o end,
	post = function(ch, o) posts[#posts + 1] = o end,
}
local queue = {}
_G.prompt = function(ia, title, qs, cb) prompts[#prompts + 1] = { title = title, qs = qs }; queue[#queue + 1] = { ia = ia, qs = qs, cb = cb } end
local function answerPrompt(fill)
	local p = table.remove(queue, 1); local r = {}
	for _, q in ipairs(p.qs) do r[q.question] = fill(q) end
	local mia = { replies = {} }
	function mia:reply(x) self.replies[#self.replies + 1] = x end
	function mia:replyDeferred() self.deferred = true end
	function mia:updateDeferred() end
	function mia:fail(m) self.failed = m end
	p.cb(mia, r); return mia
end
local roleObj = function(pos) return { position = pos } end
local positions = { [A.REVIEWER_ROLE] = 113, [A.HR.REVIEWER_ROLE] = 122 }
local channel = { id = "rev", send = function(self, payload) sent[#sent + 1] = payload; return { id = "m" .. #sent } end }
local addRoles = {}
local function member(id, roleIds, top)
	local set = {}; for _, r in ipairs(roleIds) do set[r] = { id = r } end
	return { id = id, name = "M" .. id, mentionString = "<@" .. id .. ">", highestRole = { position = top or 0 },
		hasPermission = function() return false end,
		addRole = function(_, r) addRoles[#addRoles + 1] = r end,
		roles = { get = function(_, r) return set[r] end, iter = function() local k, v; return function() k, v = next(set, k); return v end end } }
end
local members = {}
local guild = { id = A.GUILD_ID, getChannel = function() return channel end, getRole = function(_, r) return roleObj(positions[r] or 0) end, getMember = function(_, id) return members[id] end }
for _, m in pairs(members) do m.guild = guild end
local handlers = {}
_G.Client = { on = function(_, ev, fn) handlers[ev] = fn; return fn end, removeListener = function() end,
	getUser = function(_, id) return { id = id, username = "u" .. id } end, _api = { editMessage = function() end } }
local function ia(customId, m)
	m.guild = guild
	local x = { guild = guild, member = m, user = { id = m.id, username = "u" .. m.id }, channel = channel, message = { id = "m1" }, data = { custom_id = customId } }
	function x:fail(msg) self.failed = msg end
	function x:updateDeferred() end
	return x
end
local scrp = dofile("modules/server_management/scrp.lua")
scrp.Start()
local fire = function(x) handlers.interactionCreate(x) end
local fill = function(q) return string.rep("a", math.max(q.min or 1, 5)) end

-- HR: non staff is turned away politely
members["5"] = member("5", {}, 0)
local x = ia("scrpapp_hr_start", members["5"]); fire(x)
check("community member can open HR", x.failed == nil and #queue == 1 and prompts[#prompts].title == "High Rank Application (1 of 3)")
queue = {}

-- HR: staff member goes through both parts
members["6"] = member("6", {}, 100)
x = ia("scrpapp_hr_start", members["6"]); fire(x)
check("staff opens HR part 1", #queue == 1 and prompts[#prompts].title == "High Rank Application (1 of 3)")
local m1 = answerPrompt(fill)
check("HR part 1 shows continue button with HR id", m1.replies[1].opts.buttons[1].custom_id == "scrpapp_hr_next")
fire(ia("scrpapp_hr_next", members["6"]))
check("HR part 2 opens", prompts[#prompts].title == "High Rank Application (2 of 3)")
local mp2 = answerPrompt(fill)
check("HR part 2 saved, continue to part 3", mp2.replies[1].opts.buttons[1].label == "Continue to part 3" and #sent == 0)
fire(ia("scrpapp_hr_next", members["6"]))
check("HR part 3 opens", prompts[#prompts].title == "High Rank Application (3 of 3)")
local m2 = answerPrompt(fill)
local card = sent[#sent]
check("HR card sent to the review channel and deferred first", card ~= nil and m2.deferred)
check("HR card labeled HR", card.opts.title:find("^HR") ~= nil)
check("HR card pings Senior High Rank", card.allowed_mentions.roles[1] == A.HR.REVIEW_PING)
check("HR card has HR review buttons", card.opts.buttons[1].custom_id == "scrpapp_hr_acc_6" and card.opts.buttons[2].custom_id == "scrpapp_hr_deny_6")
check("HR card lists all 14 answers", #card.opts.sections == 14)
check("HR transcript file", card.opts.file == "hr-application-6.txt")
check("HR pending saved separately", db[A.GUILD_ID].scrphrapps.pending["6"] ~= nil and db[A.GUILD_ID].scrpapps == nil)

-- High Rank can't review HR apps, Senior High Rank can
members["7"] = member("7", {}, 113)
x = ia("scrpapp_hr_acc_6", members["7"]); fire(x)
check("High Rank cannot review HR", x.failed ~= nil)
members["8"] = member("8", {}, 122)
fire(ia("scrpapp_hr_acc_6", members["8"]))
check("HR accept DMs applicant", dms[#dms].title == "Your High Rank application was accepted")
check("HR result posted", posts[#posts].title == "HR application accepted")
check("HR accept gives no automatic role", #addRoles == 0)

-- Staff app still works and is not gated
members["9"] = member("9", {}, 0)
fire(ia("scrpapp_start", members["9"]))
check("staff part 1 opens for non staff", prompts[#prompts].title == "Staff Application (1 of 2)")
m1 = answerPrompt(fill)
check("staff continue id unchanged", m1.replies[1].opts.buttons[1].custom_id == "scrpapp_next")
fire(ia("scrpapp_next", members["9"]))
answerPrompt(fill)
card = sent[#sent]
check("staff card unchanged title and buttons", card.opts.title == "Staff application" and card.opts.buttons[1].custom_id == "scrpapp_acc_9")
check("staff card pings High Rank", card.allowed_mentions.roles[1] == A.REVIEW_PING)
fire(ia("scrpapp_deny_9", members["7"]))
answerPrompt(function() return "not enough detail" end)
check("staff deny DM", dms[#dms].title == "Your staff application was denied")
check("staff result posted", posts[#posts].title == "Application denied")
check("staff cooldown set", db[A.GUILD_ID].scrpapps.cooldowns["9"] ~= nil)

-- Send failure keeps answers for retry
channel.send = function() return nil, "boom" end
members["10"] = member("10", {}, 100)
fire(ia("scrpapp_hr_start", members["10"])); answerPrompt(fill)
fire(ia("scrpapp_hr_next", members["10"])); answerPrompt(fill)
fire(ia("scrpapp_hr_next", members["10"])); local mf = answerPrompt(fill)
check("HR send failure tells applicant to retry", mf.replies[#mf.replies].opts.title == "Application not sent")
channel.send = function(self, payload) sent[#sent + 1] = payload; return { id = "ok" } end
fire(ia("scrpapp_hr_next", members["10"])); answerPrompt(fill)
check("HR retry works", sent[#sent].opts.buttons[1].custom_id == "scrpapp_hr_acc_10")

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then process:exit(1) end
