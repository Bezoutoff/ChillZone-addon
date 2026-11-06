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
	assert(ReadFile(h.ADDON_DIR .. "Relay.lua"):find("Relay.LAUNCH_PINS = {}", 1, true), "no relays pinned")
	assert(ReadFile(h.ADDON_DIR .. "API.lua"):find("API.AUTHORIZED = {}", 1, true), "no partner addon trusted")
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
