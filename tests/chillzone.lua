-- ChillZone's own tests: what a release holds (Core.lua's network and people as the release has
-- them, not tests/fixtures/identity.lua's) and what the fork changed.
local ns, test, eq, h = ...

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
