-- 1.2.4 was pre-launch: the level race shipped switched off. (1.4.0, the launch) It ships switched on
-- and runs only on the launch's realms: where the author's signed list names this realm and it is none
-- of the beta's (ns.LaunchRealm). The first three tests keep 1.2.4's cases on a realm the list does not
-- name (the foundation World holds no list; W3.New with levelRace = false is that World), where the
-- release still collects, sends, relays and awards nothing and keeps old records intact; the last ones
-- are the launch's realms. The signed list's own path: tests/launch-identity.lua.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local function Net(w, c) return W3.M(w, c, "HonorsNet") end
local function Claim(c, level, now)
	local A = c.ns.Arena
	return table.concat({ A.GK(c.guid), A.B36(level), A.B36(now) }, "~")
end
local function Record(c, level, now)
	local A = c.ns.Arena
	return table.concat({ A.B36(level), A.GK(c.guid), c.ns.ArenaFights.Wire(c.name), A.B36(now) }, ":")
end
local function NoLevel(held)
	for _, h in ipairs(held) do assert(not h.key:match("^level%-race%-"), "a pre-launch level award: " .. h.key) end
end

-- (1.4.0: levelRace = false, a realm the launch list does not name: W3.New's world is a launch realm
-- now, and a shipped client there runs the race; the clock is after the race's start too.)
test("1.2.4 pre-launch level race (1.4.0: a realm the launch list does not name): shipped level-ups collect and send nothing, even after the race's start and with independent game lives on", function()
	local w, cast = W3.New({ levelRace = false, world = { compliance = "shipped", clock = 2000000000 },
		more = { { "young", "Brisa Vale", { level = 19 } } } })
	local c, net = cast.young, Net(w, cast.young)
	eq(w:Events(c, true).PLAYER_LEVEL_UP, nil, "no collection hook off the launch's realms")
	eq(c.Roles.Live(), true, "unrelated games remain live")
	w:Fire(c, "PLAYER_LEVEL_UP", 20)
	w:As(c, c.ns.HonorsNet.OnLevelUp, 40) -- a direct/manual caller must not schedule claims either
	w:Run(3700)
	eq(#w:Sent{ from = c, type = "IL" }, 0)
	eq(net.Store(), nil, "a level-up cannot allocate the historical book")
	eq(net.WatchLevels(), false)
	local ok, why = net.SendClaim(20)
	eq(ok, false); eq(why, "level-race-off")
	ok, why = c.Arena.Send("IL", "L", Claim(c, 20, w.clock))
	eq(ok, false); eq(why, "level-race-off", "raw send uses the same boundary")
	for _, t in ipairs(w:Timers(c, true)) do
		assert(not tostring(t.where):find("level", 1, true), "no deferred race timer")
	end
	eq(net.LevelRaceActive(), false)
	W3.NoErrors(w)
end)

test("1.2.4 pre-launch level race (1.4.0: a realm the launch list does not name): native IL and an authenticated clerk's AB H from an older peer allocate no claims or levels; no clerk records or answers go out", function()
	local w = World.New({ compliance = "shipped", clock = 2000000000 })
	local viewer, peer, clerk = w:Role("bettor1"), w:Role("fighterA"), w:Role("councillor")
	local net = Net(w, viewer)
	eq(w:As(viewer, viewer.ns.IsHighCouncillor, clerk.name), true, "the AB sender really passes the existing authority gate")
	viewer.comm.handlers.IL("CHANNEL", peer.name, "IL~L1~" .. Claim(peer, 20, w.clock))
	eq(net.Store(), nil, "native old-peer claim is not collected")
	viewer.comm.handlers.AB("CHANNEL", clerk.name, "AB~L1~H~" .. Record(peer, 40, w.clock))
	eq(net.Store(), nil, "authenticated historical relay is not collected")
	eq(net.TakeRecords(clerk.name, "L", Record(peer, 60, w.clock)), false, "direct receiver cannot bypass it")
	local s = net.Store(true)
	s.levels[60] = { { guid = peer.guid, name = peer.name, t = w.clock - 100, place = 1 } }
	eq(net.RecordsBody(), nil); eq(net.SendRecords(), false); eq(net.Answer(peer.name), false)
	w:Run(0)
	for _, item in ipairs(w:Sent{ from = viewer, type = "AB" }) do
		assert(not item.msg:find("~H~", 1, true), "no historical level records on the wire")
	end
	eq(s.levels[60][1].name, peer.name, "relay refusal does not erase the historical book")
	W3.NoErrors(w)
end)

test("1.2.4 pre-launch level race (1.4.0: a realm the launch list does not name): old saved places and claims survive census checks, refresh and reload without awarded titles or letters", function()
	local w = World.New({ compliance = "shipped", clock = 2000000000 })
	local c = w:Client("Brisa Vale", { level = 19 })
	local net = Net(w, c)
	local s = net.Store(true)
	local place = { guid = c.guid, name = c.name, t = w.clock - 2 * 86400, place = 1 }
	local claim = { gk = c.ns.Arena.GK(c.guid), name = c.name, level = 20,
		t = w.clock - 20 * 86400, heardLocal = w.clock - 20 * 86400, vouched = true }
	s.levels[60], s.claims.old, s.vouchRule = { place }, claim, 1
	-- This stale place contradicts the current native player level: even the old security
	-- maintenance must not erase history while collection is dormant.
	eq(#net.Holdings(c.name, c.guid), 0, "old records award no pre-launch title")
	eq(next(net.Inputs().levels), nil)
	eq(net.Known().level, true, "known-disabled, never an unknown relay gap")
	local m = w:As(c, c.ns.ArenaProfile.Mine, true)
	m.frame, m.title = "rank", "level-race-60"
	m.seen = { ["level-60"] = { place = 1, title = "level-race-60" } }
	m.standing = { ["level-60"] = { p = 1 } }
	eq(net.Standing()["level-60"], nil, "historical standing is not an effective launch award")
	eq(m.standing["level-60"].p, 1, "saved notice history remains intact")
	eq(net.Verified(c.name, c.guid).title, nil, "old configured title is not an effective award")
	eq(#net.CheckPlaces(), 0); eq(net.RaceSoon(), false); eq(#net.RunRace(), 0)
	w:As(c, function() c.ns.Fire("DATA_CHANGED"); c.ns.HonorsNet.Refresh() end)
	eq(c.ns.ArenaProfile.Pick().title, nil, "an old derived pick is not remembered as unknown")
	eq(c.ns.ArenaProfile.Pick().seen["level-60"], nil)
	eq(net.Standing()["level-60"], nil, "the disabled race has no live award standing")
	eq(m.standing["level-60"].p, 1, "no false newly-lost place replaces the historical notice")
	w:Fire(c, "PLAYER_LEVEL_UP", 20)
	w:Run(3700)
	eq(s.levels[60][1], place); eq(s.claims.old, claim); eq(s.vouchRule, 1)
	eq(next(s.struck or {}), nil); eq(#net.QueuedLetters(), 0); eq(#net.Letters(), 0)
	eq(#w:Sent{ from = c, type = "IL" }, 0)
	w:Logout(c); w:Login(c)
	net = Net(w, c)
	w:As(c, function() c.ns.Fire("DATA_CHANGED"); c.ns.HonorsNet.Refresh() end)
	w:Run(65)
	local kept = net.Store()
	eq(kept.levels[60][1].name, place.name); eq(kept.levels[60][1].t, place.t)
	eq(kept.claims.old.t, claim.t); eq(kept.claims.old.vouched, true); eq(kept.vouchRule, 1)
	eq(net.Levels(), kept.levels, "raw history remains readable")
	NoLevel(net.Holdings(c.name, c.guid)); eq(net.Verified(c.name, c.guid).title, nil)
	eq(net.LevelRaceActive(), false); eq(w:Events(c, true).PLAYER_LEVEL_UP, nil)
	eq(#net.QueuedLetters(), 0); eq(#net.Letters(), 0)
	W3.NoErrors(w)
end)

-- (1.4.0) Was "future fixture opt-in is explicit and strict; base and shipped worlds stay off": the
-- race was the future's then, and even the fixture left a shipped client off. It is the release's now:
-- a shipped client on a launch realm runs it; what stays is that nothing but the signed list and a
-- switch that is exactly true opens it, the beta's realm group never, and verification follows at once.
test("1.4.0 the launch's realms: a shipped client on a realm the signed list names watches its level-ups and claims; the foundation world (no list), the beta's realm group (whatever a list says) and a switch that is not exactly true stay off; cached verification follows", function()
	local w = World.New({ compliance = "shipped", clock = 2000000000 })
	local c = w:Client("Brisa Vale", { level = 19 })
	eq(w:Events(c, true).PLAYER_LEVEL_UP, nil, "no list held: off")
	eq(Net(w, c).LevelRaceActive(), false)
	local launch = W3.LevelRaceWorld({ compliance = "shipped", clock = 2000000000 })
	local f = launch:Client("Corin Ash", { level = 19 })
	local net = Net(launch, f)
	eq(net.LEVEL_RACE_LAUNCHED, true, "the release's switch")
	eq(net.LevelRaceActive(), true, "a launch realm")
	eq(launch:Events(f, true).PLAYER_LEVEL_UP, true, "its level-ups watched")
	W3.Rules(launch, f)
	launch:Fire(f, "PLAYER_LEVEL_UP", 20)
	launch:Run(61)
	eq(#launch:Sent{ from = f, type = "IL" }, 1, "his claim, 60 s after")
	-- Verification as the switch says, at once (a cached award never outlives it).
	local s = net.Store(true)
	s.levels[60] = { { guid = f.guid, name = f.name, t = launch.clock, place = 1 } }
	local m = launch:As(f, f.ns.ArenaProfile.Mine, true)
	m.frame, m.title = "rank", "level-race-60"
	eq(net.Verified(f.name, f.guid).title, "level-race-60")
	f.ns.HonorsNet.LEVEL_RACE_LAUNCHED = 1 -- truthy is not a launch
	eq(net.LevelRaceActive(), false); eq(next(net.Inputs().levels), nil)
	eq(net.Verified(f.name, f.guid).title, nil, "no cached award leaks across the switch")
	f.ns.HonorsNet.LEVEL_RACE_LAUNCHED = true
	eq(net.Verified(f.name, f.guid).title, "level-race-60")
	-- The beta's realm group: off, even where a list names its realm.
	local realm, group, info = f.ns.realm, f.ns.group, rawget(f.ns, "RealmInfo")
	f.ns.realm, f.ns.group = "ClassicBetaPvP", "ClassicBetaPvP+ClassicBetaPvP2"
	rawset(f.ns, "RealmInfo", function(r) return (r == "ClassicBetaPvP" or r == "ClassicBetaPvP2") and { kind = "pvp", region = "NA" } or nil end)
	eq(net.LevelRaceActive(), false, "the beta's")
	eq(net.Verified(f.name, f.guid).title, nil)
	-- A list that names other realms only: off.
	f.ns.realm, f.ns.group = realm, group
	rawset(f.ns, "RealmInfo", function() return nil end)
	eq(net.LevelRaceActive(), false, "a realm the list does not name")
	rawset(f.ns, "RealmInfo", info)
	eq(net.LevelRaceActive(), true, "named again")
	W3.NoErrors(w); W3.NoErrors(launch)
end)

-- (1.4.0, the owner's ask: no beta-era race state may award a launch place.) A realm's store is its
-- own, so the beta's books stay on the beta's realms; on a launch realm the race's start is the second
-- guard: what a store kept from before it (a realm of the same name tested before, a pre-launch book)
-- goes the first time the race opens it, and a clerk's record timed before it is refused.
test("1.4.0 the launch's realms: RACE_START is 2026-11-04 00:00 UTC; a saved book and claims timed before it go the first time the race opens the store, its places award nothing; a clerk's record timed before it is refused, one after it taken", function()
	local START = 1793750400
	local w = W3.LevelRaceWorld({ clock = START + 2 * 86400 })
	local viewer, peer, old = w:Role("bettor1"), w:Role("fighterA"), w:Role("fighterB")
	local clerk = w:Role("councillor")
	local net = Net(w, viewer)
	eq(net.RACE_START, START); eq(os.date("!%Y-%m-%d %H:%M:%S", net.RACE_START), "2026-11-04 00:00:00")
	eq(net.LevelRaceActive(), true)
	-- What an earlier session on a realm of this name kept: places and claims from before the start,
	-- one place and one claim from after it.
	local A = viewer.ns.Arena
	w:As(viewer, function()
		local r = A.RealmStore()
		r.honors = { raceStart = 1790812800, levels = {
			[20] = { { guid = old.guid, name = old.name, t = START - 86400, place = 1 } },
			[40] = { { guid = old.guid, name = old.name, place = 1 } },
			[60] = { { guid = peer.guid, name = peer.name, t = START + 3600, place = 1 } } },
			claims = {
				old = { gk = A.GK(old.guid), name = old.name, level = 40, t = START - 60, heardLocal = START - 60, vouched = true },
				new = { gk = A.GK(peer.guid), name = peer.name, level = 40, t = START + 60, heardLocal = START + 60, vouched = false } },
			lows = { [20] = { [old.name:lower()] = START - 7200 } } }
	end)
	local s = net.Store()
	eq(s.raceStart, START)
	eq(s.levels[20], nil, "before the start: gone"); eq(s.levels[40], nil, "untimed: gone")
	eq(s.levels[60][1].name, peer.name, "after it: kept")
	eq(s.claims.old, nil); eq(s.claims.new.name, peer.name)
	eq(s.lows, nil, "sightings of an earlier start: gone")
	NoLevel(net.Holdings(old.name, old.guid))
	-- A clerk's records: before the start, refused; after it, taken (a milestone with no place here).
	eq(w:As(viewer, viewer.ns.IsHighCouncillor, clerk.name), true, "the AB sender passes the authority gate")
	eq(net.TakeRecords(clerk.name, "L", Record(old, 20, START - 1)), false, "a pre-launch record")
	eq(s.levels[20], nil)
	eq(net.TakeRecords(clerk.name, "L", Record(old, 20, w.clock + 3600)), false, "a record ahead of the clock")
	eq(net.TakeRecords(clerk.name, "L", Record(peer, 20, START + 7200)), true, "a launch record")
	eq(s.levels[20][1].name, peer.name)
	W3.NoErrors(w)
end)
