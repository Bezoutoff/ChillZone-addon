local H = ...
local test, eq, World = H.test, H.eq, H.World

local function Client(w, name)
	local c = w:Client(name)
	w:As(c, function()
		local allowed = {}
		c.rankAllowed = allowed
		c.ns.Bank = {
			DirectoryViewer = function(who) return allowed[c.ns.Fold(c.ns.FullName(who))] == true end,
			SeesSisters = function() return true end,
			LordOrCaptain = function(who, guild)
				return c.ns.Fold(c.ns.FullName(who)) == c.ns.Fold("Aster Officer-Emberfall") and guild == "Olympus Ash"
			end,
			Current = function() return nil end,
			Own = function() return nil end,
			Sisters = function() return {} end,
			PriceAsks = function() end,
			Index = function() return { units = 0, stacks = 0 } end,
			Value = function() return { value = 0, pending = 0, unpriced = 0 } end,
			Correspondent = function() end,
			SISTER_OLD = 7 * 86400,
		}
		-- (The arena world's Comm has no SendBatch, the whole transfer Treasury.Private hands to
		-- Comm.lua: here its pieces go as whispers in turn, and its done comes once the last left.)
		c.ns.Comm.SendBatch = function(_, pieces, _, target, _, done, options)
			local left, failed = #pieces, false
			for _, piece in ipairs(pieces) do
				c.ns.Comm.Whisper(target, piece, nil, nil, nil, function(ok)
					failed = failed or not ok
					left = left - 1
					if left == 0 and done then done(not failed) end
				end, options and { guard = options.guard } or nil)
			end
			return true
		end
	end)
	return c
end

