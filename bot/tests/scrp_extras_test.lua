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
print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then process:exit(1) end
