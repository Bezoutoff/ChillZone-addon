-- 1.3.4 (the owner's ask before the launch: every ranking shows on every client): the Church's top 3
-- (NR~1~t), which only the author's client works out, said again as it is by the King's client and the
-- signed High Council's (ChurchCount.RelayTop), never by an Apostle's (Apostles rank Apostles: the cross)
-- nor by the author's (it relays nobody's word). A client that was never online with the author's held
-- no top 3, and showed nobody's cross or crook. On the Church's test world; every name is invented.
-- Run alone: luajit tests/run.lua "1.3.4 Church top 3"
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]church%-top%-relay%.lua$")) or "./"
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
local B36 = ns.Codec.Base36

local A1, A2 = "Aldric Vane-Realm", "Bera Stone-Realm"

-- The author, the King, two signed High Councillors (neither an Apostle), two Apostles and a plain
-- member; the public ranking opened by the author (every client online took his switch).
local function Cast()
	local w = World.New({ apostles = { A1, A2 }, head = false })
	local c = {
		author = w:Client(World.AUTHOR), king = w:Client(World.KING),
		hc1 = w:Client(World.COUNCILLOR), hc2 = w:Client("Dela Moss"),
		a1 = w:Client(A1), a2 = w:Client(A2, { guild = World.GUILD2 }),
		wes = w:Client("Wes Brook"),
	}
	w:Presence()
	w:Act(c.author, c.author.Church.SetPublic, true)
	eq(w:As(c.wes, c.wes.Church.Public), true, "the public ranking open")
	return w, c
end
-- The author's top 3 (its Apostles, then its missionaries) at time `at`, as `to` take it from him.
local function Word(at, apostles, missionaries)
	return ("NR~1~t~%s~%s~%s"):format(B36(at), apostles or "-", missionaries or "-")
