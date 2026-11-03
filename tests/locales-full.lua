-- 1.4.0 (the author, 11-03: "Vamos traduzir o aplicativo para todos eles. Garantir que esteja tudo
-- funcionando em todos eles para o lançamento"): the language files translate every line of the
-- addon, Spanish (esES and esMX), German, French, Italian and Russian, besides English and
-- Portuguese. Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local ROOT = assert(extra and extra.ROOT, "tests/run.lua hands ROOT to this file")
local ADDON = ROOT .. "Olympus/"

local LANGS = { deDE = "deDE", esES = "esES", esMX = "esES", frFR = "frFR", itIT = "itIT", ruRU = "ruRU" }
-- Lines whispered to another player stay English, the network's own language: the one who reads
-- them may not share the sender's. Every language file leaves them out.
local WHISPERS = { MENTOR_TO_CAPTAIN = true, MENTOR_TO_RECRUIT = true, JOIN_POINT_TEXT = true,
	CHARTER_LETTER_TEXT = true, VERSION_ASK_WHISPER = true, WANTED_THANK_TEXT = true }
local function Whisper(k) return WHISPERS[k] or k:match("^MATCH_SAY_") ~= nil end

-- Every locale file in the TOC's order, as a game in `code` loads them: the namespace.
local function Load(code)
	local lns = {}
	local saved = GetLocale
	GetLocale = function() return code end
	local ok, err = pcall(function()
		for line in io.lines(ADDON .. "Olympus.toc") do
			local f = line:match("^%s*(Locales%.lua)%s*$") or line:match("^%s*(Locales[\\/].-%.lua)%s*$")
			if f then assert(loadfile(ADDON .. f:gsub("\\", "/")))("Olympus", lns) end
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
			assert(loadfile(ADDON .. "Locales.lua"))("Olympus", lns)
			lns.Locale = function() calls = calls + 1 return 0 end
			for _, file in ipairs({ "deDE", "esES", "frFR", "itIT", "ruRU" }) do
				assert(loadfile(ADDON .. "Locales/" .. file .. ".lua"))("Olympus", lns)
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
