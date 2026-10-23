local ADDON, ns = ...
local L = ns.L

-- Durable, reopenable explanations for offices this character actually holds.  These are local
-- letters, not claims of authority: every action named here is still gated by its owning module.
-- Role previews are deliberately absent from CurrentRoles().
local Brief = {}
ns.RoleBriefings = Brief

Brief.RULE = 1
Brief.MAX = 48
Brief.PAPER_WRAP = 48

local current

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

local function Store()
	if type(ns.db) ~= "table" then return nil end
	local s = ns.db.roleBriefings
	if type(s) ~= "table" or s.rule ~= Brief.RULE then
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

local TITLES = {
	king = "RB_TITLE_KING", council = "RB_TITLE_COUNCIL", steward = "RB_TITLE_STEWARD",
	hand = "RB_TITLE_HAND", guildmaster = "RB_TITLE_GM", watch = "RB_TITLE_WATCH",
	treasurer = "RB_TITLE_TREASURER", apostle = "RB_TITLE_APOSTLE", missionary = "RB_TITLE_MISSIONARY",
	churchcorr = "RB_TITLE_CHURCH_CORR", legate = "RB_TITLE_LEGATE", correspondent = "RB_TITLE_CORRESPONDENT",
}
local BODIES = {
	king = { "RB_KING_1", "RB_KING_2", "RB_KING_3" },
	council = { "RB_COUNCIL_1", "RB_COUNCIL_2", "RB_COUNCIL_3" },
	steward = { "RB_STEWARD_1", "RB_STEWARD_2" },
	hand = { "RB_HAND_1", "RB_HAND_2" },
	guildmaster = { "RB_GM_1", "RB_GM_2", "RB_GM_3" },
	watch = { "RB_WATCH_1", "RB_WATCH_2", "RB_WATCH_3" },
	treasurer = { "RB_TREASURER_1", "RB_TREASURER_2" },
	apostle = { "RB_APOSTLE_1", "RB_APOSTLE_2", "RB_APOSTLE_3",
		"RB_MISSIONARY_C1", "RB_MISSIONARY_C2", "RB_MISSIONARY_C3", "RB_MISSIONARY_C4", "RB_MISSIONARY_C5", "RB_MISSIONARY_C6" },
	missionary = { "RB_MISSIONARY_1", "RB_MISSIONARY_2", "RB_MISSIONARY_C1", "RB_MISSIONARY_C2",
		"RB_MISSIONARY_C3", "RB_MISSIONARY_C4", "RB_MISSIONARY_C5", "RB_MISSIONARY_C6" },
	churchcorr = { "RB_CHURCH_CORR_1", "RB_CHURCH_CORR_2" },
	legate = { "RB_LEGATE_1", "RB_LEGATE_2", "RB_LEGATE_3" },
	correspondent = { "RB_CORRESPONDENT_1", "RB_CORRESPONDENT_2", "RB_CORRESPONDENT_3" },
}

function Brief.Title(entry)
	if type(entry) ~= "table" then return L.RB_PAGE_TITLE end
	local title = L[TITLES[entry.kind] or ""] or L.RB_PAGE_TITLE
	if entry.kind == "correspondent" then return title:format(Plain(entry.dept or "?", 60)) end
	return title
end

