-- 1.2.5.1, the quiet presence (Core.lua's ns.SetQuietPresence, Comm.QUIET_WORDS): while an authorized
-- player has it on, this client sends nothing that says he is online or where he is; what it reads
-- and the chat lines he types still go, and every word comes back once it is off. Loaded by
-- tests/run.lua with its FreshComm, WithHop and the real ns.Fire (Fire). Every name is invented.
local ns, test, eq, extra = ...
local FreshComm, WithHop, Fire = extra.FreshComm, extra.WithHop, extra.Fire
local OWNER = "test-quiet"

-- fn() with this client a High Councillor (a current signed issuer, Moderation.IsIssuer), the
-- quiet presence off again after it, whatever fn did; QUIET_PRESENCE_CHANGED reaches its real
-- listeners (only it: the harness's ns.Fire stays quiet for every other event).
-- (The harness's own Comm.Hello is quieted meanwhile: its listener would queue a hello there.)
local function AsCouncillor(fn)
	local saved = { hc = ns.IsHighCouncillor, fire = ns.Fire, hello = ns.Comm.Hello }
	local ok, err = pcall(function()
		ns.Comm.Hello = function() end
		ns.IsHighCouncillor = function(name) return type(name) == "string" and name:lower() == tostring(ns.me):lower() end
		ns.Fire = function(name, ...) if name == "QUIET_PRESENCE_CHANGED" then return Fire(name, ...) end end
		fn()
	end)
	if ns.QuietPresenceOwnedBy(OWNER) then ns.SetQuietPresence(false, OWNER) end
	ns.IsHighCouncillor, ns.Fire, ns.Comm.Hello = saved.hc, saved.fire, saved.hello
	if not ok then error(err, 0) end
end
local function Quiet(on)
	local done, why = ns.SetQuietPresence(on, OWNER)
	eq(done, true, "quiet presence " .. tostring(on) .. ": " .. tostring(why))
	eq(ns.QuietPresence(), on)
end
local function Find(list, pattern)
	for _, m in ipairs(list) do if m:find(pattern) then return m end end
	return nil
end
local function Keys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = tostring(k) end
	table.sort(out)
	return table.concat(out, ",")
end

test("quiet presence: the built-in switch withdraws location first and never steals another owner's privacy", function()
	AsCouncillor(function()
		local K, Ly, C = ns.King, ns.Layers, ns.Consent
		local saved = { isKing = K.IsKing, sharing = K.SharingLocation, toggle = K.ToggleLocation,
			setSharing = Ly.SetSharing, share = ns.db.shareLocation, print = ns.Print, fire = ns.Fire, private = ns.db.privatePresence }
		local calls, kingLocation = {}, false
		local ok, err = pcall(function()
			ns.Print = function() end
			local underlyingFire = ns.Fire
			ns.Fire = function(event, ...)
				if event == "KING_LOCATION_CHANGED" or event == "LAYER_SHARING_CHANGED" then
					eq(ns.QuietPresence(), true, "location listeners wake only after presence is private")
					calls[#calls + 1] = event
				end
				return underlyingFire(event, ...)
			end
			K.IsKing = function() return false end
			K.SharingLocation = function() return kingLocation end
			K.ToggleLocation = function(privateTransition)
				eq(ns.QuietPresence(), false, "the crown withdrawal is allowed to leave first")
				eq(privateTransition, true, "the crown suppresses its ordinary final hello")
				kingLocation = not kingLocation
				calls[#calls + 1] = "king-location"
				return true, 77
			end
			Ly.SetSharing = function(on, privateTransition)
				eq(ns.QuietPresence(), false, "the ordinary layer withdrawal leaves first")
				eq(privateTransition, true, "the layer switch suppresses its ordinary final hello")
				ns.db.shareLocation = on and true or false
				calls[#calls + 1] = on and "location-on" or "location-off"
			end

			ns.db.shareLocation = true
			eq(ns.SetPrivatePresence(true), true)
			eq(table.concat(calls, ","), "location-off,LAYER_SHARING_CHANGED")
			eq(ns.db.shareLocation, false); eq(ns.QuietPresence(), true)
			eq(ns.QuietPresenceOwnedBy(ns.PLAYER_QUIET_OWNER), true)
			eq(ns.SetPrivatePresence(false), true)
			eq(ns.QuietPresence(), false); eq(ns.db.shareLocation, false, "visibility never opts location back in")

			-- The King's own crown uses its distinct location switch, before quiet presence begins.
			calls, kingLocation = {}, true
			K.IsKing = function() return true end
			eq(ns.SetPrivatePresence(true), true)
			eq(table.concat(calls, ","), "king-location,KING_LOCATION_CHANGED")
			eq(kingLocation, false); eq(ns.QuietPresence(), true)
			eq(ns.SetPrivatePresence(false), true)

			-- Another API owner remains in charge; the built-in control neither steals nor ends it.
			K.IsKing = function() return false end
			eq(ns.SetQuietPresence(true, OWNER), true)
			eq(ns.SetPrivatePresence(true), true, "already private is a successful state")
			eq(ns.QuietPresenceOwnedBy(OWNER), true)
			eq(select(2, ns.SetPrivatePresence(false)), "owner")
			eq(ns.QuietPresence(), true)
			eq(ns.SetQuietPresence(false, OWNER), true)

			-- It is a visible, non-pending Profile choice only for an authorized character.
			local item
			for _, x in ipairs(C.Items("profile")) do if x.key == "quietpresence" then item = x end end
			assert(item, "the My profile privacy switch")
			eq(C.Answer("quietpresence"), false)
			for _, x in ipairs(C.Pending("profile")) do assert(x.key ~= "quietpresence", "a session switch never opens first-run consent") end
			eq(C.Choose("quietpresence", true), true)
			eq(C.Answer("quietpresence"), true)
			eq(C.Choose("quietpresence", false), true)
			eq(C.Answer("quietpresence"), false)
		end)
		if ns.QuietPresenceOwnedBy(ns.PLAYER_QUIET_OWNER) then ns.SetPrivatePresence(false) end
		if ns.QuietPresenceOwnedBy(OWNER) then ns.SetQuietPresence(false, OWNER) end
		K.IsKing, K.SharingLocation, K.ToggleLocation = saved.isKing, saved.sharing, saved.toggle
		Ly.SetSharing, ns.db.shareLocation, ns.Print, ns.Fire = saved.setSharing, saved.share, saved.print, saved.fire
		ns.db.privatePresence = saved.private
		if not ok then error(err, 0) end
	end)
end)

test("quiet presence: only the King, a High Councillor or the author turns it on, for this session; another owner can't touch it", function()
	local K, M, W = ns.King, ns.Moderation, ns.Workshop
	local saved = { guild = IsInGuild, steward = K.IsStewardName, author = W.IsAuthorName, hides = M.Hides, hc = ns.IsHighCouncillor }
	local before = Keys(ns.db)
	local ok, err = pcall(function()
		eq(ns.QuietPresence(), false, "off until asked")
		local state = ns.QuietPresenceState()
		eq(state.on, false); eq(state.since, nil)
		-- An ordinary member: no.
		local done, why = ns.SetQuietPresence(true, OWNER)
		eq(done, false); eq(why, "authority"); eq(ns.QuietPresence(), false)
		eq(select(2, ns.SetQuietPresence(false, OWNER)), "authority", "nor an off for someone who could never turn it on")
		-- A Steward is a signed issuer, but neither the King nor a councillor: no either.
		K.IsStewardName = function(name) return type(name) == "string" and name:lower() == ns.me:lower() end
		eq(M.IsIssuer(ns.me), true, "a signed issuer...")
		eq(select(2, ns.SetQuietPresence(true, OWNER)), "authority", "...that is not the King, a councillor or the author")
		K.IsStewardName = saved.steward
		-- Outside an Olympus guild: no.
		ns.IsHighCouncillor = function(name) return name == ns.me end
		IsInGuild = function() return false end
		eq(select(2, ns.SetQuietPresence(true, OWNER)), "guild")
		IsInGuild = saved.guild
		-- A councillor: yes, for this session alone (nothing saved).
		local t0 = ns.Now()
		eq(ns.SetQuietPresence(true, OWNER), true)
		state = ns.QuietPresenceState()
		eq(state.on, true); assert(state.since and state.since >= t0, "since when")
		eq(ns.SetQuietPresence(true, OWNER), true, "on again: still on")
		eq(select(2, ns.SetQuietPresence(false, "another-owner")), "owner", "another owner can't turn it off")
		eq(select(2, ns.SetQuietPresence(true, "another-owner")), "owner", "nor take it over")
		eq(ns.QuietPresenceOwnedBy(OWNER), true); eq(ns.QuietPresenceOwnedBy("another-owner"), false)
		eq(select(2, ns.SetQuietPresence("yes", OWNER)), "state")
		eq(Keys(ns.db), before, "nothing of it in the saved variables")
		-- Its owner always turns it off, even once the authority is gone.
		ns.IsHighCouncillor = saved.hc
		eq(ns.SetQuietPresence(false, OWNER), true)
		eq(ns.QuietPresence(), false); eq(ns.QuietPresenceState().since, nil)
		-- The pinned author: yes, unless the moderators hide him.
		W.IsAuthorName = function(name) return type(name) == "string" and name:lower() == ns.me:lower() end
		M.Hides = function(name) return type(name) == "string" and name:lower() == ns.me:lower() and {} or nil end
		eq(select(2, ns.SetQuietPresence(true, OWNER)), "authority", "an author the moderators hide")
		M.Hides = saved.hides
		eq(ns.SetQuietPresence(true, OWNER), true, "the author")
		eq(ns.SetQuietPresence(false, OWNER), true)
	end)
	if ns.QuietPresenceOwnedBy(OWNER) then ns.SetQuietPresence(false, OWNER) end
	IsInGuild, K.IsStewardName, W.IsAuthorName, M.Hides, ns.IsHighCouncillor = saved.guild, saved.steward, saved.author, saved.hides, saved.hc
	if not ok then error(err, 0) end
end)

test("quiet presence: the transport holds every word that says we are online or where, and nothing else", function()
	AsCouncillor(function()
		local C = ns.Comm
		local held = { "H1~1.2.5.1~Realm~p~z", "P1~1453~420~510~WA", "L1~1453~8~1~Olympus II", "L0~", "LO~42~0~0", "LN~42",
			"LY~R~1~7~77~1453~8~2~5", "LY~X~1~7~77", "PS~R~1~7~Olympus II~1453~1~2~3~5~Target-Realm~nearby",
			"PS~B~1~7~Olympus II~1453~1~2~3~5~Target-Realm~nearby", "PS~X~1~7~Target-Realm", "PS~W~1~7~Target-Realm",
			"T1~P~5~Olympus~1453~420~510", "T1~Q~5~Olympus", "CG~1~S~1790000000~Olympus II,10,2,600,1790000000",
			"V2~7~1.2.5.1~~E~~p~0~0~", "V4~1.2.5.1", "V8~7~1.2.5.1", "NK~1~p~M~-~Olympus II~-", "DV~1~OLK2.x", "DV~0", "DW~1", "DW~0",
			"ZQ~L1~H~-~0",
			-- (Review: these said he was online, some where, while it was on.) An auditor's check of a
			-- snapshot marks him as heard too; the court; the Wanted reviewer's lease, its No, a sighting
			-- and its taking back; a councillor's help notice and "got it"; a keeper's donations; an
			-- arbiter's availability; the tabard collector lease and its reports; a profile
			-- presentation's words; a crafter's listing, unlisting, answer and recipe list.
			"ZQ~L1~H~1a2b~3c", "T1~C~5~Olympus~1453~Stormwind City", "T1~Z~5~Olympus", "WS~R~1", "WS~R~0",
			"WS~S~1~Olympus II~ab12~1790000000~1453~400~600~7~0A000001~Grom-Realm", "WS~X~1", "HA~1", "HA~0", "HK~1",
			"TD~Olympus II~1~1790000000~1453", "TD~Olympus II~0~0~", "ZV~L1~f~-", "U2~2~abc~600~Olympus",
			"U3~2~abc~1~60~Olympus II~G", "U4~2~abc~2~Grom-Realm~Horde Guild~60~O~Olympus II", "FX~2~G~s~1~1~1790000000~Olympus II~7",
			"FX~2~S~s~1~2~1790000000~Olympus II~Issuer-Realm~7~caption", "FX~2~C~s~1~3~1790000000~Olympus II~7",
			"W1~Olympus II~alch:Alchemy:300:300:5", "W0~", "WA~ab~Olympus II~Alchemy~300~1:2", "WL~alch~1/1~1:2" }
		-- Reads, and what the player posts himself (a list he changed, a writ, his muster, his arrow
		-- word), still go: their timed repeats are held in their modules (King.lua, Acts.lua, ...).
		local passes = { "M1~A~Olympus II~1~~hello there", "Q1~", "K0~", "LQ~1~1453~8", "LR~1", "LX~1", "LY~Q~1~7~77~1453",
			"PS~Q~1~7~Target-Realm", "PS~A~1~7~1453", "PS~C~1~7~Target-Realm", "CG~1~Q~1790000000", "T1~S~5~Olympus",
			"V1~7~100", "V7~7", "ZQ~L1~R~-~0", "TA~Olympus II~1", "D1~ARMS~1~1~1~Olympus II~1~x",
			"WQ~ab~t~flask", "WR~alch", "HR~a hand please", "T7~1", "T4~5~Olympus II", "T1~H~5~Olympus~", "T1~A~5~Olympus~1800~Gates~Muster",
			"T1~W~5~Olympus~army~a writ", "OM~1~P~A~RealmGroup~1~1790000000~Olympus~1429~Gather", "K6~1~G~1~1790000000~",
			"U1~x", "UP~x", "WC~x" }
		for _, msg in ipairs(held) do eq(C.QuietHolds(msg), false, "off: " .. msg) end
		Quiet(true)
		for _, msg in ipairs(held) do eq(C.QuietHolds(msg), true, "held: " .. msg) end
		for _, msg in ipairs(passes) do eq(C.QuietHolds(msg), false, "still goes: " .. msg) end
		local st = C.Stats()
		eq(st.quietPresence, true); assert(st.quietHeld >= #held, "counted in /oly status")
		Quiet(false)
		for _, msg in ipairs(held) do eq(C.QuietHolds(msg), false, "off again: " .. msg) end
	end)
end)

test("quiet presence: no hello, census report or census answer; what waited stays home; reads and typed chat still go; all of it again once off", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		AsCouncillor(function()
			GetChannelName = function() return 5 end
			local cns, Deliver = FreshComm()
			local C = cns.Comm
			C.loginAt = cns.clock - 1000
			C.JoinChannel()
			cns.After = function(_, _, fn) fn() end
			local sent = {}
			C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
			C_ChatInfo.SendAddonMessageLogged = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
			local function Flush() for _ = 1, 60 do C.Pump() end end
			local function Count(pattern) local n = 0 for _, m in ipairs(sent) do if m:find(pattern) then n = n + 1 end end return n end
			local ours = { guild = GetGuildInfo("player"), total = 1000, online = 300, zones = {} }
			-- A hello and a census report already waiting when it begins never leave.
			C.Hello(true)
			C.Broadcast(ours)
			Quiet(true)
			Flush()
			eq(Count("^GUILD H1~"), 0, "the waiting hello stays home")
			eq(Count("^CHANNEL C"), 0, "the census report on its way stays home")
			-- Nothing new either: a forced hello, the census we would report (alone: we would be
			-- the reporter), a census request's answer.
			C.Hello(true)
			C.MaybeBroadcast(ours)
			eq(C.isReporter, false, "never the reporter"); eq(C.isRunnerUp, false)
			C.Broadcast(ours)
			Deliver("CHANNEL", "Newcomer-Realm", "Q1~")
			Flush()
			eq(#sent, 0, "nothing at all: " .. tostring(sent[1]))
			local why
			eq(C.Send("CHANNEL", "L1~1453~8~1~Olympus II", nil, nil, nil, function(_, w) why = w end), false)
			eq(why, "quiet", "a presence word handed over is refused, and says why")
			-- Reads and the player's own chat line still go.
			cns.clock = cns.clock + 31 -- (past the newcomer's ask, which would hold ours back: Comm.AskCensus)
			C.AskCensus()
			eq(C.Send("CHANNEL", "PS~Q~1~7~Target-Realm"), true)
			eq(C.SendChat("M1~A~Olympus II~1~~a line he typed"), true)
			Flush()
			eq(Count("^CHANNEL Q1~$"), 1, "the census request (a read)")
			eq(Count("^CHANNEL PS~Q~"), 1, "a sighting request (a read)")
			eq(Count("^CHANNEL M1~"), 1, "the chat line he typed")
			eq(Count("H1~") + Count("^CHANNEL C") + Count("L1~"), 0)
			-- Off: the hello and the census go again.
			Quiet(false)
			cns.clock = cns.clock + 200 -- (the next report's time, after the one held back)
			C.Hello(true)
			C.MaybeBroadcast(ours)
			eq(C.isReporter, true, "alone again: the reporter")
			Flush()
			eq(Count("^GUILD H1~"), 1, "the hello again")
			assert(Count("^CHANNEL C") > 0, "the census report again")
		end)
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("quiet presence: no layer of ours, no hop offer, invite or answer; our own hop ask still goes; the layer and the help come back once off", function()
	AsCouncillor(function()
		local ok, err = pcall(function()
			WithHop(function(w, H)
				GetGuildInfo = function() return "Olympus II", "Officer", 1 end -- (officers announce their layer)
				local function Layers() local n = 0 for _, m in ipairs(w.sent) do if m:find("^CHANNEL L1~") then n = n + 1 end end return n end
				-- An offer made before it begins: its request then gets nothing.
				w.see(7)
				eq(Layers(), 1, "our layer, before")
				H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
				eq(w.whispered[1], "Asker-Realm LO~42~0~0")
				Quiet(true)
				H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
				eq(#w.invited, 0, "no invite"); eq(#w.popups, 0, "no window"); eq(#w.whispered, 1, "no answer, not even a no")
				-- A new layer is read, for us alone; an ask gets no offer.
				w.clock = w.clock + 1000
				w.see(9)
				eq(ns.Layers.Mine().zoneUID, 9, "still read")
				eq(Layers(), 1, "not announced")
				H.HandleAsk("CHANNEL", "Second-Realm", "LQ~43~1453~9")
				eq(#w.whispered, 1, "no offer")
				-- Our own ask is a read: it goes (nobody answers it here).
				H.Ask(1453, 8, "the King's layer")
				eq(w.sent[#w.sent], "CHANNEL LQ~1~1453~8")
				w.clock = w.clock + 30
				H.Tick()
				-- Off: our layer at once (its listener), and help again.
				Quiet(false)
				eq(Layers(), 2, "announced again at once")
				assert(w.sent[#w.sent]:find("^CHANNEL L1~1453~9~"), w.sent[#w.sent])
				H.HandleAsk("CHANNEL", "Third-Realm", "LQ~44~1453~9")
				eq(w.whispered[#w.whispered], "Third-Realm LO~44~0~0", "an offer again")
			end)
		end)
		ns.Layers.Reset()
		if not ok then error(err, 0) end
	end)
end)

test("quiet presence: the King's crown never leaves, nor its removal, while it is on; it is back at once once off", function()
	AsCouncillor(function()
		local K = ns.King
		local saved = { send = ns.Comm.Send, isKing = K.IsKing, now = ns.Now, best = C_Map.GetBestMapForUnit,
			pos = C_Map.GetPlayerMapPosition, crown = ns.db.throneLocation }
		local sent, clock = {}, 2100000000
		local ok, err = pcall(function()
			K.Reset()
			ns.Layers.Reset() -- (no layer of ours: its own listener would announce it first)
			ns.db.throneLocation = nil
			ns.Now = function() return clock end
			ns.Comm.Send = function(dist, msg) sent[#sent + 1] = dist .. " " .. msg return true end
			K.IsKing = function() return true end
			C_Map.GetBestMapForUnit = function() return 1453 end
			C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.42, 0.51 end } end
			Quiet(true)
			K.ToggleLocation()
			eq(K.SharingLocation(), true, "his choice is kept")
			eq(#sent, 0, "no crown: " .. tostring(sent[1]))
			K.ToggleLocation()
			eq(K.SharingLocation(), false)
			eq(#sent, 0, "no removal either: the army's copy expires on its own")
			K.ToggleLocation()
			clock = clock + 60
			eq(#sent, 0)
			Quiet(false)
			assert(sent[1] and sent[1]:find("^CHANNEL T1~P~%d+~[^~]*~1453~420~510$"), "the crown at once: " .. tostring(sent[1]))
		end)
		ns.Comm.Send, K.IsKing, ns.Now = saved.send, saved.isKing, saved.now
		C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, ns.db.throneLocation = saved.best, saved.pos, saved.crown
		K.Reset()
		if not ok then error(err, 0) end
	end)
end)

test("quiet presence: no author presence, roll-call or version-check answer, nor census snapshot; each goes again once off", function()
	AsCouncillor(function()
		local W, V, D = ns.Workshop, ns.Versions, ns.Data
		local saved = { send = ns.Comm.Send, whisper = ns.Comm.Whisper, chunked = ns.Comm.SendChunked, now = ns.Now,
			isAuthor = W.IsAuthor, after = W.after, random = W.random, payload = D.GlobalCensusPayload, roll = ns.db.rollCall }
		-- (A clock past every other test's: the roll call's and the checks' gaps start from their last answer.)
		local sent, clock = {}, 4000000000
		local ok, err = pcall(function()
			ns.Now = function() return clock end
			ns.Comm.Send = function(dist, msg) sent[#sent + 1] = dist .. " " .. msg return true end
			ns.Comm.Whisper = function(to, msg) sent[#sent + 1] = "WHISPER " .. to .. " " .. msg return true end
			ns.Comm.SendChunked = function(payload, _, dist) sent[#sent + 1] = (dist or "CHANNEL") .. " " .. payload return true end
			W.after = function(_, _, fn) fn() end
			W.random = function(a, b) return a and b and a or 0 end
			D.GlobalCensusPayload = function() return "CG~1~S~4000000000~Olympus II,10,2,600,4000000000" end
			ns.db.rollCall = true -- (the player's yes to the author's roll calls)
			local author = ns.FullName(ns.AUTHOR, ns.AUTHOR_REALM)
			local function Again()
				W.IsAuthor = function() return true end -- (his presence is the author's own client's...)
				W.SendPresence()
				W.IsAuthor = saved.isAuthor -- (...a roll call, anyone's but his)
				W.HandleRoll("CHANNEL", author, "V1~" .. tostring(clock % 9000 + 1) .. "~100")
				V.HandlePing("WHISPER", "Asker" .. tostring(clock % 9000) .. "-Realm", "V7~12")
				return D.SendGlobalCensus()
			end
			Quiet(true)
			eq(Again(), false, "no snapshot")
			eq(#sent, 0, "nothing: " .. tostring(sent[1]))
			Quiet(false)
			clock = clock + 3600
			eq(Again(), true)
			assert(Find(sent, "^CHANNEL V4~"), "the author's presence again")
			assert(Find(sent, "^WHISPER .- V2~"), "a roll call answered again")
			assert(Find(sent, "^WHISPER Asker.- V8~12~"), "a version check answered again")
			assert(Find(sent, "^CHANNEL CG~1~S~"), "the census snapshot again")
		end)
		ns.Comm.Send, ns.Comm.Whisper, ns.Comm.SendChunked, ns.Now = saved.send, saved.whisper, saved.chunked, saved.now
		W.IsAuthor, W.after, W.random, D.GlobalCensusPayload, ns.db.rollCall = saved.isAuthor, saved.after, saved.random, saved.payload, saved.roll
		if not ok then error(err, 0) end
	end)
end)

test("quiet presence: a line on top of the Census and the Realm says so while it is on, in English and pt-BR, with what still goes", function()
	AsCouncillor(function()
		local L = ns.L
		-- (Review: "other Olympus clients see you as offline" was untrue for a guild leader or officer,
		-- whom the guildmates' census still shows online from the game's guild roster: the King first.)
		eq(L.QUIET_PRESENCE_LINE, "Quiet presence: Olympus stops announcing you and where you are. Your guild roster, the census your guildmates build from it, /who and chat still show you.")
		for _, words in ipairs({ "Olympus chat lines you type, what you post yourself and the records your client relays still go out",
			"a guild leader or officer still shows online there, and your zone may show for up to 12 minutes",
			-- (1.4.0: the built-in Private presence stays on across logins, the author's default; an
			-- addon's quiet presence still ends at a /reload, and the tooltip says which is which. The
			-- line the cherry-picked switch had, "turned it on for this session", was untrue for it.)
			"Private presence stays on across logins until you turn it off",
			"With Private presence your guild is told, and its members' Olympus clients count you offline in the census they send",
			"after a /reload, Olympus may say hello before that addon turns it on again" }) do
			assert(L.QUIET_PRESENCE_TIP:find(words, 1, true), "the tooltip says: " .. words)
		end
		local function Has(lines)
			for _, line in ipairs(lines) do
				if type(line.text) == "string" and line.text:find(L.QUIET_PRESENCE_LINE, 1, true) then return line end
			end
			return nil
		end
		eq(Has(ns.Views.Build("census")), nil, "off: no line")
		eq(Has(ns.Views.RealmLines()), nil)
		Quiet(true)
		local line = assert(Has(ns.Views.Build("census")), "on top of the Census")
		assert(Has(ns.Views.RealmLines()), "and of the Realm")
		local tip = {}
		line.tooltip({ AddLine = function(_, s) tip[#tip + 1] = s end })
		eq(tip[2], L.QUIET_PRESENCE_TIP)
		Quiet(false)
		eq(Has(ns.Views.Build("census")), nil, "gone once off")
		-- pt-BR.
		local pt, savedLocale = {}, GetLocale
		GetLocale = function() return "ptBR" end
		local ok, err = pcall(function()
			local root = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]quiet%-presence%.lua$")) or "./"
			assert(loadfile(root .. "Olympus/Locales.lua"))("Olympus", pt)
		end)
		GetLocale = savedLocale
		assert(ok, err)
		eq(pt.L.QUIET_PRESENCE_LINE, "Presença silenciosa: o Olympus para de anunciar você e onde você está. A lista da guilda, o censo que seus colegas de guilda montam com ela, o /who e o chat ainda mostram você.")
		assert(pt.L.QUIET_PRESENCE_TIP:find("linhas de chat do Olympus que você digitar, o que você mesmo publicar e os registros que seu cliente repassa ainda são enviados", 1, true))
		assert(pt.L.QUIET_PRESENCE_TIP:find("um mestre ou oficial de guilda ainda aparece online lá", 1, true))
		assert(pt.L.QUIET_PRESENCE_HELD and pt.L.QUIET_PRESENCE_HELD ~= L.QUIET_PRESENCE_HELD, "the held line in pt-BR")
	end)
end)

-- 1.4.0, Private presence (the author's default): on until the player turns it off, across logins,
-- and while it is on his own guild's clients count him offline in the census they send, so another
-- guild never sees a guild leader's online flag (the report's leaderOnline, Roster.lua). Fails
-- before: the switch lasted one session (nothing restored it at login) and a guildmate's census
-- still sent leaderOnline for him.
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]quiet%-presence%.lua$")) or "./"
if not ns.PrivatePresence then assert(loadfile(ROOT .. "Olympus/PrivatePresence.lua"))("Olympus", ns) end
local PP = ns.PrivatePresence

test("private presence: on until the player turns it off, taken up again at the next login before anything goes out; off is remembered too", function()
	AsCouncillor(function()
		local saved = { private = ns.db.privatePresence, print = ns.Print, member = ns.IsMember }
		local ok, err = pcall(function()
			ns.Print = function() end
			ns.db.privatePresence = nil
			eq(ns.SetPrivatePresence(true), true)
			eq(ns.PrivatePresenceSaved(), true, "the choice is kept for this character")
			-- A logout ends the session's quiet presence (nothing of it is saved)...
			eq(ns.SetQuietPresence(false, ns.PLAYER_QUIET_OWNER), true)
			eq(ns.QuietPresence(), false)
			-- ...and the next login takes it up again, even before the guild is known.
			ns.IsMember = function() return false end
			eq(ns.RestorePrivatePresence(), true)
			eq(ns.QuietPresenceOwnedBy(ns.PLAYER_QUIET_OWNER), true, "private again, as its owner")
			eq(ns.Comm.QuietHolds("H1~1.4.0~Realm~p"), true, "the login's hello is held")
			ns.IsMember = saved.member
			eq(ns.RestorePrivatePresence(), false, "once a login")
			-- Off is the player's choice too: it is never taken up again.
			eq(ns.SetPrivatePresence(false), true)
			eq(ns.PrivatePresenceSaved(), false)
			eq(ns.QuietPresence(), false)
			eq(ns.RestorePrivatePresence(), false, "nothing to take up after an off")
			eq(ns.QuietPresence(), false)
		end)
		if ns.QuietPresenceOwnedBy(ns.PLAYER_QUIET_OWNER) then ns.SetQuietPresence(false, ns.PLAYER_QUIET_OWNER) end
		ns.db.privatePresence, ns.Print, ns.IsMember = saved.private, saved.print, saved.member
		if not ok then error(err, 0) end
	end)
end)

test("private presence: a character no longer allowed loses it once his guild is known, with one line; not before", function()
	AsCouncillor(function()
		local saved = { private = ns.db.privatePresence, print = ns.Print, member = ns.IsMember, hc = ns.IsHighCouncillor }
		local printed = {}
		local ok, err = pcall(function()
			ns.Print = function(m) printed[#printed + 1] = m end
			ns.db.privatePresence = nil
			eq(ns.SetPrivatePresence(true), true)
			eq(ns.PrivatePresenceLapse(), false, "still allowed: kept")
			ns.IsHighCouncillor = function() return false end
			ns.IsMember = function() return false end
			eq(ns.PrivatePresenceLapse(), false, "the guild not known yet: kept")
			eq(ns.QuietPresence(), true)
			ns.IsMember = saved.member
			eq(ns.PrivatePresenceLapse(), true, "off the council: it lapses")
			eq(ns.QuietPresence(), false); eq(ns.PrivatePresenceSaved(), false)
			eq(printed[#printed], ns.L.PRIVATE_PRESENCE_LAPSED)
		end)
		if ns.QuietPresenceOwnedBy(ns.PLAYER_QUIET_OWNER) then ns.SetQuietPresence(false, ns.PLAYER_QUIET_OWNER) end
		ns.db.privatePresence, ns.Print, ns.IsMember, ns.IsHighCouncillor = saved.private, saved.print, saved.member, saved.hc
		if not ok then error(err, 0) end
	end)
end)

test("private presence: its restore is the first LOGIN listener of the addon, ahead of every hello and presence word", function()
	-- Olympus.toc's order is the order the game runs the files, and ns.On's listeners run in the
	-- order they were added: the first `ns.On("LOGIN"` of the addon must be the restore.
	local first
	for line in io.lines(ROOT .. "Olympus/Olympus.toc") do
		local file = line:match("^%s*([^#%s][^\r]-)%s*$")
		if file and file:match("%.lua$") then
			local src = assert(io.open(ROOT .. "Olympus/" .. file:gsub("\\", "/"), "rb")):read("*a")
			local at = src:find('ns.On("LOGIN"', 1, true)
			if at then first = { file = file, line = src:sub(at, (src:find("\n", at, true) or #src)) } break end
		end
	end
	assert(first, "a LOGIN listener")
	eq(first.file, "Core.lua")
	assert(first.line:find("RestorePrivatePresence", 1, true), "the first LOGIN listener: " .. first.line)
end)

test("private presence: only the player's own guild is told, PP~1 while on and PP~0 once after; an addon's quiet presence says nothing", function()
	AsCouncillor(function()
		local saved = { send = ns.Comm.Send, private = ns.db.privatePresence, print = ns.Print }
		local sent = {}
		local ok, err = pcall(function()
			ns.Print = function() end
			ns.Comm.Send = function(dist, msg) sent[#sent + 1] = dist .. " " .. msg return true end
			PP.Reset()
			ns.db.privatePresence = nil
			eq(ns.SetQuietPresence(true, OWNER), true)
			eq(PP.Say(true), false, "an addon's quiet presence: no word")
			eq(ns.SetQuietPresence(false, OWNER), true)
			eq(#sent, 0)
			-- The switch turned on says it at once (QUIET_PRESENCE_CHANGED)...
			eq(ns.SetPrivatePresence(true), true)
			eq(table.concat(sent, ","), "GUILD PP~1")
			eq(PP.Say(), false, "not again before SAY_EVERY")
			-- ...again every SAY_EVERY while it is on...
			local now = ns.Now
			ns.Now = function() return now() + PP.SAY_EVERY end
			eq(PP.Say(), true)
			ns.Now = now
			eq(table.concat(sent, ","), "GUILD PP~1,GUILD PP~1")
			-- ...and its end once.
			eq(ns.SetPrivatePresence(false), true)
			eq(sent[#sent], "GUILD PP~0")
			eq(PP.Say(true), false, "the off said once")
			for _, line in ipairs(sent) do assert(line:sub(1, 6) == "GUILD ", "never the Olympus channel: " .. line) end
		end)
		if ns.QuietPresenceOwnedBy(ns.PLAYER_QUIET_OWNER) then ns.SetQuietPresence(false, ns.PLAYER_QUIET_OWNER) end
		if ns.QuietPresenceOwnedBy(OWNER) then ns.SetQuietPresence(false, OWNER) end
		ns.Comm.Send, ns.db.privatePresence, ns.Print = saved.send, saved.private, saved.print
		PP.Reset()
		if not ok then error(err, 0) end
	end)
end)

test("private presence: a guildmate's census counts its guild leader offline while his Private presence is heard, from the guild alone and only from one allowed", function()
	local LEAD = "Lead-Realm"
	local saved = { count = GetNumGuildMembers, info = GetGuildRosterInfo, hc = ns.IsHighCouncillor, heard = ns.rdb.privateHeard }
	local ok, err = pcall(function()
		ns.rdb.privateHeard = nil
		GetNumGuildMembers = function() return 3, 3 end
		GetGuildRosterInfo = function(i)
			local name = i == 1 and LEAD or ("Member" .. i .. "-Realm")
			return name, "rank", i == 1 and 0 or 3, 60, "class", "Stormwind City", "", "", true, 0, "WARRIOR"
		end
		local r = ns.Roster.Scan()
		eq(r.leaderOnline, true, "before: the leader online"); eq(r.online, 3)
		-- Not one allowed to use it: ignored.
		ns.IsHighCouncillor = function() return false end
		PP.Handle("GUILD", LEAD, "PP~1")
		eq(ns.Roster.Scan().leaderOnline, true, "an ordinary guild leader's word changes nothing")
		ns.IsHighCouncillor = function(name) return type(name) == "string" and ns.FullName(name) == LEAD end
		-- The Olympus channel is never its way: ignored.
		PP.Handle("CHANNEL", LEAD, "PP~1")
		eq(ns.Roster.Scan().leaderOnline, true, "from the channel: ignored")
		PP.Handle("GUILD", LEAD, "PP~1")
		r = ns.Roster.Scan()
		eq(r.leaderOnline, false, "his Private presence: offline in the census we send")
		eq(r.online, 2, "and not counted online")
		local d = ns.Codec.DecodeReport(ns.Codec.EncodeReport(r))
		eq(d.leaderOnline, false, "the report on the wire says offline")
		-- It lapses KEEP after it was last heard...
		local now = ns.Now
		ns.Now = function() return now() + PP.KEEP + 1 end
		eq(ns.Roster.Scan().leaderOnline, true, "a word no longer repeated lapses")
		ns.Now = now
		eq(ns.Roster.Scan().leaderOnline, false)
		-- ...and ends at once with his PP~0.
		PP.Handle("GUILD", LEAD, "PP~0")
		eq(ns.Roster.Scan().leaderOnline, true, "off: online again")
	end)
	GetNumGuildMembers, GetGuildRosterInfo, ns.IsHighCouncillor, ns.rdb.privateHeard = saved.count, saved.info, saved.hc, saved.heard
	ns.Roster.Scan() -- (the harness's roster again, for the tests after this one)
	if not ok then error(err, 0) end
end)
