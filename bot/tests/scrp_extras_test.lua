-- Zeltra: checks the SCRP shop items and staff application settings (libs/zeltra-shop-scrp.lua, libs/zeltra-staffapp-scrp.lua)
local S = require("../libs/zeltra-shop-scrp")
local A = require("../libs/zeltra-staffapp-scrp")
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1; print("PASS  " .. name) else failed = failed + 1; print("FAIL  " .. name) end end

local subs = S.subjects()
check("five shop items", #subs == 5)
for i, s in ipairs(subs) do
	check(s.name .. " opens in the Paid Ads & Affiliates category", s.category == S.CATEGORY)
	check(s.name .. " card says PayPal only", s.embeds.open[1].description:find("PayPal only", 1, true) ~= nil)
	check(s.name .. " has a USD price", s.description:find("^%$%d+%.%d%d USD") ~= nil)
	check(s.name .. " never mentions Robux as payment", not s.description:find("Robux"))
end
local p = S.panelPayload()
local select = p.components[1].components[5].components[1]
check("select placeholder", select.placeholder == "Choose a shop item" and select.custom_id == "subjectselect")
check("select values are indexes", select.options[1].value == "1" and select.options[5].value == "5")
local function texts(c, acc) acc = acc or {}; if type(c) == "table" then if c.type == 10 then acc[#acc+1] = c.content end; for _, v in pairs(c) do texts(v, acc) end end; return acc end
local all = table.concat(texts(p), "\n")
check("no em dashes in the shop panel", not all:find("\226\128\148"))
check("panel text under 4000", #all < 4000)

check("two application pages", #A.PAGES == 2)
for i, page in ipairs(A.PAGES) do
	check("page " .. i .. " has at most 5 questions", #page.questions <= 5)
	for _, q in ipairs(page.questions) do
		check("label fits 45 chars: " .. q.question, #q.question <= 45)
		check("placeholder fits 100 chars: " .. q.key, not q.placeholder or #q.placeholder <= 100)
	end
end
check("question copies are fresh tables", A.questions(1)[1] ~= A.PAGES[1].questions[1])
check("can apply with no history", A.canApply({}, "1", 100) == true)
local ok, why = A.canApply({ cooldowns = { ["1"] = 200 } }, "1", 100)
check("denied cooldown blocks", ok == false and why:find("<t:200:R>"))
check("cooldown over", A.canApply({ cooldowns = { ["1"] = 50 } }, "1", 100) == true)
check("pending blocks", A.canApply({ pending = { ["1"] = 90 } }, "1", 100) == false)


do
	local Shop = require("../libs/zeltra-shop-scrp")
	local sub = Shop.subjects()[1]
	check("shop ticket pings Dex", sub.mentionables[1] == "1307878235383795732")
	check("Dex can see shop tickets", sub.supportusers[1] == "1307878235383795732")
	check("card says Dex handles shop tickets and payments", sub.embeds.open[1].description:find("only person who handles shop tickets and payments", 1, true) ~= nil)
	local esc = Shop.escalation()
	check("shop escalation goes to Ownership only", #esc.tiers == 1 and esc.tiers[1].key == "ownership")
	check("shop escalation has staff role and cooldown", esc.staffrole ~= nil and esc.cooldown == 120)
end
do -- High Rank application
	local H = A.HR
	check("HR has three pages", #H.PAGES == 3)
	local n = 0
	for i, page in ipairs(H.PAGES) do
		check("HR page " .. i .. " has at most 5 questions", #page.questions <= 5)
		for _, q in ipairs(page.questions) do
			n = n + 1
			check("HR label fits 45 chars: " .. q.question, #q.question <= 45)
			check("HR placeholder fits 100 chars: " .. q.key, not q.placeholder or #q.placeholder <= 100)
			if q.style == "paragraph" and q.required then check("HR long answer has a minimum: " .. q.key, (q.min or 0) >= 30) end
			local t = q.question .. (q.placeholder or "")
			check("HR text has no em dash or Ducky: " .. q.key, not t:find("\226\128\148") and not t:lower():find("ducky"))
		end
	end
	check("HR has more questions than staff", n == 14)
	check("HR questions copy from HR pages", A.questions(1, H)[1].question == H.PAGES[1].questions[1].question)
	check("HR goes to the staff review channel", H.REVIEW_CHANNEL == A.REVIEW_CHANNEL)
	check("HR state is separate from staff", H.stateKey ~= A.STAFF.stateKey)
	local c, act = A.parseId("scrpapp_start"); check("staff start id", c == A.STAFF and act == "start")
	c, act = A.parseId("scrpapp_next"); check("staff next id", c == A.STAFF and act == "next")
	local u; c, act, u = A.parseId("scrpapp_acc_123"); check("staff accept id", c == A.STAFF and act == "acc" and u == "123")
	c, act, u = A.parseId("scrpapp_deny_123"); check("staff deny id", c == A.STAFF and act == "deny" and u == "123")
	c, act = A.parseId("scrpapp_hr_start"); check("hr start id", c == H and act == "start")
	c, act = A.parseId("scrpapp_hr_next"); check("hr next id", c == H and act == "next")
	c, act, u = A.parseId("scrpapp_hr_acc_9"); check("hr accept id", c == H and act == "acc" and u == "9")
	c, act, u = A.parseId("scrpapp_hr_deny_9"); check("hr deny id", c == H and act == "deny" and u == "9")
	check("unknown id ignored", A.parseId("scrpapp_hr_bogus") == nil and A.parseId("other") == nil)
	check("prefixes", A.prefix(H) == "scrpapp_hr_" and A.prefix(A.STAFF) == "scrpapp_")
	check("HR has no staff gate", A.HR.STAFF_ROLE == nil and A.isStaff == nil)
	check("rank question is neutral", A.HR.PAGES[1].questions[3].question == "Are you staff anywhere? What rank, how long?")
	check("HR pending blocks", A.canApply({ pending = { ["1"] = 90 } }, "1", 100, H) == false)
end
print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then process:exit(1) end
