-- ChillZone's offline tests run on the network the original's tests were written for: made-up guilds
-- named after the brand ("ChillZone II", "ChillZone Zeus": ours by the name word) and the beta's King,
-- Treasurer, author and relays. A release has none of these (Core.lua: the guilds by their exact
-- names, no people; tests/chillzone.lua checks it). Each harness loads this file once, before any
-- addon file; every later loadfile of ChillZone/<file> named below gets these values right after the
-- file runs. RAW_LOADFILE is the real loadfile, for loading a file as a release has it.
--   assert(loadfile(ROOT .. "tests/fixtures/identity.lua"))()
local UPSTREAM_N = "84a62410ffd1872739d169af98d461defee07628fcd907cef84b5ca39f9a840b6b518b2a246319ec2cbd4477ee30a2a17924c3540e647687eea614f9a05bf9a305274b28f0add3de7a3aae32e4c950030cfc2336221e705110cecc4622e0d86fb15340d1e76dfdad6813f81039dce9eff82224ecab8c6b9822957b5e724d67f8de14b8188e3f0cedf8a29dd1fb33aa7e24be0630ce6bb2bf31b3e1508a6976b225ce4ec73ead73cf74c8ef4034ae8fa94b0c8adc1f8f7d40e50c5cc3080e502120c122ae2af9f0066923ee5822a639e88b1cd8b9a469e91abd260401578d4c5a9900af45c7bb8e938a8b22bc60cec354a6986918d19658ce14d98b27d7ad0e8f"
local UPSTREAM_MU = "1ee0e4804d1be7d006beb4df0bf258975cfaf34aa7c839e713b10caba290d9005af2a93d9e1c244b626e9d621d6268e9e009804b3603e9bae11a99243c944a467a710df6c40e30f76d15c8ab30ceebd0ecec7de3027e9f40fcbd7f4b1aceed476f952b61493fa08eef716840c397e023ce4427d7d45fd85ccc2dac7bbeffdc3970a28570ec960055ea9293b0af1fd6255b6257eb0d6c1609f1cc6629b806c7398767be262ce7f8ba1c84eaa576175f3b277f66d7ace2a8a1fba4e26d5d0633631cb051009fa7652a2da7872eaa98b892ca2610db956d8743d2be524b6cfbde871fd5deaa35bf335f42804a609f443b303e077023d5a6465f46feeae9889f24ac995007568"

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
	["Locales.lua"] = function(ns) ns.TEXT_LOCALE = nil end, -- (the tests: the client's language, as they set GetLocale)
	["Relay.lua"] = function(ns)
		ns.Relay.LAUNCH_PINS = { ForeverPvE = { "Developus Olympicus", "Asmongold Thereal" }, ForeverPvP = { "Twalin Firebraid", "Elrond Oaklance" } }
	end,
	-- The original's public key: tests/run.lua's lists were signed with it (the author's key there).
	["Sign.lua"] = function(ns)
		local S = ns.Sign
		local n, mu
		S.WithKey(UPSTREAM_N, UPSTREAM_MU, 86, function() n, mu = S.N, S.MU end)
		S.N, S.MU, S.K = n, mu, 86
	end,
}

-- For a harness that reads a file itself (tests/gamepad.lua's Boot): the identity right after the
-- file's chunk ran, on the namespace it ran on.
function ApplyTestIdentity(path, ns)
	local after = AFTER[tostring(path):match("([%w]+%.lua)$") or ""]
	if after then after(ns) end
end

local raw = loadfile
local setfenv, getfenv, select = setfenv, getfenv, select -- (a sandbox loading a file may not offer them)
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
