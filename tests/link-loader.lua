-- 1.4.0: ChillZone Link (the Discord role, /cz discord) is its own load-on-demand addon, ChillZone_Link,
-- kept and tested in its own repository. This addon carries only its loader (ChillZone/LinkLoader.lua):
-- the module is asked for once a session, its namespace handed over for that one call, and without
-- it everything degrades to one line. Loaded by tests/run.lua; the gamepad pass covers the load at
-- a gamepad login (tests/gamepad.lua).
local ns, test, eq, extra = ...
local ROOT, ADDON_DIR = assert(extra and extra.ROOT), assert(extra.ADDON_DIR)
local L = ns.L
local Loader = assert(ns.LinkLoader, "LinkLoader.lua")

local function Read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text
end

-- Runs fn(w) with C_AddOns.LoadAddOn answering as the game does: false, "MISSING" for a module
-- that is not installed (files nil), else files() run as its addon's files and true. Each call is
-- recorded with the handoff global as it was during the call; ns.Print and print are recorded too.
local function WithModule(files, fn)
	local saved = { addons = C_AddOns, Print = ns.Print, print = print, link = rawget(ns, "Link"), handoff = rawget(_G, "ChillZoneLinkHandoff") }
	local w = { calls = {}, printed = {} }
	local ok, err = pcall(function()
		ns.Link = nil
		Loader.Reset()
		C_AddOns = { LoadAddOn = function(name)
			w.calls[#w.calls + 1] = { name = name, handoff = rawget(_G, "ChillZoneLinkHandoff") }
			if name ~= Loader.MODULE or not files then return false, "MISSING" end
			files()
			return true
		end }
		ns.Print = function(m) w.printed[#w.printed + 1] = tostring(m) end
		print = function(m) w.printed[#w.printed + 1] = tostring(m) end
		fn(w)
	end)
	C_AddOns, ns.Print, print = saved.addons, saved.Print, saved.print
	ns.Link = saved.link
	ChillZoneLinkHandoff = saved.handoff
	Loader.Reset()
	if not ok then error(err, 0) end
end
local function Said(w, text)
	for _, p in ipairs(w.printed) do if p:find(text, 1, true) then return true end end
	return false
end

-- The module's first file as the private module writes it (Handoff.lua): it takes the namespace
-- once, clears the global, and checks the host interface; its Link.lua sets ns.Link.
local function ModuleFiles(got)
	return function()
		local host = ChillZoneLinkHandoff
		ChillZoneLinkHandoff = nil
		got.host = host
		if type(host) ~= "table" or type(host.LinkLoader) ~= "table" or host.LinkLoader.HOST_API ~= 1 then return end
		host.Link = {
			Slash = function(rest) got.slash = rest end,
			StatusLine = function() return "confirmer key abc123 (councillor)" end,
		}
	end
end

test("ChillZone Link (1.4.0): this addon ships no Link of its own: no Link.lua, no L.LINK_ line in any language, no page, key tool or Companion sidecar; the TOC loads LinkLoader.lua", function()
	local toc = assert(Read(ADDON_DIR .. "ChillZone.toc"))
	assert(toc:find("\nLinkLoader.lua\n", 1, true), "the loader in the TOC")
	assert(not toc:find("\nLink.lua\n", 1, true), "no Link.lua in the TOC")
	eq(Read(ADDON_DIR .. "Link.lua"), nil, "no Link.lua in the folder")
	for _, path in ipairs({ "web/package.json", "web/public/index.html", "scripts/link-keys.py",
		"ChillZoneCompanionBridge/ChillZoneCompanionBridge.toc", "tests/fixtures/link-sample.txt" }) do
		eq(Read(ROOT .. path), nil, path .. " lives with the ChillZone Link module, not here")
	end
	for k in pairs(L) do assert(not tostring(k):find("^LINK_"), "an ChillZone Link line here: " .. tostring(k)) end
	for _, file in ipairs({ "Locales.lua", "Locales/deDE.lua", "Locales/esES.lua", "Locales/frFR.lua", "Locales/itIT.lua", "Locales/ruRU.lua" }) do
		local text = assert(Read(ADDON_DIR .. file), file)
		assert(not text:find("\n%s*L?%.?LINK_[%u_]+%s*="), file .. " carries an ChillZone Link line")
		assert(text:find("DISCORD_NOT_INSTALLED", 1, true), file .. ": the line that says the module is not here")
	end
	assert(L.DISCORD_NOT_INSTALLED:find("ChillZone_Link", 1, true), "it names the module")
end)

test("ChillZone Link (1.4.0): not installed: its addon is asked for once a session, the namespace handed over for that call alone; /cz discord, the help and the status say it is not here, the code never repeated", function()
	WithModule(nil, function(w)
		eq(Loader.Loaded(), false)
		eq(Loader.StatusLine(), "not loaded yet")
		local loaded, why = Loader.Load()
		eq(loaded, false); eq(why, "MISSING"); eq(Loader.Why(), "MISSING")
		eq(#w.calls, 1); eq(w.calls[1].name, "ChillZone_Link")
		assert(w.calls[1].handoff == ns, "the namespace handed over during the call")
		eq(rawget(_G, "ChillZoneLinkHandoff"), nil, "and cleared after it")
		eq(rawget(ns, "Link"), nil, "no Link")
		eq(Loader.Load(), false, "asked again: nothing more"); eq(#w.calls, 1, "once a session")
		-- /cz discord <code>: one line, the module's name in it, never the code.
		SlashCmdList.CHILLZONE("discord OLC2.7K3M9QX2TB.someone.1799990000.a.ffffffff.secretsignature")
		eq(#w.printed, 1, "one line"); eq(w.printed[1], L.DISCORD_NOT_INSTALLED)
		for _, p in ipairs(w.printed) do assert(not p:find("secretsignature", 1, true), "the code repeated") end
		eq(ns.SlashWhere("discord OLC2.secret"), "slash discord", "a bug report never carries what followed /cz discord")
		-- The status: not installed; the help: no /cz discord line.
		eq(Loader.StatusLine(), "not installed")
		assert(ns.StatusText():find("discord link: not installed", 1, true), "the status line")
		w.printed = {}
		SlashCmdList.CHILLZONE("help")
		assert(#w.printed > 20, "the help printed")
		eq(Said(w, L.HELP_DISCORD), false, "no /cz discord in the help without the module")
	end)
end)

test("ChillZone Link (1.4.0): installed: its first file takes the namespace during the call; /cz discord, the help and the status are the module's; refused or broken, it says why", function()
	local got = {}
	WithModule(ModuleFiles(got), function(w)
		eq(Loader.Load(), true)
		assert(got.host == ns, "the module's first file took the namespace")
		eq(rawget(_G, "ChillZoneLinkHandoff"), nil, "cleared: no other addon finds it")
		eq(Loader.Loaded(), true); eq(Loader.Why(), nil)
		eq(Loader.Load(), true); eq(#w.calls, 1, "loaded once")
		SlashCmdList.CHILLZONE("discord status")
		eq(got.slash, "status", "/cz discord goes to the module"); eq(#w.printed, 0, "and nothing of the loader's")
		eq(Loader.StatusLine(), "confirmer key abc123 (councillor)")
		assert(ns.StatusText():find("discord link: confirmer key abc123 (councillor)", 1, true), "the module's status line")
		SlashCmdList.CHILLZONE("help")
		eq(Said(w, L.HELP_DISCORD), true, "/cz discord in the help with the module")
	end)
	-- A module that takes no namespace (a host interface it does not know, or loaded another way).
	WithModule(function() ChillZoneLinkHandoff = nil end, function(w)
		local loaded, why = Loader.Load()
		eq(loaded, false); eq(why, "nohost"); eq(Loader.StatusLine(), "not loaded (nohost)")
		SlashCmdList.CHILLZONE("discord")
		eq(w.printed[#w.printed], L.DISCORD_NOT_INSTALLED)
	end)
	-- A module whose files fail: logged, nothing else breaks, the handoff cleared all the same.
	WithModule(function() error("broken on purpose") end, function(w)
		local loaded, why = Loader.Load()
		eq(loaded, false); eq(why, "error")
		eq(rawget(_G, "ChillZoneLinkHandoff"), nil)
	end)
	-- No C_AddOns at all.
	WithModule(nil, function()
		C_AddOns = nil
		local loaded, why = Loader.Load()
		eq(loaded, false); eq(why, "api")
	end)
end)

-- A regression of the split: the login names the files an update added that only load after a
-- restart (Core.lua's stand-ins). The Link no longer ships here, so it is never one of them.
test("ChillZone Link (1.4.0): the login never asks for a restart for the Link, installed or not", function()
	local logged = {}
	local saved = { Print = ns.Print, Log = ns.Log, CheckFaction = ns.CheckFaction, me = ns.me }
	local ok, err = pcall(function()
		ns.Print = function() end
		ns.Log = function(fmt, ...) logged[#logged + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
		ns.CheckFaction = function() end
		for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "PLAYER_LOGIN") end
	end)
	ns.Print, ns.Log, ns.CheckFaction, ns.me = saved.Print, saved.Log, saved.CheckFaction, saved.me
	if not ok then error(err, 0) end
	eq(Loader.missing, nil, "the loader is loaded, not Core.lua's stand-in")
	for _, l in ipairs(logged) do
		if l:find("not loaded until the game restarts", 1, true) then
			assert(not l:find("Link", 1, true), "the login asks for a restart for the Link: " .. l)
		end
	end
end)

-- The keys this addon makes for itself draw on the entropy sample whether or not the module is
-- installed (until 1.4.0 they drew on Link.EntropySample, only while Link.lua was loaded).
test("ChillZone Link (1.4.0): the keys this addon makes for itself draw on Sign.EntropySample, with no Link loaded", function()
	WithModule(nil, function()
		Loader.Load()
		eq(rawget(ns, "Link"), nil)
		local saved, n = ns.Sign.EntropySample, 0
		local ok, err = pcall(function()
			ns.Sign.EntropySample = function() n = n + 1 return "sample " .. n end
			local key = ns.Keys.NewKey()
			assert(type(key) == "string" and #key == 20 and not key:find("[^0-9a-f]"), "a channel key: " .. tostring(key))
			eq(n, 1, "Keys.NewKey drew one sample")
		end)
		ns.Sign.EntropySample = saved
		if not ok then error(err, 0) end
	end)
end)