end
local function Take(w, to, from, text)
	local out = {}
	for _, cl in ipairs(to) do out[#out + 1] = { w:As(cl, cl.Count.Receive, "NR", "CHANNEL", from, text) } end
	return out
end
local function Relays(w, from)
	local n = 0
	for _, e in ipairs(w:Sent(from, "NR", "CHANNEL", "t")) do if e.from == from then n = n + 1 end end
	return n
end
-- `seconds` of play, a Church tick every 30 (as Church.TICK) on each online client of `list`.
local function Play(w, list, seconds)
	for _ = 1, math.floor(seconds / 30) do
		w:Run(30)
		w:Tick(list)
	end
end

test("1.3.4 Church top 3: a client never online with the author's takes the top 3 from a signed High Councillor's relay, the word as it came (its own time); an Apostle's word is refused, and an older relay never replaces a newer word", function()
	local w, c = Cast()
	local at = w.clock - 600
	local word = Word(at, "Aldric Vane,Bera Stone", "Mira Wells")
	-- Wes was away while the author's client said it: the councillor heard it.
	c.wes.online = false
	eq(Take(w, { c.hc1 }, World.AUTHOR, word)[1][1], true, "the councillor took the author's word")
	c.wes.online = true
	eq(w:As(c.wes, c.wes.Church.Top3), nil, "Wes never heard it")
	-- An Apostle's word (no Council seat): refused, whatever it says.
	local forged = Word(w.clock - 5, "Bera Stone,Aldric Vane", "-")
	local r = Take(w, { c.wes }, A2, forged)[1]
	eq(r[1], false); eq(r[2], "root", "an Apostle relays nothing")
	eq(w:As(c.wes, c.wes.Church.Top3), nil)
	-- The councillor's relay: TOP_EVERY and its grace after the word he heard, on CHANNEL and GUILD, the
	-- author's word itself.
	w:ClearSent()
	Play(w, { c.hc1 }, c.hc1.Count.TOP_EVERY + c.hc1.Count.TOP_GRACE + 60)
	local sent = w:Sent(c.hc1, "NR", "CHANNEL", "t")
	eq(#sent, 1, "said once")
	eq(sent[1].msg, word, "as it came: its time and its names")
	eq(#w:Sent(c.hc1, "NR", "GUILD", "t"), 1, "and on GUILD, as the author's")
	local top = w:As(c.wes, c.wes.Church.Top3)
	eq(top.at, at, "the author's time, never the relay's")
	eq(table.concat(top.apostles, ","), "Aldric Vane,Bera Stone"); eq(top.missionaries[1], "Mira Wells")
	eq(top.by, "Brin Tallow", "who it came from: the relay")
	assert(table.concat(c.wes.fired, ","):find("CHURCH_TOP_CHANGED", 1, true), "the honours are looked at again")
	-- An older word, a relay's too: never over the newer one.
	r = Take(w, { c.wes }, World.COUNCILLOR, Word(at - 60, "Bera Stone", "-"))[1]
	eq(r[1], false); eq(r[2], "older")
	eq(w:As(c.wes, c.wes.Church.Top3).apostles[1], "Aldric Vane")
	-- The King's character relays too; a word from a plain member or an Apostle is no relay's.
	eq(w:As(c.wes, c.wes.Count.IsTopRelay, World.KING), true)
	eq(w:As(c.wes, c.wes.Count.IsTopRelay, World.COUNCILLOR), true)
	eq(w:As(c.wes, c.wes.Count.IsTopRelay, A1), false)
	eq(w:As(c.wes, c.wes.Count.IsTopRelay, "Wes Brook-Realm"), false)
end)

test("1.3.4 Church top 3: the author's client is never a relay (it works its own out), nor an Apostle's; a relay says nothing while the ranking is closed or its word is past 30 days", function()
	local w, c = Cast()
	local at = w.clock - 60
	local word = Word(at, "Aldric Vane", "Mira Wells")
	Take(w, { c.author, c.a1, c.hc1 }, World.KING, word)
	eq(w:As(c.author, c.author.Count.IsTopRelay, World.AUTHOR), false, "the author's client: no relay")
	eq(w:As(c.a1, c.a1.Count.IsTopRelay, A1), false, "an Apostle's: no relay")
	w:ClearSent()
	for _ = 1, 3 * c.author.Count.TOP_EVERY / 30 do
		w:Run(30)
		eq(w:As(c.author, c.author.Count.RelayTop, w.clock), false)
		eq(w:As(c.a1, c.a1.Count.RelayTop, w.clock), false)
	end
	eq(#w:Sent(c.author, "NR", nil, "t"), 0, "the author's client relays nobody's word")
	eq(#w:Sent(c.a1, "NR", nil, "t"), 0, "an Apostle relays nothing")
	-- Closed: no relay. (The author's close, taken by everyone online.)
	w:Act(c.author, c.author.Church.SetPublic, false)
	Play(w, { c.hc1 }, 2 * c.hc1.Count.TOP_EVERY)
	eq(Relays(w, c.hc1), 0, "closed: nothing said")
	-- Open again, the word past TOP_MAX_AGE: nothing either.
	w:Run(5)
	w:Act(c.author, c.author.Church.SetPublic, true)
	eq(w:As(c.hc1, c.hc1.Church.Public), true)
	w.clock = at + c.hc1.Count.TOP_MAX_AGE + 1
	Play(w, { c.hc1 }, 2 * c.hc1.Count.TOP_EVERY)
	eq(Relays(w, c.hc1), 0, "a stale word names nobody: not said again")
	-- (A fresh word, the same relay: said.)
	Take(w, { c.hc1 }, World.KING, Word(w.clock, "Aldric Vane", "Mira Wells"))
	Play(w, { c.hc1 }, c.hc1.Count.TOP_EVERY + c.hc1.Count.TOP_GRACE + 60)
	eq(Relays(w, c.hc1), 1, "a fresh word is said again")
end)

test("1.3.4 Church top 3: the relays online say it about once a TOP_EVERY between them, none while the author's client says it, the King's only when no councillor is online", function()
	local w, c = Cast()
	-- (Each relay's own jitter: the second councillor 60 seconds after the first.)
	c.hc2.Count.random = function(a) return a + 60 end
	local relays = { c.hc1, c.hc2, c.king }
	local at = w.clock
	local word = Word(at, "Aldric Vane", "Mira Wells")
	Take(w, relays, World.AUTHOR, word)
	-- While the author's client says it (a newer word each TOP_EVERY, as SendTop does), no relay speaks.
	w:ClearSent()
	for i = 1, 3 do
		Play(w, relays, c.hc1.Count.TOP_EVERY)
		Take(w, relays, World.AUTHOR, Word(at + i, "Aldric Vane", "Mira Wells"))
	end
	for _, r in ipairs(relays) do eq(Relays(w, r), 0, r.name .. ": the author's word heard") end
	-- The author gone: one relay a TOP_EVERY, the first councillor's (the others heard it).
	c.author.online = false
	w:ClearSent()
	local windows = 4
	Play(w, relays, windows * c.hc1.Count.TOP_EVERY)
	local total = Relays(w, c.hc1) + Relays(w, c.hc2) + Relays(w, c.king)
	assert(total >= windows - 1 and total <= windows + 1, "about one a TOP_EVERY: " .. total)
	eq(Relays(w, c.hc2), 0, "the second councillor heard the first")
	eq(Relays(w, c.king), 0, "the King's goes last: it heard the councillor")
	for _, e in ipairs(w:Sent(nil, "NR", "CHANNEL", "t")) do eq(e.msg, Word(at + 3, "Aldric Vane", "Mira Wells"), "the last word, as it is") end
	-- The first councillor gone: the second takes over; both gone: the King's.
	c.hc1.online = false
	w:ClearSent()
	Play(w, relays, 2 * c.hc1.Count.TOP_EVERY)
	assert(Relays(w, c.hc2) >= 1 and Relays(w, c.hc2) <= 2, "the second councillor: " .. Relays(w, c.hc2))
	eq(Relays(w, c.king), 0)
	c.hc2.online = false
	w:ClearSent()
	Play(w, relays, 2 * c.hc1.Count.TOP_EVERY)
	assert(Relays(w, c.king) >= 1 and Relays(w, c.king) <= 2, "the King's alone: " .. Relays(w, c.king))
	-- What it says reaches a client that never heard the author: Wes, back now.
	eq(w:As(c.wes, c.wes.Church.Top3).at, at + 3)
end)
