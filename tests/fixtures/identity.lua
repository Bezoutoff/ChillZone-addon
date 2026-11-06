-- ChillZone's offline tests run on the network the original's tests were written for: made-up guilds
-- named after the brand ("ChillZone II", "ChillZone Zeus": ours by the name word) and the beta's King,
-- Treasurer, author and relays. A release has none of these (Core.lua: the guilds by their exact
-- names, no people; tests/chillzone.lua checks it). Each harness loads this file once, before any
-- addon file; every later loadfile of ChillZone/<file> named below gets these values right after the
-- file runs. RAW_LOADFILE is the real loadfile, for loading a file as a release has it.
--   assert(loadfile(ROOT .. "tests/fixtures/identity.lua"))()
local AFTER = {
	["Core.lua"] = function(ns)
		ns.NAME_WORD = "chillzone"
		ns.WHO_WORD = "ChillZone"
		ns.KING_GUILD = { Alliance = "ChillZone", Horde = "Mudhutters" }
		ns.KING_NAME = "Asmon"
		ns.KING_CHARACTER = { Alliance = "Asmongold Asmongler", Horde = "Duskmonkey Boneback" }
		ns.KING_REALM, ns.KING_REALM_HORDE = "ClassicBetaPvP", nil
		ns.TREASURER, ns.TREASURER_REALM = "Pyralis Ashandar", "ClassicBetaPvP"
		ns.TREASURER_CHARACTERS = { "Pyralis Ashandar", "Pyralis Andarai" }
		ns.AUTHOR, ns.AUTHOR_REALM = "Faladoriel Skylance", "ClassicBetaPvP"
		ns.APPROVED_BUILTIN = { Alliance = { "CHILLZONER", "CHILLZONERS" } }
		ns.REMOVED_BUILTIN = { Alliance = { realm = "ClassicBetaPvP", "ChillZone Defense Force" } }
	end,
	["Relay.lua"] = function(ns)
		ns.Relay.LAUNCH_PINS = { ForeverPvE = { "Developus Olympicus", "Asmongold Thereal" }, ForeverPvP = { "Twalin Firebraid" } }
	end,
}

-- For a harness that reads a file itself (tests/gamepad.lua's Boot): the identity right after the
-- file's chunk ran, on the namespace it ran on.
function ApplyTestIdentity(path, ns)
	local after = AFTER[tostring(path):match("([%w]+%.lua)$") or ""]
	if after then after(ns) end
end

local raw = loadfile
RAW_LOADFILE = raw
function loadfile(path, ...)
	local chunk, err = raw(path, ...)
	local after = chunk and AFTER[tostring(path):match("ChillZone[/\\]([%w]+%.lua)$") or ""]
	if not after then return chunk, err end
	return function(...)
		setfenv(chunk, getfenv(1)) -- (a harness's setfenv on this function reaches the file)
		chunk(...)
		after((select(2, ...)))
	end
end
