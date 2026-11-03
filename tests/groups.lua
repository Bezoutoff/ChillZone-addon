local ns, test, eq, H = ...
local WithBoard, AsSoldier = H.WithBoard, H.AsSoldier

print("Groups.lua: group listings on the Board, applications, invites")

-- The Board's harness (tests/run.lua's WithBoard), with the groups' own state cleared before and
-- after, their redraw at once, and the game's invite and group state stubbed.
local function WithGroups(fn)
	WithBoard(function(w, B)
		local G = ns.Groups
		local saved = { after = G.after, random = G.random, party = C_PartyInfo, invite = InviteUnit, members = GetNumGroupMembers,
			inGroup = IsInGroup, leader = UnitIsGroupLeader, count = GetNumQuestLogEntries, title = GetQuestLogTitle,
			unitFull = UnitFullName, unitName = UnitName, unitClass = UnitClass, inRaid = IsInRaid, split = ns.splitNames, zone = GetRealZoneText,
			kings = ns.KingsScreen }
		local ok, err = pcall(function()
			G.Reset()
			w.invited = {}
			G.after = function(_, _, f) return f() end
			G.random = function(a) return a or 0 end
			C_PartyInfo = { InviteUnit = function(name) w.invited[#w.invited + 1] = name end }
			InviteUnit = nil
			-- (The game's party units: w.party = { { name, second, class file } }, ourselves not among
			-- them; w.raid, a raid's units, ourselves among them. UnitFullName answers as the client
			-- does: on WoW: Forever (ns.splitNames, which a test sets) the second value is the
			-- surname, "Brenna", "Stoutheart" (tests/run.lua's "WoW: Forever names"); elsewhere it is
			-- the realm, none on ours.)
			w.party = {}
			GetNumGroupMembers = function() return w.members or (w.raid and #w.raid) or (#w.party > 0 and #w.party + 1 or 0) end
			IsInGroup = function() return GetNumGroupMembers() > 0 end
			IsInRaid = function() return w.raid ~= nil end
			local playerClass = UnitClass
			local function Unit(unit)
				local i = tostring(unit):match("^party(%d)$")
				if i then return w.party[tonumber(i)] end
				i = tostring(unit):match("^raid(%d+)$")
				return i and w.raid and w.raid[tonumber(i)] or nil
			end
			UnitFullName = function(unit)
				local m = Unit(unit)
				if m then return m[1], m[2] ~= "" and m[2] or nil end
				return saved.unitFull(unit)
			end
			-- (UnitName answers the same way on Forever: the surname where the realm goes.)
			UnitName = function(unit)
				local m = Unit(unit)
				if m then return m[1], m[2] ~= "" and m[2] or nil end
				if saved.unitName then return saved.unitName(unit) end
			end
			ns.splitNames = nil
			saved.classNames = LOCALIZED_CLASS_NAMES_MALE
			LOCALIZED_CLASS_NAMES_MALE = { PRIEST = "Priest", MAGE = "Mage", WARRIOR = "Warrior" }
			UnitClass = function(unit)
				local m = Unit(unit)
				if m then return m[3], m[3] end
				return playerClass(unit)
			end
			UnitIsGroupLeader = function() return not w.notLeader end
			w.quests = {}
			w.sounds = 0
			saved.alert = ns.PlayAlert
			ns.PlayAlert = function(tone, kind) if kind == "groups" then w.sounds = w.sounds + 1 end return true end
			GetNumQuestLogEntries = function() return #w.quests end
			GetQuestLogTitle = function(i)
				local q = w.quests[i]
				if not q then return nil end
				return q.title, q.level, q.group or 0, q.header or false, false, false, 0, q.id
			end
			fn(w, G, B)
		end)
		G.after, G.random, C_PartyInfo, InviteUnit, GetNumGroupMembers = saved.after, saved.random, saved.party, saved.invite, saved.members
		IsInGroup, UnitIsGroupLeader, GetNumQuestLogEntries, GetQuestLogTitle = saved.inGroup, saved.leader, saved.count, saved.title
		UnitFullName, UnitName, UnitClass, IsInRaid, ns.splitNames, GetRealZoneText = saved.unitFull, saved.unitName, saved.unitClass, saved.inRaid, saved.split, saved.zone
		ns.KingsScreen, LOCALIZED_CLASS_NAMES_MALE = saved.kings, saved.classNames
		if saved.alert then ns.PlayAlert = saved.alert end
		G.Reset()
		if not ok then error(err, 0) end
	end)
end

-- A listing as another player's addon sends it.
local function Listing(id, guild, kind, target, need, age, note, title, every)
	return ns.Groups.Encode({ id = id, guild = guild, kind = kind, target = target, level = 30, class = "WA", need = need or "113",
		size = 2, every = every or 10, age = age or 0, title = title, note = note })
end
local function Texts(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = tostring(l.text) .. " | " .. tostring(l.right or "") end
	return table.concat(out, "\n")
end
local function Line(lines, text)
	for _, l in ipairs(lines) do if l.text and l.text:find(text, 1, true) then return l end end
	return nil
end
-- A tooltip's lines, as text.
local function Tip(line)
	local out = {}
	line.tooltip({ AddLine = function(_, text) out[#out + 1] = tostring(text) end })
	return table.concat(out, "\n")
end
local function LastWhisper(w) return w.whispered[#w.whispered] end
local function Sent(w, prefix)
	for i = #w.sent, 1, -1 do if w.sent[i].msg:sub(1, #prefix) == prefix then return w.sent[i] end end
	return nil
end

test("1.4.0 groups: a listing's message, its checks, its words made safe; later fields are left for later versions", function()
	local G = ns.Groups
	local msg = G.Encode({ id = "a7", guild = "Olympus II", kind = "D", target = "DM", level = 18, class = "PR", need = "103", size = 2,
		every = 10, age = 3, note = " need |cffff0000heals|r~now " })
	eq(msg, "GL~a7~Olympus II~D~DM~18~PR~103~2~~~10~3~~need cffff0000heals r now")
	local e = G.Decode(msg)
	eq(e.kind, "D"); eq(e.target, "DM"); eq(e.need, "103"); eq(e.size, 2); eq(e.age, 3); eq(e.title, ""); eq(e.note, "need cffff0000heals r now")
	-- A quest carries its title (cut at 40 bytes); another kind's title is never read.
	e = G.Decode(G.Encode({ id = "q", guild = "Olympus II", kind = "Q", target = "1234", level = 30, need = "012", size = 1, every = 10, age = 0,
		title = "The Defias Brotherhood " .. string.rep("x", 40) }))
	eq(e.target, "1234"); eq(#e.title, 40)
	eq(G.Decode("GL~a~Olympus II~D~DM~18~PR~113~1~~~10~0~smuggled~hi").title, "", "a dungeon has no title")
	eq(G.Decode("GL~a~Olympus II~R~MC~60~PR~+++~12~~~10~0~~hi~future").note, "hi", "fields after the note: later versions'")
	-- An unknown place of a later version still shows, as Other.
	e = G.Decode("GL~a~Olympus II~D~NEWDG~18~PR~113~1~~~10~0~~")
	eq(G.Target(e.kind, e.target, e.title), ns.L.GROUPS_OTHER)
	eq(G.Target("D", "MC"), ns.L.GROUPS_OTHER, "a raid's key is no dungeon")
	for _, bad in ipairs({
		"GL~ABC~Olympus II~D~DM~18~PR~113~1~~~10~0~~", "GL~a~Olympus II~X~DM~18~PR~113~1~~~10~0~~", "GL~a~Olympus II~D~dm~18~PR~113~1~~~10~0~~",
		"GL~a~Olympus II~Q~DM~18~PR~113~1~~~10~0~~", "GL~a~Olympus II~Q~0~18~PR~113~1~~~10~0~~", "GL~a~Olympus II~D~DM~18~PR~11~1~~~10~0~~",
		"GL~a~Olympus II~D~DM~18~PR~1a3~1~~~10~0~~", "GL~a~Olympus II~D~DM~0~PR~113~1~~~10~0~~", "GL~a~Olympus II~D~DM~18~Pr~113~1~~~10~0~~",
		"GL~a~Olympus II~D~DM~18~PR~113~0~~~10~0~~", "GL~a~Olympus II~D~DM~18~PR~113~41~~~10~0~~", "GL~a~Olympus II~D~DM~18~PR~113~1~~~31~0~~",
		"GL~a~Olympus II~D~DM~18~PR~113~1~~~10~61~~", "GL~a~Olympus II~Q~12~18~PR~113~1~~~10~31~~", "GL~a~~D~DM~18~PR~113~1~~~10~0~~",
		"GL~a~Olympus II~D~DM~18~PR~113~1~~~10", "G1~a~Olympus II~D~42~PR~10~3~~", 42 }) do
		eq(G.Decode(bad), nil, tostring(bad))
	end
	-- 1.4.0: a minimum level (2-99, or empty for any); a quest by a typed name (its target 0, its
	-- title the name; never without one).
	e = G.Decode(G.Encode({ id = "m", guild = "Olympus II", kind = "D", target = "SM", level = 30, need = "113", size = 1, every = 10, age = 0, min = 30 }))
	eq(e.min, 30)
	eq(G.Decode(G.Encode({ id = "m", guild = "Olympus II", kind = "D", target = "SM", level = 30, need = "113", size = 1, every = 10, age = 0, min = 1 })).min, nil, "1: anyone")
	for _, bad in ipairs({ "1", "100", "ab", "5x" }) do
		eq(G.Decode("GL~a~Olympus II~D~DM~18~PR~113~1~" .. bad .. "~~10~0~~"), nil, "min " .. bad)
	end
	e = G.Decode(G.Encode({ id = "t", guild = "Olympus II", kind = "Q", target = "0", level = 30, need = "012", size = 1, every = 10, age = 0, title = "Mor'Ladim" }))
	eq(e.target, "0"); eq(G.Target(e.kind, e.target, e.title), "Mor'Ladim")
	-- A quest's zone (cut at 30 bytes, made safe); another kind's never read; every 5 to 30 minutes.
	e = G.Decode(G.Encode({ id = "z", guild = "Olympus II", kind = "Q", target = "176", level = 11, need = "012", size = 1, every = 5, age = 0,
		title = "Kill Hogger", zone = "Elwynn |cffff0000Forest~" .. string.rep("x", 40) }))
	eq(e.every, 5); eq(#e.zone, 30); assert(e.zone:find("^Elwynn cffff0000Forest"), e.zone)
	eq(G.Decode("GL~a~Olympus II~D~DM~18~PR~113~1~~Elwynn~10~0~~").zone, "", "a dungeon has no zone")
	eq(G.Decode("GL~a~Olympus II~D~DM~18~PR~113~1~~~4~0~~"), nil, "every 4: too often")
	eq(G.NeedShort("113"), "1T 1H 3D"); eq(G.NeedShort("0++"), "H+ D+"); eq(G.NeedShort("000"), ns.L.GROUPS_FULL)
	-- Who else is in a group (GM, review of PR #62): how many, by class and role, never a name.
	local counts = G.MemberCounts({ { name = "Brenna Stoutheart-Realm", class = "PR", role = "H" }, { name = "Cora-Other", class = "MA" },
		{ name = "Dora-Realm", class = "PR", role = "H" }, { name = "Eda-Realm", class = "" } })
	local gm = G.EncodeMembers("a7", counts)
	eq(gm, "GM~a7~---1,MA-1,PRH2", "an unknown class, a mage of no role set, two priest healers")
	assert(not gm:find("Brenna", 1, true) and not gm:find("Cora", 1, true), "no name travels")
	local m = G.DecodeMembers(gm)
	eq(m.id, "a7"); eq(m.total, 4); eq(#m.counts, 3)
	eq(m.counts[1].class, ""); eq(m.counts[1].role, nil); eq(m.counts[1].count, 1)
	eq(m.counts[2].class, "MA"); eq(m.counts[2].role, nil)
	eq(m.counts[3].class, "PR"); eq(m.counts[3].role, "H"); eq(m.counts[3].count, 2)
	-- The most a raid can say (39 others, each of a class and role of its own): one message.
	local many, classes = {}, { "", "WA", "PA", "HU", "RO", "PR", "SH", "MA", "WL", "DR" }
	for _, class in ipairs(classes) do for _, role in ipairs({ "T", "H", "D", false }) do
		if #many < 39 then many[#many + 1] = { name = "x", class = class, role = role or nil } end
	end end
	gm = G.EncodeMembers("zz", G.MemberCounts(many))
	assert(#gm <= 250, "one message: " .. #gm)
	eq(G.DecodeMembers(gm).total, 39)
	eq(#G.DecodeMembers("GM~a7~").counts, 0, "nobody else: the counts emptied")
	-- (Review of PR #62, B2: GM travels without the logged API, so it takes no words at all: a
	-- modified client's sentences, a name, more than 39, a pair twice, a count of 0 are refused.)
	for _, bad in ipairs({ "GM~a7~0~buy gold at some site dot com now:WA:T,another sentence of words here:PR:H",
		"GM~a7~0~Name:PR:", "GM~a7~Aldric:PR:H", "GM~a7~PRH0", "GM~a7~PRX1", "GM~a7~PrH1", "GM~a7~PRH100", "GM~a7~PRH20,MAD20",
		"GM~a7~PRH1,PRH1", "GM~a7~PRH1,", "GM~a7~,PRH1", "GM~a7~-H1", "GM~ABC~PRH1", "GM~a7~x~", 42 }) do
		eq(G.DecodeMembers(bad), nil, tostring(bad))
	end
	-- The longest it gets: one message.
	local worst = G.Encode({ id = "zz", guild = string.rep("\195\169", 24), kind = "Q", target = "9999999", level = 60, class = "WA", need = "+++",
		size = 40, min = 60, zone = string.rep("\195\169", 15), every = 30, age = 29, title = string.rep("\195\169", 30), note = string.rep("\195\169", 30) })
	assert(#worst <= 250, "one message: " .. #worst)
	assert(G.Decode(worst), "the longest decodes")
	-- An application: a role, the applicant's level and class, a note.
	local a = G.DecodeApply(G.EncodeApply("a7", "Olympus Zeus", "H", 31, "PR", "|cff00ff00hi~"))
	eq(a.role, "H"); eq(a.level, 31); eq(a.note, "cff00ff00hi")
	eq(G.DecodeApply("GA~a7~Olympus Zeus~X~31~PR~"), nil, "no such role")
	eq(G.DecodeApply("GA~a7~~T~31~PR~"), nil, "no guild")
	-- What a need says.
	eq(G.NeedText("113"), "Tank, Healer, Damage x3")
	eq(G.NeedText("0++"), "Healer +, Damage +")
	eq(G.NeedText("000"), ns.L.GROUPS_NEED_NONE)
	-- A 1.1 client's Board reads none of it: GL is no flag.
	eq(ns.Board.Decode(msg), nil)
end)

test("1.4.0 groups: the Board's strip; the flags page is as it was; a leader lists a dungeon group (where, roles, a note logged)", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		B.HandlePost("CHANNEL", "Aldric-Realm", ns.Board.Encode({ id = "f1", guild = "Olympus Zeus", flag = "R", level = 30, class = "WA", every = 10, age = 0, note = "lf raid" }))
		-- The Flags section first: the strip, then the Board's page as before.
		local lines = B.Lines()
		assert(lines[2].nav, "the strip under the way back")
		eq(#lines[2].nav, 5); eq(lines[2].nav[1].text, ns.L.GROUPS_TAB_FLAGS); eq(lines[2].nav[1].selected, true)
		assert(Line(lines, "lf raid"), "the flags as before")
		assert(Line(lines, ns.L.BOARD_RAISE:format(ns.L.BOARD_FLAG_D)), "raising a flag as before")
		-- Dungeons: nothing listed; the way to list one.
		lines[2].nav[2].onClick()
		eq(G.View(), "D")
		lines = B.Lines()
		assert(not Line(lines, "lf raid"), "no flags here")
		assert(Line(lines, ns.L.GROUPS_EMPTY), Texts(lines))
		Line(lines, ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_D)).onClick()
		-- Where: the dungeons, by level.
		lines = B.Lines()
		local dm = Line(lines, "> Deadmines")
		assert(dm and dm.right:find(ns.L.GROUPS_FROM_LEVEL:format(16), 1, true), Texts(lines))
		assert(not Line(lines, "Molten Core"), "no raid among the dungeons")
		dm.onClick()
		-- The roles: a click steps each one; damage from 3 to 4, then round to 0 and 1.
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_WHERE:format("|cffffd200Deadmines|r")), Texts(lines))
		local dmg = Line(lines, ns.L.GROUPS_WANTED:format(ns.L.GROUPS_ROLE_D, "|cffffd2003|r"))
		assert(dmg, Texts(lines))
		dmg.onClick(); dmg.onClick(); dmg.onClick()
		eq(G.Composing().need, "111")
		Line(B.Lines(), ns.L.GROUPS_WANTED:format(ns.L.GROUPS_ROLE_T, "|cffffd2001|r")).onClick()
		eq(G.Composing().need, "211")
		-- Post: the dialog says what goes out and to whom, before anything does.
		eq(#w.sent, 0, "nothing sent while composing")
		Line(B.Lines(), ns.L.GROUPS_POST).onClick()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_GROUPS_LIST")
		assert(p.a:find("Deadmines", 1, true) and p.a:find(ns.L.GROUPS_NEEDS:format("Tank x2, Healer, Damage"), 1, true), p.a)
		eq(p.b, ns.Comm.Audience())
		G.ConfirmList(p.data, "  bring |cffffffffwater ")
		G.ConfirmList(p.data, "twice") -- (Enter and the button both answer: once)
		local s = Sent(w, "GL~")
		eq(s.dist, "CHANNEL"); eq(s.logged, true, "a note goes logged")
		local e = G.Decode(s.msg)
		eq(e.kind, "D"); eq(e.target, "DM"); eq(e.need, "211"); eq(e.note, "bring cffffffffwater"); eq(e.guild, "Olympus II"); eq(e.size, 1)
		eq(#w.sent, 1, "one listing")
		eq(G.Mine().id, e.id)
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_MINE:format("Deadmines")), Texts(lines))
		assert(Line(lines, ns.L.GROUPS_NO_APPLICANTS))
		-- Raids say ours is under Dungeons.
		G.Show("R", true)
		assert(Line(B.Lines(), ns.L.GROUPS_MINE_ELSEWHERE:format(ns.L.GROUPS_KIND_D)))
		-- A second listing waits LIST_GAP; one without a note goes plain.
		eq(select(2, G.Post("R", "MC", nil, "+++", "")), "wait")
		w.clock = w.clock + G.LIST_GAP
		assert(G.Post("R", "MC", nil, "+++", ""))
		eq(w.sent[#w.sent - 1].msg, "GX~" .. e.id, "the old one comes down first")
		eq(w.sent[#w.sent].logged, false)
		eq(G.Mine().kind, "R")
	end)
end)

test("1.4.0 groups: others' listings on the Board, by kind; only Olympus guilds, never an ignored or netted-off player; lowered at once", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "103", 2, "lfm sfk"))
		G.HandlePost("CHANNEL", "Brenna-Realm", Listing("b1", "Olympus Zeus", "R", "MC", "+++", 0))
		G.HandlePost("CHANNEL", "Outsider-Realm", Listing("c1", "Horde Guild", "D", "DM"))
		G.HandlePost("CHANNEL", "Troll-Realm", Listing("t1", "Olympus Zeus", "D", "DM"))
		G.HandlePost("GUILD", "Cora-Realm", Listing("g1", "Olympus Zeus", "D", "DM"))
		G.HandlePost("WHISPER", "Dora-Realm", Listing("d1", "Olympus Zeus", "D", "DM"))
		eq(#G.List("D"), 1); eq(#G.List("R"), 1); eq(#G.List(), 2)
		G.Show("D", true)
		local lines = B.Lines()
		-- (PR #62 review: the row holds where and who; what it needs, short, on the right where it is never
		-- cut; the rest, the note too, in its tooltip and its card.)
		local card = Line(lines, "[Shadowfang Keep]")
		assert(card, Texts(lines))
		assert(card.text:find("Aldric", 1, true), card.text)
		assert(card.right:find("1T 3D", 1, true) and card.right:find("2/5", 1, true), card.right)
		local tip = Tip(card)
		assert(tip:find(ns.L.GROUPS_NEEDS:format("Tank, Damage x3"), 1, true) and tip:find("lfm sfk", 1, true), tip)
		eq(lines[2].nav[2].text, ns.L.GROUPS_TAB_D .. " (1)")
		eq(lines[2].nav[3].text, ns.L.GROUPS_TAB_R .. " (1)")
		-- The Realm's link counts them.
		assert(B.LinkLine().right:find(ns.L.GROUPS_LINK:format(2), 1, true))
		-- The search reads where, who and the note.
		assert(Line(B.Lines(ns.Fold("shadowfang")), "[Shadowfang Keep]"))
		assert(Line(B.Lines(ns.Fold("lfm")), "[Shadowfang Keep]"), "the note is searched though not shown on the row")
		assert(not Line(B.Lines(ns.Fold("molten")), "[Shadowfang Keep]"))
		-- A refresh updates it in place; its words without the logged API are dropped.
		w.logged = false
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "003", 3, "lfm sfk"))
		eq(G.List("D")[1].need, "003"); eq(G.List("D")[1].note, "")
		w.logged = true
		-- Lowered: gone, and a late refresh of it doesn't bring it back.
		G.HandleLower("CHANNEL", "Aldric-Realm", "GX~a1")
		eq(#G.List("D"), 0)
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "003", 4))
		eq(#G.List("D"), 0, "a lowered id stays down")
		-- Its hour over, a listing leaves; a quest's after half an hour.
		G.HandlePost("CHANNEL", "Cora-Realm", Listing("q1", "Olympus Zeus", "Q", "555", "012", 25, nil, "Kill Hogger"))
		eq(#G.List("Q"), 1)
		w.clock = w.clock + 6 * 60
		eq(#G.List("Q"), 0, "half an hour for a quest")
		eq(#G.List("R"), 1)
		w.clock = w.clock + 55 * 60
		eq(#G.List("R"), 0, "an hour for the rest, refreshed or not")
	end)
end)

test("1.4.0 groups: apply with a role the group needs (the note logged, to the leader alone); withdraw; the leader's answers", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "103", 0))
		G.Show("D", true)
		Line(B.Lines(), "Shadowfang Keep").onClick()
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)), Texts(lines))
		assert(not Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_H)), "no healer wanted: no healer's button")
		Line(lines, ns.L.GROUPS_WHISPER:format("Aldric")).onClick()
		eq(w.told[#w.told], "Aldric", "the whisper is the player's own")
		eq(#w.whispered, 0)
		Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)).onClick()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_GROUPS_APPLY")
		eq(p.a, ns.L.GROUPS_APPLY_WHAT:format(ns.L.GROUPS_ROLE_T, "Shadowfang Keep", "Aldric"))
		G.ConfirmApply(p.data, "prot war, 25")
		local wh = LastWhisper(w)
		eq(wh.to, "Aldric-Realm"); eq(wh.logged, true)
		local a = G.DecodeApply(wh.msg)
		eq(a.id, "a1"); eq(a.role, "T"); eq(a.guild, "Olympus II"); eq(a.note, "prot war, 25"); eq(a.level, 42); eq(a.class, "PR")
		eq(#w.sent, 0, "nothing on the channel")
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_APP_SENT:format(ns.L.GROUPS_ROLE_T)), Texts(lines))
		-- A role the group doesn't need is refused; so is a second application too soon.
		eq(select(2, G.Apply("Aldric-Realm", "H")), "role")
		eq(select(2, G.Apply("Aldric-Realm", "D")), "wait")
		-- An answer from anyone but that leader, or for another listing, changes nothing.
		G.HandleAnswer("WHISPER", "Brenna-Realm", "GR~a1~I")
		G.HandleAnswer("WHISPER", "Aldric-Realm", "GR~zz~I")
		G.HandleAnswer("CHANNEL", "Aldric-Realm", "GR~a1~I")
		eq(G.Applied("Aldric-Realm").state, "sent")
		G.HandleAnswer("WHISPER", "Aldric-Realm", "GR~a1~I")
		eq(G.Applied("Aldric-Realm").state, "invited")
		assert(Line(B.Lines(), ns.L.GROUPS_APP_INVITED:format(ns.L.GROUPS_ROLE_T)))
		-- Withdrawn: the leader is told.
		Line(B.Lines(), ns.L.GROUPS_WITHDRAW).onClick()
		eq(LastWhisper(w).msg, "GW~a1"); eq(G.Applied("Aldric-Realm"), nil)
		-- Declined, and a listing lowered, end an application.
		w.clock = w.clock + G.APPLY_GAP
		assert(G.Apply("Aldric-Realm", "D"))
		G.HandleAnswer("WHISPER", "Aldric-Realm", "GR~a1~D")
		eq(G.Applied("Aldric-Realm"), nil)
		w.clock = w.clock + G.APPLY_GAP
		assert(G.Apply("Aldric-Realm", "D"))
		G.HandleLower("CHANNEL", "Aldric-Realm", "GX~a1")
		eq(G.Applied("Aldric-Realm"), nil)
		-- Five applications waiting at most.
		for i = 1, 6 do
			G.HandlePost("CHANNEL", "Lead" .. i .. "-Realm", Listing("l" .. i, "Olympus Zeus", "D", "DM", "113", 0))
		end
		for i = 1, 5 do assert(G.Apply("Lead" .. i .. "-Realm", "D")) end
		eq(select(2, G.Apply("Lead6-Realm", "D")), "many")
	end)
end)

test("1.4.0 groups: the leader's applicants (a sound, details on hover); Invite as their role is the game's invite by click; the role comes off when they join, back when they don't; the last role closes the listing", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("D", "DM", nil, "112", "lfm"))
		local id = G.Mine().id
		G.HandleApply("WHISPER", "Aldric-Realm", G.EncodeApply(id, "Olympus Zeus", "T", 20, "WA", "prot"))
		G.HandleApply("WHISPER", "Brenna-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Cora-Realm", G.EncodeApply(id, "Olympus Zeus", "H", 18, "PR", ""))
		-- Not for this listing, not whispered, not of an Olympus guild, ignored: nothing.
		G.HandleApply("WHISPER", "Dora-Realm", G.EncodeApply("zz", "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("CHANNEL", "Dora-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Dora-Realm", G.EncodeApply(id, "Horde Guild", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Troll-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		eq(#G.Applicants(), 3)
		eq(w.sounds, 3, "a sound for each new applicant")
		G.HandleApply("WHISPER", "Aldric-Realm", G.EncodeApply(id, "Olympus Zeus", "T", 20, "WA", "prot"))
		eq(w.sounds, 3, "none for the same one again")
		G.Show("D", true)
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_APPLICANTS:format(3)), Texts(lines))
		local tank = Line(lines, "Aldric")
		assert(tank and tank.text:find(ns.L.GROUPS_ROLE_T, 1, true), Texts(lines))
		local tip = Tip(tank)
		assert(tip:find(ns.L.GROUPS_ROLE_T, 1, true) and tip:find("Olympus Zeus", 1, true) and tip:find("prot", 1, true), tip)
		-- Nothing invites until the leader clicks Invite as their role.
		eq(#w.invited, 0)
		tank.onClick()
		lines = B.Lines()
		Line(lines, "> " .. ns.L.GROUPS_INVITE_AS:format(ns.L.GROUPS_ROLE_T)).onClick()
		eq(w.invited[1], "Aldric")
		eq(LastWhisper(w).to, "Aldric-Realm"); eq(LastWhisper(w).msg, "GR~" .. id .. "~I")
		eq(G.Mine().need, "112", "not before they join")
		assert(Line(B.Lines(), ns.L.GROUPS_PENDING:format("Aldric", ns.L.GROUPS_ROLE_T)), Texts(B.Lines()))
		-- He joins: the tank comes off, his application is done, the listing goes out again.
		w.party = { { "Aldric", "", "WARRIOR" } }
		G.CheckJoins()
		eq(G.Mine().need, "012", "the tank is found")
		eq(#G.Applicants(), 2)
		w.clock = w.clock + G.UPDATE_GAP
		G.Tick()
		eq(G.Decode(Sent(w, "GL~").msg).need, "012", "every Board hears it")
		-- His role shows in our roster; a click changes it (a role switch), and the leader edits the need.
		local row = Line(B.Lines(), "Aldric")
		eq(row.right, "|cff40ff40" .. ns.L.GROUPS_ROLE_T .. "|r")
		row.onClick()
		eq(G.GroupMembers()[1].role, "H")
		Line(B.Lines(), ns.L.GROUPS_WANTED:format(ns.L.GROUPS_ROLE_T, "|cffffd2000|r")).onClick()
		eq(G.Mine().need, "112", "the leader wants a tank again")
		Line(B.Lines(), ns.L.GROUPS_WANTED:format(ns.L.GROUPS_ROLE_H, "|cffffd2001|r")).onClick()
		eq(G.Mine().need, "122")
		G.StepOwnNeed("H"); G.StepOwnNeed("H"); G.StepOwnNeed("H")
		eq(G.Mine().need, "102", "round to 0")
		G.StepOwnNeed("T")
		eq(G.Mine().need, "202")
		G.StepOwnNeed("T"); G.StepOwnNeed("T"); G.StepOwnNeed("T")
		eq(G.Mine().need, "002")
		G.Mine().need = "012"
		-- Declined: told, and off the list.
		G.Decline("Brenna-Realm")
		eq(LastWhisper(w).msg, "GR~" .. id .. "~D")
		eq(#G.Applicants(), 1, "Aldric joined, Brenna declined: Cora waits")
		-- Not the group's leader: no invite, and the player is told why.
		w.members, w.notLeader = 2, true
		eq(select(2, G.Invite("Cora-Realm")), "leader")
		eq(#w.invited, 1)
		w.members, w.notLeader = nil, false
		-- Cora is invited and never comes: two minutes later her role is wanted again, her application waits.
		G.Invite("Cora-Realm")
		w.clock = w.clock + G.INVITE_WAIT
		G.CheckJoins()
		eq(G.Mine().need, "012"); eq(G.Pending()["Cora-Realm"], nil)
		assert(w.printed[#w.printed]:find(ns.L.GROUPS_NOT_JOINED:format("Cora", ns.L.GROUPS_ROLE_H), 1, true), w.printed[#w.printed])
		w.clock = w.clock + 1
		G.Invite("Cora-Realm")
		w.party = { { "Aldric", "", "WARRIOR" }, { "Cora", "", "PRIEST" } }
		G.CheckJoins()
		eq(G.Mine().need, "002")
		-- The last of them: the listing closes, its GX goes, and the ones still waiting are told.
		w.clock = w.clock + G.APPLY_GAP
		G.HandleApply("WHISPER", "Dora-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Eda-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Finn-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.Invite("Dora-Realm"); G.Invite("Eda-Realm")
		assert(G.Mine(), "still listed while they haven't joined")
		w.party = { { "Aldric", "", "WARRIOR" }, { "Cora", "", "PRIEST" }, { "Dora", "", "MAGE" } }
		G.CheckJoins()
		eq(G.Mine().need, "001")
		w.party = { { "Aldric", "", "WARRIOR" }, { "Cora", "", "PRIEST" }, { "Dora", "", "MAGE" }, { "Eda", "", "MAGE" } }
		G.CheckJoins()
		eq(G.Mine(), nil, "every role found: lowered")
		eq(Sent(w, "GX~").msg, "GX~" .. id)
		eq(LastWhisper(w).to, "Finn-Realm"); eq(LastWhisper(w).msg, "GR~" .. id .. "~F")
		-- A party of five, however it filled, takes its listing down; a raid's doesn't.
		w.clock = w.clock + G.LIST_GAP
		w.party = {}
		w.members = 4
		assert(G.Post("D", "DM", nil, "001", ""))
		G.Tick()
		assert(G.Mine(), "four: still listed")
		w.members = 5
		G.Tick()
		eq(G.Mine(), nil, "five: lowered")
		w.clock = w.clock + G.LIST_GAP
		assert(G.Post("R", "MC", nil, "+++", ""))
		G.Tick()
		assert(G.Mine(), "a raid of five goes on")
	end)
end)

test("1.4.0 groups: the Board's ask is answered with our listing; it survives a /reload; it ends after its hour; /oly group", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("R", "MC", nil, "+++", ""))
		local id = G.Mine().id
		-- Someone opens the Board: holders answer with their flag, and ours with the listing.
		B.HandleAsk("CHANNEL", "Asker-Realm", "GQ~")
		for _, t in ipairs(w.later) do if t.where == "board answer" then t.fn() end end
		local wh = LastWhisper(w)
		eq(wh.to, "Asker-Realm"); eq(G.Decode(wh.msg).id, id)
		-- A whispered listing is taken only after our own ask.
		G.HandlePost("WHISPER", "Brenna-Realm", Listing("b1", "Olympus Zeus", "D", "DM"))
		eq(#G.List("D"), 0)
		ns.Comm.joinedAt = w.clock - 60
		assert(B.Ask())
		G.HandlePost("WHISPER", "Brenna-Realm", Listing("b1", "Olympus Zeus", "D", "DM"))
		eq(#G.List("D"), 1)
		-- A /reload keeps our listing and its applicants.
		G.HandleApply("WHISPER", "Aldric-Realm", G.EncodeApply(id, "Olympus Zeus", "H", 60, "PR", "hi"))
		local saved = ns.rdb.groups
		G.Reset()
		ns.rdb.groups = saved
		G.Restore()
		eq(G.Mine().id, id); eq(#G.Applicants(), 1); eq(G.Applicants()[1].note, "hi")
		-- Repeated every interval, lowered after its hour.
		local before = #w.sent
		w.clock = w.clock + 10 * 60
		G.Tick()
		eq(#w.sent, before + 1)
		w.clock = w.clock + 50 * 60
		G.Tick()
		eq(G.Mine(), nil)
		eq(w.sent[#w.sent].msg, "GX~" .. id)
		-- /oly group opens the Board on a kind; off lowers ours.
		B.Slash("group", "raid")
		eq(G.View(), "R"); eq(ns.Views.BoardShown(), true)
		B.Slash("lfg", "")
		eq(G.View(), "flags", "/oly lfg: the flags")
		B.Slash("group", "off")
		B.Slash("group", "nonsense")
		assert(w.printed[#w.printed]:find("/oly group", 1, true), w.printed[#w.printed])
		G.Show("flags", true)
	end)
end)

test("1.4.0 groups: a quest from our own log, its title with it; quests we have come first", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		w.quests = { { title = "Elwynn Forest", header = true }, { title = "Kill Hogger", level = 11, id = 176, group = 3 },
			{ title = "Wolves Across the Border", level = 6, id = 33 } }
		G.Show("Q", true)
		Line(B.Lines(), ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_Q)).onClick()
		local lines = B.Lines()
		assert(not Line(lines, "> Elwynn Forest"), "a header is no quest")
		local hogger = Line(lines, "> Kill Hogger")
		assert(hogger and hogger.right:find(ns.L.GROUPS_GROUP_QUEST, 1, true), Texts(lines))
		hogger.onClick()
		Line(B.Lines(), ns.L.GROUPS_POST).onClick()
		G.ConfirmList(w.popups[#w.popups].data, "")
		local s = Sent(w, "GL~")
		eq(s.logged, true, "a title is words: logged")
		local e = G.Decode(s.msg)
		eq(e.target, "176"); eq(e.title, "Kill Hogger")
		-- Others' quests: the ones in our log first, marked.
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "Q", "999", "012", 0, nil, "Other Quest"))
		w.clock = w.clock + 1
		G.HandlePost("CHANNEL", "Brenna-Realm", Listing("b1", "Olympus Zeus", "Q", "33", "012", 0, nil, "Wolves Across the Border"))
		local list = G.List("Q")
		eq(list[1].sender, "Brenna-Realm")
		assert(G.Card(list[1]).text:find(ns.L.GROUPS_IN_LOG, 1, true))
		assert(not G.Card(list[2]).text:find(ns.L.GROUPS_IN_LOG, 1, true))
	end)
end)

test("1.4.0 groups: English and Portuguese for every string; the help names /oly group", function()
	local pt = {}
	local saved = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales.lua"))("Olympus", pt) end)
	GetLocale = saved
	if not ok then error(err, 0) end
	local n = 0
	for key, en in pairs(ns.L) do
		if type(key) == "string" and key:find("^GROUPS_") then
			n = n + 1
			local br = rawget(pt.L, key)
			assert(type(en) == "string" and en ~= "", "English " .. key)
			assert(type(br) == "string" and br ~= "", "pt-BR " .. key)
			local function Args(s) local out = {} for a in s:gmatch("%%%a") do out[#out + 1] = a end return table.concat(out) end
			eq(Args(br), Args(en), key .. ": format arguments")
		end
	end
	assert(n > 60, "the strings: " .. n)
	assert(ns.L.HELP_GROUPS:find("/oly group", 1, true))
end)

test("1.4.0 groups: a minimum level: the composer starts at the place's own, a click steps it; under it no apply, and the leader takes none", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.Show("D", true)
		G.Compose("D")
		G.ChooseTarget("SM")
		eq(G.Composing().min, 30, "Scarlet Monastery's own level")
		local line = Line(B.Lines(), ns.L.GROUPS_MIN_LINE:format("|cffffd20030|r"))
		assert(line, Texts(B.Lines()))
		line.onClick()
		eq(G.Composing().min, 35)
		for _ = 1, 7 do G.StepMin() end -- (40, 45, 50, 55, 58, 60, then none)
		eq(G.Composing().min, nil, "past 60: none")
		G.StepMin()
		eq(G.Composing().min, 10)
		G.Composing().min = 40
		Line(B.Lines(), ns.L.GROUPS_POST).onClick()
		local p = w.popups[#w.popups]
		assert(p.a:find(ns.L.GROUPS_MIN_TIP:format(40), 1, true), p.a)
		G.ConfirmList(p.data, "")
		eq(G.Decode(Sent(w, "GL~").msg).min, 40)
		-- A level 41 applicant is taken; a level 39 one isn't (its addon would have refused it).
		local id = G.Mine().id
		G.HandleApply("WHISPER", "Low-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 39, "WA", ""))
		G.HandleApply("WHISPER", "High-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 41, "WA", ""))
		eq(#G.Applicants(), 1); eq(G.Applicants()[1].name, "High-Realm")
		-- Someone else's group from level 50: the card says so, and we (42) can't apply.
		G.HandlePost("CHANNEL", "Aldric-Realm", G.Encode({ id = "a1", guild = "Olympus Zeus", kind = "D", target = "BRD", level = 55, class = "WA",
			need = "113", size = 1, min = 50, every = 10, age = 0 }))
		local card = Line(B.Lines(), "[Blackrock Depths]")
		assert(card.right:find(ns.L.GROUPS_MIN_SHORT:format(50), 1, true), card.right)
		assert(Tip(card):find(ns.L.GROUPS_MIN_TIP:format(50), 1, true))
		card.onClick()
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_TOO_LOW:format(50)), Texts(lines))
		assert(not Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)), "no apply under the minimum")
		local before = #w.whispered
		eq(select(2, G.Apply("Aldric-Realm", "T")), "level")
		eq(#w.whispered, before, "nothing sent")
	end)
end)

test("1.4.0 groups: a quest by a typed name (an elite, a rare): its dialog, then the roles; it travels as quest 0 with the name", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.Show("Q", true)
		Line(B.Lines(), ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_Q)).onClick()
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_NO_QUESTS), "an empty log says so")
		Line(lines, ns.L.GROUPS_TYPE_NAME).onClick()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_GROUPS_NAME")
		eq(G.ConfirmName(p.data, "   "), nil, "no name: still choosing")
		p.data.answered = nil
		G.ConfirmName(p.data, "Mor'Ladim |cff00ff00now")
		eq(G.Composing().target, "0"); eq(G.Composing().title, "Mor'Ladim cff00ff00now"); eq(G.Composing().min, nil, "no minimum for a quest")
		Line(B.Lines(), ns.L.GROUPS_POST).onClick()
		G.ConfirmList(w.popups[#w.popups].data, "")
		local s = Sent(w, "GL~")
		eq(s.logged, true)
		local e = G.Decode(s.msg)
		eq(e.target, "0"); eq(e.title, "Mor'Ladim cff00ff00now")
		eq(select(2, G.Post("Q", "0", "", "012", "")), "target", "never without a name")
		-- On another Board it shows by its name, and is never "in your log".
		G.HandlePost("CHANNEL", "Aldric-Realm", (s.msg:gsub("Olympus II", "Olympus Zeus")))
		local card = G.Card(G.List("Q")[1])
		assert(card.text:find("[Mor'Ladim cff00ff00now]", 1, true) and not card.text:find(ns.L.GROUPS_IN_LOG, 1, true), card.text)
	end)
end)

test("1.4.0 groups: who is in a listed group: the leader's GM counts them by class and role, never by name (review of PR #62); on hover and on its card; again when it changes", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		ns.splitNames = true
		assert(G.Post("D", "DM", nil, "113", ""))
		eq(Sent(w, "GM~"), nil, "alone: no GM")
		local id = G.Mine().id
		G.HandleApply("WHISPER", "Brenna Stoutheart-Realm", G.EncodeApply(id, "Olympus Zeus", "H", 20, "PR", ""))
		G.Invite("Brenna Stoutheart-Realm")
		-- She and a friend from the chat (outside Olympus) join; the next send carries the listing
		-- and how many are in it. (Forever's unit names: a first name, then the surname.)
		w.party = { { "Brenna", "Stoutheart", "PRIEST" }, { "Cora", "Wildmane", "MAGE" } }
		w.clock = w.clock + G.UPDATE_GAP
		G.Tick()
		local gm = Sent(w, "GM~")
		assert(gm, "a GM")
		eq(gm.logged, nil, "numbers only: no words to log")
		eq(gm.msg, "GM~" .. id .. "~MA-1,PRH1", "a mage of no role set, a priest healer")
		assert(not gm.msg:find("Brenna", 1, true) and not gm.msg:find("Cora", 1, true), "no name goes out: " .. gm.msg)
		eq(G.Decode(Sent(w, "GL~").msg).size, 3)
		local gl, first = Sent(w, "GL~").msg, gm.msg
		-- Cora leaves; the GM goes again, with the priest alone.
		w.party = { { "Brenna", "Stoutheart", "PRIEST" } }
		w.clock = w.clock + 30
		G.Tick()
		w.clock = w.clock + G.UPDATE_GAP
		G.Tick()
		eq(Sent(w, "GM~").msg, "GM~" .. id .. "~PRH1")
		-- The Board's ask is answered with the GM too.
		B.HandleAsk("CHANNEL", "Asker-Realm", "GQ~")
		for _, t in ipairs(w.later) do if t.where == "board answer" then t.fn() end end
		eq(LastWhisper(w).to, "Asker-Realm"); eq(LastWhisper(w).msg, "GM~" .. id .. "~PRH1")
		-- Another Board (a reader of another Olympus guild: the leader's guild by its claim) shows
		-- the counts in the card's tooltip and on its card.
		G.Reset()
		w.party = {}
		GetGuildInfo = function() return "Olympus Zeus", "Member", 3 end
		ns.me = "Reader-Realm"
		G.HandleMembers("CHANNEL", "Soldier-Realm", first)
		eq(#G.List("D"), 0, "a GM before its listing is nothing")
		G.HandlePost("CHANNEL", "Soldier-Realm", gl)
		G.HandleMembers("GUILD", "Soldier-Realm", first)
		G.HandleMembers("CHANNEL", "Other-Realm", first)
		eq(G.List("D")[1].counts, nil, "only its leader's, only on the channel")
		G.HandleMembers("CHANNEL", "Soldier-Realm", first)
		G.Show("D", true)
		local card = Line(B.Lines(), "[Deadmines]")
		assert(card and card.text:find("Soldier", 1, true), Texts(B.Lines()))
		local tip = Tip(card)
		assert(tip:find(ns.L.GROUPS_IN_GROUP, 1, true) and tip:find(ns.L.GROUPS_COUNT:format("Priest", 1), 1, true) and tip:find(ns.L.GROUPS_ROLE_H, 1, true)
			and tip:find(ns.L.GROUPS_COUNT:format("Mage", 1), 1, true) and tip:find(ns.L.GROUPS_ROLE_UNSET, 1, true), tip)
		card.onClick()
		local lines = B.Lines()
		local priests = Line(lines, ns.L.GROUPS_COUNT:format("Priest", 1))
		assert(priests and priests.right:find(ns.L.GROUPS_ROLE_H, 1, true), Texts(lines))
		assert(not Texts(lines):find("Brenna", 1, true) and not Texts(lines):find("Cora", 1, true), Texts(lines))
		-- The same counts again change nothing.
		local changes = 0
		G.after = function(_, where, f) if where == "groups changed" then changes = changes + 1 end return f() end
		G.HandleMembers("CHANNEL", "Soldier-Realm", first)
		eq(changes, 0, "the same counts: no redraw")
		G.HandleMembers("CHANNEL", "Soldier-Realm", "GM~" .. id .. "~PRH1")
		eq(changes, 1, "new counts: one")
		eq(#G.List("D")[1].counts, 1)
	end)
end)

test("1.4.0 flags for several places: roles and picks after the note (a 1.1 Board reads the plain flag); matching players in each group section", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		-- The composer on the flags page: roles, then places by kind, Any for a whole kind.
		local lines = B.Lines()
		Line(lines, ns.L.GROUPS_FLAG_MULTI).onClick()
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_FLAG_PICK_ONE), "nothing to raise yet")
		assert(not Line(lines, ns.L.BOARD_RAISE:format(ns.L.BOARD_FLAG_D)), "the one-click flags wait")
		G.FlagRole("T"); G.FlagRole("H")
		Line(B.Lines(), "+ " .. ns.L.GROUPS_TAB_D).onClick()
		Line(B.Lines(), "Shadowfang Keep").onClick()
		Line(B.Lines(), "Deadmines").onClick()
		G.FlagOpen("P")
		Line(B.Lines(), ns.L.GROUPS_ANY_P).onClick()
		-- Eight places at most.
		G.FlagOpen("R")
		for _, key in ipairs({ "ZG", "AQ20", "MC", "ONY", "BWL", "AQ40", "NAXX" }) do G.FlagPick("R", key) end
		assert(w.printed[#w.printed]:find(ns.L.GROUPS_FLAG_PICKS_MAX:format(8), 1, true), w.printed[#w.printed])
		G.FlagPick("R", "*")
		G.FlagPick("R", "*")
		Line(B.Lines(), ns.L.GROUPS_FLAG_RAISE).onClick()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_BOARD_RAISE")
		eq(p.a, "Deadmines, Shadowfang Keep, " .. ns.L.GROUPS_ANY_P .. "  (" .. ns.L.GROUPS_ROLE_T .. ", " .. ns.L.GROUPS_ROLE_H .. ")")
		B.Confirm(p.data, "any time tonight")
		local s = Sent(w, "G1~")
		local plain = B.Encode({ id = B.Mine().id, guild = "Olympus II", flag = "D", level = 42, class = "PR", every = s.msg:match("^G1~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~(%d+)"),
			age = 0, note = "any time tonight" })
		eq(s.msg, plain .. "~TH~D:DM,SFK;P:*", "the flag as before, then its roles and picks")
		eq(G.FlagComposing(), false, "raised: the composer closes")
		assert(Line(B.Lines(), ns.L.BOARD_MINE:format("Deadmines, Shadowfang Keep, " .. ns.L.GROUPS_ANY_P)), Texts(B.Lines()))
		-- Read back: a flag with roles and picks; malformed ones are the plain flag.
		local e = B.Decode(s.msg)
		eq(e.flag, "D"); eq(e.roles, "TH"); eq(e.picks, "D:DM,SFK;P:*"); eq(e.note, "any time tonight")
		eq(B.Decode(plain .. "~TH~R:MC").picks, "", "its first pick must be its own kind")
		eq(B.Decode(plain .. "~XX~D:dm").roles, ""); eq(B.Decode(plain .. "~XX~D:dm").picks, "")
		eq(B.Decode(plain .. "~T~P:*;D:DM").picks, "", "kinds in order")
		eq(B.ParsePicks("D:A,B,C,D,E,F,G,H,I"), nil, "nine places")
		-- Someone else's: on the flags page by name and roles; in Dungeons and PvP, not in Raids.
		B.HandlePost("CHANNEL", "Aldric-Realm", s.msg:gsub("^G1~[^~]*", "G1~a1"):gsub("Olympus II", "Olympus Zeus"))
		B.HandlePost("CHANNEL", "Brenna-Realm", B.Encode({ id = "b1", guild = "Olympus Zeus", flag = "R", level = 60, class = "PR", every = 10, age = 0 }))
		local card = Line(B.Lines(), "Aldric")
		assert(card.text:find("[Deadmines, Shadowfang Keep, " .. ns.L.GROUPS_ANY_P .. "]", 1, true) and card.text:find(ns.L.GROUPS_ROLE_T .. ", " .. ns.L.GROUPS_ROLE_H, 1, true), card.text)
		eq(#G.Looking("D"), 1); eq(#G.Looking("P"), 1); eq(#G.Looking("R"), 1); eq(G.Looking("R")[1].sender, "Brenna-Realm", "a plain raid flag")
		eq(#G.Looking("Q"), 0)
		-- With our Deadmines group needing a tank, Aldric fits, first, and Invite is the game's invite.
		B.Lower(true)
		assert(G.Post("D", "DM", nil, "103", "", 16))
		G.Show("D", true)
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_LOOKING:format(1)), Texts(lines))
		local looking = Line(lines, "Aldric")
		assert(looking.text:find(ns.L.GROUPS_FITS, 1, true), looking.text)
		looking.onClick()
		Line(B.Lines(), "> " .. ns.L.GROUPS_INVITE).onClick()
		eq(w.invited[#w.invited], "Aldric")
		-- A Stockade group doesn't fit him (not among his dungeons); a raid section has no invite without a raid listed.
		eq(G.Fits(G.Looking("D")[1], { kind = "D", target = "STOCK", need = "103" }), false)
		eq(G.Fits(G.Looking("D")[1], { kind = "D", target = "DM", need = "003" }), false, "no role of his wanted")
		eq(G.Fits(G.Looking("D")[1], { kind = "D", target = "DM", need = "103", min = 50 }), false, "under the minimum")
		G.Show("R", true)
		Line(B.Lines(), "Brenna").onClick()
		eq(Line(B.Lines(), "> " .. ns.L.GROUPS_INVITE), nil)
		assert(Line(B.Lines(), ns.L.GROUPS_WHISPER:format("Brenna")))
		G.Show("flags", true)
	end)
end)

test("1.4.0 groups: our own group shows in the list, marked, with its card and our roster on hover; someone else's card in full; the notices", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		ns.splitNames = true
		assert(G.Post("D", "SFK", nil, "103", "bring food", 18))
		w.party = { { "Brenna", "Stoutheart", "PRIEST" } }
		G.SetMemberRole("Brenna Stoutheart-Realm", "H")
		G.Show("D", true)
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_UP:format(1)), "ours counts in the list")
		local mine = Line(lines, ns.L.GROUPS_YOUR_GROUP)
		assert(mine and mine.text:find("[Shadowfang Keep]", 1, true), Texts(lines))
		assert(mine.right:find("1T 3D", 1, true) and mine.right:find(ns.L.GROUPS_MIN_SHORT:format(18), 1, true) and mine.right:find("2/5", 1, true), mine.right)
		local tip = Tip(mine)
		assert(tip:find("bring food", 1, true) and tip:find(ns.L.GROUPS_IN_GROUP, 1, true) and tip:find("Brenna Stoutheart", 1, true)
			and tip:find(ns.L.GROUPS_ROLE_H, 1, true) and tip:find(ns.L.GROUPS_OWN_TIP, 1, true), tip)
		-- The Your group line has the same card on hover.
		assert(Tip(Line(lines, ns.L.GROUPS_MINE:format("Shadowfang Keep"))):find("Brenna Stoutheart", 1, true))
		mine.onClick()
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_MANAGE_ABOVE) and not Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)), Texts(lines))
		-- Someone else's group: its card has its leader, needs, minimum, note and members, then Apply.
		G.HandlePost("CHANNEL", "Aldric-Realm", G.Encode({ id = "a1", guild = "Olympus Zeus", kind = "D", target = "DM", level = 20, class = "WA",
			need = "011", size = 2, min = 16, every = 5, age = 0, note = "chill run" }))
		G.HandleMembers("CHANNEL", "Aldric-Realm", G.EncodeMembers("a1", { { class = "MA", role = "D", count = 1 } }))
		Line(B.Lines(), "[Deadmines]").onClick()
		lines = B.Lines()
		for _, want in ipairs({ ns.L.GROUPS_CARD_LEADER:format("Aldric", "Olympus Zeus"), ns.L.GROUPS_NEEDS:format("Healer, Damage"),
			ns.L.GROUPS_MIN_TIP:format(16), '"chill run"', ns.L.GROUPS_IN_GROUP, ns.L.GROUPS_COUNT:format("Mage", 1), ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_H) }) do
			assert(Line(lines, want), want .. "\n" .. Texts(lines))
		end
		-- The notices: in an instance, not our group's leader, a raid's party of five.
		local savedLocked = ns.ChatLocked
		ns.ChatLocked = function() return true end
		local before = #w.sent
		w.clock = w.clock + 10 * 60
		G.Tick()
		eq(#w.sent, before, "nothing goes from an instance")
		assert(Line(B.Lines(), ns.L.GROUPS_LOCKED))
		ns.ChatLocked = savedLocked
		G.Tick()
		eq(#w.sent > before, true, "it goes once we are out")
		w.notLeader = true
		assert(Line(B.Lines(), ns.L.GROUPS_NOT_LEADER))
		w.notLeader = false
		w.clock = w.clock + G.LIST_GAP
		assert(G.Post("R", "MC", nil, "+++", ""))
		G.Show("R", true)
		assert(not Line(B.Lines(), ns.L.GROUPS_CONVERT))
		w.party = { { "A", "", "MAGE" }, { "B", "", "MAGE" }, { "C", "", "MAGE" }, { "D", "", "MAGE" } }
		assert(Line(B.Lines(), ns.L.GROUPS_CONVERT), "five in a party: convert to a raid")
	end)
end)

test("1.4.0 groups: filters (I can join, in my log, my zone; players by fit and role); a flag's player invited as a role their flag names", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.HandlePost("CHANNEL", "Aldric-Realm", G.Encode({ id = "a1", guild = "Olympus Zeus", kind = "D", target = "BRD", level = 55, class = "WA",
			need = "113", size = 1, min = 50, every = 5, age = 0 }))
		G.HandlePost("CHANNEL", "Brenna-Realm", G.Encode({ id = "b1", guild = "Olympus Zeus", kind = "D", target = "SM", level = 40, class = "PR",
			need = "113", size = 1, min = 30, every = 5, age = 0 }))
		G.HandlePost("CHANNEL", "Cora-Realm", G.Encode({ id = "c1", guild = "Olympus Zeus", kind = "D", target = "RFC", level = 15, class = "MA",
			need = "000", size = 5, every = 5, age = 0 }))
		G.Show("D", true)
		local lines = B.Lines()
		local strip
		for _, l in ipairs(lines) do if l.id == "board-filter-D" then strip = l end end
		assert(strip and strip.nav[1].selected, "the filters, All first")
		strip.nav[2].onClick()
		eq(G.Filter("D"), "join")
		lines = B.Lines()
		assert(Line(lines, "[Scarlet Monastery]"), Texts(lines))
		assert(not Line(lines, "[Blackrock Depths]"), "level 50 and up: not us (42)")
		assert(not Line(lines, "[Ragefire Chasm]"), "full")
		-- Quests: in my log; my zone.
		w.quests = { { title = "Elwynn Forest", header = true }, { title = "Kill Hogger", level = 11, id = 176, group = 3 } }
		G.HandlePost("CHANNEL", "Dora-Realm", G.Encode({ id = "d1", guild = "Olympus Zeus", kind = "Q", target = "176", level = 12, class = "MA",
			need = "012", size = 1, every = 5, age = 0, title = "Kill Hogger", zone = "Elwynn Forest" }))
		G.HandlePost("CHANNEL", "Eda-Realm", G.Encode({ id = "e1", guild = "Olympus Zeus", kind = "Q", target = "0", level = 30, class = "MA",
			need = "012", size = 1, every = 5, age = 0, title = "Mor'Ladim", zone = "Duskwood" }))
		G.Show("Q", true)
		G.SetFilter("Q", "log")
		lines = B.Lines()
		assert(Line(lines, "[Kill Hogger]") and not Line(lines, "[Mor'Ladim]"), Texts(lines))
		local savedZone = GetRealZoneText
		GetRealZoneText = function() return "Duskwood" end
		G.SetFilter("Q", "zone")
		lines = B.Lines()
		assert(Line(lines, "[Mor'Ladim]") and not Line(lines, "[Kill Hogger]"), Texts(lines))
		GetRealZoneText = savedZone
		assert(Tip(Line(lines, "[Mor'Ladim]")):find(ns.L.GROUPS_ZONE:format("Duskwood"), 1, true))
		-- Players looking, by fit and role; invited as a role their flag names and we need.
		local function Flagged(id, name, roles, picks)
			B.HandlePost("CHANNEL", name, B.Encode({ id = id, guild = "Olympus Zeus", flag = "D", level = 40, class = "PR", every = 10, age = 0, roles = roles, picks = picks }))
		end
		Flagged("f1", "Tanky-Realm", "T", "D:SM")
		Flagged("f2", "Heals-Realm", "H", "D:*")
		Flagged("f3", "Quiet-Realm", "", nil)
		assert(G.Post("D", "SM", nil, "103", "", 30))
		G.Show("D", true)
		G.SetFilter("looking", "fits")
		lines = B.Lines()
		assert(Line(lines, "Tanky") and not Line(lines, "Heals") and not Line(lines, "Quiet"), Texts(lines))
		G.SetFilter("looking", "H")
		lines = B.Lines()
		assert(Line(lines, "Heals") and not Line(lines, "Tanky"), Texts(lines))
		G.SetFilter("looking", "all")
		eq(table.concat(G.InviteRoles(G.Looking("D")[1]), ""), "T", "Tanky: tank only")
		local quiet
		for _, e in ipairs(G.Looking("D")) do if e.sender == "Quiet-Realm" then quiet = e end end
		eq(table.concat(G.InviteRoles(quiet), ""), "TD", "a flag naming no role: any role we need")
		Line(B.Lines(), "Tanky").onClick()
		lines = B.Lines()
		eq(Line(lines, "> " .. ns.L.GROUPS_INVITE_AS:format(ns.L.GROUPS_ROLE_D)), nil, "not as a role he doesn't play")
		Line(lines, "> " .. ns.L.GROUPS_INVITE_AS:format(ns.L.GROUPS_ROLE_T)).onClick()
		eq(w.invited[#w.invited], "Tanky")
		eq(G.Mine().need, "103", "until he joins")
		w.party = { { "Tanky", "", "WARRIOR" } }
		G.CheckJoins()
		eq(G.Mine().need, "003")
		eq(G.GroupMembers()[1].role, "T", "his role, as he was invited")
	end)
end)

test("1.4.0 groups: a listing repeats every 5 minutes while few are up (up to 30 when the Board is full), and leaves every Board about 12 minutes after its leader went quiet", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		eq(G.Interval(0), 5); eq(G.Interval(40), 8); eq(G.Interval(150), 30)
		assert(G.Post("D", "DM", nil, "113", ""))
		eq(G.Decode(Sent(w, "GL~").msg).every, 5)
		AsSoldier("Reader")
		GetGuildInfo = function() return "Olympus Zeus", "Member", 3 end
		G.HandlePost("CHANNEL", "Soldier-Realm", Sent(w, "GL~").msg)
		eq(#G.List("D"), 1)
		w.clock = w.clock + 11 * 60
		eq(#G.List("D"), 1, "two refreshes missed: still there at 11 minutes")
		w.clock = w.clock + 60
		eq(#G.List("D"), 0, "gone at 12")
	end)
end)

---------------------------------------------------------------------------
-- The review of PR #62: each finding's regression test, failing on the PR's head.
---------------------------------------------------------------------------

test("1.4.0 groups review (B1): on WoW: Forever an invited applicant who joins is recognised; the unit functions give the surname where the realm goes", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		ns.splitNames = true
		assert(G.Post("D", "DM", nil, "112", ""))
		local id = G.Mine().id
		G.HandleApply("WHISPER", "Aldric Stoutheart-Realm", G.EncodeApply(id, "Olympus Zeus", "T", 20, "WA", ""))
		eq(#G.Applicants(), 1)
		G.Invite("Aldric Stoutheart-Realm")
		-- As tests/run.lua's "WoW: Forever names" models the client: "Aldric", "Stoutheart".
		w.party = { { "Aldric", "Stoutheart", "WARRIOR" } }
		eq(G.GroupMembers()[1].name, "Aldric Stoutheart-Realm", "the name the server stamps, the one he applied under")
		G.CheckJoins()
		eq(G.Mine().need, "012", "the tank who joined comes off the need")
		eq(#G.Applicants(), 0, "his application done")
		eq(G.Pending()["Aldric Stoutheart-Realm"], nil)
		assert(w.printed[#w.printed]:find(ns.L.GROUPS_JOINED:format("Aldric Stoutheart", ns.L.GROUPS_ROLE_T), 1, true), w.printed[#w.printed])
		-- Two minutes on, no "didn't join" line: he is in.
		w.clock = w.clock + G.INVITE_WAIT
		G.CheckJoins()
		assert(not w.printed[#w.printed]:find(ns.L.GROUPS_NOT_JOINED:format("Aldric Stoutheart", ns.L.GROUPS_ROLE_T), 1, true), w.printed[#w.printed])
		-- In a raid, ourselves among its units, the leader is never one of the others.
		w.raid = { { "Soldier", "", "PRIEST" }, { "Aldric", "Stoutheart", "WARRIOR" } }
		local others = G.GroupMembers()
		eq(#others, 1); eq(others[1].name, "Aldric Stoutheart-Realm")
	end)
end)

test("1.4.0 groups review (B3): the listing dialog says what goes out: counts by class and role, never the group's names", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.Show("D", true)
		G.Compose("D")
		G.ChooseTarget("DM")
		G.PromptList()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_GROUPS_LIST")
		local text = ns.L.GROUPS_LIST_ASK
		assert(text:find("by class and role", 1, true) and text:find("never their names", 1, true), text)
		assert(ns.L.GROUPS_YOURS_TIP:find("never their names", 1, true), ns.L.GROUPS_YOURS_TIP)
	end)
end)

test("1.4.0 groups review (B4): a typed name's listing carries the leader's zone only while he shares it, never from an instance, read again at each send", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		GetRealZoneText = function() return "Duskwood" end
		w.share = false
		G.Show("Q", true)
		G.Compose("Q")
		G.ConfirmName({}, "Mor'Ladim")
		eq(G.Composing().zone, "", "no zone kept with a typed name")
		-- The dialog says the zone goes only while it does.
		G.PromptList()
		assert(not w.popups[#w.popups].a:find("Duskwood", 1, true), w.popups[#w.popups].a)
		w.share = true
		G.PromptList()
		assert(w.popups[#w.popups].a:find(ns.L.GROUPS_ZONE:format("Duskwood"), 1, true), w.popups[#w.popups].a)
		w.share = false
		G.PromptList()
		G.ConfirmList(w.popups[#w.popups].data, "")
		eq(G.Decode(Sent(w, "GL~").msg).zone, "", "not shared: no zone sent")
		-- He shares it now: the next send carries it; from an instance, none again.
		w.share = true
		w.clock = w.clock + G.UPDATE_GAP
		G.StepOwnNeed("D")
		eq(G.Decode(Sent(w, "GL~").msg).zone, "Duskwood", "shared: the zone he is in")
		IsInInstance = function() return true end
		eq(G.Decode(G.Message(G.Mine(), w.clock)).zone, "", "from an instance: none")
		IsInInstance = function() return false end
		-- A quest from his log keeps its log's zone (where the quest is, not where he is).
		eq(G.OwnZone({ kind = "Q", target = "176", zone = "Elwynn Forest" }), "Elwynn Forest")
		w.share = false
		eq(G.OwnZone({ kind = "Q", target = "176", zone = "Elwynn Forest" }), "Elwynn Forest")
	end)
end)

test("1.4.0 groups review (B5): on the King's screen a quest's title and zone are a player's words: a typed name never shows, a log quest only as his own log has it", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("t1", "Olympus Zeus", "Q", "0", "012", 0, "rude note", "some rude words"))
		G.HandlePost("CHANNEL", "Brenna-Realm", G.Encode({ id = "b1", guild = "Olympus Zeus", kind = "Q", target = "176", level = 12, class = "MA",
			need = "012", size = 1, every = 5, age = 0, title = "more rude words", zone = "rude zone" }))
		G.HandlePost("CHANNEL", "Cora-Realm", G.Encode({ id = "c1", guild = "Olympus Zeus", kind = "Q", target = "33", level = 12, class = "MA",
			need = "012", size = 1, every = 5, age = 0, title = "rude again", zone = "rude place" }))
		w.quests = { { title = "Elwynn Forest", header = true }, { title = "Kill Hogger", level = 11, id = 176, group = 3 } }
		G.Show("Q", true)
		-- Anyone else's screen: as they came.
		assert(Line(B.Lines(), "[some rude words]"), Texts(B.Lines()))
		ns.KingsScreen = function() return true end
		local lines = B.Lines()
		local function Clean(where, text) assert(not tostring(text):find("rude", 1, true), where .. ": " .. tostring(text)) end
		Clean("the rows", Texts(lines))
		assert(Line(lines, "[" .. ns.L.GROUPS_QUEST_UNNAMED .. "]"), Texts(lines))
		assert(Line(lines, "[Kill Hogger]"), "quest 176 by his own log's title")
		for _, l in ipairs(lines) do if l.tooltip then Clean("a tooltip", Tip(l)) end end
		assert(Tip(Line(lines, "[Kill Hogger]")):find(ns.L.GROUPS_ZONE:format("Elwynn Forest"), 1, true), "his own log's zone")
		for _, who in ipairs({ "Aldric", "Brenna", "Cora" }) do
			for _, l in ipairs(B.Lines()) do if l.text and l.text:find(who, 1, true) and l.onClick then l.onClick() break end end
			Clean(who .. "'s card", Texts(B.Lines()))
		end
		-- The search reads what shows: the hidden words find nothing.
		eq(Line(B.Lines(ns.Fold("rude")), "Aldric"), nil)
		-- His own typed listing on his own screen: no typed name either.
		eq(G.Target("Q", "0", "Mor'Ladim"), ns.L.GROUPS_QUEST_UNNAMED)
	end)
end)

test("1.4.0 groups review (B6): the Board's answer share counts group listings too, so about ANSWER_TARGET holders answer an ask", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		for i = 1, 99 do
			G.HandlePost("CHANNEL", ("Holder%02d-Realm"):format(i), Listing(("%02d"):format(i), "Olympus Zeus", "D", "DM", "113", 0))
		end
		eq(G.Count(), 99)
		eq(B.Count(), 0)
		assert(G.Post("D", "SFK", nil, "113", ""))
		-- 0.9 > 40 / 100: this holder is not among the ~40 who answer.
		B.random = function(a) if a then return a end return 0.9 end
		B.HandleAsk("CHANNEL", "Asker-Realm", "GQ~")
		local answering = false
		for _, t in ipairs(w.later) do if t.where == "board answer" then answering = true end end
		eq(answering, false, "with 100 listings up, a 0.9 draw does not answer")
		-- 0.3 < 0.4: it does.
		B.random = function(a) if a then return a end return 0.3 end
		B.HandleAsk("CHANNEL", "Asker2-Realm", "GQ~")
		for _, t in ipairs(w.later) do if t.where == "board answer" then answering = true end end
		eq(answering, true)
	end)
end)

test("1.4.0 groups review (B7): /oly group before the game restarts after the update (Groups.lua not loaded yet) says to restart, no error", function()
	local savedSlash, savedEvents, savedDialogs = {}, #EVENT_SCRIPTS, {}
	for k, v in pairs(SlashCmdList) do savedSlash[k] = v end
	for k, v in pairs(StaticPopupDialogs) do savedDialogs[k] = v end
	local savedGroups = ns.Groups
	local ok, err = pcall(function()
		-- Core.lua as the game loads it at a /reload after the update: its stand-in for a file the
		-- game hasn't read yet.
		local fresh = setmetatable({}, { __index = ns })
		assert(loadfile(H.ADDON_DIR .. "Core.lua"))("Olympus", fresh)
		local standIn = rawget(fresh, "Groups")
		assert(type(standIn) == "table" and standIn.missing == true, "Groups.lua stood in for")
		-- (Its "restart the game" line is that namespace's print, as it is the game's.)
		local printed = {}
		fresh.Print = function(msg) printed[#printed + 1] = tostring(msg) end
		WithBoard(function(w, B)
			AsSoldier()
			ns.Groups = standIn
			B.Slash("group", "")
			eq(#printed, 1); eq(printed[1], ns.L.RESTART_NEEDED)
			B.Slash("groups", "raid")
			eq(#printed, 2); eq(printed[2], ns.L.RESTART_NEEDED)
			-- The Board itself goes on as it was: its page (no section strip), its link, its answers.
			local lines = B.Lines()
			for _, l in ipairs(lines) do assert(l.id ~= "board-sections", "no section strip without Groups.lua") end
			assert(B.LinkLine())
			assert(B.Raise("D", ""))
			B.HandleAsk("CHANNEL", "Asker-Realm", "GQ~")
			for _, t in ipairs(w.later) do if t.where == "board answer" then t.fn() end end
			assert(w.whispered[#w.whispered].msg:find("^G1~"), "the flag answers as before")
		end)
	end)
	ns.Groups = savedGroups
	for k in pairs(SlashCmdList) do SlashCmdList[k] = savedSlash[k] end
	for k, v in pairs(savedSlash) do SlashCmdList[k] = v end
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = savedDialogs[k] end
	for k, v in pairs(savedDialogs) do StaticPopupDialogs[k] = v end
	for i = #EVENT_SCRIPTS, savedEvents + 1, -1 do EVENT_SCRIPTS[i] = nil end
	if not ok then error(err, 0) end
end)

test("1.4.0 groups review (8): a quest's zone is the sender's words too: heard without the logged API it shows without it", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		w.logged = false
		G.HandlePost("CHANNEL", "Aldric-Realm", G.Encode({ id = "a1", guild = "Olympus Zeus", kind = "Q", target = "176", level = 12, class = "MA",
			need = "012", size = 1, every = 5, age = 0, title = "Kill Hogger", zone = "some words here" }))
		local e = G.List("Q")[1]
		eq(e.zone, ""); eq(e.title, ""); eq(e.note, "")
		w.logged = true
		G.HandlePost("CHANNEL", "Brenna-Realm", G.Encode({ id = "b1", guild = "Olympus Zeus", kind = "Q", target = "176", level = 12, class = "MA",
			need = "012", size = 1, every = 5, age = 0, title = "Kill Hogger", zone = "Elwynn Forest" }))
		for _, x in ipairs(G.List("Q")) do if x.sender == "Brenna-Realm" then eq(x.zone, "Elwynn Forest") end end
	end)
end)

test("1.4.0 groups review (9): the Quests section reads the quest log once for the whole page, however many listings it shows", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		w.quests = { { title = "Elwynn Forest", header = true }, { title = "Kill Hogger", level = 11, id = 176, group = 3 } }
		for i = 1, 8 do
			G.HandlePost("CHANNEL", ("Lead%d-Realm"):format(i), G.Encode({ id = "q" .. i, guild = "Olympus Zeus", kind = "Q", target = tostring(170 + i),
				level = 12, class = "MA", need = "012", size = 1, every = 5, age = 0, title = "Quest " .. i, zone = "Elwynn Forest" }))
		end
		local reads, count = 0, GetNumQuestLogEntries
		GetNumQuestLogEntries = function() reads = reads + 1 return count() end
		G.Show("Q", true)
		G.SetFilter("Q", "log")
		B.Lines()
		eq(reads, 1, "one read of the log for the page")
		G.SetFilter("Q", "all")
		reads = 0
		local lines = B.Lines()
		eq(reads, 1)
		assert(Line(lines, ns.L.GROUPS_IN_LOG), "quest 176 marked: " .. Texts(lines))
		GetNumQuestLogEntries = count
	end)
end)

test("1.4.0 groups review (10): a roster change redraws the Board only when it changes what it shows: never without a listing or an invite", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		local changes, roster = 0, 0
		G.after = function(_, where, f) if where == "groups changed" then changes = changes + 1 end return f() end
		-- (The harness's ns.Fire does nothing: this one counts what Groups.lua tells.)
		local savedFire = ns.Fire
		ns.Fire = function(name) if name == "GROUPS_ROSTER" then roster = roster + 1 end end
		local ok, err = pcall(function()
			w.party = { { "Aldric", "", "WARRIOR" } }
			G.OnRoster()
			eq(changes, 0, "no listing, no invite: nothing on the Board changed")
			eq(roster, 1, "the API is told (its MY_GROUP_CHANGED)")
			assert(G.Post("D", "DM", nil, "113", ""))
			changes = 0
			w.party = { { "Aldric", "", "WARRIOR" }, { "Brenna", "", "PRIEST" } }
			G.OnRoster()
			eq(changes, 1, "our listed group's roster: redrawn once")
		end)
		ns.Fire = savedFire
		if not ok then error(err, 0) end
	end)
end)

test("1.4.0 groups review (11): an application for a role the listing no longer wants is refused; the chat line comes once for each applicant or new role", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("D", "DM", nil, "103", ""))
		local id = G.Mine().id
		G.HandleApply("WHISPER", "Aldric-Realm", G.EncodeApply(id, "Olympus Zeus", "H", 20, "PR", ""))
		eq(#G.Applicants(), 0, "no healer wanted: refused")
		local before = #w.printed
		G.HandleApply("WHISPER", "Brenna-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 20, "MA", ""))
		eq(#G.Applicants(), 1); eq(#w.printed, before + 1, "a new applicant: one line")
		w.clock = w.clock + G.APPLY_GAP
		G.HandleApply("WHISPER", "Brenna-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 20, "MA", ""))
		eq(#w.printed, before + 1, "the same application again: no second line")
		w.clock = w.clock + G.APPLY_GAP
		G.HandleApply("WHISPER", "Brenna-Realm", G.EncodeApply(id, "Olympus Zeus", "T", 20, "MA", ""))
		eq(#w.printed, before + 2, "another role: its line"); eq(G.Applicants()[1].role, "T")
		-- Her earlier application stays as it was when the new role is one no longer wanted.
		G.Mine().need = "003"
		w.clock = w.clock + G.APPLY_GAP
		G.HandleApply("WHISPER", "Brenna-Realm", G.EncodeApply(id, "Olympus Zeus", "H", 20, "MA", ""))
		eq(G.Applicants()[1].role, "T")
	end)
end)

test("1.4.0 groups review (12): a refused game invite never breaks the click: nothing marked invited, nobody told, the player told", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("D", "DM", nil, "113", ""))
		local id = G.Mine().id
		G.HandleApply("WHISPER", "Aldric-Realm", G.EncodeApply(id, "Olympus Zeus", "T", 20, "WA", ""))
		C_PartyInfo = { InviteUnit = function() error("refused") end }
		local whispers = #w.whispered
		local ok, why = G.Invite("Aldric-Realm")
		eq(ok, false); eq(why, "invite")
		eq(G.Pending()["Aldric-Realm"], nil); eq(G.Applicants()[1].state, "new")
		eq(#w.whispered, whispers, "no GR~I")
		eq(w.printed[#w.printed], ns.L.GROUPS_INVITE_FAILED)
		eq(select(2, G.InviteFlag("Brenna-Realm", "T")), "invite")
	end)
end)

test("1.4.0 groups review (13, 15): /oly status counts the groups (no name); players looking are sorted with their fit worked out once each", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("D", "DM", nil, "103", ""))
		local status = ns.StatusText()
		assert(status:find("board groups: groups 0  |  mine: D DM", 1, true), status)
		for i = 1, 6 do
			B.HandlePost("CHANNEL", ("Flag%d-Realm"):format(i), B.Encode({ id = "f" .. i, guild = "Olympus Zeus", flag = "D", level = 40, class = "PR",
				every = 10, age = i, roles = i % 2 == 0 and "T" or "H", picks = "D:DM" }))
		end
		local calls, fits = 0, G.Fits
		G.Fits = function(...) calls = calls + 1 return fits(...) end
		local list = G.Looking("D")
		G.Fits = fits
		eq(#list, 6)
		eq(calls, 6, "once a flag")
		eq(list[1].sender, "Flag2-Realm", "the ones that fit first (a tank wanted), newest first")
		eq(list[4].sender, "Flag1-Realm")
	end)
end)

-- 1.4.0 (the merge into 1.4.0): a moderator's cover name (Embrace Anonymity, Cover.lua) shows on
-- the Board's group sections as on its flags (Board.Card): his listing's row, tooltip and card,
-- the apply dialog, his application to our listing and the chat lines about it, for a player who
-- said Yes to moderator protection. The whisper and the game's invite keep the real name.
test("1.4.0 groups: a moderator's cover name on the group sections, as on the flags; the whisper and the invite keep the real name", function()
	if not ns.Cover then
		assert(loadfile(H.ADDON_DIR .. "Locales/CoverText.lua"))("Olympus", ns)
		assert(loadfile(H.ADDON_DIR .. "Cover.lua"))("Olympus", ns)
	end
	WithGroups(function(w, G, B)
		AsSoldier()
		local saved = { council = ns.rdb.council, covers = ns.rdb.covers, consent = ns.db.coverConsent }
		local ok, err = pcall(function()
			ns.rdb.council = { at = 1, names = { ["watch keeper"] = "Watch Keeper" } }
			ns.rdb.covers = {}
			ns.db.coverConsent = true
			ns.Cover.Handle("CHANNEL", "Watch Keeper-Realm", "MC~Corwin Ashdale")
			eq(ns.CoverSwap("Watch Keeper"), "Corwin Ashdale", "the cover is held")
			local function NoRealName(text, what) assert(not tostring(text):find("Watch Keeper", 1, true), what .. ": " .. tostring(text)) end
			-- His listing: the row, its tooltip, its card and the apply dialog say the cover name.
			G.HandlePost("CHANNEL", "Watch Keeper-Realm", Listing("m1", "Olympus Zeus", "D", "SFK", "103", 0))
			G.Show("D", true)
			local row = Line(B.Lines(), "[Shadowfang Keep]")
			assert(row and row.text:find("Corwin Ashdale", 1, true), Texts(B.Lines()))
			NoRealName(row.text, "the row")
			local tip = Tip(row)
			assert(tip:find("Corwin Ashdale", 1, true), tip)
			NoRealName(tip, "the tooltip")
			row.onClick()
			local lines = B.Lines()
			for _, l in ipairs(lines) do NoRealName(l.text, "the card") end
			local whisper = assert(Line(lines, ns.L.GROUPS_WHISPER:format("Corwin Ashdale")), Texts(lines))
			whisper.onClick()
			eq(w.told[#w.told], "Watch Keeper", "the whisper goes to the real name")
			Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)).onClick()
			eq(w.popups[#w.popups].a, ns.L.GROUPS_APPLY_WHAT:format(ns.L.GROUPS_ROLE_T, "Shadowfang Keep", "Corwin Ashdale"))
			G.Reset()
			-- His application to our listing: the chat line, the applicant's row and tooltip, the
			-- pending line; the game's invite goes to the real name.
			assert(G.Post("D", "DM", nil, "112", ""))
			local id = G.Mine().id
			local printed = #w.printed
			G.HandleApply("WHISPER", "Watch Keeper-Realm", G.EncodeApply(id, "Olympus Zeus", "T", 20, "WA", ""))
			eq(#G.Applicants(), 1)
			assert(#w.printed > printed and w.printed[#w.printed]:find("Corwin Ashdale", 1, true), tostring(w.printed[#w.printed]))
			NoRealName(w.printed[#w.printed], "the chat line")
			G.Show("D", true)
			local applicant = assert(Line(B.Lines(), "Corwin Ashdale"), Texts(B.Lines()))
			NoRealName(applicant.text, "the applicant's row")
			NoRealName(Tip(applicant), "the applicant's tooltip")
			applicant.onClick()
			Line(B.Lines(), "> " .. ns.L.GROUPS_INVITE_AS:format(ns.L.GROUPS_ROLE_T)).onClick()
			eq(w.invited[#w.invited], "Watch Keeper", "the game's invite takes the real name")
			assert(w.printed[#w.printed]:find("Corwin Ashdale", 1, true), w.printed[#w.printed])
			assert(Line(B.Lines(), ns.L.GROUPS_PENDING:format("Corwin Ashdale", ns.L.GROUPS_ROLE_T)), Texts(B.Lines()))
			-- Without the player's Yes to moderator protection: the real name, as the Board's flags show it.
			ns.db.coverConsent = false
			assert(Line(B.Lines(), ns.L.GROUPS_PENDING:format("Watch Keeper", ns.L.GROUPS_ROLE_T)), Texts(B.Lines()))
		end)
		ns.rdb.council, ns.rdb.covers, ns.db.coverConsent = saved.council, saved.covers, saved.consent
		if not ok then error(err, 0) end
	end)
end)