test("treasury ranking relay: two distinct authorized holders make a dated numeric row durable without exposing a bank", function()
	local w = World.New({ compliance = "shipped" })
	local late = Client(w, "Quillon Scribe")
	local first = "Brannoc Weald-Emberfall"
	local second = "Idris Vane-Emberfall"
	w:As(late, function()
		late.rankAllowed[late.ns.Fold(first)] = true
		late.rankAllowed[late.ns.Fold(second)] = true
		local row = { guild = "Olympus Ash", by = "Aster Officer-Emberfall", t = w.clock - 20,
			money = 120000, units = 41, stacks = 12, value = 33000, pending = 2, unpriced = 1,
			total = 153000, level = 57, correspondent = "Cora Ledger-Emberfall", home = false }
		local wire = assert(late.ns.Treasury.RankRelayWire(row))
		local ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", "Stranger-Emberfall", wire)
		eq(ok, false); eq(why, "access", "an unauthorized holder cannot witness a row")
		ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", first, wire)
		eq(ok, true); eq(why, "witness")
		eq(#late.ns.Treasury.RelayedRanking(), 0, "one holder is not consensus")
		ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", first, wire)
		eq(ok, true); eq(why, "witness")
		eq(#late.ns.Treasury.RelayedRanking(), 0, "repeating one identity is still one witness")
		ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", second, wire)
		eq(ok, true); eq(why, "accepted")
		local rows = late.ns.Treasury.RelayedRanking()
		eq(#rows, 1); eq(rows[1].guild, "Olympus Ash"); eq(rows[1].total, 153000)
		local ranking = late.ns.Treasury.Ranking()
		eq(#ranking.rows, 1, "the accepted total appears without a local bank snapshot")
		eq(ranking.rows[1].guild, "Olympus Ash"); eq(ranking.rows[1].relay, true)
		eq(late.rdb.treasuryRankRelay.rows[late.ns.Fold("Olympus Ash")][wire].accepted, true,
			"the accepted row is saved for later logins and relays")
	end)
end)

test("treasury ranking relay: malformed totals and a sender without source authority fail closed", function()
	local w = World.New({ compliance = "shipped" })
	local late = Client(w, "Quillon Scribe")
	local first = "Brannoc Weald-Emberfall"
	w:As(late, function()
		late.rankAllowed[late.ns.Fold(first)] = true
		local row = { guild = "Olympus Ash", by = "Aster Officer-Emberfall", t = w.clock,
			money = 100, units = 1, stacks = 1, value = 20, pending = 0, unpriced = 0,
			total = 120, level = 60, home = false }
		local wire = assert(late.ns.Treasury.RankRelayWire(row))
		local forged = wire:gsub("~120~60~", "~999~60~", 1)
		local ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", first, forged)
		eq(ok, false); eq(why, "shape")
		late.ns.Bank.LordOrCaptain = function() return false end
		ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", first, wire)
		eq(ok, false); eq(why, "source")
	end)
end)

test("treasury ranking relay: unconfirmed newer candidates cannot evict a row already accepted by two holders", function()
	local w = World.New({ compliance = "shipped" })
	local late = Client(w, "Quillon Scribe")
	local first = "Brannoc Weald-Emberfall"
	local second = "Idris Vane-Emberfall"
	w:As(late, function()
		late.rankAllowed[late.ns.Fold(first)] = true
		late.rankAllowed[late.ns.Fold(second)] = true
		local base = { guild = "Olympus Ash", by = "Aster Officer-Emberfall", t = w.clock - 100,
			money = 120000, units = 41, stacks = 12, value = 33000, pending = 2, unpriced = 1,
			total = 153000, level = 57, correspondent = "Cora Ledger-Emberfall", home = false }
		local accepted = assert(late.ns.Treasury.RankRelayWire(base))
		eq(select(2, late.ns.Treasury.HandleRankRelay("WHISPER", first, accepted)), "witness")
		eq(select(2, late.ns.Treasury.HandleRankRelay("WHISPER", second, accepted)), "accepted")

		-- One authorized holder can propose newer rows, but cannot establish any of them alone.
		-- They must not push the already corroborated row out of the bounded candidate store.
		for i = 1, late.ns.Treasury.RANK_RELAY_CANDIDATES do
			local candidate = {}
			for k, v in pairs(base) do candidate[k] = v end
			candidate.t = base.t + i
			candidate.money = base.money + i
			candidate.total = candidate.money + candidate.value
			eq(select(2, late.ns.Treasury.HandleRankRelay("WHISPER", first,
				assert(late.ns.Treasury.RankRelayWire(candidate)))), "witness")
		end

		local rows = late.ns.Treasury.RelayedRanking()
		eq(#rows, 1, "the accepted row remains durable while newer claims await consensus")
		eq(rows[1].t, base.t)
		eq(rows[1].total, base.total)
	end)
end)

-- 1.4.0: the census keeps a guild's average level to the tenth (Data.AvgTenths), and the direct
-- ranking row carries it as it is (47.9). The TY row is whole levels: a fractional level made
-- RankRelayWire refuse the row, so a guild whose census average was not a whole number was never
-- relayed at all. The level is floored for the wire instead; the row is otherwise unchanged.
test("treasury ranking relay: a fractional average level is floored on the wire, not a reason to drop the row", function()
	local w = World.New({ compliance = "shipped" })
	local late = Client(w, "Quillon Scribe")
	w:As(late, function()
		local row = { guild = "Olympus Ash", by = "Aster Officer-Emberfall", t = w.clock - 20,
			money = 120000, units = 41, stacks = 12, value = 33000, pending = 0, unpriced = 0,
			total = 153000, level = 47.9, correspondent = "Cora Ledger-Emberfall", home = false }
		local wire = late.ns.Treasury.RankRelayWire(row)
		assert(wire, "a level of 47.9 still makes a row")
		eq(wire:match("^TY~1~[^~]*~[^~]*~%d+~%d+~%d+~%d+~%d+~%d+~%d+~%d+~(%d+)~"), "47", "the level goes whole, floored")
		row.level = 48
		eq(late.ns.Treasury.RankRelayWire(row):match("~153000~(%d+)~"), "48", "a whole level goes as it is")
		row.level = -0.5
		eq(late.ns.Treasury.RankRelayWire(row), nil, "a negative level is still refused")
		row.level = 255.5
		eq(late.ns.Treasury.RankRelayWire(row):match("~153000~(%d+)~"), "255", "255.5 floors to the highest level the wire takes")
		row.level = 256
		eq(late.ns.Treasury.RankRelayWire(row), nil, "past 255 is still refused")
	end)
end)

test("treasury ranking relay: a direct guild whose census average level is 47.9 is relayed to a viewer who asks", function()
	local w = World.New({ compliance = "shipped" })
	local holder = Client(w, "Brannoc Weald")
	local viewer = Client(w, "Idris Vane")
	holder.rankAllowed[holder.ns.Fold(viewer.name)] = true
	viewer.rankAllowed[viewer.ns.Fold(holder.name)] = true
	local wire
	w:As(holder, function()
		holder.ns.Bank.Sisters = function()
			return { { guild = "Olympus Ash", by = "Aster Officer-Emberfall", t = w.clock - 30, money = 120000, tabs = {} } }
		end
		-- (The census is the harness's own Data.lua in this world, not loaded per client: this
		-- client's census row for that guild, as Data.Guild gives it, with the level to the tenth.)
		local census = { ["olympus ash"] = { name = "Olympus Ash", avgLevel = 47.9, t = w.clock - 60 } }
		holder.ns.Data = setmetatable({ Guild = function(name) return type(name) == "string" and census[name:lower()] or nil end },
			{ __index = holder.ns.Data })
		local rows = holder.ns.Treasury.Ranking(nil, true).rows
		eq(#rows, 1); eq(rows[1].level, 47.9, "the direct row shows the census level to the tenth")
		eq(holder.ns.Treasury.SendRankRelays(viewer.name), 1, "the guild's row goes to the viewer")
		wire = holder.ns.Treasury.RankRelayWire(rows[1])
		eq(wire:match("~120000~%d+~%d+~%d+~%d+~%d+~%d+~(%d+)~"), "47", "with the level floored")
	end)
	w:Run(30)
	w:As(viewer, function()
		local set = viewer.rdb.treasuryRankRelay and viewer.rdb.treasuryRankRelay.rows[viewer.ns.Fold("Olympus Ash")]
		local e = set and set[wire]
		assert(e, "the viewer holds the row as it was sent")
		assert(e.seen[viewer.ns.Fold(holder.name)], "with the holder as one witness")
		eq(e.accepted, nil, "one holder is still no consensus")
	end)
end)
