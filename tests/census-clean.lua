-- The sanitized census (Daniel, 2026-10-19; docs/CENSUS-STATS.md): CensusClean.lua's banned and
-- departed guilds, confidence and outlier rule, and the Bridge's "stats" section that hands them to
-- the Companion beside the census page's own figures. Loaded by tests/run.lua.
local ns, test, eq = ...
local C, D = ns.CensusClean, ns.Data

local NOW = 1800000000

local function Vote(sig, n, t) return { t = t or NOW - 60, sig = sig, ranks = { ["Lead-Realm"] = 0 }, n = n } end

-- A report as Data keeps it: `age` seconds old, these senders' votes ({ "Ann-Realm", ... }).
local function Report(total, age, senders, more)
	local r = { total = total, online = math.floor(total / 10), users = math.floor(total / 20), zones = {}, t = NOW - (age or 60),
		leader = "Lead", officers = {}, avgLevel = 40 }
	if senders then
		r.vouch = {}
		for _, who in ipairs(senders) do r.vouch[who] = Vote("Lead-Realm=0", total, NOW - (age or 60)) end
	end
	for k, v in pairs(more or {}) do r[k] = v end
	return r
end

-- fn with these reports, these banned guilds ({ [name] = true }), these linked alts per guild, and
-- a fresh store; everything as it was afterwards.
local function With(o, fn)
	local M, A = ns.Moderation, ns.Alts
	local saved = { guilds = ns.rdb.guilds, global = ns.rdb.censusGlobal, seen = ns.rdb.seen, clean = ns.rdb.censusClean,
		now = ns.Now, list = M.List, guild = M.Guild, dup = A.Duplicates, stats = ns.CensusStats }
	ns.rdb.guilds, ns.rdb.censusGlobal, ns.rdb.seen, ns.rdb.censusClean = o.guilds or {}, o.global or {}, o.seen or {}, nil
	ns.CensusStats = o.page
	local clock = { now = NOW }
	ns.Now = function() return clock.now end
	local banned = o.banned or {}
	M.Guild = function(name)
		for b in pairs(banned) do if b:lower() == tostring(name):lower() then return { kind = "g", name = b, off = true } end end
		return nil
	end
	M.List = function()
		local out = {}
		for b in pairs(banned) do out[#out + 1] = { kind = "g", name = b, off = true, at = NOW - 3600 } end
		return out
	end
	A.Duplicates = function(set)
		local n = 0
		for name, alts in pairs(o.alts or {}) do if set[name:lower()] then n = n + alts end end
		return n
	end
	local ok, err = pcall(fn, clock)
	ns.rdb.guilds, ns.rdb.censusGlobal, ns.rdb.seen, ns.rdb.censusClean = saved.guilds, saved.global, saved.seen, saved.clean
	ns.Now, M.List, M.Guild, A.Duplicates, ns.CensusStats = saved.now, saved.list, saved.guild, saved.dup, saved.stats
	if not ok then error(err, 0) end
end

local function Army()
	return {
		["Olympus Home"] = Report(100, 60, nil, { mine = true }),
		["Olympus Agreed"] = Report(200, 60, { "Ann-Realm", "Bob-Realm" }),
		["Olympus Lonely"] = Report(50, 60, { "Cid-Realm" }),
		["Olympus Split"] = Report(60, 60, { "Dee-Realm", "Eve-Realm" }, { conflict = true }),
		["Olympus Asleep"] = Report(80, 2 * 3600),
		["Olympus Gone"] = Report(30, 2 * 86400),
		["Olympus Banned"] = Report(40, 600),
	}
end

local function Find(list, name)
	for _, e in ipairs(list) do if e.name == name then return e end end
	return nil
end

test("census clean: banned guilds apart, departed guilds tombstoned, each counted guild's confidence", function()
	With({ guilds = Army(), banned = { ["Olympus Banned"] = true }, alts = { ["Olympus Home"] = 3 } }, function()
		local s = D.Summary()
		local c = C.Compute(s)
		eq(s.characters, 100 + 200 + 50 + 60 + 80, "the census counts neither the banned guild nor the departed one")
		eq(c.banned.guilds, 1); eq(c.banned.characters, 40); eq(c.banned.list[1].name, "Olympus Banned")
		eq(c.departed.guilds, 1); eq(c.departed.list[1].name, "Olympus Gone"); eq(c.departed.list[1].members, 30)
		eq(c.confidence.own, 100); eq(c.confidence.confirmed, 200); eq(c.confidence.single, 50)
		eq(c.confidence.disputed, 60); eq(c.confidence.stale, 80); eq(c.confidence.relayed, 0)
		eq(c.confirmedPeople, 300 - 3, "own and confirmed, their linked alts once")
		eq(c.addonOnline, 5 + 10 + 2 + 3, "fresh reports only")
		eq(c.excess, 0)
		eq(Find(c.guilds, "Olympus Gone"), nil); eq(Find(c.guilds, "Olympus Banned"), nil)
		eq(Find(c.guilds, "Olympus Asleep").status, "stale"); eq(Find(c.guilds, "Olympus Asleep").online, 0)
		eq(c.guilds[1].name, "Olympus Agreed", "biggest first")
	end)
end)

test("census clean: a banned guild never heard is listed with its size unknown; a relay row gives one", function()
	With({ guilds = Army(), banned = { ["Olympus Unheard"] = true, ["Olympus Relayed"] = true },
		global = { ["olympus relayed"] = { name = "Olympus Relayed", total = 70, online = 5, avg10 = 400, observed = NOW - 300 } } }, function()
		local c = C.Compute()
		eq(Find(c.banned.list, "Olympus Unheard").known, false)
		eq(Find(c.banned.list, "Olympus Relayed").members, 70)
		eq(c.banned.characters, 70)
	end)
end)

test("census clean: a lone reporter's jump past the guild's reach is held back on the statistics only, until agreement or an hour", function()
	local guilds = { ["Olympus Lonely"] = Report(100, 60, { "Cid-Realm" }) }
	With({ guilds = guilds }, function(clock)
		eq(C.Compute().excess, 0, "the first size is the last good one")
		clock.now = NOW + 120
		guilds["Olympus Lonely"] = Report(500, 0, { "Cid-Realm" })
		guilds["Olympus Lonely"].t = clock.now
		local c = C.Compute()
		eq(c.outliers.guilds, 1); eq(c.outliers.list[1].reported, 500); eq(c.outliers.list[1].kept, 100)
		eq(c.excess, 400)
		eq(Find(c.guilds, "Olympus Lonely").status, "outlier")
		eq(D.Summary().total, 500, "the header's count is untouched")
		-- Within its reach: 100 + max(25, 10) + 20 a minute for 2 minutes is 165.
		guilds["Olympus Lonely"] = Report(160, 0, { "Cid-Realm" })
		guilds["Olympus Lonely"].t = clock.now
		eq(C.Compute().excess, 0, "a size within reach is taken")
		guilds["Olympus Lonely"] = Report(600, 0, { "Cid-Realm" })
		guilds["Olympus Lonely"].t = clock.now
		eq(C.Compute().excess, 440)
		clock.now = clock.now + C.OUTLIER_HOLD
		guilds["Olympus Lonely"].t = clock.now
		for _, v in pairs(guilds["Olympus Lonely"].vouch) do v.t = clock.now end
		eq(C.Compute().excess, 0, "held for an hour, it is the guild's size")
	end)
	local agreed = { ["Olympus Agreed"] = Report(100, 60, { "Ann-Realm", "Bob-Realm" }) }
	With({ guilds = agreed }, function()
		C.Compute()
		agreed["Olympus Agreed"] = Report(700, 30, { "Ann-Realm", "Bob-Realm" })
		eq(C.Compute().excess, 0, "two reporters agreeing take a jump at once")
	end)
end)

-- (2026-10-20) What the census page's "How the census works" says of it (CensusStats.HowTopics):
-- two reporters' agreement confirms a size only while its last report is under Data.FRESH old, and
-- a size held back may be a fall as well as a rise.
test("census clean: as the census page says: agreement confirms a size only while its last report is fresh; a lone reporter's fall past the guild's reach is held as a rise is", function()
	With({ guilds = { ["Olympus Agreed"] = Report(200, D.FRESH + 60, { "Ann-Realm", "Bob-Realm" }) } }, function()
		local s = D.Summary()
		eq(s.guilds[1].counted, true, "still counted")
		eq(C.Confidence(s.guilds[1], NOW), "stale", "two reporters agreed, but its last report is older than FRESH: not confirmed")
	end)
	With({ guilds = { ["Olympus Agreed"] = Report(200, D.FRESH - 60, { "Ann-Realm", "Bob-Realm" }) } }, function()
		eq(C.Confidence(D.Summary().guilds[1], NOW), "confirmed", "under FRESH old: confirmed")
	end)
	local guilds = { ["Olympus Lonely"] = Report(500, 60, { "Cid-Realm" }) }
	With({ guilds = guilds }, function(clock)
		eq(C.Compute().excess, 0)
		clock.now = NOW + 120
		guilds["Olympus Lonely"] = Report(100, 0, { "Cid-Realm" })
		guilds["Olympus Lonely"].t = clock.now
		local c = C.Compute()
		eq(c.outliers.guilds, 1); eq(c.outliers.list[1].reported, 100); eq(c.outliers.list[1].kept, 500, "a fall past its reach, held")
	end)
end)

-- (2026-10-20) The page's "5 members or 5%" and "25 members or 10%" say "whichever is larger": the
-- code takes the larger margin (math.max), and in a large guild the share is the larger one.
test("census clean: as the census page says: the dispute's and the held size's margins are the larger of the members and the share", function()
	-- Two fresh senders of a 900-member guild, at the same moment: 5% of 900 is 45 members.
	local function Pair(lo, hi)
		local r = Report(hi, 60, { "Ann-Realm", "Bob-Realm" })
		r.vouch["Ann-Realm"].n = lo
		return r
	end
	With({ guilds = { ["Olympus Big"] = Pair(860, 900) } }, function()
		local g = ns.rdb.guilds["Olympus Big"]
		local d = D.Dispute(g, NOW)
		eq(d and d.sizes, nil, "40 apart: more than 5 members, within 5%, not disputed")
		eq(C.Confidence(D.Summary().guilds[1], NOW), "confirmed")
		ns.rdb.guilds["Olympus Big"] = Pair(850, 900)
		d = D.Dispute(ns.rdb.guilds["Olympus Big"], NOW)
		assert(d and d.disputed and d.sizes, "50 apart: past 5%, disputed")
	end)
	With({ guilds = { ["Olympus Small"] = Pair(30, 40) } }, function()
		local d = D.Dispute(ns.rdb.guilds["Olympus Small"], NOW)
		assert(d and d.disputed and d.sizes, "a small guild: 10 apart is past 5 members (5% would be 2)")
	end)
	-- A lone reporter's move at the same moment: 10% of 900 is 90 members.
	local guilds = { ["Olympus Big"] = Report(900, 0, { "Cid-Realm" }) }
	With({ guilds = guilds }, function()
		eq(C.Compute().excess, 0)
		guilds["Olympus Big"] = Report(850, 0, { "Cid-Realm" })
		eq(C.Compute().outliers.guilds, 0, "50 members: more than 25, within 10%, taken")
		guilds["Olympus Big"] = Report(750, 0, { "Cid-Realm" })
		local c = C.Compute()
		eq(c.outliers.guilds, 1, "100 members: past 10% of 850, held"); eq(c.outliers.list[1].kept, 850)
	end)
	local small = { ["Olympus Small"] = Report(100, 0, { "Cid-Realm" }) }
	With({ guilds = small }, function()
		eq(C.Compute().excess, 0)
		small["Olympus Small"] = Report(130, 0, { "Cid-Realm" })
		local c = C.Compute()
		eq(c.outliers.guilds, 1, "a small guild: 30 members is past 25 (10% would be 10), held"); eq(c.outliers.list[1].kept, 100)
	end)
end)

-- (The author, 2026-10-20: "que o processo de sanitização fosse bem estruturado, como por um
-- profissional data analyst, e explicado na página como funciona: info/records mais recentes no
-- jogo por cima de base sólida com data e hora e regras de como funciona".) The census page's first
-- topic, how the census is built, and its numbered rules S1 to S5 (CensusStats.HowTopics): the
-- behaviour behind each claim, through the addon's own functions.
local Codec = ns.Codec

-- A report as the channel carries it (Codec.EncodeReport), for a guild named "Olympus Door" unless said.
local function Wire(fields)
	if fields.guild == nil then fields.guild = "Olympus Door" end
	fields.zones = fields.zones or {}
	return Codec.EncodeReport(fields)
end

-- fn with a keeper the Church trusts as a relay (`keeper`), and this client as `me` when asked.
local function WithKeeper(keeper, me, fn)
	local savedChurch, savedMe = ns.Church, ns.me
	ns.Church = setmetatable({ IsLedgerRelay = function(name) return name == keeper end }, { __index = savedChurch })
	if me then ns.me = me end
	local ok, err = pcall(fn)
	ns.Church, ns.me = savedChurch, savedMe
	if not ok then error(err, 0) end
end

-- A keeper's snapshot made at `made`: rows { name, total, online, avg10, observed } each.
local function Snapshot(made, rows)
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = ("%s,%d,%d,%d,%d"):format(r[1], r[2], r[3], r[4], r[5]) end
	return ("CG~%d~S~%d~%s"):format(D.GLOBAL_PROTOCOL, made, table.concat(out, ";"))
end

test("census clean: as the census page says (S1): a report must parse, name an Olympus guild, carry at most the game's cap and no more players by zone, class or level than online; online above the size is cut to it; a relayed row must have no more online than members and not be dated more than 5 minutes ahead", function()
	eq(Codec.DecodeReport("R2~not a report"), nil, "does not parse")
	eq(Codec.DecodeReport(Wire({ guild = "", total = 10, online = 1 })), nil, "names no guild")
	assert(Codec.DecodeReport(Wire({ total = Codec.GUILD_CAP, online = 10 })), "the cap itself")
	eq(Codec.DecodeReport(Wire({ total = Codec.GUILD_CAP + 1, online = 10 })), nil, "past the game's cap")
	eq(Codec.DecodeReport(Wire({ total = 10, online = 5, zones = { m1453 = 6 } })), nil, "more by zone than online")
	eq(Codec.DecodeReport(Wire({ total = 10, online = 5, levels = { 3, 3 } })), nil, "more by level than online")
	eq(Codec.DecodeReport(Wire({ total = 10, online = 20 })).online, 10, "online above the size: cut to the size, not refused")
	With({}, function()
		eq(D.Receive(Codec.DecodeReport(Wire({ guild = "Horde Raiders", total = 10, online = 1 })), "Sone-Realm"), false, "not an Olympus guild")
		eq(next(ns.rdb.guilds), nil, "refused at the door: never in the census")
		eq(D.Receive(Codec.DecodeReport(Wire({ total = 10, online = 1 })), "Stwo-Realm"), true, "an Olympus guild's report enters")
		eq(ns.rdb.guilds["Olympus Door"].t, NOW, "a report heard takes this client's time: it cannot be dated ahead")
	end)
	WithKeeper("Keeper-Realm", nil, function()
		With({}, function()
			assert(D.ReceiveGlobalCensus("CHANNEL", "Keeper-Realm", Snapshot(NOW, {
				{ "Olympus Ahead", 100, 10, 400, NOW + 5 * 60 + 1 },
				{ "Olympus Edge", 100, 10, 400, NOW + 5 * 60 },
				{ "Olympus Crowd", 100, 101, 400, NOW - 60 },
				{ "Olympus Full", 100, 100, 400, NOW - 60 },
			})))
			local store = ns.rdb.censusGlobal
			eq(store["olympus ahead"], nil, "dated more than 5 minutes ahead: refused")
			eq(store["olympus edge"].total, 100, "5 minutes ahead: taken")
			eq(store["olympus crowd"], nil, "more online than members: refused")
			eq(store["olympus full"].online, 100, "as many online as members: taken")
			eq(D.ReceiveGlobalCensus("CHANNEL", "Keeper-Realm", Snapshot(NOW + 5 * 60 + 1, { { "Olympus Later", 100, 10, 400, NOW } })), false,
				"a snapshot made more than 5 minutes ahead: refused whole")
			eq(store["olympus later"], nil)
		end)
	end)
end)

test("census clean: as the census page says (how the census is built): a record keeps the time it was observed; a newer report replaces the older one unless outvoted; a relay keeps the first observation's time and never replaces a record observed after it", function()
	-- Field 25: the server's clock when the report was made, kept with the report; a relay carries it.
	eq(Codec.DecodeReport(Wire({ total = 10, online = 1, st = NOW - 30 })).st, NOW - 30)
	WithKeeper("Keeper-Realm", "Keeper-Realm", function()
		With({ guilds = { ["Olympus Dawn"] = Report(200, 60, nil, { st = NOW - 600 }) } }, function()
			local payload = assert(D.GlobalCensusPayload())
			assert(payload:find("Olympus Dawn,200,20,400," .. (NOW - 600), 1, true), "the relay carries when it was observed, not when it was heard")
		end)
	end)
	-- A newer report replaces the older one; one the guild's other reporters outvote does not.
	With({}, function(clock)
		local function Send(sender, total, officer)
			return D.Receive(Codec.DecodeReport(Wire({ guild = "Olympus Newer", total = total, online = 1, leader = "Lead",
				officers = { { name = officer } } })), sender)
		end
		eq(Send("Bann-Realm", 200, "Duke"), true); eq(Send("Bbob-Realm", 200, "Duke"), true)
		clock.now = NOW + 60
		eq(Send("Bann-Realm", 210, "Duke"), true, "newer"); eq(ns.rdb.guilds["Olympus Newer"].total, 210, "the newer report is the guild's")
		clock.now = NOW + 61
		eq(Send("Bcid-Realm", 250, "Usurper"), false, "against the other reporters' picture")
		eq(ns.rdb.guilds["Olympus Newer"].total, 210, "outvoted: the row stays"); eq(ns.rdb.guilds["Olympus Newer"].outvoted, true)
	end)
	-- A keeper's relay against the guild's own report: shown only when observed after it.
	local global = {}
	With({ guilds = { ["Olympus Dawn"] = Report(200, 60, { "Ann-Realm", "Bob-Realm" }, { st = NOW - 60 }) }, global = global }, function()
		global["olympus dawn"] = { name = "Olympus Dawn", total = 300, online = 30, avg10 = 400, observed = NOW - 120 }
		local e = D.Summary().guilds[1]
		eq(e.g.total, 200, "a relay observed before the report: the report stays"); eq(e.g.relayed, nil)
		global["olympus dawn"].observed = NOW - 30
		e = D.Summary().guilds[1]
		eq(e.g.total, 300, "observed after it: the relay"); eq(e.g.relayed, true)
	end)
	-- The relay store: an older observation never replaces a newer one, and a row is aged by when it was observed.
	WithKeeper("Keeper-Realm", nil, function()
		With({}, function()
			D.ReceiveGlobalCensus("CHANNEL", "Keeper-Realm", Snapshot(NOW, { { "Olympus Kept", 100, 10, 400, NOW - 100 } }))
			D.ReceiveGlobalCensus("CHANNEL", "Keeper-Realm", Snapshot(NOW, { { "Olympus Kept", 999, 10, 400, NOW - 200 } }))
			eq(ns.rdb.censusGlobal["olympus kept"].total, 100, "the older observation refused"); eq(ns.rdb.censusGlobal["olympus kept"].observed, NOW - 100)
			D.ReceiveGlobalCensus("CHANNEL", "Keeper-Realm", Snapshot(NOW, {
				{ "Olympus Stale", 100, 10, 400, NOW - D.FRESH - 60 }, { "Olympus Departed", 100, 10, 400, NOW - D.TOTAL_KEEP - 60 } }))
			local s = D.Summary()
			local stale, departed
			for _, e in ipairs(s.guilds) do
				if e.name == "Olympus Stale" then stale = e elseif e.name == "Olympus Departed" then departed = e end
			end
			eq(stale.fresh, false, "heard now, observed past FRESH: stale"); eq(stale.counted, true)
			eq(departed.counted, false, "observed past TOTAL_KEEP: departed, though heard now")
		end)
	end)
end)

test("census clean: as the census page says (S2, S3): forgotten KEEP after the last report; banned guilds' new reports refused, listed with their last size; guilds /who alone saw in no total, listed with the players it saw online", function()
	With({ guilds = { ["Olympus Week"] = Report(70, D.KEEP - 60), ["Olympus Past"] = Report(70, D.KEEP + 60) } }, function()
		local c = C.Compute()
		eq(c.departed.guilds, 1, "departed and listed until KEEP after its last report"); eq(c.departed.list[1].name, "Olympus Week")
	end)
	With({ guilds = Army(), banned = { ["Olympus Banned"] = true } }, function()
		eq(D.Receive(Codec.DecodeReport(Wire({ guild = "Olympus Banned", total = 400, online = 1 })), "Bdan-Realm"), false, "a banned guild's new report")
		local c = C.Compute()
		eq(Find(c.banned.list, "Olympus Banned").members, 40, "listed apart with the last size this client holds")
		eq(c.banned.characters, 40)
	end)
	With({ guilds = { ["Olympus Agreed"] = Report(200, 60, { "Ann-Realm", "Bob-Realm" }) },
		seen = { ["Olympus Seen"] = { online = 7, t = NOW - 60 }, ["Olympus Agreed"] = { online = 3, t = NOW - 60 } } }, function()
		local s = D.Summary()
		eq(s.characters, 200, "a guild /who alone saw: in no total"); eq(s.online, 20)
		eq(#s.seen, 1, "a guild this client holds a report of is not listed as seen"); eq(s.seen[1].name, "Olympus Seen")
		local c = C.Compute(s)
		eq(Find(c.guilds, "Olympus Seen"), nil)
		eq(c.seen[1].name, "Olympus Seen"); eq(c.seen[1].online, 7, "listed with the players /who saw online"); eq(c.seen[1].members, nil, "no size: /who knows none")
	end)
end)

test("census clean: as the census page says (S4, S5): a relay confirms only while under FRESH old; a stale relay's jump is held; a held size stays held while its guild goes stale, until the minutes since bring it within reach or the same size holds for an hour", function()
	local global = { ["olympus relay"] = { name = "Olympus Relay", total = 100, online = 5, avg10 = 400, observed = NOW - D.FRESH - 120 } }
	With({ global = global }, function(clock)
		eq(C.Confidence(D.Summary().guilds[1], NOW), "stale", "a relay observed past FRESH: stale, not relayed")
		eq(C.Compute().excess, 0, "the first size is the last good one")
		clock.now = NOW + 60
		global["olympus relay"] = { name = "Olympus Relay", total = 500, online = 5, avg10 = 400, observed = NOW - D.FRESH }
		local c = C.Compute()
		eq(c.outliers.guilds, 1, "a stale relay's jump is not confirmed: held"); eq(c.outliers.list[1].kept, 100)
		global["olympus relay"].observed = clock.now - 60
		eq(C.Confidence(D.Summary().guilds[1], clock.now), "relayed", "under FRESH old: confirmed")
		c = C.Compute()
		eq(c.excess, 0, "a fresh relay gives it"); eq(Find(c.guilds, "Olympus Relay").members, 500)
	end)
	-- 100 to 500 is 400 members: past 25 + 20 a minute since the last good size until its 19th minute.
	local function Jump(clock, guilds)
		eq(C.Compute().excess, 0)
		clock.now = NOW + 120
		guilds["Olympus Lonely"] = Report(500, 0, { "Cid-Realm" })
		guilds["Olympus Lonely"].t = clock.now
		eq(C.Compute().outliers.guilds, 1, "a lone reporter's jump: held")
	end
	local guilds = { ["Olympus Lonely"] = Report(100, 60, { "Cid-Realm" }) }
	With({ guilds = guilds }, function(clock)
		Jump(clock, guilds)
		clock.now = NOW + 18 * 60
		local s = D.Summary()
		eq(C.Confidence(s.guilds[1], clock.now), "stale", "its guild gone stale")
		eq(C.Compute(s).outliers.guilds, 1, "still held: 400 members past 25 + 20 a minute for 18 minutes")
		clock.now = NOW + 19 * 60
		local c = C.Compute()
		eq(c.outliers.guilds, 0, "the minutes since bring it within reach: taken"); eq(Find(c.guilds, "Olympus Lonely").members, 500)
	end)
	-- The same size for OUTLIER_HOLD, whatever the reach (no drift a minute here, so the hour alone decides).
	local savedDrift = C.JUMP_DRIFT
	C.JUMP_DRIFT = 0
	local ok, err = pcall(function()
		local held = { ["Olympus Lonely"] = Report(100, 60, { "Cid-Realm" }) }
		With({ guilds = held }, function(clock)
			Jump(clock, held)
			clock.now = NOW + 120 + C.OUTLIER_HOLD - 60
			eq(C.Compute().outliers.guilds, 1, "stale, the same size short of an hour: held")
			clock.now = NOW + 120 + C.OUTLIER_HOLD
			local c = C.Compute()
			eq(c.outliers.guilds, 0, "the same size held for an hour: taken"); eq(Find(c.guilds, "Olympus Lonely").members, 500)
		end)
	end)
	C.JUMP_DRIFT = savedDrift
	if not ok then error(err, 0) end
end)

-- (2026-10-20, the review of S1 to S5.) What the page says of the votes and the outvote, checked
-- against Data: a sender stands behind a guild for Data.VOUCH_TTL (Data.Dispute counts senders in
-- those minutes and compares only the sizes of the last FRESH), so "two or more reporters agree on
-- it" was more than the code holds; and the outvote keeps a row only while it is FRESH.
test("census clean: as the census page says (S4): two or more reporters who voted on the guild in the last VOUCH_TTL, with no dispute marked, confirm its size; one alone in those minutes is single", function()
	-- Ann reports 500 now; Bob, the same leader and officers, gave 200 between FRESH and VOUCH_TTL ago.
	local function Pair(bobAge)
		local r = Report(500, 60, { "Ann-Realm", "Bob-Realm" })
		r.vouch["Bob-Realm"].t, r.vouch["Bob-Realm"].n = NOW - bobAge, 200
		return r
	end
	assert(D.VOUCH_TTL > D.FRESH + 120, "the votes outlast the sizes compared")
	local guilds = { ["Olympus Pair"] = Report(200, 60, { "Ann-Realm", "Bob-Realm" }) }
	With({ guilds = guilds }, function()
		eq(C.Compute().excess, 0, "200, the last good size")
		guilds["Olympus Pair"] = Pair(D.FRESH + 60)
		eq(D.Dispute(guilds["Olympus Pair"], NOW), nil, "Bob's size is past FRESH: not compared, and he still stands behind the guild")
		eq(C.Confidence(D.Summary().guilds[1], NOW), "confirmed", "two reporters voted in the last VOUCH_TTL, no dispute marked")
		local c = C.Compute()
		eq(c.outliers.guilds, 0, "confirmed: the jump is taken (S5 holds only what is not)"); eq(Find(c.guilds, "Olympus Pair").members, 500)
	end)
	guilds = { ["Olympus Pair"] = Report(200, 60, { "Ann-Realm", "Bob-Realm" }) }
	With({ guilds = guilds }, function()
		C.Compute()
		guilds["Olympus Pair"] = Pair(D.VOUCH_TTL + 60)
		local d = D.Dispute(guilds["Olympus Pair"], NOW)
		eq(d and d.single, "Ann-Realm", "Bob's vote is past VOUCH_TTL: Ann alone")
		eq(C.Confidence(D.Summary().guilds[1], NOW), "single")
		local c = C.Compute()
		eq(c.outliers.guilds, 1, "single: the jump is held"); eq(c.outliers.list[1].kept, 200)
	end)
end)

test("census clean: as the census page says (how the census is built): the guild's other reporters outvote a newer report only while the row it would replace is under FRESH old", function()
	local function Send(sender, total, officer)
		return D.Receive(Codec.DecodeReport(Wire({ guild = "Olympus Votes", total = total, online = 1, leader = "Lead",
			officers = { { name = officer } } })), sender)
	end
	With({}, function(clock)
		eq(Send("Vann-Realm", 200, "Duke"), true); eq(Send("Vbob-Realm", 200, "Duke"), true)
		clock.now = NOW + D.FRESH - 60
		eq(Send("Vcid-Realm", 260, "Usurper"), false, "the row under FRESH old: outvoted, the row stays")
		eq(ns.rdb.guilds["Olympus Votes"].total, 200)
	end)
	With({}, function(clock)
		eq(Send("Vann-Realm", 200, "Duke"), true); eq(Send("Vbob-Realm", 200, "Duke"), true)
		clock.now = NOW + D.FRESH + 60
		eq(Send("Vcid-Realm", 260, "Usurper"), true, "the row past FRESH: the newer report replaces it, though the others' votes still stand")
		local g = ns.rdb.guilds["Olympus Votes"]
		eq(g.total, 260); eq(g.reporterFull, "Vcid-Realm"); eq(g.outvoted, nil)
	end)
end)

test("census clean: as the census page says (S3): a guild /who saw that this client holds a relay of is not listed as seen", function()
	With({ global = { ["olympus relayed"] = { name = "Olympus Relayed", total = 70, online = 5, avg10 = 400, observed = NOW - 300 } },
		seen = { ["Olympus Relayed"] = { online = 4, t = NOW - 60 }, ["Olympus Seen"] = { online = 7, t = NOW - 60 } } }, function()
		local s = D.Summary()
		eq(#s.seen, 1, "only the guild of which this client holds no report or relay"); eq(s.seen[1].name, "Olympus Seen")
		eq(s.characters, 70, "the relay counts; /who adds nothing")
	end)
end)

test("census clean: last good sizes older than Data.KEEP go at login", function()
	With({ guilds = Army() }, function(clock)
		C.Compute()
		assert(ns.rdb.censusClean.sizes["olympus agreed"], "kept")
		clock.now = NOW + D.KEEP + 1
		C.Prune()
		eq(next(ns.rdb.censusClean.sizes), nil)
	end)
end)

test("census stats section: the page's figures and series, the sanitized census beside them, no registered users yet", function()
	local page = {
		DaySeries = function() return { { t = NOW - 86400, c = 480, p = 470, o = 30 }, { t = NOW - 43200 }, { t = NOW, c = 490, p = 487, o = 41 } } end,
		HourSeries = function() return { { ago = 1 }, { t = NOW - 600, c = 490, p = 487, o = 41 } } end,
		AverageLevel = function() return "40.0" end,
	}
	With({ guilds = Army(), banned = { ["Olympus Banned"] = true }, alts = { ["Olympus Home"] = 3 }, page = page }, function()
		local section = assert(OlympusBridge.GetSection("stats"), "the section")
		eq(section.version, 1)
		local data, s = section.data, D.Summary()
		eq(data.characters, s.characters); eq(data.people, s.total); eq(data.linkedAlts, s.alts); eq(data.online, s.online)
		eq(data.charactersWithBanned, s.characters + 40)
		eq(data.sanitizedPeople, s.total)
		eq(data.confirmedPeople, 297)
		eq(data.countedGuilds, 5); eq(data.freshGuilds, 4)
		eq(data.avgLevel, "40.0")
		eq(data.registered, nil, "not counted yet"); eq(data.accounts, nil)
		eq(data.confidence.disputed, 60)
		eq(data.banned.list[1], "40~Olympus Banned")
		eq(data.departed.list[1], ("30~%d~Olympus Gone"):format(NOW - 2 * 86400))
		eq(#data.days, 2, "a day without a sample is left out")
		eq(data.days[2], ("%d~490~487~41"):format(NOW))
		eq(data.hours[1], ("%d~490~487~41"):format(NOW - 600))
		eq(data.guilds[1], "200~20~10~400~confirmed~Olympus Agreed")
		eq(#data.guilds, 5)
	end)
	-- A build without the census page: the figures still go, without the series.
	With({ guilds = Army() }, function()
		local data = assert(OlympusBridge.GetSection("stats")).data
		eq(data.people, D.Summary().total)
		eq(#data.days, 0); eq(#data.hours, 0); eq(data.avgLevel, nil)
	end)
end)

test("census stats section: validated people only from a moderation team client, as numbers, never a tag or a name", function()
	local saved = ns.Accord
	local team = true
	ns.Accord = {
		TeamShown = function() return team end,
		Groups = function() return { { tag = "Secret#1234", rows = { { name = "A-Realm" }, { name = "B-Realm" } } }, { tag = "Other#99", rows = { { name = "C-Realm" } } } } end,
		Count = function() return 3 end,
	}
	local ok, err = pcall(With, { guilds = Army() }, function()
		local data = assert(OlympusBridge.GetSection("stats")).data
		eq(data.validated.battleTags, 2); eq(data.validated.characters, 3)
		local function Holds(t, depth)
			for k, v in pairs(t) do
				if type(v) == "string" and (v:find("#", 1, true) or v:find("-Realm", 1, true)) then return k end
				if type(v) == "table" and depth < 5 then local found = Holds(v, depth + 1) if found then return found end end
			end
		end
		eq(Holds(data.validated, 0), nil, "no tag or name")
		team = false
		eq(assert(OlympusBridge.GetSection("stats")).data.validated, nil, "any other client: none")
	end)
	ns.Accord = saved
	if not ok then error(err, 0) end
end)

-- (The author, 2026-10-20) The people as the header shows them, handed to the Companion: a team
-- client's "~" estimate as peopleEstimate, a whole number (the shape the Companion's census page
-- reads), and its staff figures; a member's client sends no estimate, so the Companion shows
-- `people`, his header's plain count. Added beside the section's fields, none of them renamed.
test("census stats section: peopleEstimate only while a team client's estimate shows, a whole number; its staff figures and rate off the King's stream; a member's client sends none; never a tag or a name", function()
	local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]census%-clean%.lua$")) or "./"
	local cns = setmetatable({ rdb = {}, On = function() end, Every = function() end }, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/CensusStats.lua"))("Olympus", cns)
	local savedAccord, savedSample = ns.Accord, ns.Alts.Sample
	local team, stream, alts, tags = false, false, { 250, 100 }, { 60, 50 }
	ns.Accord = { TeamShown = function() return team end, Stream = function() return stream end,
		Groups = function() return { { tag = "Secret#1234", rows = { { name = "A-Realm" } } } } end, Count = function() return 1 end,
		Sample = function() return tags[1], tags[2] end }
	ns.Alts.Sample = function() return alts[1], alts[2] end
	local function Holds(t, depth)
		for k, v in pairs(t) do
			if type(v) == "string" and (v:find("#", 1, true) or v:find("-Realm", 1, true) or v:find("Secret", 1, true)) then return k end
			if type(v) == "table" and depth < 5 then local found = Holds(v, depth + 1) if found then return found end end
		end
	end
	local ok, err = pcall(With, { guilds = Army(), banned = { ["Olympus Banned"] = true }, alts = { ["Olympus Home"] = 3 }, page = cns.CensusStats }, function()
		local s = D.Summary()
		eq(s.characters, 490); eq(s.total, 487)
		-- An ordinary member: his header's plain count, so no estimate: the Companion shows `people`.
		local data = assert(OlympusBridge.GetSection("stats")).data
		eq(data.peopleEstimate, nil, "a member's client: no estimate")
		eq(data.people, 487, "the plain count, as before"); eq(data.validated, nil, "no validated figures off the team")
		-- A moderation team client: 50 validated accounts of 60 characters, 50 + 430 / 1.2 = 408.
		team = true
		data = assert(OlympusBridge.GetSection("stats")).data
		eq(data.peopleEstimate, 408); eq(type(data.peopleEstimate), "number", "a whole number, as the Companion reads it")
		eq(data.people, 487, "people keeps its meaning")
		eq(data.validated.battleTags, 1); eq(data.validated.characters, 1, "the store's own figures, as before")
		eq(data.validated.countedBattleTags, 50); eq(data.validated.countedCharacters, 60); eq(data.validated.unvalidated, 430)
		eq(data.validated.rate, 1.2, "the validated accounts' characters per account, two decimals")
		eq(Holds(data, 0), nil, "no tag or name")
		-- (The review of 2026-10-20) The King's stream: the estimate as his header shows it, but none
		-- of the staff's figures his page hides there: no rate, no counted validated ones. (The
		-- store's own two figures are sent as before.)
		stream = true
		data = assert(OlympusBridge.GetSection("stats")).data
		eq(data.peopleEstimate, 408)
		eq(data.validated.countedBattleTags, nil); eq(data.validated.countedCharacters, nil); eq(data.validated.unvalidated, nil)
		eq(data.validated.rate, nil)
		eq(data.validated.battleTags, 1); eq(data.validated.characters, 1)
		-- A team client whose own sample is too small: the plain count as members see it, so no
		-- estimate; off the stream its counted figures still go, without a rate.
		tags = { 6, 5 }
		data = assert(OlympusBridge.GetSection("stats")).data
		eq(data.peopleEstimate, nil); eq(data.validated.countedBattleTags, nil, "still on the stream")
		stream = false
		data = assert(OlympusBridge.GetSection("stats")).data
		eq(data.peopleEstimate, nil); eq(data.validated.countedBattleTags, 5); eq(data.validated.unvalidated, 484)
		eq(data.validated.rate, nil, "no rate made the number")
	end)
	ns.Accord, ns.Alts.Sample = savedAccord, savedSample
	if not ok then error(err, 0) end
end)

-- The section reads the page's own estimate where the build has it, and none without the page.
test("census stats section: peopleEstimate is the page's own estimate, and absent without the census page or while it is no estimate", function()
	local approx = true
	local page = { PeopleEstimate = function() return { shown = 480, approx = approx, people = 487 } end,
		StaffShown = function() return false end }
	With({ guilds = Army(), page = page }, function()
		eq(assert(OlympusBridge.GetSection("stats")).data.peopleEstimate, 480, "the header's estimate, as the page shows it")
		approx = false
		eq(assert(OlympusBridge.GetSection("stats")).data.peopleEstimate, nil, "the plain count: none")
	end)
	With({ guilds = Army() }, function()
		eq(assert(OlympusBridge.GetSection("stats")).data.peopleEstimate, nil, "no estimate without the page")
	end)
end)
