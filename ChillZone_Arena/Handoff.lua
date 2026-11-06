local ADDON, own = ...

-- ChillZone Arena, the Blood Arena's load-on-demand module (1.2, the design). An addon's private
-- table is not shared, so ChillZone hands its namespace over for one synchronous call: Arena.LoadUI
-- sets ChillZoneArenaHandoff, calls C_AddOns.LoadAddOn and clears it. This file takes it at once.
-- Every other file of the ChillZone Arena module starts with
--   local _, own = ...; local ns = own.host; if not ns then return end
-- so the module loaded any other way (another addon's LoadAddOn, "load always" set by the player)
-- finds no host and does nothing; Arena.LoadUI then says to /reload.
own.host, ChillZoneArenaHandoff = ChillZoneArenaHandoff, nil
local ns = own.host
if type(ns) ~= "table" or type(ns.Arena) ~= "table" then
	own.host = nil
	return
end
local Arena = ns.Arena

-- The ChillZone Arena module's version is ChillZone's (the base version, a test build's too: package.sh --test
-- edits only ChillZone.toc). Another one means files from two installs: nothing loads, and ChillZone
-- says to restart the game.
local mine = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
if mine ~= ns.VERSION then
	Arena.companionRefused = "version"
	own.host = nil
	return
end
own.VERSION = mine

-- The screens' shared table (Panes.lua fills it; the core reaches it as Arena.ui).
own.ArenaUI = own.ArenaUI or {}
Arena.ui = own.ArenaUI

-- Its saved variables (ChillZoneArenaDB, the heavy tables: the design) are the game's once the files
-- have run: handed to Arena.Heavy at this addon's ADDON_LOADED.
ns.RegisterEvent("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	if type(ChillZoneArenaDB) ~= "table" then ChillZoneArenaDB = {} end
	Arena.AttachHeavy(ChillZoneArenaDB)
end)

Arena.companionReady = true
