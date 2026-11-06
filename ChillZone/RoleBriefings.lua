local ADDON, ns = ...
local L = ns.L

-- The duty letters (1.4.0, the author's ask of 2026-10-20): a letter from the King for each office a
-- character holds, the first time it holds it, in the King's own voice and signed "- The King"
-- (texts: Locales/RoleBriefingsText.lua). The High Council (with its department's paragraph), the
-- Steward, a Hand, the Federal Treasurer, a treasury keeper, a Legate, each department's
-- correspondent, the Church correspondent, a Watcher, an ChillZone moderator, an Apostle and a
-- missionary. Two letters belong to the launch: every guild master's, with a live checklist of what
-- he must name (each line ticks itself from the addon's own state, and its button opens that step),
-- reopened from his Guild tab; and every Apostle's launch letter (an Apostle first seen within
-- LAUNCH_DAYS of this account's first letters gets it in place of the naming letter). The launch
-- letter itself is the version letter of LAUNCH_VERSION (Letters.lua), with the King's signature and
-- a button that copies the site's link (a copyable pop-up, never chat).
--
-- Visibility (the author, 2026-10-20: "ja podemos fazer e deixar so no workshop"): while LIVE is
-- false nothing is made, shown or said by itself, to anyone; the author (the Workshop) and the King
-- read every letter in preview (the Realm's Duty letters page), and a preview saves nothing, sends
-- nothing, marks nothing read and its buttons do nothing (the site's copy aside). The author turns
-- LIVE on for the launch release.
--
-- These are local letters, not claims of authority: every action named here is still gated by its
-- owning module, and nothing here is sent. A letter is kept per character in the account's saved
-- data (ns.db.roleBriefings), keyed on the office and its holder (and the guild or department the
-- office belongs to), never on a date of the appointment, so a roster gap, a re-signed list or a
-- removal and a new naming never make a second one. Read ones stay on the Realm's Duty letters page,
-- under My profile > Letters, in the Church's Mine page and (a guild master's) on his Guild tab, and
-- `/cz duties` reopens them. The letters open on the ChillZone window's own parchment page (no window
-- of the game's): nothing here reaches into Blizzard's UI, with mouse and keyboard or the gamepad.
local Brief = {}
ns.RoleBriefings = Brief

Brief.LIVE = true -- (1.4.0, the launch: the author turned them on)
Brief.RULE = 1
Brief.MAX = 48
Brief.PAPER_WRAP = 48
Brief.LAUNCH_VERSION = "1.4.0"
Brief.SITE = "https://chillzone.roachcouncil.com/"
Brief.LAUNCH_DAYS = 7
Brief.SCAN_WAIT = 2 -- the change events' scans, gathered into one this long after the first

local current    -- the id of the saved letter the page shows, or nil
local previewing -- the preview the page shows (an entry of its own, never saved), or nil

local function Safe(obj, fn, ...)
	if type(obj) ~= "table" or obj.missing or type(obj[fn]) ~= "function" then return nil end
	local ok, a, b, c = pcall(obj[fn], ...)
	if not ok then return nil end
	return a, b, c
end
local function Lower(s) return type(s) == "string" and s:lower() or "" end
local function Owner() return Lower(ns.FullName(ns.me or "")) end
local function Plain(s, n)
	return ns.Cut(tostring(s or ""):gsub("[|%c]", " "):gsub("%s+", " "), n or 120)
end

-- The saved letters; make: start them when there are none (only a LIVE scan does).
local function Store(make)
	if type(ns.db) ~= "table" then return nil end
	local s = ns.db.roleBriefings
	if type(s) ~= "table" or s.rule ~= Brief.RULE then
		if not make then return nil end
		s = { rule = Brief.RULE, entries = {}, active = {}, seq = 0 }
		ns.db.roleBriefings = s
	end
	if type(s.entries) ~= "table" then s.entries = {} end
	if type(s.active) ~= "table" then s.active = {} end
	if type(s.seq) ~= "number" or s.seq < 0 then s.seq = 0 end
	local kept = {}
	for _, e in ipairs(s.entries) do
		if type(e) == "table" and type(e.id) == "string" and type(e.kind) == "string"
			and type(e.owner) == "string" and type(e.t) == "number" then
			kept[#kept + 1] = e
		end
	end
	while #kept > Brief.MAX do table.remove(kept, 1) end
	s.entries = kept
	return s
end

---------------------------------------------------------------------------
-- The letters
---------------------------------------------------------------------------

-- The six departments (Nominees.DEPARTMENT_LIST), each with its words' code and its button.
local DEPTS = {
	{ name = "Federal Treasury", code = "TREASURY", button = "ownbank" },
	{ name = "Department of War", code = "WAR", button = "war" },
	{ name = "Council of Justice", code = "JUSTICE", button = "watch" },
	{ name = "Association of Artisanry", code = "ARTISANRY", button = "crafters" },
	{ name = "Department of Heraldry", code = "HERALDRY", button = "decrees" },
	{ name = "The Missionary Church of ChillZone", code = "CHURCHDEPT", button = "church" },
}
Brief.DEPTS = DEPTS
local function Dept(name)
	if type(name) ~= "string" then return nil end
	local normal = Safe(ns.Nominees, "DepartmentName", name)
	name = type(normal) == "string" and normal or name
	for _, d in ipairs(DEPTS) do if d.name:lower() == name:lower() then return d end end
	return nil
end

-- Each letter: its title and body (locale keys), what its %s is (the guild, or a missionary's
-- network), its buttons. family: the kind OpenKind and Has also find it by.
local KINDS = {
	launch = { title = "RB_LAUNCH_TITLE", body = { "RB_LAUNCH" }, buttons = { "site" } },
	guildmaster = { title = "RB_GM_TITLE" },
	council = { title = "RB_COUNCIL_TITLE", body = { "RB_COUNCIL" }, buttons = { "watch", "throne" } },
	steward = { title = "RB_STEWARD_TITLE", body = { "RB_STEWARD" }, buttons = { "throne" } },
	hand = { title = "RB_HAND_TITLE", body = { "RB_HAND" }, buttons = { "throne" } },
	treasurer = { title = "RB_TREASURER_TITLE", body = { "RB_TREASURER" }, buttons = { "treasury" } },
	keeper = { title = "RB_KEEPER_TITLE", body = { "RB_KEEPER" }, buttons = { "treasury" } },
	legate = { title = "RB_LEGATE_TITLE", body = { "RB_LEGATE" }, arg = "guild", buttons = { "war" } },
	correspondent = { arg = "guild" }, -- (its department's title, body and second button)
	churchcorr = { title = "RB_CHURCHCORR_TITLE", body = { "RB_CHURCHCORR" }, arg = "guild", buttons = { "church" } },
	watcher = { title = "RB_WATCHER_TITLE", body = { "RB_WATCHER" }, arg = "guild", buttons = { "watch" } },
	moderator = { title = "RB_MODERATOR_TITLE", body = { "RB_MODERATOR" }, buttons = { "watch" } },
	apostle = { title = "RB_APOSTLE_TITLE", body = { "RB_APOSTLE_1", "RB_APOSTLE_RED", "RB_APOSTLE_2" }, buttons = { "churchname" }, family = "apostle" },
	apostlelaunch = { title = "RB_APOSTLE_LAUNCH_TITLE", body = { "RB_APOSTLE_LAUNCH" }, buttons = { "church" }, family = "apostle" },
	missionary = { title = "RB_MISSIONARY_TITLE", body = { "RB_MISSIONARY" }, arg = "net", buttons = { "church" } },
}
Brief.KINDS = KINDS

local function Go(fn) return function() ns.SafeCall("duty letter", fn) end end
local function Tab(key) return function() ns.UI.SelectTab(key) end end
local BUTTONS = {
	throne = { label = "RB_BTN_THRONE", fn = Tab("throne") },
	guild = { label = "RB_BTN_GUILD", fn = Tab("throne") },
	watch = { label = "RB_BTN_WATCH", fn = function()
		if ns.Watch and ns.Watch.Show then ns.Watch.Show("chat") end
		ns.UI.SelectTab("watch")
	end },
	treasury = { label = "RB_BTN_TREASURY", fn = Tab("treasury") },
	ownbank = { label = "RB_BTN_TREASURY", fn = function() ns.Treasury.OpenOwnGuild() end },
	war = { label = "RB_BTN_WAR", fn = function() ns.War.Show() end },
	church = { label = "RB_BTN_CHURCH", fn = Tab("church") },
	churchname = { label = "RB_BTN_CHURCH", fn = function()
		ns.UI.SelectTab("church")
		if ns.ChurchView and ns.ChurchView.Show then ns.ChurchView.Show("name") end
	end },
	crafters = { label = "RB_BTN_CRAFTERS", fn = Tab("crafters") },
	decrees = { label = "RB_BTN_DECREES", fn = Tab("decrees") },
	-- The site's link in a copyable pop-up (never chat): harmless, so a preview keeps it.
	site = { label = "LETTERS_COPY_LINK", fn = function() Brief.CopySite() end, preview = true },
}

function Brief.CopySite()
	return ns.UI.ShowCopy(L.RB_SITE_TITLE, Brief.SITE)
end

function Brief.Title(entry)
	if type(entry) ~= "table" then return L.RB_PAGE_TITLE end
	if entry.kind == "correspondent" then
		local d = Dept(entry.dept)
		return d and L["RB_CORR_" .. d.code .. "_TITLE"] or L.RB_PAGE_TITLE
	end
	local k = KINDS[entry.kind]
	return k and k.title and L[k.title] or L.RB_PAGE_TITLE
end

-- The red cross in My profile is offered only to an Apostle on the author's signed list.
local function RedCross()
	return Safe(ns.Borders, "OwnLookAllowed", "apostle-red") == true
end

local function Fill(text, entry)
	local k = KINDS[entry.kind] or {}
	local arg = k.arg == "guild" and Plain(entry.guild or "?", 40)
		or k.arg == "net" and Plain(entry.net or L.CHURCH_HEAD or "?", 40) or nil
	if not arg then return text end
	return (text:gsub("%%s", function() return arg end))
end

-- The letter's words, as paragraphs (each a string; "- " lines are items of a list).
local function Body(entry)
	local out, keys = {}, nil
	if entry.kind == "correspondent" then
		local d = Dept(entry.dept)
		keys = d and { "RB_CORR_" .. d.code } or {}
	else
		keys = (KINDS[entry.kind] or {}).body or {}
	end
	for _, key in ipairs(keys) do
		local text = L[key]
		if type(text) == "string" and (key ~= "RB_APOSTLE_RED" or RedCross()) then out[#out + 1] = Fill(text, entry) end
	end
	-- A titled councillor's department.
	if entry.kind == "council" then
		local d = Dept(entry.dept)
		if not d and not entry.preview then
			local t = type(ns.CouncilTitle) == "function" and ns.CouncilTitle(ns.me) or nil
			d = type(t) == "table" and Dept(t.dept) or nil
		end
		if d then out[#out + 1] = L.RB_COUNCIL_BADGE .. " " .. L["RB_COUNCIL_" .. d.code] end
	end
	return out
end
Brief.Body = Body

function Brief.Letters()
	local out, s, owner = {}, Store(), Owner()
	for _, e in ipairs(s and s.entries or {}) do if e.owner == owner then out[#out + 1] = e end end
	table.sort(out, function(a, b) return a.t == b.t and a.id < b.id or a.t < b.t end)
	return out
end

---------------------------------------------------------------------------
-- The offices this character holds
---------------------------------------------------------------------------

local function Add(list, kind, signature, data)
	data = type(data) == "table" and data or {}
	data.kind, data.signature = kind, signature
	list[#list + 1] = data
end

-- Current, real roles only.  This intentionally does not consult King.Preview, Nominees.DevView,
-- ViewAs or Watch.CouncilDeskShown. Each signature is the office and its holder (and the guild or
-- department an office belongs to), never a date of the appointment: one letter per office held.
-- The King has none (he signs them), nor does the King's guild's master, who is the King.
local function CurrentRoles()
	local roles = {}
	if not ns.IsMember() then return roles end
	local guild, _, rank = GetGuildInfo("player")
	local owner = Owner()
	local king = Safe(ns.King, "IsKing") == true
	if king then return roles end
	local council = ns.IsHighCouncillor(ns.me) == true
	if council then Add(roles, "council", "council:" .. owner) end
	if Safe(ns.King, "IsSteward") == true then Add(roles, "steward", "steward:" .. owner) end
	if Safe(ns.King, "IsHand") == true then Add(roles, "hand", "hand:" .. owner) end
	if rank == 0 and type(guild) == "string" and ns.IsFederation(guild) and not (ns.IsKingGuild and ns.IsKingGuild(guild)) then
		Add(roles, "guildmaster", "guildmaster:" .. owner .. ":" .. Lower(guild), { guild = guild })
	end
	local pin = Safe(ns.Treasury, "TreasurerPin", ns.me)
	if pin == 1 then Add(roles, "treasurer", "treasurer:" .. owner)
	elseif pin == nil and Safe(ns.Treasury, "RealKeeper") == true then Add(roles, "keeper", "keeper:" .. owner) end

	-- (Not Church.Place().since: a signed Apostle's is the signed list's time, moved by every re-sign.)
	local churchRole = Safe(ns.Church, "Role", ns.me)
	if churchRole == "A" then Add(roles, "apostle", "apostle:" .. owner)
	elseif churchRole == "M" then
		local p, S = Safe(ns.Church, "Place", ns.me), Safe(ns.Church, "State")
		local a = type(p) == "table" and p.net and type(S) == "table" and type(S.apostle) == "table" and S.apostle[p.net]
		Add(roles, "missionary", "missionary:" .. owner, { net = type(a) == "table" and type(a.n) == "string" and ns.DisplayName(a.n) or nil })
	elseif churchRole == "C" then
		local S = Safe(ns.Church, "State")
		local key = Safe(ns.Church, "Key", ns.me)
		local gkey = type(S) == "table" and type(S.corrOf) == "table" and key and S.corrOf[key]
		local c = gkey and type(S.corr) == "table" and S.corr[gkey]
		local of = type(c) == "table" and type(c.g) == "string" and c.g or guild
		Add(roles, "churchcorr", "churchcorr:" .. owner .. ":" .. Lower(of), { guild = of })
	end

	local role, dept = Safe(ns.Nominees, "RoleOf", ns.me, guild)
	local d = role == "correspondent" and Dept(dept) or nil
	if role == "centurion" then
		Add(roles, "legate", "legate:" .. owner .. ":" .. Lower(guild), { guild = guild })
	elseif d then
		Add(roles, "correspondent", "correspondent:" .. owner .. ":" .. Lower(guild) .. ":" .. Lower(d.name), { guild = guild, dept = d.name })
	end
	-- A Watcher his guild master named (the Justice correspondent has his own letter), and an
	-- ChillZone moderator (the council names them: a councillor's own letter says it all).
	if (not d or d.code ~= "JUSTICE") and Safe(ns.WatchChat, "IsNamedWatcher", ns.me) == true then
		Add(roles, "watcher", "watcher:" .. owner .. ":" .. Lower(guild), { guild = guild })
	end
	if not council and Safe(ns.WatchChat, "IsMod", ns.me) == true then Add(roles, "moderator", "moderator:" .. owner) end
	return roles
end
Brief.CurrentRoles = CurrentRoles -- focused tests; read-only result

local function Queue(s, role, quiet)
	s.seq = s.seq + 1
	local now = ns.Now()
	local e = { id = Owner() .. ":" .. tostring(now) .. ":" .. tostring(s.seq), owner = Owner(),
		kind = role.kind, signature = role.signature, t = now, read = false,
		guild = role.guild, dept = role.dept, net = role.net }
	s.entries[#s.entries + 1] = e
	while #s.entries > Brief.MAX do table.remove(s.entries, 1) end
	if not quiet then ns.Print(L.RB_READY:format(Brief.Title(e))) end
	return e
end

-- Queue once per office and holder (the signature).  A missing role is not enough to erase the
-- stamp: at login the live roster and relayed appointment books can be temporarily unknown, and
-- treating that gap as a removal would manufacture the same letter on every login.  A holder named
-- again to an office he held keeps the letter he has: it stays in My profile > Letters to reread.
-- Nothing at all while the letters are not LIVE.
function Brief.Scan(quiet)
	if Brief.LIVE ~= true then return 0 end
	local s, owner = Store(true), Owner()
	if not s or owner == "" then return 0 end
	local now = ns.Now()
	if type(s.liveAt) ~= "number" then s.liveAt = now end
	local prefix, made = owner .. "|", 0
	for _, role in ipairs(CurrentRoles()) do
		local slot = prefix .. role.kind .. (role.kind == "correspondent" and (":" .. Lower(role.dept)) or "")
		if s.active[slot] ~= role.signature then
			s.active[slot] = role.signature
			-- An Apostle at the launch: the Church's launch letter, in place of the naming one.
			if role.kind == "apostle" and now - s.liveAt <= Brief.LAUNCH_DAYS * 86400 then role.kind = "apostlelaunch" end
			Queue(s, role, quiet)
			made = made + 1
		end
	end
	if made > 0 and ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return made
end

local function Find(id, kind)
	local letters = Brief.Letters()
	for i = #letters, 1, -1 do
		local e = letters[i]
		local family = KINDS[e.kind] and KINDS[e.kind].family
		if (id == nil or e.id == id) and (kind == nil or e.kind == kind or family == kind) then return e end
	end
	return nil
end
function Brief.Has(kind) return Find(nil, kind) ~= nil end

function Brief.ShowPage()
	if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("realm") end
	if ns.Views and ns.Views.ShowPage then ns.Views.ShowPage("rolebriefings") end
end

-- (1.4.4, the author's ask) The letter as the window shows it: the version letter's parchment
-- (Letters.ShowText), its own title, its words, the King's signature, and a button to the page
-- of every duty letter (where a guild master's checklist and the letters' buttons live).
function Brief.Window(e)
	local parts = {}
	if e.kind == "guildmaster" then
		for _, key in ipairs({ "RB_GM_OPEN", "RB_GM_GET", "RB_GM_CLOSE" }) do
			if type(L[key]) == "string" then parts[#parts + 1] = L[key] end
		end
	else
		for _, text in ipairs(Body(e)) do parts[#parts + 1] = text end
	end
	return { head = L.RB_PAGE_TITLE, title = Brief.Title(e), body = table.concat(parts, "\n\n"), sign = L.HONOR_LETTER_SIGN,
		button = L.RB_BACK, onButton = Brief.ShowPage }
end

function Brief.Open(id)
	local e = Find(id)
	if not e then return false, "missing" end
	e.read, current, previewing = true, e.id, nil
	-- (1.4.4) In a window of its own, like the version letter; the page keeps every letter.
	local Lt = ns.Letters
	if type(Lt) == "table" and type(Lt.ShowText) == "function" and Lt.ShowText(Brief.Window(e)) == true then return true end
	Brief.ShowPage()
	return true
end

function Brief.OpenKind(kind)
	Brief.Scan(true)
	local e = Find(nil, kind)
	if not e then return false, "missing" end
	return Brief.Open(e.id)
end

-- Who reads every letter in preview: the author (the Workshop's own gate, never View as) and the
-- King himself.
function Brief.PreviewAllowed()
	if Safe(ns.Workshop, "Visible") == true then return true end
	return Safe(ns.King, "IsKing") == true
end

-- A letter in preview: an entry of its own, never saved; false for anyone else.
function Brief.Preview(kind, dept)
	if not Brief.PreviewAllowed() or not KINDS[kind] then return false end
	if kind == "correspondent" and not Dept(dept) then return false end
	local guild = GetGuildInfo("player")
	previewing = { kind = kind, dept = dept, preview = true, t = ns.Now(), net = L.CHURCH_HEAD,
		guild = type(guild) == "string" and guild ~= "" and guild or "ChillZone" }
	current = nil
	Brief.ShowPage()
	return true
end

function Brief.Slash(rest)
	rest = Lower(tostring(rest or ""):match("^%s*(.-)%s*$"))
	if Brief.LIVE ~= true and not Brief.PreviewAllowed() then
		ns.Print(L.RB_NOT_LIVE)
		return false
	end
	Brief.Scan(true)
	if rest ~= "" and rest ~= "list" then
		if Brief.OpenKind(rest) then return true end
	end
	current, previewing = nil, nil
	Brief.ShowPage()
	return true
end

---------------------------------------------------------------------------
-- The guild master's checklist
---------------------------------------------------------------------------

-- What this character's own guild has done of it now (the addon's own state, read live).
function Brief.GMState()
	local st = { legates = 0, named = {}, church = false, watchers = false, charter = false, bank = false }
	local guild = GetGuildInfo("player")
	st.guild = guild
	local ours = Safe(ns.Nominees, "Ours")
	for _, e in ipairs(type(ours) == "table" and type(ours.entries) == "table" and ours.entries or {}) do
		if e.role == "centurion" then st.legates = st.legates + 1
		elseif e.role == "correspondent" then
			local d = Dept(e.dept)
			if d then st.named[d.code] = true end
		end
	end
	-- The Church's correspondent as the Church tab shows him (Church.State().corr).
	local S = Safe(ns.Church, "State")
	if type(guild) == "string" and type(S) == "table" and type(S.corr) == "table" then st.church = S.corr[ns.Fold(guild)] ~= nil end
	local list = Safe(ns.WatchChat, "GuildList")
	st.watchers = type(list) == "table" and type(list.names) == "table" and next(list.names) ~= nil
	st.charter = Safe(ns.GuildCharter, "Ours") ~= nil
	st.bank = Safe(ns.Bank, "OwnGuildSnapshot") ~= nil
	return st
end

-- How many of the eight he must name are named: at least one Legate, the six correspondents and the
-- Church's correspondent.
function Brief.GMProgress(st)
	st = st or Brief.GMState()
	local done = (st.legates > 0 and 1 or 0) + (st.church and 1 or 0)
	for _, d in ipairs(DEPTS) do if st.named[d.code] then done = done + 1 end end
	return done, 2 + #DEPTS
end

---------------------------------------------------------------------------
-- The page (the Realm's, on the window's parchment)
---------------------------------------------------------------------------

local INK, TITLE = "QuestFont", "QuestTitleFont"
local function Paper(text, font, extra)
	local line = { text = text, font = font or INK }
	for key, value in pairs(extra or {}) do line[key] = value end
	return line
end
-- Words wrapped to the page (a row never wraps itself); extra on the last row, indent on all.
local function Paragraph(lines, text, font, extra, indent)
	local row = ""
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + #word + 1 > Brief.PAPER_WRAP then
			lines[#lines + 1] = Paper(row, font, { indent = indent })
			row = word
		else row = row == "" and word or row .. " " .. word end
	end
	if row ~= "" then
		local last = Paper(row, font, extra)
		last.indent = last.indent or indent
		lines[#lines + 1] = last
	end
end
-- A body: paragraphs apart, a list's items each its own rows.
local function Words(lines, text)
	for para in (tostring(text or "") .. "\n\n"):gmatch("(.-)\n\n") do
		local rows = {}
		for row in (para .. "\n"):gmatch("(.-)\n") do if row ~= "" then rows[#rows + 1] = row end end
		for i, row in ipairs(rows) do
			local last = i == #rows
			if row:sub(1, 2) == "- " then Paragraph(lines, row, INK, last and { gapAfter = true } or nil, 1)
			else Paragraph(lines, row, INK, last and { gapAfter = true } or nil) end
		end
	end
end

local function Button(lines, key, preview)
	local b = BUTTONS[key]
	if not b then return end
	local live = not preview or b.preview
	lines[#lines + 1] = Paper("> " .. L[b.label], INK, { onClick = live and Go(b.fn) or nil })
end

local function Item(lines, done, label, parts, button, fn, preview)
	lines[#lines + 1] = Paper((done and L.RB_GM_DONE or L.RB_GM_TODO):format(label), INK)
	for _, part in ipairs(parts) do Paragraph(lines, part, INK, nil, 1) end
	lines[#lines + 1] = Paper("> " .. button, INK, { indent = 1, gapAfter = true, onClick = not preview and Go(fn) or nil })
end

local function ChecklistLines(lines, preview)
	local st = Brief.GMState()
	local guild = st.guild
	if preview then Paragraph(lines, L.RB_GM_PREVIEW, INK, { gapAfter = true }) end
	lines[#lines + 1] = Paper(L.RB_GM_MUST, TITLE, { gapAfter = true })
	local max = ns.Nominees and ns.Nominees.MAX_CENTURIONS or 25
	Item(lines, st.legates > 0, L.RB_GM_LEGATES:format(st.legates, max),
		{ L.RB_GM_JOB:format(L.RB_GM_LEGATES_JOB), L.RB_GM_SHOWS:format(L.RB_GM_LEGATES_SHOWS), L.RB_GM_UNLOCKS:format(L.RB_GM_LEGATES_UNLOCKS) },
		L.RB_GM_BTN_LEGATE, function()
			ns.UI.SelectTab("throne")
			ns.Nominees.Prompt("centurion")
		end, preview)
	for _, d in ipairs(DEPTS) do
		local name = d.name
		Item(lines, st.named[d.code] == true, L["RB_GM_" .. d.code],
			{ L.RB_GM_JOB:format(L["RB_GM_" .. d.code .. "_JOB"]), L.RB_GM_SHOWS:format(L["RB_GM_" .. d.code .. "_SHOWS"]),
				L.RB_GM_UNLOCKS:format(L["RB_GM_" .. d.code .. "_UNLOCKS"]) },
			L.RB_GM_BTN_NAME, function()
				ns.UI.SelectTab("throne")
				ns.Nominees.Prompt("correspondent", name)
			end, preview)
	end
	Item(lines, st.church, L.RB_GM_CHURCH,
		{ L.RB_GM_JOB:format(L.RB_GM_CHURCH_JOB), L.RB_GM_SHOWS:format(L.RB_GM_CHURCH_SHOWS), L.RB_GM_UNLOCKS:format(L.RB_GM_CHURCH_UNLOCKS) },
		L.RB_GM_BTN_CHURCH, function()
			ns.UI.SelectTab("church")
			ns.ChurchView.Show("name")
			ns.ChurchView.Ask("correspondent", { guild = guild })
		end, preview)
	lines[#lines + 1] = Paper(L.RB_GM_WORTH, TITLE, { gapAfter = true })
	Item(lines, st.watchers, L.RB_GM_WATCHERS, { L.RB_GM_WATCHERS_TEXT }, L.RB_GM_BTN_WATCHER, function()
		if ns.Watch and ns.Watch.Show then ns.Watch.Show("chat") end
		ns.UI.SelectTab("watch")
		ns.ShowDialog("CHILLZONE_WATCHCHAT_NAME", L.WATCHCHAT_WATCHERS_ADD, nil, { kind = "watcher" })
	end, preview)
	Item(lines, st.charter, L.RB_GM_CHARTER, { L.RB_GM_CHARTER_TEXT }, L.RB_GM_BTN_WRITE, function()
		ns.UI.SelectTab("realm")
		ns.Views.ShowPage("guildcharter")
	end, preview)
	Item(lines, st.bank, L.RB_GM_BANK, { L.RB_GM_BANK_TEXT }, L.RB_GM_BTN_OPEN, function() ns.Treasury.OpenOwnGuild() end, preview)
end

local function Back()
	current, previewing = nil, nil
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local function LetterLines(entry, q)
	local preview = entry.preview == true
	local title = Brief.Title(entry)
	local lines = { Paper(L.RB_BACK, INK, { gapAfter = true, onClick = Back }), Paper(title, TITLE, { gapAfter = true }) }
	if preview then Paragraph(lines, L.RB_PREVIEW_LETTER, INK, { gapAfter = true }) end
	if entry.kind == "guildmaster" then
		Words(lines, L.RB_GM_OPEN)
		ChecklistLines(lines, preview)
		Words(lines, L.RB_GM_GET)
		Words(lines, L.RB_GM_CLOSE)
	else
		for _, text in ipairs(Body(entry)) do
			if not q or ns.Holds(q, title, text) then Words(lines, text) end
		end
	end
	local buttons = KINDS[entry.kind] and KINDS[entry.kind].buttons or {}
	if entry.kind == "correspondent" then
		local d = Dept(entry.dept)
		buttons = { "guild", d and d.button or nil }
	end
	for _, key in ipairs(buttons) do Button(lines, key, preview) end
	if #buttons > 0 then lines[#lines].gapAfter = true end
	lines[#lines + 1] = Paper(L.HONOR_LETTER_SIGN, INK)
	return lines
end
Brief.LetterLines = LetterLines

-- Every letter, in the order the preview lists them: { kind, dept, label }.
function Brief.PreviewList()
	local out = {}
	local function Put(kind, dept, label) out[#out + 1] = { kind = kind, dept = dept, label = label } end
	Put("launch"); Put("guildmaster"); Put("council")
	for _, d in ipairs(DEPTS) do Put("council", d.name, L.RB_PREVIEW_DEPT:format(L.RB_COUNCIL_TITLE, d.name)) end
	for _, kind in ipairs({ "steward", "hand", "treasurer", "keeper", "legate" }) do Put(kind) end
	for _, d in ipairs(DEPTS) do Put("correspondent", d.name) end
	for _, kind in ipairs({ "churchcorr", "watcher", "moderator", "apostle", "apostlelaunch", "missionary" }) do Put(kind) end
	for _, x in ipairs(out) do x.label = x.label or Brief.Title({ kind = x.kind, dept = x.dept }) end
	return out
end

function Brief.Link()
	local own = Brief.LIVE == true and #Brief.Letters() > 0
	if not own and not Brief.PreviewAllowed() then return nil end
	return { text = "|TInterface\\Icons\\INV_Letter_15:14:14|t |cffffd200" .. (own and L.RB_LINK or L.RB_LINK_PREVIEW) .. "|r", gapAfter = true,
		onClick = function() Brief.Slash("list") end }
end

function Brief.Page(q)
	if previewing then return LetterLines(previewing, q) end
	local selected = current and Find(current) or nil
	if selected then return LetterLines(selected, q) end
	local lines = {}
	lines[#lines + 1] = Paper(L.RB_REALM_BACK, INK, { gapAfter = true, onClick = function() Back(); ns.Views.ShowPage(nil) end })
	lines[#lines + 1] = Paper(L.RB_PAGE_TITLE, TITLE, { gapAfter = true })
	Paragraph(lines, L.RB_PAGE_NOTE, INK, { gapAfter = true })
	local letters = Brief.LIVE == true and Brief.Letters() or {}
	if #letters == 0 then Paragraph(lines, L.RB_NONE, INK, { gapAfter = true }) end
	for i = #letters, 1, -1 do
		local e, id = letters[i], letters[i].id
		local title = Brief.Title(e)
		if not q or ns.Holds(q, title) then
			lines[#lines + 1] = Paper((e.read and "" or "|cffffd200") .. "> " .. title .. (e.read and "" or "|r"), INK, {
				right = type(date) == "function" and date("%Y-%m-%d", e.t) or "", onClick = function() Brief.Open(id) end,
			})
		end
	end
	if #letters > 0 then lines[#lines].gapAfter = true end
	if Brief.PreviewAllowed() then
		lines[#lines + 1] = Paper(L.RB_PREVIEW_HEAD, TITLE, { gapAfter = true })
		Paragraph(lines, L.RB_PREVIEW_NOTE, INK, { gapAfter = Brief.LIVE == true })
		if Brief.LIVE ~= true then Paragraph(lines, L.RB_PREVIEW_OFF, INK, { gapAfter = true }) end
		for _, x in ipairs(Brief.PreviewList()) do
			local kind, dept = x.kind, x.dept
			if not q or ns.Holds(q, x.label) then
				lines[#lines + 1] = Paper("> " .. x.label, INK, { onClick = function() Brief.Preview(kind, dept) end })
			end
		end
	end
	return lines
end

-- The Workshop's line to the preview (Workshop.Build; not in its copy).
function Brief.WorkshopLines(lines)
	if not Brief.PreviewAllowed() then return end
	lines[#lines + 1] = { text = "|cffffd200> " .. L.RB_WORKSHOP_LINK .. "|r", noReport = true, gapAfter = true,
		onClick = function() Brief.Slash("list") end }
end

-- A guild master's Guild tab (King.Build): his letter, with how many of the eight he named. Only his
-- own (never a View as preview), once the letters are out and his letter is made.
function Brief.GuildTabLine(lines)
	if Brief.LIVE ~= true or type(lines) ~= "table" then return false end
	local _, _, rank = GetGuildInfo("player")
	if rank ~= 0 then return false end
	local e = Find(nil, "guildmaster")
	if not e then return false end
	local id = e.id
	local done, total = Brief.GMProgress()
	table.insert(lines, math.min(2, #lines + 1), Paper("> " .. L.RB_GUILD_TAB_LINK:format(done, total), INK,
		{ gapAfter = true, onClick = function() Brief.Open(id) end }))
	return true
end

-- The launch letter is the version letter of LAUNCH_VERSION once the letters are out: the King's
-- signature and the site's link with it (Letters.lua reads L.LETTER_<v>_SIGNED and _LINK). A release
-- that wrote its own letter for that version keeps it.
function Brief.RegisterLaunch()
	local Lt = ns.Letters
	if Brief.LIVE ~= true or type(Lt) ~= "table" or Lt.missing or type(Lt.LIST) ~= "table" then return false end
	local key = "LETTER_" .. Brief.LAUNCH_VERSION:gsub("%.", "_")
	if rawget(L, key) ~= nil then return false end
	L[key .. "_TITLE"], L[key], L[key .. "_SIGNED"], L[key .. "_LINK"] = L.RB_LAUNCH_TITLE, L.RB_LAUNCH, L.HONOR_LETTER_SIGN, Brief.SITE
	for _, v in ipairs(Lt.LIST) do if v == Brief.LAUNCH_VERSION then return true end end
	table.insert(Lt.LIST, 1, Brief.LAUNCH_VERSION)
	return true
end
Brief.RegisterLaunch()

ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "rolebriefings", Link = Brief.Link, Lines = Brief.Page,
	tip = "RB_PAGE_NOTE", parchment = true, beforeBoard = true })

local waiting = false
local function Soon()
	if Brief.LIVE ~= true or waiting then return end
	waiting = true
	ns.After(Brief.SCAN_WAIT, "duty letters", function()
		waiting = false
		Brief.Arrived(Brief.Scan(false))
	end)
end
-- (1.4.0, the author's ask before the launch: "uma carta de cargo deve abrir, mas ela so deve esperar a
-- outra") A new duty letter opens by itself, never over the version letter: it waits while that letter
-- holds the screen (shown, still to show, its privacy page first) or the game is in combat, a few
-- seconds at a time and OPEN_TRIES at most (its line in chat was said anyway). The newest unread one
-- opens; a read one never reopens by itself.
Brief.OPEN_WAIT = 15 -- after the scan that made it (the version letter's LOGIN_WAIT goes first)
Brief.OPEN_EVERY = 5
Brief.OPEN_TRIES = 120
local opening = false
function Brief.OpenWhenFree(tries)
	tries = tonumber(tries) or 0
	if Brief.LIVE ~= true then opening = false return false end
	local Lt = ns.Letters
	local held = type(Lt) == "table" and not Lt.missing and type(Lt.Holds) == "function" and Lt.Holds() == true
	if held or (InCombatLockdown and InCombatLockdown()) then
		if tries < Brief.OPEN_TRIES then
			opening = true
			ns.After(Brief.OPEN_EVERY, "duty letter open", function() Brief.OpenWhenFree(tries + 1) end)
		else
			opening = false
		end
		return false
	end
	opening = false
	local letters = Brief.Letters()
	for i = #letters, 1, -1 do
		local e = letters[i]
		if e.read ~= true then return Brief.Open(e.id) end
	end
	return false
end
-- A scan made new letters: the newest opens once it may.
function Brief.Arrived(made)
	if Brief.LIVE ~= true or (tonumber(made) or 0) <= 0 or opening then return false end
	opening = true
	ns.After(Brief.OPEN_WAIT, "duty letter open", function() Brief.OpenWhenFree(0) end)
	return true
end
ns.On("LOGIN", function()
	-- The role sources have already loaded when LOGIN is fired.  Scan once now, then rely on their
	-- change events below; an idle client must not keep a polling timer merely to maintain letters.
	Brief.Arrived(Brief.Scan(false))
end)
for _, event in ipairs({ "DATA_CHANGED", "CHURCH_CHANGED", "TREASURY_CHANGED", "WATCH_CHANGED", "THRONE_CHANGED" }) do
	ns.On(event, Soon)
end

-- Test-only state reset; saved letters are reset by replacing ns.db.roleBriefings.
function Brief.Reset() current, previewing, waiting, opening = nil, nil, false, false end
