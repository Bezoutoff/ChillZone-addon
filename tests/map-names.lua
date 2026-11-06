-- Shared free-text map names: exercise the shipped module, with actual Core identity checks.
local base, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]map%-names%.lua$") or "./"
local function WithNames(fn)
	local savedDB, savedMe, savedClock, savedMap = base.rdb, base.me, GetServerTime, C_Map
	local ok, err = pcall(function()
		base.rdb = { council = { names = { councillor = "Councillor" }, realm = base.realm } }
		local epoch = 1800000000
		GetServerTime = function() return epoch end
		C_Map = {
			GetMapInfo = function(id)
				if type(id) == "number" and id >= 1 and id <= 5000 then return { mapID = id, name = "Place " .. id, parentMapID = 947 } end
			end,
		}
		local king = assert(base.KingFullName())
		local council = base.FullName("Councillor")
		local clients = {}
		local function New(name, db)
			local c = setmetatable({ me = name, rdb = db or {}, sent = {}, changes = 0, member = true, blocked = {}, barred = {} }, { __index = base })
			c.L = {}
			assert(loadfile(ROOT .. "ChillZone/Locales/MapNamesText.lua"))("ChillZone", c)
			c.IsMember = function() return c.member end
			c.Now = function() return epoch end
			c.WatchChat = { Barred = function(_, who) return c.barred[who or c.me] == true end }
			c.Filter = { Hides = function(text) return c.blocked[text] == true end }
			c.Comm = {
				Handle = function(_, f) c.handler = f end,
				Send = function(dist, msg, key, urgent, logged, done, options)
					c.sent[#c.sent + 1] = { dist = dist, msg = msg, key = key, logged = logged, guard = options.guard }
					return true
				end,
			}
			c.On = function() end
			c.Fire = function(event) if event == "MAP_NAMES_CHANGED" then c.changes = c.changes + 1 end end
			c.QuietPresence = function() return c.quiet == true end
			assert(loadfile(ROOT .. "ChillZone/MapNames.lua"))("ChillZone", c)
			clients[#clients + 1] = c
			return c
		end
		fn({ New = New, king = king, council = council, epoch = epoch,
			Advance = function(n) epoch = epoch + n end })
	end)
	base.rdb, base.me, GetServerTime, C_Map = savedDB, savedMe, savedClock, savedMap
	if not ok then error(err, 0) end
end

test("map names: free text needs preview and explicit confirmation; ordinary author and preview have no authority", function()
	WithNames(function(W)
		local K, H, ordinary = W.New(W.king), W.New(W.council), W.New(base.FullName("Author"))
		eq(K.MapNames.CanEdit(), true); eq(H.MapNames.CanEdit(), true)
		ordinary.King = { IsKing = function() return true end, Preview = function() return true end, IsHand = function() return true end }
		ordinary.Workshop = { IsAuthor = function() return true end }
		eq(ordinary.MapNames.CanEdit(), false)
		eq(ordinary.MapNames.Preview(1429, "Any free text"), nil)
		local p = assert(K.MapNames.Preview(1429, "King's picnic grove"))
		eq(K.MapNames.Name(1429), "Place 1429"); eq(#K.sent, 0, "preview stays local")
		eq(K.MapNames.Confirm(p), true)
		eq(K.MapNames.Name(1429), "King's picnic grove"); eq(K.sent[1].logged, true)
		assert(#K.sent[1].msg <= 255)
		eq(H.handler("CHANNEL", W.king, K.sent[1].msg), true)
		eq(H.MapNames.Name(1429), "King's picnic grove", "another client hears the edit immediately")
		H.member = false; eq(H.MapNames.CanEdit(), false); eq(H.MapNames.Name(1429), "Place 1429")
	end)
end)

test("map names: arbitrary artwork places keep stable map coordinates and can be reverted", function()
	WithNames(function(W)
		local K, H = W.New(W.king), W.New(W.council)
		local key = assert(K.MapNames.Point(1429, 0.413, 0.652))
		eq(key, "p1429:413:652")
		local map, x, y = K.MapNames.Place(key)
		eq(map, 1429); eq(x, .413); eq(y, .652)
		eq(K.MapNames.Confirm(assert(K.MapNames.Preview(key, "Grove of the Queen"))), true)
		eq(H.handler("CHANNEL", W.king, K.sent[1].msg), true)
		eq(H.MapNames.Entries()[1].key, key)
		eq(H.MapNames.Name(key), "Grove of the Queen")
		eq(K.MapNames.Confirm(assert(K.MapNames.Preview(key, "", true))), true)
		eq(H.handler("CHANNEL", W.king, K.sent[2].msg), true)
		eq(#H.MapNames.Entries(), 0, "revert uncovers original artwork")
		eq(H.handler("CHANNEL", W.king, K.sent[1].msg), false, "old edit cannot resurrect after revert")
		eq(K.MapNames.Point(1429, -1, 0), nil); eq(K.MapNames.Place("p1429:1001:0"), nil)
	end)
end)

test("map names: rejects spoofed senders, malformed text, huge packets and invalid maps", function()
	WithNames(function(W)
		local K, H = W.New(W.king), W.New(W.council)
		for _, value in ipairs({ "", " leading", "trailing ", "line\nbreak", "|Hplayer:x|hname|h", "bad~wire", "bad\127text", string.rep("x", 97) }) do
			eq(K.MapNames.Preview(1429, value), nil, "reject " .. value)
		end
		eq(K.MapNames.Preview(99999, "Unknown"), nil)
		assert(K.MapNames.Confirm(assert(K.MapNames.Preview(1429, "Valid"))))
		local msg = K.sent[1].msg
		eq(H.handler("CHANNEL", "Stranger-Realm", msg), false)
		eq(H.handler("WHISPER", W.king, msg), false)
		eq(H.handler("GUILD", W.king, msg), false)
		eq(H.handler("CHANNEL", W.king, string.rep("x", 256)), false)
		eq(H.handler("CHANNEL", W.king, msg:gsub("~1429~", "~99999~")), false)
		eq(H.handler("CHANNEL", W.king, msg:gsub("~1800000000~", "~1900000000~")), false)
		eq(H.handler("CHANNEL", W.king, "MN~1~1429~1800000000~Stranger-Realm~Forged"), false)
		eq(next(H.rdb.mapNames or {}), nil)
	end)
end)

test("map names: filters and current council authority cover display, queued publication, confirmation and repeat", function()
	WithNames(function(W)
		local H, K = W.New(W.council), W.New(W.king)
		local p = assert(H.MapNames.Preview(1429, "Hidden grove"))
		H.blocked["Hidden grove"] = true
		eq(H.MapNames.Confirm(p), false)
		H.blocked["Hidden grove"] = nil
		assert(H.MapNames.Confirm(p))
		local msg, guard = H.sent[1].msg, H.sent[1].guard
		eq(guard(), true)
		K.blocked["Hidden grove"] = true
		eq(K.handler("CHANNEL", W.council, msg), true, "retain revision but do not show blocked text")
		eq(K.MapNames.Name(1429), "Place 1429"); eq(K.MapNames.Tick(), 0)
		K.blocked["Hidden grove"] = nil; eq(K.MapNames.Name(1429), "Hidden grove")
		H.barred[W.council] = true; eq(guard(), false); eq(H.MapNames.CanEdit(), false)
		H.barred[W.council] = nil
		base.rdb.council.names = {}
		eq(guard(), false); eq(H.MapNames.Name(1429), "Place 1429"); eq(K.MapNames.Tick(), 0)
		eq(K.handler("CHANNEL", W.king, msg), false, "a relay cannot resurrect a revoked author's record")
	end)
end)

test("map names: changed previews reject conflicts and equal-time edits converge", function()
	WithNames(function(W)
		local K, H = W.New(W.king), W.New(W.council)
		local p = assert(K.MapNames.Preview(1429, "First"))
		assert(H.MapNames.Confirm(assert(H.MapNames.Preview(1429, "Newer"))))
		assert(K.handler("CHANNEL", W.council, H.sent[1].msg))
		eq(K.MapNames.Confirm(p), false, "stale preview needs renewed confirmation")
		local A, B = W.New(W.king), W.New(W.council)
		assert(A.MapNames.Confirm(assert(A.MapNames.Preview(1436, "West name"))))
		assert(B.MapNames.Confirm(assert(B.MapNames.Preview(1436, "East name"))))
		A.handler("CHANNEL", W.council, B.sent[1].msg)
		B.handler("CHANNEL", W.king, A.sent[1].msg)
		eq(A.MapNames.Name(1436), B.MapNames.Name(1436), "deterministic ties")
	end)
end)

test("map names: persisted names and tombstones reach late arrivals in bounded batches", function()
	WithNames(function(W)
		local K = W.New(W.king)
		for i = 1, 7 do assert(K.MapNames.Confirm(assert(K.MapNames.Preview(i, "Name " .. i)))) end
		assert(K.MapNames.Confirm(assert(K.MapNames.Preview(1, "", true))))
		local reloaded, late = W.New(W.council, K.rdb), W.New(base.FullName("Member"))
		eq(reloaded.MapNames.Name(2), "Name 2")
		eq(reloaded.MapNames.Tick(), 4); eq(reloaded.MapNames.Tick(), 4)
		for _, packet in ipairs(reloaded.sent) do late.handler("CHANNEL", W.council, packet.msg) end
		eq(late.MapNames.Name(7), "Name 7"); eq(late.MapNames.Name(1), "Place 1")
		eq(late.handler("CHANNEL", W.king, K.sent[1].msg), false)
		late.MapNames.Tick(); eq(#late.sent, 0, "ordinary clients cannot authenticate claimed authors")
		reloaded.quiet = true; eq(reloaded.MapNames.Tick(), 0)
		for i = 8, K.MapNames.MAX_PLACES do assert(K.MapNames.Confirm(assert(K.MapNames.Preview(i, "Name " .. i)))) end
		eq(K.MapNames.Preview(129, "Overflow"), nil)
		assert(K.MapNames.Preview(128, "Changed"), "full list still editable")
		K.rdb.mapNames.bad = {}; K.rdb.mapNames[200] = { at = W.epoch, by = W.king, text = "Too many" }
		K.MapNames.Prune()
		local n = 0 for _ in pairs(K.rdb.mapNames) do n = n + 1 end
		eq(n, K.MapNames.MAX_PLACES)
	end)
end)

test("map names: another editor's matching copy suppresses repeats already queued", function()
	WithNames(function(W)
		local K, H = W.New(W.king), W.New(W.council)
		assert(K.MapNames.Confirm(assert(K.MapNames.Preview(1429, "Shared grove"))))
		assert(H.handler("CHANNEL", W.king, K.sent[1].msg))
		eq(H.MapNames.Tick(), 0, "fresh copy needs no echo")
		W.Advance(H.MapNames.REPEAT * 2)
		eq(H.MapNames.Tick(), 1)
		local guard = H.sent[1].guard
		eq(guard(), true)
		eq(H.handler("CHANNEL", W.king, K.sent[1].msg), false, "matching revision changes nothing")
		eq(guard(), false, "matching copy cancels queued repeat")
	end)
end)
