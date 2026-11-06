-- ChillZone's own tests: what a release holds (Core.lua's network and people as the release has
-- them, not tests/fixtures/identity.lua's) and what the fork changed.
local ns, test, eq, h = ...

-- The first 32 hex digits of ChillZone's public N (ChillZone/Sign.lua).
local CHILLZONE_N_PREFIX = "8c3e3436516bc7c5846363269e111fbe"

local function ReadFile(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- Core.lua as a release loads it (RAW_LOADFILE: no test identity), in a table of its own.
local function Release()
	local r = {}
	for _, file in ipairs({ "Bootstrap", "Locales" }) do assert(loadfile(h.ADDON_DIR .. file .. ".lua"))("ChillZone", r) end
	assert(RAW_LOADFILE(h.ADDON_DIR .. "Core.lua"))("ChillZone", r)
	r.faction, r.realm, r.me, r.db = "Alliance", "Realm", "Tester-Realm", { guilds = {} }
	return r
end

-- Relay.lua as a release loads it (RAW_LOADFILE: no test pins); the modules it registers with
-- (ns.Comm, ns.Net, ...) are stubs whose every function does nothing.
local function ReleaseRelay()
	local noop
	noop = setmetatable({}, { __index = function() return function() end end, __call = function() end })
	local rel = setmetatable({}, { __index = function() return noop end })
	assert(RAW_LOADFILE(h.ADDON_DIR .. "Relay.lua"))("ChillZone", rel)
	return rel
end

test("ChillZone release: the network is <Чиллзон> and <Чиллзон Навсегда> by their exact names, no name word", function()
	local r = Release()
	eq(r.NAME_WORD, nil)
	eq(r.IsFederation("Чиллзон"), true, "the King's guild")
	eq(r.IsFederation("Чиллзон Навсегда"), true, "shipped with the addon")
	eq(r.IsFederation("ChillZone II"), false, "no word of a name makes a guild ours in a release")
	eq(r.IsFederation("Чиллзон Навсегда II"), false, "nor a longer name")
	eq(r.IsFederation("Olympus"), false)
	eq(r.IsKingGuild("Чиллзон"), true); eq(r.IsKingGuild("Чиллзон Навсегда"), false)
	eq(r.IsMainGuildName("Чиллзон"), true)
	eq(r.WHO_WORD, "Чиллзон")
	r.faction = "Horde"
	eq(r.IsKingGuild("Чиллзон"), false, "no King's guild on the Horde")
end)

test("ChillZone release: no person is named in the code (the author's signed list names them)", function()
	local r = Release()
	eq(next(r.KING_CHARACTER), nil); eq(r.KING_NAME, nil)
	eq(r.TREASURER, nil); eq(#r.TREASURER_CHARACTERS, 0); eq(r.AUTHOR, nil)
	eq(next(r.REMOVED_BUILTIN), nil)
	eq(r.IsKingCharacter("Asmongold Asmongler-ClassicBetaPvP"), false)
	eq(r.IsTreasurer("Pyralis Ashandar-ClassicBetaPvP", "Чиллзон"), false)
	eq(#(r.AuthorCharacters()), 0)
	eq(r.KingName("Lead Chill-Realm"), "Lead Chill", "the King by his character's name")
	local rel = ReleaseRelay()
	local want = { "Вован Дубан", "Татарин Уфимский" }
	for _, fam in ipairs({ "ForeverPvE", "ForeverPvP" }) do
		eq(#rel.Relay.LAUNCH_PINS[fam], 2, fam)
		eq(rel.Relay.LAUNCH_PINS[fam][1], want[1], fam); eq(rel.Relay.LAUNCH_PINS[fam][2], want[2], fam)
	end
	assert(ReadFile(h.ADDON_DIR .. "API.lua"):find("API.AUTHORIZED = {}", 1, true), "no partner addon trusted")
end)

test("ChillZone release: the pinned relays are in Relay.Names on a Forever realm (either family)", function()
	local rel = ReleaseRelay()
	rel.ShortName, rel.ForeverFamily = ns.ShortName, ns.ForeverFamily
	rel.splitNames, rel.rdb, rel.me = true, {}, "Someone Else-Realm"
	rel.KingCharacter, rel.TreasurerPins, rel.AuthorCharacters = function() end, function() return {} end, function() return {} end
	for _, realm in ipairs({ "CAMWOWEU1Realm3PvP", "CAMWOWEU1Realm3PvE" }) do
		rel.realm = realm
		eq(rel.Relay.On(), true)
		eq(table.concat(rel.Relay.Names(), "|"), "Вован Дубан|Татарин Уфимский", realm)
	end
	rel.realm = "Realm"
	eq(#rel.Relay.Names(), 0, "no pins off Forever")
end)

test("ChillZone release: the signed lists are checked with ChillZone's key, not Olympus's", function()
	local text = ReadFile(h.ADDON_DIR .. "Sign.lua")
	assert(not text:find("84a62410ffd1872739d169af98d461de", 1, true), "Olympus's key is gone")
	assert(text:find('Sign.N = FromHex("' .. CHILLZONE_N_PREFIX, 1, true), "ChillZone's key")
end)

test("ChillZone release: a King named only by the signed list shows by his character's name in the Treasury", function()
	local T = ns.Treasury
	local saved = { name = ns.KING_NAME, is = ns.IsKingCharacter, faction = ns.faction, kc = ns.KingCharacter, me = ns.me, gi = GetGuildInfo, role = T.Role, mode = T.mode }
	local ok, err = pcall(function()
		ns.KING_NAME, ns.faction = nil, "Alliance" -- (as the release has it: no name in the code)
		ns.IsKingCharacter = function(name) return name == "Вован Дубан-Realm" end
		local text = T.DonationText("Вован Дубан-Realm", nil)
		assert(text:find("Вован Дубан", 1, true), "the donation line names the King: " .. tostring(text))
		assert(not text:find("?", 1, true), "not an unknown: " .. text)
		eq(ns.KingName("Вован Дубан-Realm"), "Вован Дубан")
		-- The keepers tab builds (it formats the King's line) and names him.
		ns.KingCharacter = function() return "Вован Дубан" end
		GetGuildInfo, ns.me = function() return "Чиллзон", "King", 0 end, "Вован Дубан-Realm"
		T.Role = function() return "king" end -- (the signed list makes him the King)
		T.Show("keepers")
		local page = {}
		for _, l in ipairs(T.Build()) do page[#page + 1] = tostring(l.text) end
		assert(table.concat(page, "\n"):find(ns.L.TREASURY_KEEPER_KING:format("Вован Дубан"), 1, true), "the keepers tab names the King: " .. table.concat(page, "|"))
	end)
	ns.KING_NAME, ns.IsKingCharacter, ns.faction, ns.KingCharacter = saved.name, saved.is, saved.faction, saved.kc
	GetGuildInfo, ns.me, T.Role, T.mode = saved.gi, saved.me, saved.role, saved.mode
	assert(ok, err)
end)

test("ChillZone: crafters: a Russian client's profession names (two bytes a letter) are listed whole", function()
	h.WithCraft(function(w, Cr)
		Cr.HandleListing("CHANNEL", "Kuznec-Realm",
			"W1~ChillZone Zeus~164:Кузнечное дело:150:300:12,Инженерное дело:Инженерное дело:120:300:8")
		local b = Cr.Board()
		eq(#b, 1)
		eq(#b[1].profs, 2, "27 and 29 bytes, 14 and 15 letters: both kept")
		eq(b[1].profs[1].name, "Кузнечное дело")
		Cr.HandleListing("CHANNEL", "Long-Realm", "W1~ChillZone Zeus~164:" .. ("Ж"):rep(25) .. ":150:300:12")
		eq(#Cr.Board(), 1, "more than 24 letters: still refused")
	end)
end)

-- The guilds' officers who take recruits (the owner's list, 2026-11-06): Forever's "First Surname",
-- Latin and Cyrillic (up to 31 bytes, 42 with "-ForeverPvP").
local OFFICERS = { "Wipe Copium", "Татарин Уфимский", "Peepo Ingore", "Vladimir Goyda", "Гулдан Казмодан",
	"Сундук Открою", "Yara Pimaru", "Джейн Джинджер", "Наруто Узумаки", "Метал Чел" }

test("ChillZone: the officers' names, Cyrillic and Latin, pass the addon's name checks whole", function()
	for _, name in ipairs(OFFICERS) do
		local full = ns.FullName(name, "ForeverPvP")
		eq(full, name .. "-ForeverPvP", name)
		eq(ns.ShortName(full), name, name)
		eq(ns.Workshop.NameLike(full), true, name)
		eq(ns.Workshop.NameLike(name), true, name)
	end
end)

test("ChillZone release: the addon speaks Russian on any client (ns.TEXT_LOCALE), the tests the client's language", function()
	eq(ns.TEXT_LOCALE, nil, "the tests' identity: the client's language")
	local savedLocale = GetLocale
	GetLocale = function() return "enUS" end
	local r = {}
	local ok, err = pcall(function()
		assert(loadfile(h.ADDON_DIR .. "Bootstrap.lua"))("ChillZone", r)
		assert(RAW_LOADFILE(h.ADDON_DIR .. "Locales.lua"))("ChillZone", r)
		assert(RAW_LOADFILE(h.ADDON_DIR .. "Locales/AccordText.lua"))("ChillZone", r) -- (the English line ruRU.lua overrides)
		assert(RAW_LOADFILE(h.ADDON_DIR .. "Locales/ruRU.lua"))("ChillZone", r)
	end)
	GetLocale = savedLocale
	if not ok then error(err, 0) end
	eq(r.TEXT_LOCALE, "ruRU")
	eq(r.TextLocale(), "ruRU")
	eq(r.L.ACCORD_ACCEPT, "Принимаю", "Russian on an English client")
end)

test("ChillZone help page: the guild master's Twitch is linked and the download link is labelled as such", function()
	local UI, uns = h.LoadUI()
	local L = uns.L
	eq(UI.LINKS.twitch, "https://www.twitch.tv/melharucos")
	local text = UI.HelpText()
	local function has(s) return text:find(s, 1, true) ~= nil end
	eq(has("  " .. L.HELP_TWITCH .. ": https://www.twitch.tv/melharucos"), true, "the Twitch line")
	eq(has("  " .. L.HELP_DOWNLOAD .. ": " .. UI.LINKS.curseforge), true, "the download line")
	eq(has("CurseForge: "), false, "no CurseForge label for a GitHub releases link")
end)

test("ChillZone release: KingName() with no argument names the signed King, else the word for the King, never '?'", function()
	local r = Release()
	-- (as the release has it: no name in the code, the King from the signed list)
	local savedKC = r.KingCharacter
	r.KingCharacter = function() return "Вован Дубан" end
	eq(r.KingName(), "Вован Дубан", "the signed King's character")
	eq(r.KingName("Lead Chill-Realm"), "Lead Chill", "the leader named, as before")
	r.KingCharacter = function() return nil end
	eq(r.KingName(), r.L.KING, "no King at all: the word")
	r.KingCharacter = savedKC
	r.faction = "Horde"
	eq(r.KingName(), "?", "the Horde's is unchanged")
end)

test("ChillZone release: the answer bank follows the text language (Russian texts on an English client)", function()
	local savedLocale, savedText = GetLocale, ns.TextLocale
	GetLocale, ns.TextLocale = function() return "enUS" end, function() return "ruRU" end
	local ok, err = pcall(function() eq(ns.Answers.English(), false) end)
	GetLocale, ns.TextLocale = savedLocale, savedText
	assert(ok, err)
	ns.TextLocale = function() return "enUS" end
	local ok2, err2 = pcall(function() eq(ns.Answers.English(), true) end)
	ns.TextLocale = savedText
	assert(ok2, err2)
end)

-- A ported upstream patch must not bring Olympus's people, guild or contact back into a text.
test("ChillZone release: no Olympus name or contact is left in a locale file's strings", function()
	local files = { h.ADDON_DIR .. "Locales.lua" }
	local p = assert(io.popen('ls "' .. h.ADDON_DIR .. 'Locales/"*.lua "' .. h.ADDON_DIR .. '../ChillZone_Arena/Locales/"*.lua 2>/dev/null'))
	for path in p:lines() do files[#files + 1] = path end
	p:close()
	assert(#files > 5, "the locale files were found: " .. #files)
	local banned = { "Asmon", "олимпи", "Олимпи", "Developus", "roachcouncil", "olympus-guild" }
	for _, path in ipairs(files) do
		-- (comments may mention them: whole `--` lines are left out)
		local text = ReadFile(path):gsub("\n[ \t]*%-%-[^\n]*", "\n")
		for _, word in ipairs(banned) do
			assert(not text:find(word, 1, true), path .. " holds '" .. word .. "'")
		end
	end
end)
