-- CR-02 / KH-08 (the author's ask, 2026-10-19): the people next to the characters in the window's
-- header, smaller and darker; a click on that count opens the census's own page inside the Census
-- tab (CensusStats.lua): its numbers, its largest guilds and levels online, and two graphs of this
-- client's own light history (a sample every 15 minutes, 30 days kept, bounded, never sent).
-- Loaded by tests/run.lua with the harness's WithUI and LoadUI.
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]census%-stats%.lua$")) or "./"
local WithUI, LoadUI = extra.WithUI, extra.LoadUI
local L, V = ns.L, ns.Views

-- The page's words, as the game loads them (English here; Portuguese below).
assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", ns)

local function Bare(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local T0 = os.time({ year = 2026, month = 10, day = 19, hour = 15, min = 0, sec = 0 })

-- CensusStats.lua in a namespace of its own: its own saved store (rdb), clock and listeners, and
-- (o.data) a census of its own, or the harness's real one (Data.Summary over ns.rdb.guilds).
-- Anything sent fails the test: the history is this client's alone.
local function World(o)
	o = o or {}
	local w = { clock = o.clock or T0, on = {}, every = {}, sent = 0 }
	local census = { characters = 1000, total = 990, online = 120, guilds = {} }
	w.census = census
	local data = o.realData and ns.Data or setmetatable({
		Summary = function() return census end,
		Rebuilding = function() return w.rebuilding end,
		CROWN_AFTER = 200,
	}, { __index = ns.Data })
	local cns = setmetatable({
		rdb = o.rdb or {},
		Data = data,
		Now = function() return w.clock end,
		Comm = { loginAt = o.loginAt or (T0 - 100 * 86400), Send = function() w.sent = w.sent + 1 end, SendChunked = function() w.sent = w.sent + 1 end },
		On = function(name, fn) w.on[name] = w.on[name] or {}; table.insert(w.on[name], fn) end,
		Every = function(seconds, where, fn) w.every[#w.every + 1] = { seconds = seconds, where = where, fn = fn } end,
	}, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/CensusStats.lua"))("Olympus", cns)
	w.ns, w.CS = cns, cns.CensusStats
	function w.History() return cns.rdb.censusHistory end
	function w.Fire(name) for _, fn in ipairs(w.on[name] or {}) do fn() end end
	return w
end

local function Keys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end

test("census history: a sample every 15 minutes once the census is rebuilt after login, the day's highest counts kept; nothing sent", function()
	local w = World({ loginAt = T0 - 60 })
	local CS = w.CS
	eq(CS.EVERY, 15 * 60); eq(CS.DAYS, 30)
	-- Right after login, the census is still being rebuilt: no sample (it would look like growth).
	eq(CS.Sample(), false, "within Data.CROWN_AFTER of login")
	w.clock = T0 - 60 + 200
	w.rebuilding = 4
	eq(CS.Sample(), false, "the census still says it is rebuilding")
	w.rebuilding = nil
	eq(CS.Sample(), true, "the first sample")
	local h = w.History()
	eq(#h.recent, 1); eq(h.recent[1], ("%d,1000,990,120"):format(w.clock)); eq(h.t, w.clock)
	local today = os.date("%Y-%m-%d", w.clock)
	eq(h.days[today], "1000,990,120,1")
	-- Not again before the quarter-hour is over.
	w.clock = w.clock + CS.EVERY - 1
	eq(CS.Sample(), false)
	-- Then again; the day keeps its highest counts and how many samples it holds.
	w.clock = w.clock + 1
	w.census.characters, w.census.total, w.census.online = 1012, 1001, 80
	eq(CS.Sample(), true)
	eq(#w.History().recent, 2)
	eq(w.History().days[today], "1012,1001,120,2", "the highest characters and people, the most online")
	-- An empty census (nothing heard) is no sample.
	w.clock = w.clock + CS.EVERY
	w.census.characters, w.census.total, w.census.online = 0, 0, 0
	eq(CS.Sample(), false)
	eq(w.sent, 0, "nothing sent")
	-- The sampler runs on its own minute tick from login, and the store is mended at INIT.
	eq(#w.every, 0)
	w.Fire("LOGIN")
	eq(#w.every, 1); eq(w.every[1].seconds, CS.TICK)
	assert(w.on.INIT and #w.on.INIT == 1, "pruned at INIT")
end)

test("census history: bounded: the last 48 hours sample by sample, 30 days of daily lines, nothing from the future; a damaged store starts again", function()
	local w = World()
	local CS = w.CS
	-- 32 days of a sample every 15 minutes.
	local start = T0 - 32 * 86400
	for k = 0, 32 * 96 do
		w.clock = start + k * CS.EVERY
		w.census.characters = 1000 + math.floor(k / 96)
		w.census.total = w.census.characters - 10
		CS.Sample()
	end
	local h = w.History()
	assert(#h.recent <= CS.RECENT_MAX, "recent " .. #h.recent)
	eq(#h.recent, 193, "two days of quarter-hours (both ends)")
	local first = tonumber(h.recent[1]:match("^(%d+),"))
	assert(w.clock - first <= CS.RECENT_KEEP, "nothing older than 48 hours")
	local days = Keys(h.days)
	eq(#days, CS.DAYS, "30 days")
	eq(days[#days], os.date("%Y-%m-%d", w.clock), "today the last")
	eq(days[1], os.date("%Y-%m-%d", w.clock - 29 * 86400), "29 days ago the first")
	-- The clock went back an hour: what was taken "later" is dropped, and a sample is due again.
	w.clock = w.clock - 3600 - CS.FUTURE - 1
	eq(CS.Sample(), true, "a store from the future does not stop the sampler")
	for _, s in ipairs(w.History().recent) do
		assert(tonumber(s:match("^(%d+),")) <= w.clock + CS.FUTURE, "no sample from the future")
	end
	-- Damaged: another shape, junk entries, keys and text.
	local d = World({ rdb = { censusHistory = "junk" } })
	d.CS.Prune()
	eq(type(d.History()), "table"); eq(d.History().v, 1); eq(#d.History().recent, 0)
	local j = World({ rdb = { censusHistory = { v = 1, t = 0,
		recent = { "x", ("%d,5,4,3"):format(T0 - 60), ("%d,5,4,3|cffff0000"):format(T0), 42, ("%d,99999999999,1,1"):format(T0) },
		days = { [os.date("%Y-%m-%d", T0)] = "5,4,3,1", ["2026-13-99x"] = "1,1,1,1", [7] = "1,1,1,1", [os.date("%Y-%m-%d", T0 - 86400)] = "a,b" } } } })
	j.CS.Prune()
	eq(#j.History().recent, 1, "only the well formed sample"); eq(j.History().recent[1], ("%d,5,4,3"):format(T0 - 60))
	eq(table.concat(Keys(j.History().days), ","), os.date("%Y-%m-%d", T0))
end)

test("census history: the 30 days oldest first (no sample: no value), the 24 hours each its most online", function()
	local w = World()
	local CS = w.CS
	w.clock = T0 - 2 * 86400
	CS.Sample() -- two days ago
	w.clock = T0 - 3 * 3600 - 45 * 60
	w.census.online = 50
	CS.Sample()
	w.clock = w.clock + CS.EVERY
	w.census.online = 70
	w.census.characters = 1005
	CS.Sample()
	w.clock = T0
	w.census.online = 30
	CS.Sample()
	local days = CS.DaySeries()
	eq(#days, 30)
	eq(days[30].key, os.date("%Y-%m-%d", T0)); eq(days[30].ago, 0); eq(days[30].c, 1005)
	eq(days[28].c, 1000, "two days ago"); eq(days[29].c, nil, "yesterday: no sample")
	eq(days[1].key, os.date("%Y-%m-%d", T0 - 29 * 86400))
	local hours = CS.HourSeries()
	eq(#hours, 24)
	eq(hours[24].o, 30, "the last hour")
	eq(hours[21].o, 70, "three hours back: the most online of its two samples"); eq(hours[21].c, 1005)
	eq(hours[22].o, nil); eq(hours[23].o, nil)
	eq(hours[1].ago, 23)
	local first = os.date("*t", T0 - 2 * 86400)
	eq(CS.Since(), os.time({ year = first.year, month = first.month, day = first.day, hour = 0 }), "since the first day's start")
	-- Scales: online from 0 to a round number; the army from a round number under its lowest.
	local lo, hi = CS.Scale({ 30, nil, 3210 }, 3, true)
	eq(lo, 0); eq(hi, 4000)
	lo, hi = CS.Scale({ 84900, 85012 }, 2, false)
	assert(lo < 84900 and hi > 85012, lo .. " " .. hi)
	eq(lo % 10, 0); eq(hi % 10, 0)
	lo, hi = CS.Scale({ 500, 500 }, 2, false)
	assert(lo < 500 and hi > 500, "a flat series still has a scale")
	eq(CS.Scale({}, 3, true), nil)
end)

-- fn with these reports as the census, a sample history from `samples` ({ ago, c, p, o } each),
-- and the page built by CensusStats.Build with the harness's real Data.Summary.
local function Report(total, more)
	local r = { total = total, online = 10, zones = {}, t = os.time(), leader = "Lead", leaderOnline = true, officers = {}, mine = true }
	for k, v in pairs(more or {}) do r[k] = v end
	return r
end
local function WithCensus(guilds, alts, fn)
	local saved = { guilds = ns.rdb.guilds, seen = ns.rdb.seen, alts = ns.Alts }
	ns.rdb.guilds, ns.rdb.seen = guilds, {}
	ns.Alts = { Duplicates = function() return alts end }
	local ok, err = pcall(fn)
	ns.rdb.guilds, ns.rdb.seen, ns.Alts = saved.guilds, saved.seen, saved.alts
	if not ok then error(err, 0) end
end
local function Find(lines, text)
	for i, line in ipairs(lines) do if Bare(line.text) == text then return line, i end end
end

test("census page: characters, people, linked alts, online, guilds counted, the weighted average level, the largest guilds against the cap and the levels online", function()
	WithCensus({
		["Olympus"] = Report(900, { online = 200, avgLevel = 40, levels = { 10, 20, 30, 40, 50, 30, 20 } }),
		["Olympus II"] = Report(300, { online = 50, avgLevel = 60, levels = { 0, 0, 0, 0, 10, 20, 20 } }),
		["Olympus III"] = Report(100, { online = 0, avgLevel = nil, t = os.time() - ns.Data.FRESH - 60 }),
	}, 4, function()
		local w = World({ realData = true, clock = os.time() })
		local lines, title, text = w.CS.Build()
		eq(title, L.CENSUS_STATS_DETAIL_TITLE); eq(text, L.CENSUS_STATS_DETAIL)
		assert(L.CENSUS_STATS_PEOPLE:lower():find("estimated", 1, true), "the page labels people as an estimate")
		assert(text:find("characters - confirmed linked alts", 1, true), "the visible detail explains the formula")
		assert(text:find("estimate can be high", 1, true), "the visible detail explains why it is approximate")
		eq(Bare(lines[1].text), L.CENSUS_STATS_BACK, "the way back first"); assert(lines[1].onClick)
		eq(lines[2].text, L.CENSUS_STATS_TITLE); eq(lines[2].header, true)
		eq(Bare(Find(lines, L.CENSUS_STATS_CHARACTERS).right), "1,300")
		eq(Bare(Find(lines, L.CENSUS_STATS_PEOPLE).right), "1,296", "the linked alts counted once")
		eq(Bare(Find(lines, L.CENSUS_STATS_ALTS).right), "4")
		eq(Bare(Find(lines, L.CENSUS_STATS_ONLINE).right), "250", "online: the guilds reporting now")
		eq(Bare(Find(lines, L.CENSUS_STATS_GUILDS).right), "3  " .. L.CENSUS_STATS_GUILDS_LIVE:format(2))
		-- (40 x 900 + 60 x 300) / 1200 = 45; the guild without one is left out.
		eq(Bare(Find(lines, L.CENSUS_STATS_AVG).right), "45.0")
		-- The people row explains itself.
		local tip = {}
		Find(lines, L.CENSUS_STATS_PEOPLE).tooltip({ AddLine = function(_, s) tip[#tip + 1] = s end })
		eq(tip[2], L.CENSUS_STATS_PEOPLE_TIP)
		-- The largest guilds, each a meter of the game's 1,000 cap, an old report grey.
		local largest, at = Find(lines, L.CENSUS_STATS_LARGEST)
		eq(largest.header, true)
		eq(Bare(lines[at + 1].text), "Olympus"); eq(Bare(lines[at + 1].right), "900 " .. L.CENSUS_STATS_OF_CAP:format("1,000"))
		eq(lines[at + 1].meter.value, 900); eq(lines[at + 1].meter.total, ns.Codec.GUILD_CAP)
		eq(lines[at + 3].text, V.Grey("Olympus III"), "an old report: grey")
		tip = {}
		lines[at + 1].tooltip({ AddLine = function(_, s) tip[#tip + 1] = s end, AddDoubleLine = function(_, a, b) tip[#tip + 1] = a .. "=" .. b end })
		eq(tip[#tip], L.CENSUS_STATS_SHARE:format("69"), "900 of 1,300 characters")
		-- The levels online, the highest band first, from the guilds reporting now.
		local _, lv = Find(lines, L.CENSUS_STATS_LEVELS)
		assert(lv, "levels online")
		eq(Bare(lines[lv + 1].text), L.CENSUS_STATS_LEVEL_TOP:format(60)); eq(lines[lv + 1].meter.value, 40)
		eq(Bare(lines[lv + 1].right), "40 16%", "40 of 250")
		eq(Bare(lines[lv + 7].text), L.CENSUS_STATS_LEVEL_BAND:format(1, 9))
		-- No history yet: each graph says why there is none.
		local _, g = Find(lines, L.CENSUS_STATS_ARMY_GRAPH)
		eq(Bare(lines[g + 1].text), L.CENSUS_STATS_EMPTY_GRAPH); eq(lines[g + 1].graph, nil)
		eq(Find(lines, L.CENSUS_STATS_KEPT:format("x")), nil)
	end)
end)

-- Regression: the largest guilds were the first five in the default order, which puts every guild
-- reporting now ahead of the rest. A guild still counted (a report within the day) but not reporting
-- now (its reporters logged off) fell behind smaller ones and out of the five, however large it was.
test("census page: the largest guilds by their size, a large guild not reporting now still among them (grey); ties: the exact <OLYMPUS>, the average level, the name", function()
	local old = os.time() - ns.Data.FRESH - 10 * 60
	WithCensus({
		["Olympus"] = Report(300, { online = 30 }),
		["Olympus II"] = Report(200, { online = 20 }),
		["Olympus III"] = Report(150, { online = 15 }),
		["Olympus IV"] = Report(120, { online = 12 }),
		["Olympus V"] = Report(110, { online = 11, avgLevel = 30 }),
		["Olympus VI"] = Report(950, { online = 0, t = old }),
		["Olympus VII"] = Report(110, { online = 0, avgLevel = 50, t = old }),
	}, 0, function()
		local w = World({ realData = true, clock = os.time() })
		local lines = w.CS.Build()
		local _, at = Find(lines, L.CENSUS_STATS_LARGEST)
		local names = {}
		for i = at + 1, at + w.CS.TOP_GUILDS do names[#names + 1] = Bare(lines[i].text) end
		eq(table.concat(names, " | "), "Olympus VI | Olympus | Olympus II | Olympus III | Olympus IV")
		eq(lines[at + 1].text, V.Grey("Olympus VI"), "not reporting now: grey, still the largest")
		eq(lines[at + 1].meter.value, 950)
		eq(lines[at + 2].text, "Olympus", "reporting now: plain")
		eq(Bare(lines[at + w.CS.TOP_GUILDS + 1].text), L.CENSUS_STATS_MORE_GUILDS:format(2))
	end)
	-- A tie at the same size: the exact <OLYMPUS> first, then the higher average level, then the name,
	-- whether reporting now or not.
	WithCensus({
		["Olympus Reborn"] = Report(400, { online = 40, avgLevel = 20 }),
		["Olympus Rising"] = Report(400, { online = 0, avgLevel = 55, t = old }),
		["OLYMPUS"] = Report(400, { online = 0, avgLevel = 10, t = old }),
		["Olympus Alpha"] = Report(400, { online = 40, avgLevel = 20 }),
	}, 0, function()
		local w = World({ realData = true, clock = os.time() })
		local lines = w.CS.Build()
		local _, at = Find(lines, L.CENSUS_STATS_LARGEST)
		local names = {}
		for i = at + 1, at + 4 do names[#names + 1] = Bare(lines[i].text) end
		eq(table.concat(names, " | "), "OLYMPUS | Olympus Rising | Olympus Alpha | Olympus Reborn")
	end)
end)

test("census page: the graphs: 30 days of characters, the scale's ends written on its left, today last and brighter; 24 hours of online from 0; each slot its own tooltip", function()
	WithCensus({ ["Olympus"] = Report(900, { online = 200 }) }, 0, function()
		-- (Noon today: the samples' days and hours whatever the time the test runs.)
		local d = os.date("*t")
		local now = os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
		local w = World({ realData = true, clock = now - 2 * 86400 })
		w.CS.Sample()
		w.clock = now - 30 * 60
		w.CS.Sample()
		w.clock = now
		local lines = w.CS.Build()
		local _, g = Find(lines, L.CENSUS_STATS_ARMY_GRAPH)
		local army = lines[g + 1].graph
		assert(army, "the army's graph")
		eq(army.n, 30); eq(army.values[30], 900); eq(army.values[28], 900); eq(army.values[29], nil)
		eq(army.left, L.CENSUS_STATS_DAYS_AGO:format(29)); eq(army.right, L.CENSUS_STATS_TODAY)
		assert(army.min < 900 and army.max > 900)
		eq(army.top, ns.FormatNumber(army.max)); eq(army.bottom, ns.FormatNumber(army.min))
		local tip = {}
		local tt = { AddLine = function(_, s) tip[#tip + 1] = s end, AddDoubleLine = function(_, a, b) tip[#tip + 1] = a .. "=" .. b end }
		army.tips[30](tt)
		eq(tip[1], L.CENSUS_STATS_TODAY); eq(tip[2], L.CENSUS_STATS_CHARACTERS .. "=900"); eq(tip[3], L.CENSUS_STATS_PEOPLE .. "=900")
		tip = {}
		army.tips[29](tt)
		eq(tip[2], L.CENSUS_STATS_NO_SAMPLE)
		-- The scale's own tooltip sums the series up (the row takes no mouse).
		eq(lines[g + 1].tooltip, nil); eq(lines[g + 1].onClick, nil)
		tip = {}
		army.tip(tt)
		eq(tip[1], L.CENSUS_STATS_ARMY_GRAPH); eq(tip[2], L.CENSUS_STATS_HIGHEST .. "=" .. L.CENSUS_STATS_WHEN:format("900", L.CENSUS_STATS_TODAY))
		local _, o = Find(lines, L.CENSUS_STATS_ONLINE_GRAPH)
		local online = lines[o + 1].graph
		eq(online.n, 24); eq(online.min, 0); eq(online.values[24], 200); eq(online.right, L.CENSUS_STATS_NOW)
		assert(Find(lines, L.CENSUS_STATS_KEPT:format(os.date(L.CENSUS_STATS_DAY_FORMAT, w.CS.Since()))), "how long it is kept")
	end)
end)

test("census page: a graph row drawn with plain textures: a step line at each value over a faint fill, a dot where none, the last slot brighter, each slot's tooltip on hover, gone when the row shows text again", function()
	WithUI(function()
		local content = CreateFrame("Frame", nil, UIParent)
		content:SetWidth(346)
		content.style = "old"
		local graph = { n = 4, values = { 10, nil, 20, 30 }, min = 0, max = 40, color = { 1, 0.82, 0 },
			top = "40", bottom = "0", left = "first", right = "last",
			tips = { function(tt) tt:AddLine("slot one") end, nil, nil, function(tt) tt:AddLine("slot four") end },
			tip = function(tt) tt:AddLine("the whole series") end }
		V.Render(content, { { text = "Heading", header = true }, { graph = graph } })
		local r = content.rows[2]
		eq(r.h, V.GraphHeight(graph)); eq(V.GraphHeight(graph), V.GRAPH_H + V.GRAPH_AXIS_H + 4)
		eq(V.LinesHeight({ { graph = graph } }, false, 346), 2 + V.GraphHeight(graph) + 8, "measured as drawn")
		local g = r.graph
		assert(g and g:IsShown(), "the graph's holder")
		eq(r.left:IsShown(), false)
		eq(g.top:GetText(), "40"); eq(g.bottom:GetText(), "0"); eq(g.left:GetText(), "first"); eq(g.right:GetText(), "last")
		local plotW = 346 - V.GRAPH_GUTTER - 4
		local s1, s2, s3, s4 = g.slots[1], g.slots[2], g.slots[3], g.slots[4]
		-- Slot one: its fill from the baseline up to a quarter of the plot, its line on top.
		local base = V.GRAPH_AXIS_H
		eq(s1.fill:Anchor("BOTTOMLEFT")[4], V.GRAPH_GUTTER); eq(s1.fill:Anchor("BOTTOMLEFT")[5], base)
		eq(s1.fill.h, V.GRAPH_H / 4); eq(s1.cap.h, 2); eq(s1.cap:Anchor("BOTTOMLEFT")[5], base + V.GRAPH_H / 4 - 1)
		eq(s1.rise:IsShown(), false, "nothing before it")
		-- Slot two has no value: a dot on the baseline, no fill.
		eq(s2.fill:IsShown(), false); eq(s2.cap.w, 2); eq(s2.cap.h, 2); eq(s2.cap:Anchor("BOTTOMLEFT")[5], base)
		eq(s3.rise:IsShown(), false, "no step from a slot with no value")
		-- Slot four: a step up from slot three.
		eq(s4.rise:IsShown(), true); eq(s4.rise.w, 2)
		eq(s4.rise:Anchor("BOTTOMLEFT")[5], base + V.GRAPH_H / 2 - 1); eq(s4.rise.h, V.GRAPH_H / 4 + 2)
		-- Across the plot, slot by slot, nothing past its end.
		local right = s4.hit:Anchor("BOTTOMLEFT")[4] + s4.hit.w
		assert(math.abs(right - (V.GRAPH_GUTTER + plotW)) <= 1, "the last slot ends with the plot: " .. right)
		-- The colours: the last slot brighter than the others, the empty slot's dot grey.
		for _, s in ipairs({ s1, s2, s4 }) do
			for _, t in ipairs({ s.fill, s.cap }) do t.SetVertexColor = function(self, ...) self.vc = { ... } end end
		end
		V.Render(content, { { text = "Heading", header = true }, { graph = graph } })
		assert(s4.cap.vc[4] > s1.cap.vc[4] and s4.fill.vc[4] > s1.fill.vc[4], "the last slot brighter")
		eq(s1.cap.vc[1], 1); eq(s2.cap.vc[1], 0.62, "a grey dot")
		-- A slot's own tooltip; a slot without one takes no mouse.
		GameTooltip.AddDoubleLine = function(self, a, b) self.lines[#self.lines + 1] = a .. "=" .. b end
		s4.hit:Fire("OnEnter")
		eq(GameTooltip.owner, s4.hit); eq(GameTooltip.lines[1], "slot four")
		s2.hit:Fire("OnEnter")
		eq(GameTooltip.owner, s4.hit, "no tooltip for a slot without one")
		-- The scale on the left: the whole series; the row itself takes no mouse.
		eq(g.scale.w, V.GRAPH_GUTTER - 2); eq(g.scale.h, V.GRAPH_H)
		g.scale:Fire("OnEnter")
		eq(GameTooltip.owner, g.scale); eq(GameTooltip.lines[1], "the whole series")
		-- Fewer slots: the rest hide; the same row as text: the graph goes.
		V.Render(content, { { text = "Heading", header = true }, { graph = { n = 2, values = { 1, 2 }, min = 0, max = 2 } } })
		eq(s3.hit:IsShown(), false); eq(s4.cap:IsShown(), false)
		V.Render(content, { { text = "Heading", header = true }, { text = "a line again" } })
		eq(r.graph:IsShown(), false); eq(r.left:IsShown(), true); eq(r.h, 16)
	end)
end)

-- The window opened on the Census with these reports, this module as the game has it (ns.CensusStats).
local function OpenWindow(fn)
	WithUI(function()
		WithCensus({
			["Olympus"] = Report(900, { online = 200, avgLevel = 40 }),
			["Olympus II"] = Report(300, { online = 50 }),
		}, 4, function()
			local w = World({ realData = true, clock = os.time() })
			local saved = ns.CensusStats
			ns.CensusStats = w.CS
			local ok, err = pcall(function()
				local UI = LoadUI()
				UI.Toggle()
				fn(OlympusFrame, UI, w)
			end)
			ns.CensusStats = saved
			if not ok then error(err, 0) end
		end)
	end)
end

test("census header: the characters, and next to them, smaller and darker, the people; lit under the mouse; the same in the copy for Discord and on the minimap button", function()
	OpenWindow(function(main, UI)
		eq(main.tab, "census")
		eq(main.total:GetText(), L.ARMY_TOTAL:format("1,200"), "the characters")
		eq(main.people:GetText(), L.ARMY_PEOPLE:format("1,196"), "the people: the 4 linked alts once")
		eq(main.people:IsShown(), true)
		eq(main.people.font, "GameFontNormalSmall", "smaller than the characters'"); eq(main.total.font, "GameFontNormalLarge")
		eq(table.concat(main.people.textColor, ","), table.concat(UI.PEOPLE_COLOR, ","), "darker")
		assert(UI.PEOPLE_COLOR[1] < 1 and UI.PEOPLE_COLOR[2] < 0.82, "darker than the gold of the characters")
		-- Right after the characters' words, on their line, inside the window.
		local a = main.people:Anchor("BOTTOMLEFT")
		eq(a[2], main.total); eq(a[4], main.total:GetUnboundedStringWidth() + UI.PEOPLE_GAP)
		assert(main.headerX + a[4] + main.people:GetUnboundedStringWidth() <= main:GetWidth() - 26, "inside the header")
		-- The hover lights it and says a click opens the page.
		main.headerHover:Fire("OnEnter")
		eq(table.concat(main.people.textColor, ","), table.concat(UI.PEOPLE_LIT, ","))
		eq(GameTooltip.lines[#GameTooltip.lines], L.HEADER_TIP_OPEN)
		main.headerHover:Fire("OnLeave")
		eq(table.concat(main.people.textColor, ","), table.concat(UI.PEOPLE_COLOR, ","))
		-- The copy for Discord: the same two counts.
		local copy = ns.Data.DiscordText()
		assert(copy:find(L.DISCORD_HEADER:format("1,200", "250", 2) .. " · " .. L.ARMY_PEOPLE:format("1,196"), 1, true), copy)
		-- The minimap button's tooltip: the same two counts, the people in the same colour.
		eq(UI.PEOPLE_CODE, "|cffb89957")
		Minimap = CreateFrame("Frame", "Minimap", UIParent)
		Minimap:SetSize(140, 140)
		UI.UpdateMinimapButton()
		OlympusMinimapButton:Fire("OnEnter")
		eq(GameTooltip.lines[2], L.ARMY_TOTAL:format("1,200") .. "  " .. UI.PEOPLE_CODE .. L.ARMY_PEOPLE:format("1,196") .. "|r")
		Minimap = nil
		-- On the Join screen (no Olympus guild) the header is the roast's alone.
		GetGuildInfo = function() return nil end
		UI.Refresh()
		eq(main.people:IsShown(), false)
	end)
end)

test("census page: a click on the header's count opens it inside the Census tab from any tab, no column titles, its own page id; Back, the tab or another tab returns to the list; a drag opens nothing", function()
	OpenWindow(function(main, UI, w)
		local CS = w.CS
		eq(main.colHeader:IsShown(), true)
		UI.SelectTab("realm")
		-- A drag of the window from the count opens nothing.
		local hover = main.headerHover
		hover:Fire("OnMouseDown", "LeftButton"); hover:Fire("OnDragStart"); hover:Fire("OnDragStop"); hover:Fire("OnMouseUp", "LeftButton")
		eq(main.tab, "realm"); eq(CS.Shown(), false)
		-- A right click neither.
		hover:Fire("OnMouseDown", "RightButton"); hover:Fire("OnMouseUp", "RightButton")
		eq(CS.Shown(), false)
		-- A click: the Census tab, its own page.
		hover:Fire("OnMouseDown", "LeftButton"); hover:Fire("OnMouseUp", "LeftButton")
		eq(main.tab, "census"); eq(CS.Shown(), true)
		eq(main.colHeader:IsShown(), false, "no column titles over the page")
		eq(UI.PageId(), "census/stats")
		local rows = main.views.census.rows
		eq(Bare(rows[1].left:GetText()), L.CENSUS_STATS_BACK)
		eq(rows[2].left:GetText(), L.CENSUS_STATS_TITLE)
		eq(main.detailTitle:GetText(), L.CENSUS_STATS_DETAIL_TITLE)
		eq(main.people:IsShown(), true, "the count stays in the header")
		-- Back: the list again, its column titles too.
		rows[1]:Click()
		eq(CS.Shown(), false); eq(main.colHeader:IsShown(), true); eq(UI.PageId(), "census/")
		assert(main.views.census.rows[1].line.input, "the Census's search on top again")
		-- The Census tab clicked, or another tab: the list.
		UI.OpenCensusStats()
		eq(CS.Shown(), true)
		UI.SelectTab("census")
		eq(CS.Shown(), false); eq(main.colHeader:IsShown(), true)
		UI.OpenCensusStats()
		UI.SelectTab("realm")
		eq(CS.Shown(), false)
		-- Never from a person page or the Join screen.
		GetGuildInfo = function() return nil end
		UI.Refresh()
		eq(UI.OpenCensusStats(), false); eq(CS.Shown(), false)
	end)
end)

test("census page: a client updated without a restart (no CensusStats.lua yet) keeps the Census list, says to restart on a click, and offers no click in the tooltip", function()
	WithUI(function()
		WithCensus({ ["Olympus"] = Report(900) }, 0, function()
			local saved = ns.CensusStats
			ns.CensusStats = nil
			local printed = {}
			local savedPrint = ns.Print
			ns.Print = function(s) printed[#printed + 1] = s end
			local ok, err = pcall(function()
				local UI = LoadUI()
				UI.Toggle()
				local main = OlympusFrame
				eq(main.people:GetText(), L.ARMY_PEOPLE:format("900"))
				main.headerHover:Fire("OnEnter")
				for _, line in ipairs(GameTooltip.lines) do assert(line ~= L.HEADER_TIP_OPEN, "no click offered") end
				main.headerHover:Fire("OnMouseDown", "LeftButton"); main.headerHover:Fire("OnMouseUp", "LeftButton")
				eq(printed[#printed], L.RESTART_NEEDED)
				eq(main.colHeader:IsShown(), true); eq(UI.PageId(), "census/")
			end)
			ns.CensusStats, ns.Print = saved, savedPrint
			if not ok then error(err, 0) end
		end)
	end)
end)

---------------------------------------------------------------------------
-- (The author, 2026-10-20) The people, estimated: CensusStats.PeopleEstimate, and where it shows. A
-- member's client keeps the plain count in the words above ("about 1,196 people"); a moderation
-- team client (the King's is one) with SAMPLE_MIN validated accounts shows the BattleTag estimate,
-- marked "~", and the staff's figures off the King's stream.
---------------------------------------------------------------------------

-- A census of `characters` characters and `people` people, over a guild counted and one that is
-- out of every total.
local function Census(characters, people)
	return { characters = characters, total = people, online = 0,
		guilds = { { name = "Olympus", counted = true }, { name = "Olympus Gone", counted = false } } }
end

-- World with the samples this client holds, as the modules count them: o.team ({ characters,
-- accounts }: a moderation team client's validated sample, Accord.Sample), o.alts ({ characters,
-- people }: the players who linked alts, Alts.Sample; false: an Alts without Sample). The guilds
-- each sample was asked about: w.asked.
local function Sampled(o)
	local w = World()
	w.asked = {}
	w.ns.Accord = { TeamShown = function() return o.team ~= nil end, Stream = function() return false end,
		Sample = function(counted) w.asked.team = counted return o.team.characters, o.team.accounts end }
	local alts = o.alts or { characters = 0, people = 0 }
	w.ns.Alts = o.alts == false and {} or { Sample = function(counted) w.asked.alts = counted return alts.characters, alts.people end }
	return w
end

test("census people estimate: on a moderation team client, the validated sample: its accounts, then the characters not yet validated at its characters per account, to three significant figures; only the guilds counted asked", function()
	local w = Sampled({ team = { characters = 960, accounts = 800 }, alts = { characters = 250, people = 100 } })
	local e = w.CS.PeopleEstimate(Census(10000, 9850))
	eq(e.approx, true); eq(e.sample.kind, "battletag")
	eq(e.sample.size, 800); eq(e.sample.characters, 960); eq(e.rate, 1.2)
	-- 800 + 9,040 / 1.2 = 8,333.3: 8,330.
	eq(e.estimate, 8330); eq(e.shown, 8330); eq(e.people, 9850, "the plain count kept beside it")
	eq(e.staff, true); eq(e.validated, 800); eq(e.validatedCharacters, 960); eq(e.unvalidated, 9040)
	eq(w.asked.team.olympus, true); eq(w.asked.team["olympus gone"], nil, "a guild out of the total is not in the sample")
	eq(w.CS.PeopleText(Census(10000, 9850)), L.ARMY_PEOPLE_APPROX:format("8,330"))
	eq(w.CS.StaffLine(e), L.PEOPLE_STAFF_TAGS:format("800", "1.20", "9,040"))
	local notes = w.CS.PeopleNotes(Census(10000, 9850))
	eq(notes[1], L.PEOPLE_ESTIMATE_TIP, "what ~ means"); eq(notes[2], L.PEOPLE_STAFF_TAGS:format("800", "1.20", "9,040")); eq(#notes, 2)
	eq(w.CS.DetailText(e), L.CENSUS_STATS_DETAIL_TAGS)
end)

test("census people estimate: a member's client, or a team client under SAMPLE_MIN validated accounts, keeps the plain count in the members' words, never an alt-link rate; the staff told why; an empty census: nothing", function()
	local w = Sampled({ alts = { characters = 250, people = 100 } })
	local e = w.CS.PeopleEstimate(Census(10000, 9850))
	eq(e.approx, false); eq(e.shown, 9850, "the count, not 10,000 / 2.5"); eq(e.estimate, nil)
	eq(e.rate, nil, "no rate"); eq(e.sample, nil, "no sample")
	eq(e.staff, nil, "no staff figures off the team"); eq(e.validated, nil); eq(e.unvalidated, nil)
	eq(w.asked.alts, nil, "the alt links are not even asked on a member's client")
	eq(w.CS.StaffLine(e), nil)
	eq(w.CS.PeopleText(Census(10000, 9850)), L.ARMY_PEOPLE:format("9,850"), "the members' words, as before")
	eq(#w.CS.PeopleNotes(Census(10000, 9850)), 0, "nothing to say about a ~ that is not there")
	eq(w.CS.DetailText(e), L.CENSUS_STATS_DETAIL, "the members' formula")
	-- No Alts.Sample (a client updated without a restart): the same.
	e = Sampled({ alts = false }).CS.PeopleEstimate(Census(10000, 9850))
	eq(e.approx, false); eq(e.shown, 9850)
	-- A team client whose validated sample is too small: the count as members see it; its staff
	-- figures stay, and say the estimate needs more validated accounts.
	w = Sampled({ team = { characters = 6, accounts = 5 }, alts = { characters = 250, people = 100 } })
	e = w.CS.PeopleEstimate(Census(10000, 9850))
	eq(e.approx, false); eq(e.shown, 9850); eq(e.rate, nil); eq(e.sample, nil)
	eq(e.staff, true); eq(e.validated, 5); eq(e.unvalidated, 9994)
	eq(w.CS.PeopleText(Census(10000, 9850)), L.ARMY_PEOPLE:format("9,850"))
	eq(w.CS.StaffLine(e), L.PEOPLE_STAFF_NONE:format("5", "9,994", tostring(w.CS.SAMPLE_MIN)))
	eq(w.CS.PeopleNotes(Census(10000, 9850))[1], L.PEOPLE_STAFF_NONE:format("5", "9,994", tostring(w.CS.SAMPLE_MIN)))
	-- An empty census, even on a team client with a big sample.
	e = Sampled({ team = { characters = 960, accounts = 800 } }).CS.PeopleEstimate(Census(0, 0))
	eq(e.approx, false); eq(e.shown, 0)
end)

-- The review's census, and the regression the members-plain decision fixed: from the alt-link rate a
-- member saw ~480 where a team client saw ~960 for the same census.
test("census people estimate: the same census, a member's plain count and never the alt-link rate's half; a team client with SAMPLE_MIN validated accounts takes the BattleTag rate, one fewer the plain count", function()
	-- 1,200 characters, 1,196 people as counted, 100 players linked 250 characters.
	local member = Sampled({ alts = { characters = 250, people = 100 } })
	local e = member.CS.PeopleEstimate(Census(1200, 1196))
	eq(e.shown, 1196); eq(e.approx, false); eq(member.CS.PeopleText(Census(1200, 1196)), L.ARMY_PEOPLE:format("1,196"))
	assert(e.shown ~= 480, "the alt-link rate's 1,200 / 2.5")
	-- A team client with 24 validated accounts of 30 characters: 24 + 1,170 / 1.25 = 960, the alt
	-- links beside it changing nothing.
	local team = Sampled({ team = { characters = 30, accounts = 24 }, alts = { characters = 250, people = 100 } })
	e = team.CS.PeopleEstimate(Census(1200, 1196))
	eq(e.shown, 960); eq(e.approx, true); eq(e.rate, 1.25); eq(e.sample.kind, "battletag"); eq(e.sample.size, 24)
	eq(team.CS.PeopleText(Census(1200, 1196)), L.ARMY_PEOPLE_APPROX:format("960"))
	-- One validated account fewer than SAMPLE_MIN: the count as members see it.
	team = Sampled({ team = { characters = 30, accounts = team.CS.SAMPLE_MIN - 1 }, alts = { characters = 250, people = 100 } })
	e = team.CS.PeopleEstimate(Census(1200, 1196))
	eq(e.shown, 1196); eq(e.approx, false); eq(e.rate, nil)
	team = Sampled({ team = { characters = 30, accounts = team.CS.SAMPLE_MIN } })
	eq(team.CS.PeopleEstimate(Census(1200, 1196)).approx, true, "SAMPLE_MIN itself is enough")
end)

test("census people estimate: three significant figures; never more than the plain count (nor the characters), never fewer than the players the samples tell apart", function()
	local CS = World().CS
	for _, c in ipairs({ { 8333.3, 8330 }, { 80544, 80500 }, { 123456, 123000 }, { 999.6, 1000 }, { 99950, 100000 }, { 47.4, 47 }, { 0, 0 } }) do
		eq((CS.Round3(c[1])), c[2], tostring(c[1]))
	end
	-- Every validated account one character: the rate 1 would make every character a player; the plain count is the most.
	local w = Sampled({ team = { characters = 100, accounts = 100 } })
	eq(w.CS.PeopleEstimate(Census(10000, 9850)).estimate, 9850)
	-- Rounded above it (9,849 to 9,850): down to the step under it.
	eq(w.CS.PeopleEstimate(Census(10000, 9849)).estimate, 9840)
	-- A census whose people say more than its characters: the characters are the most.
	eq(w.CS.PeopleEstimate(Census(1000, 1200)).estimate, 1000)
	-- The team's rate (10 characters per account) gives 20 + 800 / 10 = 100, but 300 players linked
	-- alts here: at least 300.
	w = Sampled({ team = { characters = 200, accounts = 20 }, alts = { characters = 600, people = 300 } })
	local e = w.CS.PeopleEstimate(Census(1000, 1000))
	eq(e.sample.kind, "battletag"); eq(e.estimate, 300)
	eq(w.asked.alts.olympus, true); eq(w.asked.alts["olympus gone"], nil, "the floor asks the guilds counted alone")
	-- A sample bigger than the census (rows of guilds since grown smaller) never counts past it.
	w = Sampled({ team = { characters = 5000, accounts = 4000 } })
	e = w.CS.PeopleEstimate(Census(1000, 1000))
	eq(e.validatedCharacters, 1000); eq(e.unvalidated, 0); assert(e.estimate <= 1000 and e.estimate >= e.validated, e.estimate)
end)

test("census people estimate: Alts.Sample counts the players whose confirmed links have a character in the guilds counted, and those characters; a link one side claims counts nothing", function()
	local A = ns.Alts -- (the real Alts.lua: the harness loads it before these files)
	local saved = { claims = ns.rdb.altClaims, alts = ns.db.alts }
	local ok, err = pcall(function()
		ns.db.alts, ns.rdb.altClaims = nil, nil
		A.Reset()
		local function AL(sender, role, guild, names) A.Handle("CHANNEL", sender, ("AL~1~%s~%s~%s"):format(role, guild, names)) end
		AL("Main One-Realm", "M", "Olympus", "Alt One,Alt Two")
		AL("Alt One-Realm", "A", "Olympus", "Main One")
		AL("Alt Two-Realm", "A", "Olympus Far", "Main One")
		AL("Main Two-Realm", "M", "Olympus Far", "Alt Three")
		AL("Alt Three-Realm", "A", "Olympus", "Main Two")
		AL("Main Three-Realm", "M", "Olympus", "Alt Four") -- (Alt Four never says so)
		local c, p = A.Sample({ olympus = true })
		eq(c, 3, "Main One, Alt One and Alt Three"); eq(p, 2)
		c, p = A.Sample({ olympus = true, ["olympus far"] = true })
		eq(c, 5); eq(p, 2)
		c, p = A.Sample({})
		eq(c, 0); eq(p, 0)
	end)
	ns.db.alts, ns.rdb.altClaims = saved.alts, saved.claims
	A.Reset()
	if not ok then error(err, 0) end
end)

-- fn with the harness's real census over these reports (WithCensus, o.dups linked alts), the
-- players who linked alts as o.alts says ({ characters, people }, Alts.Sample), and the real
-- Accord.lua's BattleTag store holding o.rows, this client on the moderation team while o.team
-- (Accord.TeamShown) and on the King's stream while o.stream (Accord.Stream), as they are when asked.
local function WithSamples(guilds, o, fn)
	local A = ns.Accord
	local saved = { tags = ns.rdb.battletags, team = A.TeamShown, stream = A.Stream, sample = ns.Alts.Sample }
	ns.rdb.battletags = o.rows and { v = 1, rows = o.rows } or nil
	A.TeamShown = function() return o.team == true end
	A.Stream = function() return o.stream == true end
	local ok, err = pcall(WithCensus, guilds, o.dups or 0, function()
		ns.Alts.Sample = function()
			local a = o.alts or { characters = 0, people = 0 }
			return a.characters, a.people
		end
		fn()
	end)
	ns.rdb.battletags, A.TeamShown, A.Stream, ns.Alts.Sample = saved.tags, saved.team, saved.stream, saved.sample
	if not ok then error(err, 0) end
end
-- BattleTag rows as a team client keeps them: `accounts` players in `guild`, the first `seconds`
-- of them with a second character, and two rows of a guild out of the census.
local function TagRows(accounts, seconds, guild)
	local rows = {}
	for i = 1, accounts do
		local tag = ("Hidden%d#%d"):format(i, 1000 + i)
		rows[("hidden%d-realm"):format(i)] = { name = ("Hidden%d-Realm"):format(i), tag = tag, guild = guild or "Olympus", last = os.time() }
		if i <= seconds then rows[("second%d-realm"):format(i)] = { name = ("Second%d-Realm"):format(i), tag = tag, guild = guild or "Olympus", last = os.time() } end
	end
	rows["far1-realm"] = { name = "Far1-Realm", tag = "Faraway#4242", guild = "Olympus Far", last = os.time() }
	rows["far2-realm"] = { name = "Far2-Realm", tag = "Faraway#4243", guild = "Olympus Far", last = os.time() }
	return rows
end
-- Every word a list of lines shows: text, right side and tooltip.
local function Said(lines)
	local out = {}
	local tt = { AddLine = function(_, s) out[#out + 1] = tostring(s) end, AddDoubleLine = function(_, a, b) out[#out + 1] = tostring(a) .. "=" .. tostring(b) end }
	for _, line in ipairs(lines) do
		out[#out + 1] = tostring(line.text or "") .. " | " .. tostring(line.right or "")
		if type(line.tooltip) == "function" then line.tooltip(tt) end
	end
	return table.concat(out, "\n")
end
local function Tip(line)
	local out = {}
	line.tooltip({ AddLine = function(_, s) out[#out + 1] = s end })
	return out
end
local function NoTagOrName(text, where)
	for _, bit in ipairs({ "#", "Hidden", "Second1", "Faraway", "Far1" }) do
		assert(not text:find(bit, 1, true), (where or "") .. ": " .. bit .. " in\n" .. text)
	end
end
local ESTIMATE_GUILDS = function()
	return { ["Olympus"] = Report(900, { online = 200, avgLevel = 40 }), ["Olympus II"] = Report(300, { online = 50 }) }
end

test("census page: a member's people as before; a team client's ~ estimate, its tooltip and detail saying how it is made, the staff's validated accounts, characters not yet validated and rate under it, never on the King's stream; no BattleTag or name anywhere", function()
	-- 1,200 characters, 4 linked alts: 1,196 people as counted.
	local o = { dups = 4, alts = { characters = 250, people = 100 } }
	WithSamples(ESTIMATE_GUILDS(), o, function()
		local w = World({ realData = true, clock = os.time() })
		-- An ordinary member: the plain count, the members' words, nothing of the staff's.
		local lines, _, detail = w.CS.Build()
		local row = Find(lines, L.CENSUS_STATS_PEOPLE)
		eq(Bare(row.right), "1,196")
		eq(Tip(row)[2], L.CENSUS_STATS_PEOPLE_TIP); eq(#Tip(row), 2)
		eq(Tip(Find(lines, L.CENSUS_STATS_ALTS))[2], L.CENSUS_STATS_PEOPLE_TIP)
		eq(detail, L.CENSUS_STATS_DETAIL)
		local all = Said(lines)
		assert(not all:find(L.PEOPLE_ESTIMATE_TIP, 1, true), "no ~ to explain:\n" .. all)
		eq(Find(lines, L.CENSUS_STATS_VALIDATED), nil); eq(Find(lines, L.CENSUS_STATS_UNVALIDATED), nil); eq(Find(lines, L.CENSUS_STATS_RATE), nil)
		assert(not all:find("Staff", 1, true), "nothing the staff alone see:\n" .. all)
		-- A moderation team client: 24 validated accounts of 30 characters in the guilds counted (the
		-- two rows of a guild out of the census aside): 24 + 1,170 / 1.25 = 960.
		ns.rdb.battletags = { v = 1, rows = TagRows(24, 6) }
		o.team = true
		lines, _, detail = w.CS.Build()
		row = Find(lines, L.CENSUS_STATS_PEOPLE)
		eq(Bare(row.right), L.CENSUS_STATS_APPROX:format("960"))
		eq(detail, L.CENSUS_STATS_DETAIL_TAGS, "the page's detail says how the ~ is made")
		local staff = L.PEOPLE_STAFF_TAGS:format("24", "1.25", "1,170")
		-- (The review of 2026-10-20: beside the ~, what it means takes the place of the plain count's
		-- words, and the linked alts' row has words of its own.)
		local tip = Tip(row)
		eq(tip[2], L.PEOPLE_ESTIMATE_TIP); eq(tip[3], staff); eq(#tip, 3)
		eq(Tip(Find(lines, L.CENSUS_STATS_ALTS))[2], L.CENSUS_STATS_ALTS_TIP)
		assert(not Said(lines):find(L.CENSUS_STATS_PEOPLE_TIP, 1, true), "the plain count's words, beside an estimate")
		local validated, at = Find(lines, L.CENSUS_STATS_VALIDATED)
		eq(Bare(validated.right), "24"); eq(validated.indent, 1)
		eq(Bare(lines[at + 1].text), L.CENSUS_STATS_UNVALIDATED); eq(Bare(lines[at + 1].right), "1,170")
		eq(Bare(lines[at + 2].text), L.CENSUS_STATS_RATE); eq(Bare(lines[at + 2].right), "1.25 " .. L.CENSUS_STATS_RATE_TAGS:format("24"))
		eq(Tip(validated)[2], staff)
		NoTagOrName(Said(lines), "the team's page")
		-- The King's stream: the estimate, nothing of the staff's.
		o.stream = true
		lines = w.CS.Build()
		eq(Bare(Find(lines, L.CENSUS_STATS_PEOPLE).right), L.CENSUS_STATS_APPROX:format("960"))
		eq(Find(lines, L.CENSUS_STATS_VALIDATED), nil); eq(#Tip(Find(lines, L.CENSUS_STATS_PEOPLE)), 2)
		o.stream = false
		-- Too few validated accounts: the count as members see it, in their words; the staff told why.
		ns.rdb.battletags = { v = 1, rows = TagRows(3, 0) }
		lines, _, detail = w.CS.Build()
		row = Find(lines, L.CENSUS_STATS_PEOPLE)
		eq(Bare(row.right), "1,196"); eq(detail, L.CENSUS_STATS_DETAIL)
		eq(Bare(Find(lines, L.CENSUS_STATS_RATE).right), "-")
		tip = Tip(row)
		eq(tip[2], L.CENSUS_STATS_PEOPLE_TIP); eq(tip[3], L.PEOPLE_STAFF_NONE:format("3", "1,197", tostring(w.CS.SAMPLE_MIN))); eq(#tip, 3)
		eq(Tip(Find(lines, L.CENSUS_STATS_ALTS))[2], L.CENSUS_STATS_PEOPLE_TIP)
	end)
end)

-- Every word the page's graphs show on hover: each slot's tooltip and the series' own.
local function GraphSaid(lines)
	local out = {}
	local tt = { AddLine = function(_, s) out[#out + 1] = tostring(s) end, AddDoubleLine = function(_, a, b) out[#out + 1] = tostring(a) .. "=" .. tostring(b) end }
	for _, line in ipairs(lines) do
		local g = line.graph
		if g then
			for i = 1, g.n do if g.tips[i] then g.tips[i](tt) end end
			if g.tip then g.tip(tt) end
		end
	end
	return table.concat(out, "\n")
end

-- (The review of 2026-10-20: the header and the people's row said "~" while each graph's day and
-- hour still said the plain count.)
test("census page: the graphs' days and hours give the people as the header does: a team client's at the estimate's people per character, never above the sample's count; a member's each sample's own count", function()
	local o = { dups = 4, alts = { characters = 250, people = 100 } }
	WithSamples(ESTIMATE_GUILDS(), o, function()
		local d = os.date("*t")
		local now = os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
		local w = World({ realData = true, clock = now - 30 * 60 })
		eq(w.CS.Sample(), true, "a sample: 1,200 characters, 1,196 people")
		w.clock = now
		local function Tips(lines, title, slot)
			local _, g = Find(lines, title)
			local out = {}
			lines[g + 1].graph.tips[slot]({ AddLine = function(_, s) out[#out + 1] = s end, AddDoubleLine = function(_, a, b) out[#out + 1] = a .. "=" .. b end })
			return table.concat(out, "\n")
		end
		-- An ordinary member: the sample's 1,196, today and in the last hour, as his header.
		local lines = w.CS.Build()
		assert(Tips(lines, L.CENSUS_STATS_ARMY_GRAPH, 30):find(L.CENSUS_STATS_PEOPLE .. "=1,196", 1, true))
		assert(Tips(lines, L.CENSUS_STATS_ONLINE_GRAPH, 24):find(L.CENSUS_STATS_PEOPLE .. "=1,196", 1, true))
		local all = GraphSaid(lines)
		assert(not all:find("480", 1, true), "the alt-link rate's:\n" .. all)
		assert(all:find(L.CENSUS_STATS_DETAIL, 1, true), "the members' detail under each graph:\n" .. all)
		-- A moderation team client: 960, the same in the graphs; no tag or name there either.
		ns.rdb.battletags = { v = 1, rows = TagRows(24, 6) }
		o.team = true
		lines = w.CS.Build()
		assert(Tips(lines, L.CENSUS_STATS_ARMY_GRAPH, 30):find(L.CENSUS_STATS_PEOPLE .. "=" .. L.CENSUS_STATS_APPROX:format("960"), 1, true))
		assert(Tips(lines, L.CENSUS_STATS_ONLINE_GRAPH, 24):find(L.CENSUS_STATS_PEOPLE .. "=" .. L.CENSUS_STATS_APPROX:format("960"), 1, true))
		all = Said(lines) .. "\n" .. GraphSaid(lines)
		assert(not all:find("1,196", 1, true), all)
		assert(not all:find(L.CENSUS_STATS_DETAIL, 1, true) and all:find(L.CENSUS_STATS_DETAIL_TAGS, 1, true), "the estimate's detail:\n" .. all)
		NoTagOrName(GraphSaid(lines), "the team's graphs")
	end)
	-- The arithmetic: with the BattleTag rate, the estimate's people per character, three significant
	-- figures, never above the sample's own count (rounded above it: the step under it); no estimate
	-- (or one without a rate): the plain count.
	local CS = World().CS
	local e = { approx = true, shown = 960, characters = 1200, rate = 1.25 }
	eq(CS.PeopleAt(1196, 1200, e), L.CENSUS_STATS_APPROX:format("960"))
	eq(CS.PeopleAt(1000, 1100, e), L.CENSUS_STATS_APPROX:format("880"))
	eq(CS.PeopleAt(9849, 10000, { approx = true, shown = 9850, characters = 10000, rate = 1 }), L.CENSUS_STATS_APPROX:format("9,840"))
	eq(CS.PeopleAt(50, 1000, { approx = true, shown = 900, characters = 1000, rate = 1.1 }), L.CENSUS_STATS_APPROX:format("50"), "never above its own count")
	eq(CS.PeopleAt(1196, 1200, { approx = true, shown = 1196, characters = 1200 }), "1,196", "no rate: the plain count")
	eq(CS.PeopleAt(990, 1000, { approx = false, shown = 990, characters = 1000 }), "990")
	eq(CS.PeopleAt(990, 1000, nil), "990")
end)

-- The window opened on the Census over ESTIMATE_GUILDS with these samples (WithSamples).
local function OpenSampled(o, fn)
	WithUI(function()
		WithSamples(ESTIMATE_GUILDS(), o, function()
			local w = World({ realData = true, clock = os.time() })
			local saved = ns.CensusStats
			ns.CensusStats = w.CS
			local ok, err = pcall(function()
				local UI = LoadUI()
				UI.Toggle()
				fn(OlympusFrame, UI, w)
			end)
			ns.CensusStats = saved
			if not ok then error(err, 0) end
		end)
	end)
end

test("census header: a member's people as before; a team client's ~ estimate, the hover saying what it means and that the more players use the Olympus addon and the Olympus Companion the more precise, the staff's line never on the King's stream; the same on the minimap and in the copy for Discord", function()
	local o = { dups = 4, alts = { characters = 250, people = 100 } }
	OpenSampled(o, function(main, UI)
		local function Hover()
			main.headerHover:Fire("OnEnter")
			local lines = {}
			for _, l in ipairs(GameTooltip.lines) do lines[#lines + 1] = tostring(l) end
			main.headerHover:Fire("OnLeave")
			return lines
		end
		local function Has(lines, text) for _, l in ipairs(lines) do if l == text then return true end end return false end
		local function Minimap2()
			Minimap = CreateFrame("Frame", "Minimap", UIParent)
			Minimap:SetSize(140, 140)
			UI.UpdateMinimapButton()
			OlympusMinimapButton:Fire("OnEnter")
			local line = GameTooltip.lines[2]
			Minimap = nil
			return line
		end
		-- An ordinary member: the plain count in the members' words, never an alt-link rate's 480.
		eq(main.people:GetText(), L.ARMY_PEOPLE:format("1,196"))
		local tip = Hover()
		assert(Has(tip, L.HEADER_TIP_ALTS:format("1,200", "4")), "the linked alts, as before")
		eq(Has(tip, L.PEOPLE_ESTIMATE_TIP), false, "no ~ to explain")
		for _, l in ipairs(tip) do assert(not l:find("Staff", 1, true), "no staff line: " .. l) end
		eq(Minimap2(), L.ARMY_TOTAL:format("1,200") .. "  " .. UI.PEOPLE_CODE .. L.ARMY_PEOPLE:format("1,196") .. "|r")
		local copy = ns.Data.DiscordText()
		assert(copy:find(" · " .. L.ARMY_PEOPLE:format("1,196"), 1, true), copy)
		-- A moderation team client: the validated sample, and the staff's line.
		ns.rdb.battletags = { v = 1, rows = TagRows(24, 6) }
		o.team = true
		UI.Refresh()
		eq(main.people:GetText(), L.ARMY_PEOPLE_APPROX:format("960"))
		tip = Hover()
		assert(Has(tip, L.PEOPLE_ESTIMATE_TIP))
		assert(Has(tip, L.PEOPLE_STAFF_TAGS:format("24", "1.25", "1,170")), table.concat(tip, "\n"))
		eq(Minimap2(), L.ARMY_TOTAL:format("1,200") .. "  " .. UI.PEOPLE_CODE .. L.ARMY_PEOPLE_APPROX:format("960") .. "|r")
		assert(ns.Data.DiscordText():find(" · " .. L.ARMY_PEOPLE_APPROX:format("960"), 1, true))
		local everything = table.concat(tip, "\n") .. "\n" .. main.people:GetText() .. "\n" .. Minimap2() .. "\n" .. ns.Data.DiscordText()
		NoTagOrName(everything, "the header")
		-- The King's stream: the estimate shows, the staff's line does not.
		o.stream = true
		UI.Refresh()
		eq(main.people:GetText(), L.ARMY_PEOPLE_APPROX:format("960"))
		tip = Hover()
		assert(Has(tip, L.PEOPLE_ESTIMATE_TIP))
		for _, l in ipairs(tip) do assert(not l:find("Staff", 1, true), "on the stream: " .. l) end
		-- Back to an ordinary member: the members' words again.
		o.stream, o.team = false, false
		UI.Refresh()
		eq(main.people:GetText(), L.ARMY_PEOPLE:format("1,196"))
		eq(Has(Hover(), L.PEOPLE_ESTIMATE_TIP), false)
	end)
end)

test("census people estimate: its words in English and Portuguese: the sign, how a team client's estimate is made and that the more players use the Olympus addon and the Olympus Companion, the more precise it gets; the staff's lines; the members' words unchanged", function()
	local function Words(locale)
		local savedLocale = GetLocale
		GetLocale = function() return locale end
		local w = { L = setmetatable({}, { __index = function(_, k) return k end }) }
		local ok, err = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", w) end)
		GetLocale = savedLocale
		if not ok then error(err, 0) end
		return w.L
	end
	local en, pt = Words("enUS"), Words("ptBR")
	eq(en.ARMY_PEOPLE_APPROX:format("80,500"), "~80,500 people"); eq(pt.ARMY_PEOPLE_APPROX:format("80.500"), "~80.500 pessoas")
	eq(en.CENSUS_STATS_APPROX:format("480"), "~480")
	eq(en.ARMY_PEOPLE:format("80,500"), "about 80,500 people", "the members' words, as before")
	assert(en.PEOPLE_ESTIMATE_TIP:find("estimate", 1, true) and en.PEOPLE_ESTIMATE_TIP:find("BattleTags", 1, true), en.PEOPLE_ESTIMATE_TIP)
	assert(en.PEOPLE_ESTIMATE_TIP:find("The more players use the Olympus addon and the Olympus Companion, the more precise this number gets.", 1, true))
	assert(pt.PEOPLE_ESTIMATE_TIP:find("estimativa", 1, true) and pt.PEOPLE_ESTIMATE_TIP:find("BattleTags", 1, true), pt.PEOPLE_ESTIMATE_TIP)
	assert(pt.PEOPLE_ESTIMATE_TIP:find("Quanto mais jogadores usarem o addon Olympus e o Olympus Companion, mais preciso fica este número.", 1, true))
	-- A member's number has no rate behind it, and the tip says so.
	assert(en.PEOPLE_ESTIMATE_TIP:find("Members see the characters minus the confirmed linked alts", 1, true), en.PEOPLE_ESTIMATE_TIP)
	assert(pt.PEOPLE_ESTIMATE_TIP:find("Os membros veem os personagens menos os alts ligados e confirmados", 1, true), pt.PEOPLE_ESTIMATE_TIP)
	assert(en.CENSUS_STATS_DETAIL_TAGS:find("People (~) = validated accounts", 1, true), en.CENSUS_STATS_DETAIL_TAGS)
	assert(pt.CENSUS_STATS_DETAIL_TAGS:find("Pessoas (~) = contas validadas", 1, true), pt.CENSUS_STATS_DETAIL_TAGS)
	eq(en.PEOPLE_STAFF_ALTS, "PEOPLE_STAFF_ALTS", "no staff line of an alt-link rate"); eq(pt.PEOPLE_STAFF_ALTS, "PEOPLE_STAFF_ALTS")
	eq(pt.PEOPLE_STAFF_TAGS:format("800", "1,20", "9.040"), "Staff: 800 contas validadas, 1,20 personagens por conta; 9.040 personagens ainda não validados.")
	eq(en.PEOPLE_STAFF_TAGS:format("800", "1.20", "9,040"), "Staff: 800 accounts validated, 1.20 characters per account; 9,040 characters not yet validated.")
	-- The linked alts' row beside an estimate: what a link does, not how the plain count goes.
	assert(en.CENSUS_STATS_ALTS_TIP:find("/oly alts", 1, true) and pt.CENSUS_STATS_ALTS_TIP:find("/oly alts", 1, true))
	assert(en.CENSUS_STATS_ALTS_TIP ~= pt.CENSUS_STATS_ALTS_TIP)
	-- Not a word of "not counted": the words say what is shown, never what is missing.
	for _, key in ipairs({ "ARMY_PEOPLE_APPROX", "CENSUS_STATS_APPROX", "PEOPLE_ESTIMATE_TIP" }) do
		assert(not en[key]:lower():find("not counted", 1, true) and not pt[key]:lower():find("não contad", 1, true), key)
	end
	-- The rate in each language's own decimal mark.
	local w = World()
	eq(w.CS.Rate(1.25), "1.25"); eq(w.CS.Rate(2), "2.00"); eq(w.CS.Rate(1.006), "1.01")
	local savedMark = L.DECIMAL_MARK
	L.DECIMAL_MARK = ","
	local ok, err = pcall(function() eq(w.CS.Rate(1.25), "1,25") end)
	L.DECIMAL_MARK = savedMark
	if not ok then error(err, 0) end
end)

test("census page: every line in English and Portuguese, the Portuguese its own", function()
	local pt = {}
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function()
		pt.L = setmetatable({}, { __index = function(_, k) return k end })
		assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", pt)
	end)
	GetLocale = savedLocale
	if not ok then error(err, 0) end
	local en = {}
	en.L = setmetatable({}, { __index = function(_, k) return k end })
	assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", en)
	-- (A team client's estimate adds CENSUS_STATS_APPROX, "~" and a number, the same in every
	-- language, so it joins the keys allowed to read alike.)
	local same = { CENSUS_STATS_TIME_FORMAT = true, CENSUS_STATS_WHEN = true, CENSUS_STATS_OF_CAP = true, CENSUS_STATS_APPROX = true }
	local n = 0
	for key, text in pairs(en.L) do
		n = n + 1
		assert(type(rawget(pt.L, key)) == "string", "Portuguese " .. key)
		if not same[key] then assert(pt.L[key] ~= text, "Portuguese of its own: " .. key) end
		local function Codes(s) local c = {} for spec in s:gsub("%%%%", ""):gmatch("%%%a") do c[#c + 1] = spec end return table.concat(c) end
		if key ~= "CENSUS_STATS_DAY_FORMAT" then eq(Codes(pt.L[key]), Codes(text), key .. ": the same format codes") end
	end
	assert(n >= 40, "lines: " .. n)
	eq(pt.L.ARMY_PEOPLE:format("80.544"), "aprox. 80.544 pessoas")
	eq(pt.L.CENSUS_STATS_TITLE, "O censo em números")
	assert(pt.L.CENSUS_STATS_PEOPLE:find("estimativa", 1, true))
	assert(pt.L.CENSUS_STATS_DETAIL:find("personagens contados - alts ligados", 1, true))
end)
