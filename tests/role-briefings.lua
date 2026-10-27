-- Durable role letters: only real appointments create them, one per office and its holder (a
-- removal, a roster gap or a re-signed list never makes a second), and the Missionary/Legate pages
-- preserve the operational decisions they explain. Every name is invented.
local ns, test, eq, extra = ...
local ROOT = assert(extra and extra.ROOT)
local ADDON = ROOT .. "Olympus/"

assert(loadfile(ADDON .. "Locales/RoleBriefingsText.lua"))("Olympus", ns)
assert(loadfile(ADDON .. "RoleBriefings.lua"))("Olympus", ns)
local RB = ns.RoleBriefings

local function Text(lines)
	local out = {}
	for _, line in ipairs(lines or {}) do if type(line.text) == "string" then out[#out + 1] = line.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end end
	return table.concat(out, "\n")
end

local function WithRoles(options, fn)
	options = options or {}
	local saved = { guildInfo = GetGuildInfo, member = ns.IsMember, fed = ns.IsFederation,
		hc = ns.IsHighCouncillor, king = ns.King, watch = ns.Watch, treasury = ns.Treasury,
		church = ns.Church, nominees = ns.Nominees, ui = ns.UI, views = ns.Views, now = ns.Now,
		print = ns.Print, store = ns.db.roleBriefings }
	local rank, clock, opened = options.rank == nil and 3 or options.rank, 2200000000, {}
	local ok, err = pcall(function()
		GetGuildInfo = function() return options.guild or "Olympus II", "rank", rank end
		ns.IsMember = function() return options.member ~= false end
		ns.IsFederation = function(g) return type(g) == "string" and g:find("Olympus", 1, true) ~= nil end
		ns.IsHighCouncillor = function() return options.council == true end
		ns.King = {
			IsKing = function() return options.king == true end,
			IsSteward = function() return options.steward == true end,
			IsHand = function() return options.hand == true end,
		}
		ns.Watch = {
			CanRead = function() return options.watch == true end,
			CouncilDeskShown = function() return options.councilDesk == true end,
		}
		ns.Treasury = { RealKeeper = function() return options.treasurer == true end }
		ns.Church = {
			Role = function() return options.churchRole end,
			Place = function() return options.place end,
		}
		ns.Nominees = {
			RoleOf = function() return options.nomineeRole, options.department end,
			DepartmentHelp = function(dept) return options.duty or ("purpose of " .. tostring(dept)) end,
		}
		ns.UI = { SelectTab = function(tab) opened[#opened + 1] = "tab:" .. tostring(tab); return true end,
			Refresh = function() end }
		ns.Views = { ShowPage = function(page) opened[#opened + 1] = "page:" .. tostring(page) end }
		ns.Now = function() clock = clock + 1 return clock end
		ns.Print = function() end
		ns.db.roleBriefings = nil
		RB.Reset()
		fn({ setRank = function(v) rank = v end, opened = opened })
	end)
	GetGuildInfo, ns.IsMember, ns.IsFederation = saved.guildInfo, saved.member, saved.fed
	ns.IsHighCouncillor, ns.King, ns.Watch, ns.Treasury = saved.hc, saved.king, saved.watch, saved.treasury
	ns.Church, ns.Nominees, ns.UI, ns.Views = saved.church, saved.nominees, saved.ui, saved.views
	ns.Now, ns.Print, ns.db.roleBriefings = saved.now, saved.print, saved.store
	RB.Reset()
	if not ok then error(err, 0) end
end

test("role briefings: a real Guild Master is recorded once and temporary roster gaps or previews cannot duplicate it", function()
	WithRoles({ rank = 0, councilDesk = true }, function(w)
		eq(RB.Scan(true), 1)
		eq(#RB.Letters(), 1); eq(RB.Letters()[1].kind, "guildmaster")
		eq(RB.Scan(true), 0, "a relog/data refresh does not repeat the letter")
		-- CouncilDeskShown is presentation only and must not manufacture a Watch appointment.
		for _, e in ipairs(RB.Letters()) do assert(e.kind ~= "watch") end
		w.setRank(3)
		eq(RB.Scan(true), 0, "a missing role does not manufacture state")
		w.setRank(0)
		eq(RB.Scan(true), 0, "the same signature is not repeated after a temporary roster gap")
		eq(#RB.Letters(), 1)
	end)
end)

test("role briefings: The Watch is offered only when the real guild-local desk can be read", function()
	WithRoles({ watch = false, councilDesk = true }, function()
		eq(RB.Scan(true), 0, "a council presentation is not Watch staffing")
	end)
	WithRoles({ watch = true }, function()
		eq(RB.Scan(true), 1)
		eq(RB.Letters()[1].kind, "watch")
	end)
end)

test("role briefings: Missionaries get a reopenable, practical recruiting checklist", function()
	local opts = { churchRole = "M", place = { since = 123, ac = "Apostle-Realm" } }
	WithRoles(opts, function(w)
		eq(RB.Scan(true), 1)
		eq(RB.OpenKind("missionary"), true)
		local page = Text(RB.Page()):gsub("%s+", " ")
		assert(page:find("Church > Mine", 1, true), page)
		assert(page:find("Blizzard's normal guild interface", 1, true), page)
		assert(page:find("Register a recruit", 1, true), page)
		assert(page:find("another updated guild client", 1, true), page)
		assert(page:find("seven days", 1, true), page)
		eq(RB.Letters()[1].read, true)
		eq(RB.Open(RB.Letters()[1].id), true, "the read letter remains reopenable")
		assert(#w.opened >= 4, "each open routes back into the main Realm page")
		-- (Changed with the fix keying letters on the office and its holder: a new date on the same
		-- place, which a re-signed list or a keep makes, was taken for a new appointment and made a
		-- second letter. The author's rule is one letter per office held, reread from My profile.)
		opts.place = { since = 456, ac = "Another-Apostle" }
		eq(RB.Scan(true), 0, "a new date on the same office is not a new letter")
		eq(#RB.Letters(), 1)
	end)
end)

test("role briefings: the legacy wire role is explained only as a 25-by-40 Legate structure", function()
	WithRoles({ nomineeRole = "centurion" }, function()
		eq(RB.Scan(true), 1)
		eq(RB.Letters()[1].kind, "legate")
		eq(RB.OpenKind("legate"), true)
		local page = Text(RB.Page())
		assert(page:find("Legate", 1, true), page)
		assert(page:find("40", 1, true) and page:find("39", 1, true), page)
		assert(page:find("High Council", 1, true), page)
		assert(not page:lower():find("centurion", 1, true), "the compatibility wire name is not taught to players")
	end)
end)

test("role briefings: relevant offices each have a durable title and body", function()
	local scenarios = {
		{ key = "king", opts = { king = true, rank = 0 } },
		{ key = "council", opts = { council = true } },
		{ key = "steward", opts = { steward = true } },
		{ key = "hand", opts = { hand = true } },
		{ key = "treasurer", opts = { treasurer = true } },
		{ key = "apostle", opts = { churchRole = "A", place = { since = 45 } } },
		{ key = "churchcorr", opts = { churchRole = "C" } },
		{ key = "correspondent", opts = { nomineeRole = "correspondent", department = "Department of War", duty = "coordinate guild operations" } },
	}
	for _, scenario in ipairs(scenarios) do
		WithRoles(scenario.opts, function()
			assert(RB.Scan(true) >= 1, scenario.key)
			assert(RB.OpenKind(scenario.key), scenario.key)
			local page = Text(RB.Page())
			assert(#page > 100, scenario.key .. ": " .. page)
		end)
	end
end)


-- The real Church (tests/church-world.lua): a client of that small world with the duty letters
-- loaded into its own namespace. The other role sources are absent there, so only the Church's own
-- state can make a letter.
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
local function ChurchLetters(w, cl)
	local c = cl.c
	c.RealmPages = {}
	c.King, c.Watch, c.Treasury, c.Nominees, c.WatchChat = {}, {}, {}, {}, {}
	c.db.roleBriefings = nil
	w:As(cl, function() assert(loadfile(ADDON .. "RoleBriefings.lua"))("Olympus", c) end)
	return c.RoleBriefings
end

-- Review of the first duty letters: an Apostle's letter was keyed on Church.Place().since, which is
-- the signed Apostles list's time for a signed Apostle, so every re-sign of that list made a second
-- letter for the same office. Fails before the fix: the re-signed list makes 1 more letter.
test("role briefings: an Apostle's letter is keyed on the office and its holder, so a re-signed Apostles list never duplicates it (real Church)", function()
	local apostle = "Aldric Vane-Realm"
	local w = World.New({ apostles = { apostle } })
	local cl = w:Client(apostle, { view = true })
	local RB = ChurchLetters(w, cl)
	eq(w:As(cl, cl.Church.Role, apostle), "A")
	eq(w:As(cl, RB.Scan, true), 1, "the Apostle's letter")
	-- The same Apostles signed again a day later: the signed place is re-dated, the office is not new.
	w.clock = w.clock + 86400
	w:SignedList({ apostle }, true, w.clock)
	eq(w:As(cl, function() return cl.Church.Place(apostle).since end), w.clock, "the re-sign re-dates the signed place")
	eq(w:As(cl, RB.Scan, true), 0, "the same Apostle in the same office: no second letter")
	eq(#w:As(cl, RB.Letters), 1)
end)
