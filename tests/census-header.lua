-- Header presentation uses the same Data.Groups totals as the detailed census.
local ns, test, eq, extra = ...

test("census header 1.5.2: current-server soldiers stay prominent, all-server total is secondary, people stay inside", function()
	extra.WithUI(function()
		local UI = extra.LoadUI()
		local oldGroups, oldRebuilding = ns.Data.Groups, ns.Data.Rebuilding
		local ok, err = pcall(function()
			local s = { characters = 1200, total = 1000, online = 40, newest = ns.Now(), guilds = {} }
			ns.Data.Groups = function(received)
				eq(received, s)
				return { characters = 3456, people = 2500 }
			end
			ns.Data.Rebuilding = function() return nil end
			local h = UI.CensusHeader(s)
			eq(h.characters, 1200)
			eq(h.secondary, ns.L.CENSUS_HEADER_ALL:format(ns.FormatNumber(3456)))
			assert(not h.secondary:find("2500", 1, true), "cross-server player estimates never replace soldiers")
			eq(h.note, nil)
		end)
		ns.Data.Groups, ns.Data.Rebuilding = oldGroups, oldRebuilding
		if not ok then error(err, 0) end
	end)
end)

test("census header 1.5.2: retained count shows its original date and partial refresh, stale history is labelled", function()
	extra.WithUI(function()
		local UI = extra.LoadUI()
		local oldGroups, oldRebuilding = ns.Data.Groups, ns.Data.Rebuilding
		local ok, err = pcall(function()
			local at = 1793966400
			local s = { characters = 4000, total = 3600, online = 10, newest = at,
				guilds = {}, snapshot = { observed = at }, live = { guilds = 2 } }
			ns.Data.Groups = function() return { characters = 5500 } end
			ns.Data.Rebuilding = function() return 2 end
			local h = UI.CensusHeader(s, at + 600)
			eq(h.characters, 4000)
			eq(h.sub, ns.L.CENSUS_HEADER_SAVED:format(date("%m/%d %H:%M", at), 2))
			eq(h.note, ns.L.CENSUS_HEADER_SAVED_TIP:format(date("%m/%d %H:%M", at)))
			s.history, s.snapshot, s.characters, s.total = { observed = at, characters = 4000 }, nil, 100, 100
			h = UI.CensusHeader(s, at + 2 * 86400)
			eq(h.characters, 100, "expired saved history is not asserted as the live total")
			eq(h.sub, ns.L.CENSUS_HEADER_HISTORY:format(ns.FormatNumber(4000), date("%m/%d %H:%M", at)))
		end)
		ns.Data.Groups, ns.Data.Rebuilding = oldGroups, oldRebuilding
		if not ok then error(err, 0) end
	end)
end)
