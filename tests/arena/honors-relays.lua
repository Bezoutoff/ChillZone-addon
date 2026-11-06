-- 1.3.4 (the owner's ask before the launch: every ranking and every frame shows on every client): the
-- honours that depend on a ranking's word reach a client that was never online with that word's author.
-- The Church's top 3 (NR~1~t, worked out by the author's client alone) is said again by a signed High
-- Councillor's client (ChurchCount.RelayTop): a client that never heard the author's then shows the
-- Apostles' gold cross the red cross's wearer holds (HonorsNet.OwnLookFrame), where it showed him with
-- no frame. The donors' word (ID) is the Treasurer's: the King's client no longer puts its own book's
-- top 3 over it, and the Council's and the King's clients say the Treasurer's again (H.RelayDonors), so
-- the cornucopia shows on a client that logged in after it. On the test world; every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local MEDIA = "Interface\\AddOns\\ChillZone\\media\\honors\\"
local DAY = 86400

local function HN(w, c) return W3.M(w, c, "HonorsNet") end
local function PE(w, c) return W3.M(w, c, "ProfileEdit") end

-- The game's unit frames on client c and Borders.lua loaded into it (as tests/arena/honors-own-look.lua
-- stands them in): what each container shows (its metal underlay, sublevel 2, aside).
local function Frames(w, c)
	local rec = { textures = {} }
	local function Texture(owner, sublevel)
		local t = { owner = owner, sublevel = sublevel, shown = true }
		t.SetTexture = function(self, file) self.file, self.atlas = file, nil return true end
		t.SetAtlas = function(self, a) self.atlas, self.file = a, nil end
		t.SetSize = function(self, x, y) self.w, self.h = x, y end
		t.SetPoint = function() end
		t.ClearAllPoints = function() end
		t.SetTexCoord = function() end
		t.SetDesaturated = function() end
		t.SetVertexColor = function() end
		t.Show = function(self) self.shown = true end
		t.Hide = function(self) self.shown = false end
		t.IsShown = function(self) return self.shown end
		rec.textures[#rec.textures + 1] = t
		return t
	end
	local function Container(label)
		return { label = label, CreateTexture = function(_, _, _, _, sublevel) return Texture(label, sublevel) end }
	end
	local g = c.globals
	g.TargetFrame = { TargetFrameContainer = Container("target"), CheckClassification = function() end }
	g.FocusFrame = { TargetFrameContainer = Container("focus"), CheckClassification = function() end }
	g.PlayerFrame = { PlayerFrameContainer = Container("player") }
	g.hooksecurefunc = function(t, key, post)
		if type(t) ~= "table" then return end
		local original = t[key]
		t[key] = function(...) local r = { original(...) } post(...) return unpack(r) end
	end
	g.C_Texture = { GetAtlasInfo = function() return {} end }
	g.InCombatLockdown = function() return false end
	g.UnitIsUnit = function(a, b) return a == b end
	w:As(c, function()
		rawset(c.ns, "Borders", nil)
		assert(loadfile(H.ADDON_DIR .. "Borders.lua"))("ChillZone", c.ns)
	end)
	rec.B = W3.M(w, c, "Borders")
	function rec.Shown(owner)
		local found
		for _, t in ipairs(rec.textures) do
			if t.owner == owner and t.sublevel ~= 2 and t.shown then
				assert(not found, "two at once on " .. owner)
				found = t
			end
		end
		return found and (found.file or found.atlas) or nil
	end
	return rec
end

-- The real Church.lua and ChurchCount.lua over each client's namespace (a login first: the frames the
-- world wears, the rules said yes to), holding a signed titles list naming `apostles`, the public
-- ranking open. What each client's Church sends is kept (c.churchSent), never delivered by itself.
local function ChurchOn(w, clients, apostles)
	local titles = {}
	local field = "Department of War^^Brannoc Weald=Marshal;^apostles^Alliance^" .. table.concat(apostles, ",")
	titles.at, titles.depts = 1800000000, {}
	titles.blob = ("HT1~%d~Emberfall~1~%s~%s"):format(titles.at, field, ("ab"):rep(256))
	for _, c in ipairs(clients) do
		w:Logout(c)
		w:Login(c)
		W3.Rules(w, c)
		local sent = {}
		local cns = setmetatable({ Comm = { Handle = function() end, Whisper = function() end,
			Send = function(dist, text) sent[#sent + 1] = { dist = dist, text = text } return true end },
			On = function() end, ChatRooms = false, CouncilTitles = function() return titles end }, { __index = c.ns })
		w:As(c, function()
			assert(loadfile(H.ADDON_DIR .. "Church.lua"))("ChillZone", cns)
			assert(loadfile(H.ADDON_DIR .. "ChurchCount.lua"))("ChillZone", cns)
		end)
		rawset(c.ns, "Church", cns.Church)
		rawset(c.ns, "ChurchCount", cns.ChurchCount)
		cns.ChurchCount.random = function(a) return a end
		c.churchSent = sent
		c.rdb.church = c.rdb.church or {}
		c.rdb.church.pub = { on = true, at = w.clock - 3600 }
	end
end
local function TakeTop(w, c, from, text) return w:As(c, c.ns.ChurchCount.Receive, "NR", "CHANNEL", from, text) end

test("1.3.4 honours relayed: a client never online with the author's takes the Church's top 3 from a signed High Councillor's relay and shows the gold cross the red cross's wearer holds (it showed him with no frame); an Apostle's word is refused; an older word never replaces it", function()
	local w, cast = W3.New({ more = { { "councillor", N.councillor } } })
	local apostle, viewer, other, relay = cast.A, cast.spectator, cast.B, cast.councillor
	local function Later() w:Run(apostle.ns.ArenaProfile.RATE_CHANGED + 1) end
	ChurchOn(w, { apostle, viewer, other, relay }, { apostle.short, other.short })
	eq(w:As(viewer, viewer.ns.IsHighCouncillor, relay.name), true, "a signed High Councillor")
	eq(w:As(viewer, viewer.ns.ChurchCount.IsTopRelay, relay.name), true)
	eq(w:As(viewer, viewer.ns.ChurchCount.IsTopRelay, other.name), false, "an Apostle: no relay")
	-- The author's top 3 (the apostle first): heard by the apostle's client and the councillor's only.
	local B36 = viewer.ns.Arena.B36
	local at = w.clock
	local word = ("NR~1~t~%s~%s,%s~-"):format(B36(at), apostle.short, other.short)
	eq(TakeTop(w, apostle, N.author, word), true, "the author's word")
	eq(TakeTop(w, relay, N.author, word), true)
	w:Run(3)
	eq(apostle.ns.ArenaProfile.Pick().frame, "apostle-1", "the gold cross switched on")
	w:As(apostle, apostle.ns.HonorsNet.CloseLetter, false)
	-- He wears the red cross: his own screen alone; his pick, the one everyone else is told, the gold one.
	local mine, theirs = Frames(w, apostle), Frames(w, viewer)
	Later()
	eq(PE(w, apostle).PickFrame("apostle-red"), true)
	eq(apostle.ns.ArenaProfile.Pick().frame, "apostle-1", "his pick: the cross he holds")
	w:Run(3)
	mine.B.Refresh("player", true)
	eq(mine.Shown("player"), MEDIA .. "cross-red", "the red cross on his own screen")
	viewer.target = apostle.name
	theirs.B.Refresh("target", true)
	-- What was reported: the viewer knows his pick, but no top 3 holds it here, so no frame shows.
	eq(w:As(viewer, viewer.ns.ArenaProfile.Of, apostle.name).frame, "apostle-1", "his pick heard")
	eq(w:As(viewer, viewer.ns.ChurchCount.Top3), nil, "never online with the author's")
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, apostle.name, apostle.guid).frame, "rank")
	eq(theirs.Shown("target"), nil, "no frame")
	-- An Apostle's word (Apostles rank Apostles): refused.
	local ok, why = TakeTop(w, viewer, other.name, ("NR~1~t~%s~%s,%s~-"):format(B36(w.clock), other.short, apostle.short))
	eq(ok, false); eq(why, "root")
	eq(w:As(viewer, viewer.ns.ChurchCount.Top3), nil)
	-- The councillor's relay, TOP_EVERY and its grace after the word it heard: the author's word as it came.
	local C = relay.ns.ChurchCount
	w:Run(C.TOP_EVERY + C.TOP_GRACE)
	eq(w:As(relay, C.RelayTop, w.clock), true)
	local said = relay.churchSent[#relay.churchSent - 1]
	eq(said.dist, "CHANNEL"); eq(said.text, word, "its own time and names")
	eq(relay.churchSent[#relay.churchSent].dist, "GUILD")
	eq(TakeTop(w, viewer, relay.name, said.text), true, "taken from the councillor")
	-- No refresh of the test's: the newly taken word (CHURCH_TOP_CHANGED, then HONORS_CHANGED) redraws it.
	eq(theirs.Shown("target"), MEDIA .. "cross-gold", "the gold cross he holds, to everyone else")
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, apostle.name, apostle.guid).frame, "apostle-1")
	mine.B.Refresh("player", true)
	eq(mine.Shown("player"), MEDIA .. "cross-red", "still red on his own screen alone")
	-- An older word, a relay's too: never over it.
	ok, why = TakeTop(w, viewer, relay.name, ("NR~1~t~%s~%s~-"):format(B36(at - 60), other.short))
	eq(ok, false); eq(why, "older")
	eq(w:As(viewer, viewer.ns.ChurchCount.Top3).at, at)
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, apostle.name, apostle.guid).frame, "apostle-1")
	W3.NoErrors(w)
