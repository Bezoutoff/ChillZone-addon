-- Live Bones regressions: actual table, rules, companion and signed-record adapter.
local H = ...
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local UI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
H.test("1.5.2 Bones lesson: the first request loads the real companion and opens training", function()
	local w = FW.New({compliance = "shipped"}); local a = w:Player(H.World.NAMES.fighterA, {companion = {}, bonesTrained = false})
	a.K = UI.New(function() return w.clock end); a.K.Install(a.globals)
	assert(w:As(a, a.ns.FarkleTable.ShowUI, "practice", nil, {target = 2000, learn = true}))
	assert(#a.errors == 0, table.concat(a.errors, "\n"))
	assert(#a.K.errors == 0, table.concat(a.K.errors, "\n"))
	assert(a.ns.Arena.ui.FarkleBoard._.S.id, "no lesson")
end)

H.test("1.5.2 Bones opening: simultaneous server rolls converge despite opposite arrival order", function()
	local w = FW.New({compliance = "shipped"})
	local a = w:Player(H.World.NAMES.fighterA)
	local b = w:Player(H.World.NAMES.fighterB)
	w:Group({a, b})
	local function Do(c, key, ...) return w:As(c, c.ns.FarkleTable[key], ...) end
	local id = assert(Do(a, "Create", {guest = b.name, target = 2000}))
	w:Run(0); assert(Do(b, "Answer", id, true)); w:Run(0)
	local seenA, seenB = {}, {}
	w:As(a, function() a.ns.On("FARKLE_EVENT", function(_, e) if e.t == "O" then seenA[#seenA+1] = e.seat end end) end)
	w:As(b, function() b.ns.On("FARKLE_EVENT", function(_, e) if e.t == "O" then seenB[#seenB+1] = e.seat end end) end)
	w.lineDelay = function(from, to) return from == to and 0 or 0.5 end
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	assert(Do(a, "Roll", id)); assert(Do(b, "Roll", id)); w:Run(1)
	local ta, tb = Do(a, "Get", id), Do(b, "Get", id)
	H.eq(ta.state, "play", "host proceeds after both verified opening lines")
	H.eq(tb.state, "play", "guest proceeds after both verified opening lines")
	H.eq(ta.game.chain, tb.game.chain, "same opening handshake")
	H.eq(a.ns.FarkleRules.Hash(ta.game), b.ns.FarkleRules.Hash(tb.game), "same ranked transcript")
	H.eq(table.concat(seenA, ", "), "1, 2", "host animates its two actual observations")
	H.eq(table.concat(seenB, ", "), "2, 1", "guest animates its two actual observations")
	w.lineDelay = nil; w:Run(20)
	assert(Do(a, "Concede", id)); w:Run(0)
	H.eq(#Do(a, "Best", "L"), 2, "both signed results agree for the host")
	H.eq(#Do(b, "Best", "L"), 2, "both signed results agree for the guest")
	for _, c in ipairs({a, b}) do H.eq(#c.errors, 0, table.concat(c.errors, "\n")) end
end)

H.test("1.5.2 Bones rankings: a counted free game is recoverable from its original halves after a record queue failure", function()
	local w = FW.New({compliance = "shipped"})
	local a = w:Player(H.World.NAMES.fighterA)
	local b = w:Player(H.World.NAMES.fighterB)
	w:Group({a, b})
	local function Do(c, key, ...) return w:As(c, c.ns.FarkleTable[key], ...) end
	local R = a.ns.Records
	local take = R.Take
	R.Take = function() return false, "busy" end
	local id = assert(Do(a, "Create", {guest = b.name, target = 2000}))
	w:Run(0); assert(Do(b, "Answer", id, true)); w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	assert(Do(a, "Roll", id)); assert(Do(b, "Roll", id)); w:Run(20)
	H.eq(Do(a, "Get", id).mode, "T", "free games use the test lane while the live switch is off")
	H.eq(Do(a, "Counted", id), true, "the release still counts this free game")
	assert(Do(a, "Concede", id)); w:Run(0)
	R.Take = take
	H.eq(w:As(a, R.Count, "b"), 0, "shared record was not admitted by the busy queue")
	w:As(a, R.Load); w:Run(3)
	H.eq(w:As(a, R.Count, "b"), 1, "login recovery republishes the actual signed counted game")
	for _, c in ipairs({a, b}) do H.eq(#c.errors, 0, table.concat(c.errors, "\n")) end
end)

H.test("1.5.2 Bones opening: tied rounds, replay and an unfinished round retain each observation exactly once", function()
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(H.World.NAMES.fighterA)
	w:As(a, function()
		local R = a.ns.FarkleRules
		local fields = { id = "Kopening152", target = 2000, players = { "Alpha One", "Beta Two" } }
		local left, right = assert(R.New(fields)), assert(R.New(fields))
		for _, pair in ipairs({ { 50, 50 }, { 30, 30 }, { 90, 10 } }) do
			for _, seat in ipairs({ 1, 2 }) do assert(R.Apply(left, { t = "O", p = seat, value = pair[seat] })) end
			for _, seat in ipairs({ 2, 1 }) do assert(R.Apply(right, { t = "O", p = seat, value = pair[seat] })) end
			H.eq(R.Transcript(left), R.Transcript(right), "every completed opening pair has one canonical transcript")
		end
		H.eq(right.step, 6); H.eq(right.ties, 2); H.eq(right.current, 1)
		local replay = assert(R.Replay(fields, right.events))
		H.eq(R.Hash(replay), R.Hash(right)); H.eq(replay.step, 6)
		local partial = assert(R.New(fields))
		assert(R.Apply(partial, { t = "O", p = 2, value = 10 }))
		local resumed = assert(R.Replay(fields, partial.events))
		H.eq(resumed.opening[2], 10, "a reload still knows the guest's first observation")
		H.eq(R.Apply(resumed, { t = "O", p = 2, value = 99 }), nil, "duplicate roll cannot replace it")
		assert(R.Apply(resumed, { t = "O", p = 1, value = 90 }))
		H.eq(resumed.events[1], "O1:90"); H.eq(resumed.events[2], "O2:10")
	end)
end)