local function Body(entry)
	local out = {}
	for _, key in ipairs(BODIES[entry.kind] or {}) do
		local text = L[key]
		if type(text) == "string" then
			if entry.kind == "correspondent" then
				local dept = Plain(entry.dept or "?", 60)
				if key == "RB_CORRESPONDENT_1" then text = text:format(dept)
				elseif key == "RB_CORRESPONDENT_2" then text = text:format(Plain(entry.duty or dept, 180)) end
			end
			out[#out + 1] = text
		end
	end
	return out
end

function Brief.Letters()
	local out, s, owner = {}, Store(), Owner()
	for _, e in ipairs(s and s.entries or {}) do if e.owner == owner then out[#out + 1] = e end end
	table.sort(out, function(a, b) return a.t == b.t and a.id < b.id or a.t < b.t end)
	return out
end

local function Add(list, kind, signature, data)
	data = type(data) == "table" and data or {}
	data.kind, data.signature = kind, signature
	list[#list + 1] = data
end

-- Current, real roles only.  This intentionally does not consult King.Preview, Nominees.DevView,
-- ViewAs or Watch.CouncilDeskShown.
local function CurrentRoles()
	local roles = {}
	if not ns.IsMember() then return roles end
	local guild, _, rank = GetGuildInfo("player")
	local king = Safe(ns.King, "IsKing") == true
	if king then Add(roles, "king", "king:" .. tostring(guild or ""), { guild = guild }) end
	if ns.IsHighCouncillor(ns.me) == true then Add(roles, "council", "council:" .. Owner()) end
	if Safe(ns.King, "IsSteward") == true then Add(roles, "steward", "steward:" .. Owner()) end
	if Safe(ns.King, "IsHand") == true then Add(roles, "hand", "hand:" .. Owner()) end
	if rank == 0 and type(guild) == "string" and ns.IsFederation(guild) and not king then
		Add(roles, "guildmaster", "guildmaster:" .. Lower(guild), { guild = guild })
	end
	if Safe(ns.Watch, "CanRead") == true then Add(roles, "watch", "watch:" .. Lower(guild), { guild = guild }) end
	if Safe(ns.Treasury, "RealKeeper") == true then Add(roles, "treasurer", "treasurer:" .. Lower(guild), { guild = guild }) end

	local churchRole = Safe(ns.Church, "Role", ns.me)
	local place = Safe(ns.Church, "Place", ns.me)
	local churchStamp = type(place) == "table" and tostring(place.since or place.at or place.ac or place.net or "") or ""
	if churchRole == "A" then Add(roles, "apostle", "apostle:" .. churchStamp)
	elseif churchRole == "M" then Add(roles, "missionary", "missionary:" .. churchStamp)
	elseif churchRole == "C" then Add(roles, "churchcorr", "churchcorr:" .. Lower(guild), { guild = guild }) end

	local role, dept = Safe(ns.Nominees, "RoleOf", ns.me, guild)
	if role == "centurion" then
		Add(roles, "legate", "legate:" .. Lower(guild), { guild = guild })
	elseif role == "correspondent" and type(dept) == "string" then
		Add(roles, "correspondent", "correspondent:" .. Lower(guild) .. ":" .. Lower(dept), {
			guild = guild, dept = dept, duty = Safe(ns.Nominees, "DepartmentHelp", dept),
		})
	end
	return roles
end
Brief.CurrentRoles = CurrentRoles -- focused tests; read-only result

local function Queue(s, role, quiet)
	s.seq = s.seq + 1
	local now = ns.Now()
	local e = { id = Owner() .. ":" .. tostring(now) .. ":" .. tostring(s.seq), owner = Owner(),
		kind = role.kind, signature = role.signature, t = now, read = false,
		guild = role.guild, dept = role.dept, duty = role.duty }
	s.entries[#s.entries + 1] = e
	while #s.entries > Brief.MAX do table.remove(s.entries, 1) end
	if not quiet then ns.Print(L.RB_READY:format(Brief.Title(e))) end
	return e
end

-- Queue once per verifiable appointment signature.  A missing role is not enough to erase the
-- stamp: at login the live roster and relayed appointment books can be temporarily unknown, and
-- treating that gap as a removal would manufacture the same letter on every login.  Sources with
-- a real appointment epoch (the Church) put it in their signature, so an actual later appointment
-- still receives a new briefing.
function Brief.Scan(quiet)
	local s, owner = Store(), Owner()
	if not s or owner == "" then return 0 end
	local prefix, made = owner .. "|", 0
	for _, role in ipairs(CurrentRoles()) do
		local slot = prefix .. role.kind .. (role.kind == "correspondent" and (":" .. Lower(role.dept)) or "")
		if s.active[slot] ~= role.signature then
			s.active[slot] = role.signature
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
		if (id == nil or e.id == id) and (kind == nil or e.kind == kind) then return e end
	end
	return nil
end

function Brief.Open(id)
	local e = Find(id)
	if not e then return false, "missing" end
	e.read, current = true, e.id
	if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("realm") end
	if ns.Views and ns.Views.ShowPage then ns.Views.ShowPage("rolebriefings") end
	return true
end

function Brief.OpenKind(kind)
	Brief.Scan(true)
	local e = Find(nil, kind)
	if not e then return false, "missing" end
	return Brief.Open(e.id)
end

function Brief.Slash(rest)
	rest = Lower(tostring(rest or ""):match("^%s*(.-)%s*$"))
	Brief.Scan(true)
	if rest ~= "" and rest ~= "list" then
		if Brief.OpenKind(rest) then return true end
	end
	current = nil
	if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("realm") end
	if ns.Views and ns.Views.ShowPage then ns.Views.ShowPage("rolebriefings") end
	return true
end

local INK, TITLE = "QuestFont", "QuestTitleFont"
local function Paper(text, font, extra)
	local line = { text = text, font = font or INK }
	for key, value in pairs(extra or {}) do line[key] = value end
	return line
end
local function Paragraph(lines, text, font, extra)
	local row = ""
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + #word + 1 > Brief.PAPER_WRAP then
			lines[#lines + 1] = Paper(row, font)
			row = word
		else row = row == "" and word or row .. " " .. word end
	end
	if row ~= "" then lines[#lines + 1] = Paper(row, font, extra) end
end

function Brief.Link()
	if #Brief.Letters() == 0 then return nil end
	return { text = "|TInterface\\Icons\\INV_Letter_15:14:14|t |cffffd200" .. L.RB_LINK .. "|r", gapAfter = true,
		onClick = function() Brief.Slash("list") end }
end

function Brief.Page(q)
	local letters = Brief.Letters()
	local selected = current and Find(current) or nil
	local lines = {}
	if selected then
		lines[#lines + 1] = Paper(L.RB_BACK, INK, { gapAfter = true, onClick = function() current = nil; ns.UI.Refresh() end })
		lines[#lines + 1] = Paper(Brief.Title(selected), TITLE, { gapAfter = true })
		local when = type(date) == "function" and date("%Y-%m-%d", selected.t) or tostring(selected.t)
		Paragraph(lines, L.RB_APPOINTED:format(ns.DisplayName(ns.me), when), INK, { gapAfter = true })
		local body = Body(selected)
		for i, text in ipairs(body) do
			if not q or ns.Holds(q, Brief.Title(selected), text) then
				if (selected.kind == "missionary" or selected.kind == "apostle") and i == 3 then
					lines[#lines + 1] = Paper(L.RB_CHECKLIST, TITLE)
				end
				Paragraph(lines, text, INK, { gapAfter = true })
			end
		end
		return lines
	end
	lines[#lines + 1] = Paper(L.RB_REALM_BACK, INK, { gapAfter = true, onClick = function() ns.Views.ShowPage(nil) end })
	lines[#lines + 1] = Paper(L.RB_PAGE_TITLE, TITLE, { gapAfter = true })
	Paragraph(lines, L.RB_PAGE_NOTE, INK, { gapAfter = true })
	if #letters == 0 then Paragraph(lines, L.RB_NONE, INK); return lines end
	for i = #letters, 1, -1 do
		local e, id = letters[i], letters[i].id
		local title = Brief.Title(e)
		if not q or ns.Holds(q, title) then
			lines[#lines + 1] = Paper((e.read and "" or "|cffffd200") .. "> " .. title .. (e.read and "" or "|r"), INK, {
				right = type(date) == "function" and date("%Y-%m-%d", e.t) or "", onClick = function() Brief.Open(id) end,
			})
		end
	end
	return lines
end

ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "rolebriefings", Link = Brief.Link, Lines = Brief.Page,
	tip = "RB_PAGE_NOTE", parchment = true, beforeBoard = true })

ns.On("LOGIN", function()
	-- The role sources have already loaded when LOGIN is fired.  Scan once now, then rely on their
	-- change events below; an idle client must not keep a polling timer merely to maintain letters.
	Brief.Scan(false)
end)
for _, event in ipairs({ "DATA_CHANGED", "CHURCH_CHANGED", "TREASURY_CHANGED", "WATCH_CHANGED", "THRONE_CHANGED" }) do
	ns.On(event, function() Brief.Scan(false) end)
end

-- Test-only state reset; saved letters are reset by replacing ns.db.roleBriefings.
function Brief.Reset() current = nil end