end)

-- A treasury book (Treasury.DonationRecords, the money part's) on client c: rows of { name, money }.
local function Book(w, c, rows)
	local out = {}
	for i, r in ipairs(rows) do out[i] = { name = r[1], money = r[2], t = w.clock - 40 * DAY } end
	local real = c.ns.Treasury
	rawset(c.ns, "Treasury", setmetatable({ DonationRecords = function() return out end, RankingShown = function() return false end },
		{ __index = real }))
end
-- The cornucopia (all time's 1st donor) as `name`'s pick, his profile's word as client c hears it.
local function Picks(w, c, from, frame)
	w:As(c, function()
		c.ns.Arena.Inject("CHANNEL", from.name, "AP~L1~" .. table.concat({ "-", "WA", "1", "2", "60", "0.0", "-", "0", frame, "-",
			c.ns.Arena.B36(w.clock) }, "~"))
	end)
end
local function Relayed(w, c) return #w:Sent{ from = c, type = "ID", dist = "CHANNEL" } end

test("1.3.4 honours relayed: the King's client no longer puts its own book's top 3 over the Treasurer's donors' word; where none of the Treasurer's is known (or his last is past 30 days) it still works one out", function()
	local w, cast = W3.New({ more = { { "treasurer", N.treasurer, { guild = World.KING_GUILD } }, { "councillor", N.councillor } } })
	local tr, king, viewer, A, B, relay = cast.treasurer, cast.king, cast.spectator, cast.A, cast.B, cast.councillor
	Book(w, tr, { { A.short, 500000 }, { B.short, 300000 }, { viewer.short, 100000 } })
	Book(w, king, { { B.short, 900000 }, { viewer.short, 50000 } })
	-- None of the Treasurer's known yet (as on a side with no Treasurer): the King's own, as before.
	eq(HN(w, king).SendDonors(true), true, "no Treasurer's word known: the King's client works one out")
	w:Run(0)
	eq(HN(w, viewer).Donors().all[1], B.name)
	-- A word the King's client worked out itself is no relay's to say again (only the Treasurer's is).
	eq(HN(w, relay).Donors().all[1], B.name)
	local said, none = HN(w, relay).RelayDonors()
	eq(said, false); eq(none, "none")
	-- The Treasurer's word: everyone's, the King's client's too.
	w:Run(30)
	eq(HN(w, tr).SendDonors(true), true)
	w:Run(0)
	eq(HN(w, viewer).Donors().all[1], A.name)
	eq(HN(w, king).Donors().all[1], A.name)
	-- The King's client again: it works out none now, and the Treasurer's top 3 stays everywhere.
	w:Run(30)
	local sent = #w:Sent{ from = king, type = "ID" }
	local ok, why = HN(w, king).SendDonors(true)
	eq(ok, false); eq(why, "treasurer")
	w:Run(0)
	eq(#w:Sent{ from = king, type = "ID" }, sent, "nothing of his book's sent")
	eq(HN(w, viewer).Donors().all[1], A.name, "the Treasurer's top 3 stays")
	eq(HN(w, viewer).Holdings(A.name)[1].key, "donor-top-1")
	-- The Treasurer gone, his last word past DONOR_TREASURER_DAYS: the King's own again.
	w:Logout(tr)
	w.clock = w.clock + (king.ns.HonorsNet.DONOR_TREASURER_DAYS + 1) * DAY
	eq(HN(w, king).SendDonors(true), true, "the Treasurer's last word is past 30 days")
	w:Flush()
	eq(HN(w, viewer).Donors().all[1], B.name)
	W3.NoErrors(w)
end)

test("1.3.4 honours relayed: a High Councillor's client says the Treasurer's donors' word again, as it came, to a client that logged in after it: its cornucopia shows; none while the Treasurer's client says it, about one a DONOR_EVERY, the King's last; an older word never replaces a newer one", function()
	local w, cast = W3.New({ more = { { "treasurer", N.treasurer, { guild = World.KING_GUILD } }, { "councillor", N.councillor },
		{ "councillor2", N.councillor2 } } })
	local tr, king, relay, relay2, A = cast.treasurer, cast.king, cast.councillor, cast.councillor2, cast.A
	-- (Each relay's own jitter: the second councillor a minute after the first.)
	relay.ns.HonorsNet.random = function(a) return a end
	relay2.ns.HonorsNet.random = function(a) return a + 60 end
	king.ns.HonorsNet.random = function(a) return a end
	eq(w:As(relay, relay.ns.HonorsNet.IsDonorRelay, relay.name), true)
	eq(w:As(relay, relay.ns.HonorsNet.IsDonorRelay, tr.name), false, "the Treasurer's characters: his own word")
	eq(w:As(relay, relay.ns.HonorsNet.IsDonorRelay, A.name), false)
	Book(w, tr, { { A.short, 500000 }, { cast.B.short, 300000 }, { cast.spectator.short, 100000 } })
	-- While the Treasurer's client says it (every DONOR_EVERY), no relay speaks.
	w:Run(4 * tr.ns.HonorsNet.DONOR_EVERY)
	local t0 = HN(w, relay).Donors().t
	eq(HN(w, relay).Donors().all[1], A.name)
	eq(Relayed(w, relay) + Relayed(w, relay2) + Relayed(w, king), 0, "the Treasurer's client is online")
	-- He logs out; a client logs in that never heard him.
	w:Logout(tr)
	local late = w:Client(N.bettor3)
	W3.Rules(w, late)
	eq(HN(w, late).Donors(), nil, "never heard the Treasurer")
	Picks(w, late, A, "donor-top-1")
	eq(HN(w, late).Verified(A.name, A.guid).frame, "rank", "his cornucopia: not shown yet")
	-- The first councillor's relay, DONOR_EVERY and its grace after the Treasurer's last word.
	local HNr = relay.ns.HonorsNet
	w:Run(HNr.DONOR_EVERY + HNr.DONOR_GRACE)
	eq(Relayed(w, relay), 1, "said once")
	eq(#w:Sent{ from = relay, type = "ID", dist = "GUILD" }, 1, "and on GUILD")
	local d = HN(w, late).Donors()
	eq(d.t, t0, "the Treasurer's time, never the relay's")
	eq(d.all[1], A.name); eq(d.from, relay.name, "who it came from: the relay")
	eq(HN(w, late).Verified(A.name, A.guid).frame, "donor-top-1", "the cornucopia shows")
	eq(HN(w, late).Holdings(A.name)[1].art, "cornucopia-gold")
	-- About one a DONOR_EVERY: the first councillor's; the second and the King heard it.
	w:Run(4 * HNr.DONOR_EVERY)
	local total = Relayed(w, relay) + Relayed(w, relay2) + Relayed(w, king)
	assert(total >= 3 and total <= 5, "about one a DONOR_EVERY: " .. total)
	eq(Relayed(w, relay2), 0, "the second councillor heard the first")
	eq(Relayed(w, king), 0, "the King's goes last")
	-- The councillors gone: the King's client says it (the Treasurer's, never its own book's).
	w:Logout(relay); w:Logout(relay2)
	w:Run(2 * HNr.DONOR_EVERY + HNr.DONOR_KING_AFTER)
	assert(Relayed(w, king) >= 1, "the King's alone")
	for _, s in ipairs(w:Sent{ from = king, type = "ID" }) do
		assert(s.msg:find(late.ns.Arena.B36(t0), 1, true), "the Treasurer's word: " .. s.msg)
	end
	-- An older word, a relay's too: never over the newer one.
	local refused = late.ns.HonorsNet.Stats().refused.older or 0
	w:As(late, function()
		late.ns.Arena.Inject("CHANNEL", relay2.name, "ID~L1~" .. table.concat({ late.ns.Arena.B36(t0 - 60), late.ns.Arena.B36(1), "-",
			cast.spectator.short }, "~"))
	end)
	eq(late.ns.HonorsNet.Stats().refused.older, refused + 1)
	eq(HN(w, late).Donors().all[1], A.name)
	W3.NoErrors(w)
end)
