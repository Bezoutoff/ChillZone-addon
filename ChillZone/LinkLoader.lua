local ADDON, ns = ...
local L = ns.L

-- 1.4.0: ChillZone Link (a character's Discord role, proved by players in game: /cz discord) is not
-- part of this addon. It is its own load-on-demand addon, ChillZone_Link (## LoadOnDemand: 1,
-- ## Dependencies: ChillZone), distributed separately. This file is the one way it starts: when it
-- is installed next to ChillZone, ChillZone loads it once its saved variables are read (INIT, before
-- the login), so its login and message handlers are in place as before; without it nothing of the
-- Link runs, ns.Link stays nil, and /cz discord says the module is not installed.
--
-- An addon's private table is not shared, so ChillZone hands its namespace over for one synchronous
-- call, as ArenaNet.lua does for ChillZone_Arena: Load sets the global ChillZoneLinkHandoff, calls
-- C_AddOns.LoadAddOn("ChillZone_Link") and clears it. The module's first file takes it at once
--   own.host, ChillZoneLinkHandoff = ChillZoneLinkHandoff, nil
-- and checks ns.LinkLoader.HOST_API; every other file of the module starts with
--   local _, own = ...; local ns = own.host; if not ns then return end
-- so the module loaded any other way (another addon's LoadAddOn, "load always" set by the
-- player) finds no host and does nothing. The module sets ns.Link (its Slash and StatusLine are
-- what ChillZone calls). Every other addon reaches ChillZone through its public API alone
-- (ChillZoneAPI, docs/API.md); this handoff is for ChillZone's own load-on-demand modules.
local Loader = {}
ns.LinkLoader = Loader

Loader.MODULE = "ChillZone_Link"
-- The host interface the module may rely on; a module made for another one refuses the handoff.
Loader.HOST_API = 1

local tried, why = false, nil

-- The module is loaded and took the namespace (its Link.lua set ns.Link).
function Loader.Loaded()
	local Link = rawget(ns, "Link")
	return type(Link) == "table" and not Link.missing and true or false
end

-- Why it is not loaded (nil when it is, or before the first try): "api" (no C_AddOns.LoadAddOn),
-- "error", "nohost" (loaded without taking the namespace), or the game's reason ("MISSING" when it
-- is not installed, "DISABLED", "DEP_...", "INTERFACE_VERSION"...).
function Loader.Why() return why end

-- Loads the module once a session (the game reads the list of addons at startup: one installed
-- later needs a restart). True when it is loaded.
function Loader.Load()
	if Loader.Loaded() then return true end
	if tried then return false, why end
	tried = true
	if not ns.Gate.Allowed("load-link") then why = "gate" return false, why end
	local AO = C_AddOns
	if type(AO) ~= "table" or type(AO.LoadAddOn) ~= "function" then why = "api" return false, why end -- gp:load-link
	ChillZoneLinkHandoff = ns
	local ok, loaded, reason = pcall(AO.LoadAddOn, Loader.MODULE) -- gp:load-link
	ChillZoneLinkHandoff = nil
	if not ok then
		why = "error"
		ns.Log("chillzone link: the module failed to load: %s", tostring(loaded))
		return false, why
	end
	if not loaded then
		why = tostring(reason or "?")
		if why ~= "MISSING" then ns.Log("chillzone link: the module did not load: %s", why) end
		return false, why
	end
	if not Loader.Loaded() then why = "nohost" return false, why end
	why = nil
	ns.Log("chillzone link: module loaded")
	return true
end

-- /cz discord: the module's command, or one line saying it is not here. What follows the command
-- (a Discord code, a confirmer's key) is never printed or logged (Core.lua's SlashWhere).
function Loader.Slash(rest)
	if Loader.Loaded() and type(ns.Link.Slash) == "function" then return ns.Link.Slash(rest) end
	ns.Print(L.DISCORD_NOT_INSTALLED)
end

-- For /cz status: the module's own line (a key's id and tier, never the key), or why it is not here.
function Loader.StatusLine()
	if Loader.Loaded() then
		local fn = ns.Link.StatusLine
		return type(fn) == "function" and tostring(fn()) or "loaded"
	end
	if why == nil and not tried then return "not loaded yet" end
	if why == "MISSING" or why == nil then return "not installed" end
	return "not loaded (" .. tostring(why) .. ")"
end

-- Tests start again from a session where nothing was tried.
function Loader.Reset() tried, why = false, nil end

ns.On("INIT", function() Loader.Load() end)
