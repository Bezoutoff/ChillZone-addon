-- 1.4.0 (the author, 11-03: "Vamos traduzir o aplicativo para todos eles. Garantir que esteja tudo
-- funcionando em todos eles para o lançamento"): the language files translate every line of the
-- addon, Spanish (esES and esMX), German, French, Italian and Russian, besides English and
-- Portuguese. Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local ROOT = assert(extra and extra.ROOT, "tests/run.lua hands ROOT to this file")
local ADDON = ROOT .. "ChillZone/"

local LANGS = { deDE = "deDE", esES = "esES", esMX = "esES", frFR = "frFR", itIT = "itIT", ruRU = "ruRU" }
-- Lines whispered to another player stay English, the network's own language: the one who reads
-- them may not share the sender's. Every language file leaves them out.
local WHISPERS = { MENTOR_TO_CAPTAIN = true, MENTOR_TO_RECRUIT = true, JOIN_POINT_TEXT = true,
	CHARTER_LETTER_TEXT = true, VERSION_ASK_WHISPER = true, WANTED_THANK_TEXT = true,
	-- (1.4.0, the guild verification: the guild master's whisper to a verifier, the ask to the High
	-- Council and a verifier's nudge to a guild master.)
	VERIFY_WHISPER_TEXT = true, VERIFY_ASK_TEXT = true, VERIFY_NUDGE_TEXT = true }
local function Whisper(k) return WHISPERS[k] or k:match("^MATCH_SAY_") ~= nil end

-- Every locale file in the TOC's order, as a game in `code` loads them: the namespace.
local function Load(code)
	local lns = {}
	local saved = GetLocale
	GetLocale = function() return code end
	local ok, err = pcall(function()
		for line in io.lines(ADDON .. "ChillZone.toc") do
			local f = line:match("^%s*(Locales%.lua)%s*$") or line:match("^%s*(Locales[\\/].-%.lua)%s*$")
			if f then assert(loadfile(ADDON .. f:gsub("\\", "/")))("ChillZone", lns) end
		end
	end)
	GetLocale = saved
	if not ok then error(err, 0) end
	return lns
end

local english = Load("enUS")
local function EnglishKeys()
	local n = 0
	for k, v in pairs(english.L) do if type(v) == "string" and not Whisper(k) then n = n + 1 end end
	return n
end

test("languages (1.4.0): each language file takes every line it carries, nearly every English line, and leaves none out", function()
	local total = EnglishKeys()
	for code, file in pairs(LANGS) do
		local lns = Load(code)
		local report = lns.LocaleReport()
		assert(not report:find("left out", 1, true), file .. ": " .. report)
		local taken = tonumber(report:match("^" .. code .. ", (%d+) of %d+ lines$"))
		assert(taken, file .. ": " .. report)
		assert(taken >= math.floor(total * 0.99), ("%s: %d of %d English lines"):format(file, taken, total))
		-- Lines a member reads first are in the language.
		for _, k in ipairs({ "TAB_CENSUS", "ARMS", "ARMY_PEOPLE", "CENSUS_STATS_SERVERS", "CONSENT_TITLE", "ACCORD_ACCEPT" }) do
			assert(lns.L[k] ~= english.L[k], file .. " translates " .. k)
		end
	end
end)

test("languages (1.4.0): lines whispered to another player stay English in every language", function()
	local n = 0
	for k, v in pairs(english.L) do
		if type(v) == "string" and Whisper(k) then
			n = n + 1
			for code, file in pairs(LANGS) do eq(Load(code).L[k], v, file .. " " .. k) end
		end
	end
	assert(n >= 10, "whispered lines: " .. n)
end)

test("languages (1.4.0): an English or Portuguese game builds no other language's table", function()
	for _, code in ipairs({ "enUS", "enGB", "ptBR" }) do
		local calls = 0
		local lns = {}
		local saved = GetLocale
		GetLocale = function() return code end
		local ok, err = pcall(function()
			assert(loadfile(ADDON .. "Locales.lua"))("ChillZone", lns)
			lns.Locale = function() calls = calls + 1 return 0 end
			for _, file in ipairs({ "deDE", "esES", "frFR", "itIT", "ruRU" }) do
				assert(loadfile(ADDON .. "Locales/" .. file .. ".lua"))("ChillZone", lns)
			end
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		eq(calls, 0, code .. ": every language file stops at its first line")
	end
end)

test("languages (1.4.0): the Agenda reads a day or today/tomorrow in each language", function()
	local W = assert(ns.Week, "Week.lua")
	for _, input in ipairs({ "lun 20:00 Banda", "mié 21:00 Mazmorra", "mañana 19h Corte", "hoy 22:30 Raid",
		"Do 20:00 Schlachtzug", "morgen 20h Rat", "sam 20:00 Raid", "demain 21:30 Cour", "aujourd'hui 22:00 Raid",
		"gio 20:00 Incursione", "domani 21:00 Corte", "Пт 20:00 Рейд", "завтра 21:00 Совет", "сб 20:00 Рейд",
		"Sat 20:00 Raid night", "amanhã 20h Corte" }) do
		local at, title = W.Parse(input)
		assert(at and title and title ~= "", "parsed: " .. input)
	end
	eq(W.Parse("xyz 20:00 Raid"), nil, "an unknown word is no day")
end)

test("languages (1.4.0): the lists (places, weekdays, months, class and race names, honours, the King's letters, the nickname words) are each language's own, every key the English one's", function()
	for code, file in pairs(LANGS) do
		local L = Load(code).L
		for name, en in pairs(english.L) do
			if type(en) == "table" then
				local t = L[name]
				assert(type(t) == "table" and t ~= en, file .. " " .. name .. ": its own list")
				for k, v in pairs(en) do
					assert(type(t[k]) == "string" and t[k] ~= "", file .. " " .. name .. "[" .. tostring(k) .. "]")
					eq(ns.LocaleCodes(t[k]), ns.LocaleCodes(v), file .. " " .. name .. "[" .. tostring(k) .. "] codes")
				end
				for k in pairs(t) do assert(en[k] ~= nil, file .. " " .. name .. ": no key the English lacks: " .. tostring(k)) end
			end
		end
		assert(L.WEEK_WEEKDAYS[1] ~= english.L.WEEK_WEEKDAYS[1], file .. ": its own Sunday")
	end
end)

-- 1.4.0 (the Board's groups and IsChillZoneMember join the API): what another addon's Yes gives grew
-- (API.CONSENT_VERSION 10), and the two privacy lines say so. (Changed on purpose: they were held in
-- English until translated from contract 10's words; translated now, each language names the groups
-- and the unit check in its own words, never the earlier English's.)
local CONTRACT_10 = { "API_CONSENT_TEXT", "API_CONSENT_TEXT_BASIC" }
test("languages (1.4.0): the API's privacy lines, translated from contract 10's words, in every language", function()
	assert(english.L.API_CONSENT_TEXT:find("Board's group listings", 1, true), "the English line names the groups")
	assert(english.L.API_CONSENT_TEXT:find("is in an ChillZone guild", 1, true), "and the unit check")
	for code, file in pairs(LANGS) do
		local L = Load(code).L
		for _, k in ipairs(CONTRACT_10) do
			assert(type(L[k]) == "string" and L[k] ~= english.L[k], file .. " " .. k .. ": its own words")
			eq(ns.LocaleCodes(L[k]), ns.LocaleCodes(english.L[k]), file .. " " .. k .. " codes")
			assert(#L[k] > #english.L[k] * 0.6, file .. " " .. k .. ": the whole of contract 10, not the earlier shorter line")
		end
	end
end)
