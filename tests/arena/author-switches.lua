-- 1.4.0 (the owner's rule for the launch: the King does not work these switches, so the addon's author
-- must be able to): the author's character, as Core.lua names him (here the world's code pin; on a
-- launch realm group the signed titles list's), publishes the Games tab's Arena and Bones rankings
-- (ArenaRoles.MayPublish) and sets the Treasury tab's "ranking" switch (Treasury.SetAuthorRanking,
-- T1~r); every client takes, keeps and repeats his words as the King's, and he gets nothing else of
-- the King's. On the test world (tests/arena/lib/world.lua); every name is invented. Both fail on the
-- 1.4.0 candidate, where only the King (and the councillors he named) could do either.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local N = World.NAMES

local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end
local function Public(w, c, game) return w:As(c, c.ns.ArenaHome.RankingsPublic, game) end
local function Word(w, c, game) return w:As(c, c.ns.ArenaRoles.PublishWord, game) end
local function Sent(w, from, type, pattern)
	local n = 0
	for _, s in ipairs(w:Sent({ from = from, type = type })) do if not pattern or s.msg:find(pattern) then n = n + 1 end end
	return n
end

print("1.4.0: the author's switches (the Games tab's rankings, the Treasury's ranking)")

test("1.4.0 author switches: the author shows Arena's ranking; members take it, a later login gets it from a holder, his client repeats it at his next login, and he is never the King", function()
	local w = World.New()
	local author = w:Role("author")
	local lida = w:Client("Lida Fenn")
	-- Not the King, not a Steward, naming no publisher: only this switch.
	eq(w:As(author, author.ns.King.IsKing), false)
	eq(w:As(author, author.ns.King.SetsLists), false)
	eq(w:As(author, author.ns.ArenaHome.NamesPublishers), false, "he names no councillor for a game")
	eq(w:As(author, author.ns.ArenaHome.MaySetRankings, "arena"), true, "the Games tab gives him the switch")
	assert(w:As(author, author.ns.ArenaRoles.Publish, "arena", true))
	w:Run(0)
	eq(Public(w, lida, "arena"), true, "taken from the author")
	eq(Word(w, lida, "arena").from, N.author)
	eq(Public(w, lida, "bones"), false, "one game at a time")
	-- A member's word in the author's name is a copy: it only fills, and the author's own replaces it.
	w:Logout(author)
	w:Run(author.ns.ArenaRoles.REPEAT * 2)
	local late = w:Client("Parric Stowe")
	w:Run(60)
	eq(Public(w, late, "arena"), false, "nothing heard yet")
	w:As(late, late.ns.ArenaHome.TabLines)
	w:Run(late.ns.ArenaRoles.ANSWER_MIN + late.ns.ArenaRoles.ANSWER_SPREAD + 2)
	eq(Public(w, late, "arena"), true, "told by a holder, the author away")
	local word = Word(w, late, "arena")
	eq(word.from, N.author); eq(word.copy, true)
	-- His next login: his client repeats his word, which replaces the copy.
	local before = Sent(w, author, "AU", "^AU~L1~a~1~")
	w:Login(author)
	w:Run(author.ns.ArenaRoles.LOGIN_REPEAT + 1)
	assert(Sent(w, author, "AU", "^AU~L1~a~1~") > before, "repeated after his login")
	eq(Word(w, late, "arena").copy, nil, "the author's own word now")
	-- He hides it again: everyone online takes it.
	assert(w:As(author, author.ns.ArenaRoles.Publish, "arena", false))
	w:Run(0)
	eq(Public(w, lida, "arena"), false); eq(Public(w, late, "arena"), false)
	NoErrors(w)
end)

test("1.4.0 author switches: the author sets the Treasury's ranking switch alone; members take it, a later login gets his repeat, a King's older word changes only the rest, a newer word of the King's stands, and nobody else's T1~r counts", function()
	local w = World.New()
	local king, author = w:Role("king"), w:Role("author")
	local lida = w:Client("Lida Fenn")
	local function Shows(c, what) return w:As(c, c.ns.Treasury.Shows, what) end
	eq(w:As(author, author.ns.Treasury.AuthorSetsRanking), true)
	eq(w:As(lida, lida.ns.Treasury.AuthorSetsRanking), false)
	w:As(author, author.ns.Treasury.SetFlag, "ranking", true)
	w:Run(0)
	eq(Shows(lida, "ranking"), true, "the army sees the ranking")
	eq(w:As(lida, lida.ns.Treasury.PublicShows, "ranking"), true)
	eq(Shows(king, "ranking"), true, "the King's client takes it too")
	-- Only the ranking: the balance and the book stay the King's.
	w:As(author, author.ns.Treasury.SetFlag, "balance", true)
	w:As(author, author.ns.Treasury.SetFlag, "book", true)
	w:Run(0)
	eq(Shows(lida, "balance"), false); eq(Shows(lida, "book"), false)
	eq(Shows(author, "balance"), false, "not even on his own screen")
	-- A plain member's T1~r: not the author's.
	w:As(lida, function() lida.ns.Comm.Send("CHANNEL", ("T1~r~1~%s~0~%d"):format(World.GUILD, w.clock + 5), "x") end)
	w:Run(0)
	eq(Shows(king, "ranking"), true, "a member's word counts for nothing")
	-- A later login: the author's client repeats his word (FLAGS_EVERY).
	local late = w:Client("Parric Stowe")
	eq(Shows(late, "ranking"), false)
	w:Run(author.ns.Treasury.FLAGS_EVERY + 61)
	eq(Shows(late, "ranking"), true, "his repeat reaches a later login")
	-- A King's word older than the author's: the balance and the book alone are taken from it.
	local rankingAt = lida.rdb.treasuryFlags.rankingAt
	w:As(king, function() king.ns.Comm.Send("CHANNEL", ("T1~T~%d~%s~100~%d"):format(king.ns.King.NewId(), World.KING_GUILD, rankingAt - 30), "y") end)
	w:Run(0)
	eq(Shows(lida, "balance"), true, "the King's balance")
	eq(Shows(lida, "ranking"), true, "the author's newer ranking stands")
	-- The King's click later keeps the ranking as it stands, and his newer word on it stands.
	w:As(king, king.ns.Treasury.SetFlag, "book", true)
	w:Run(0)
	eq(Shows(lida, "book"), true); eq(Shows(lida, "ranking"), true)
	w:As(king, king.ns.Treasury.SetFlag, "ranking", false)
	w:Run(0)
	eq(Shows(lida, "ranking"), false, "the King's newer word on it")
	-- The author's old word, repeated after that, changes nothing; his client no longer repeats it.
	local before = Sent(w, author, "T1", "^T1~r~")
	w:Run(author.ns.Treasury.FLAGS_EVERY + 61)
	eq(Sent(w, author, "T1", "^T1~r~"), before, "a word that no longer stands is not repeated")
	eq(Shows(late, "ranking"), false)
	NoErrors(w)
end)
