local ADDON, ns = ...
local Relay = {}
ns.Relay = Relay

-- 1.4.3 (launch night, 2026-11-04). WoW: Forever's live realms accept an addon's messages on any
-- player-made chat channel and never deliver them, not even back to the sender (measured on launch
-- night: 0 of 123 members' messages heard in a minute; the beta delivered them, as Classic's beta
-- did before patch 1.13.3 cut it). The guild and addon whispers are delivered, to any player of the
-- faction on any of Forever's sub-realms, by his plain "First Surname". So where names split
-- (ns.splitNames: Forever), everything the addon says "on the channel" travels like this instead,
-- and no module changes: the census, the signed lists, the key, the rankings' words, the chat.
--
--   hop 1  origin -> relay      RL~<f>~<text>            by whisper, to one relay (Pick)
--   hop 2  relay -> reporters   RM~<f>~<origin>~<text>   by whisper, one per guild (its reporter)
--   hop 3  reporter -> guild    RG~<f>~<origin>~<text>   over GUILD, once, to everyone there
--
-- The relays are the signed High Council's characters, the author's, the King and the Treasurer:
-- names every client holds from the signed list, so a guild that just arrived knows whom to
-- whisper. A client picks one relay (its guild's name decides which, changing every PICK_WINDOW so
-- the load spreads), pings it once (RP) and expects an answer (RA): a relay that does not answer
-- (offline, or an older version that cannot; the answer is RY: RA is the Records' ask) is left out for DEAD_FOR and the next one is picked;
-- the server's "No player named X" names an offline one at once. The relays know each guild's
-- reporter from its registration (RR, sent every REGISTER_EVERY while elected: Comm.MaybeBroadcast)
-- and forward to those alone; a reporter hands each message to its guild over GUILD once, where
-- every guildmate takes it as if it had come on the channel (Comm.Inject: the same handlers, the
-- origin as its sender). What came by the relay is taken once (Seen): a relay's copy and the
-- guild's copy of one message count once. <f> is L for a chat line (the origin sends it logged,
-- so his own words are on the server's log) and P for anything else. A piece too long for one
-- whisper travels in Codec's pieces (the assemblers put RL, RM and RG together like any other).
--
-- Trust: the server stamps every hop's sender. A relay is believed about the origin because it is
-- a signed councillor's, the author's, the King's or the Treasurer's character (RM from anyone else
-- is dropped); a reporter is believed by its guild because it is a guildmate (GUILD). Nothing here
-- lets a stranger speak as the King: his words still reach the guilds only through those clients.
-- Off Forever (the beta, Era, Anniversary) nothing here runs and the channel works as before.

Relay.PICK_WINDOW = 600      -- seconds one relay serves a guild before the pick moves on
Relay.DEAD_FOR = 600         -- a relay that did not answer, or is offline, is left out this long
Relay.PING_WAIT = 30         -- an answer to the ping is due within this
Relay.REGISTER_EVERY = 170   -- a reporter tells its relay it is the reporter this often
Relay.REPORTER_FOR = 600     -- a relay keeps a reporter this long past its last registration
Relay.SEEN_FOR = 300         -- a message taken is remembered this long (a second copy counts once)
Relay.SEEN_MAX = 2000
Relay.MAX_RELAYS = 40

local offline = {}   -- relay name (lower) -> until (ns.Now())
local verified = {}  -- relay name (lower) -> when its RA last came
local pinged = {}    -- relay name (lower) -> when we pinged it, while an answer is due
local reporters = {} -- (on a relay) guild name (lower) -> { name = "First Surname-Realm", t = when }
local seen = {}      -- origin .. "|" .. text -> when
local seenCount = 0
local stats = { out = 0, forwarded = 0, delivered = 0, dropped = 0, dead = 0, registered = 0 }
function Relay.Stats()
	local n = 0
	for _, r in pairs(reporters) do n = n + 1 end
	return { out = stats.out, forwarded = stats.forwarded, delivered = stats.delivered, dropped = stats.dropped,
		dead = stats.dead, reporters = n, relay = Relay.Pick(), on = Relay.On() }
end

local function Now() return ns.Now() end
local function Lower(s) return type(s) == "string" and s:lower() or "" end

-- Where it runs: where the game splits names (Forever), unless switched off for a test.
function Relay.On()
	return ns.splitNames == true and ns.rdb ~= nil and ns.rdb.relayOff ~= true
end

-- The relays' names, as whispers reach them: the plain "First Surname", sorted; ours left out
-- unless asked for (IsRelay asks: our own client is a relay too).
function Relay.Names(withSelf)
	local out, set = {}, {}
	local mine = ns.ShortName(ns.me or ""):lower()
	local function Add(n)
		if type(n) ~= "string" or n == "" then return end
		local short = ns.ShortName(n)
		local key = short:lower()
		if key == "" or set[key] or (not withSelf and key == mine) then return end
		if #out >= Relay.MAX_RELAYS then return end
		set[key] = true
		out[#out + 1] = short
	end
	local c = ns.rdb and ns.rdb.council
	if type(c) == "table" and type(c.names) == "table" then
		local list = {}
		for _, name in pairs(c.names) do list[#list + 1] = name end
		table.sort(list)
		for _, name in ipairs(list) do Add(name) end
	end
	if ns.AuthorCharacters then for _, n in ipairs((ns.AuthorCharacters())) do Add(n) end end
	if ns.KingCharacter then Add(ns.KingCharacter()) end
	if ns.TreasurerPins then for _, n in ipairs((ns.TreasurerPins())) do Add(n) end end
	table.sort(out)
	return out
end
function Relay.IsRelay(name)
	local key = ns.ShortName(name or ""):lower()
	if key == "" then return false end
	for _, n in ipairs(Relay.Names(true)) do if n:lower() == key then return true end end
	return false
end

local function Hash(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
	return h
end
-- The relay this client whispers to now: among those not left out, the one our guild's name and
-- the window pick; nil without any (then the channel, as before).
function Relay.Pick()
	if not Relay.On() then return nil end
	local now = Now()
	local names = Relay.Names(true) -- (our own client too, when it is a relay: no whisper needed)
	local live = {}
	for _, n in ipairs(names) do
		if (offline[n:lower()] or 0) <= now then live[#live + 1] = n end
	end
	if #live == 0 then return nil end
	local seed = Lower(GetGuildInfo and GetGuildInfo("player") or ns.me or "") .. "#" .. tostring(math.floor(now / Relay.PICK_WINDOW))
	return live[(Hash(seed) % #live) + 1]
end

local function LeaveOut(name, why)
	local key = ns.ShortName(name or ""):lower()
	if key == "" then return end
	offline[key] = Now() + Relay.DEAD_FOR
	pinged[key] = nil
	stats.dead = stats.dead + 1
	ns.Log("relay %s left out for %ds: %s", tostring(name), Relay.DEAD_FOR, tostring(why))
end
Relay.LeaveOut = LeaveOut

-- The envelope of hop 1 for one message: whole, or in pieces when a whisper cannot carry it.
local relayId = 0
local function Envelope(kind, text)
	if #text <= 255 then return { text } end
	relayId = (relayId + 1) % 1000
	return ns.Codec.Chunk(text, "R" .. relayId)
end

-- A relay not answered lately is pinged once; no answer in PING_WAIT leaves it out.
local function Ping(relay)
	local key = relay:lower()
	local now = Now()
	if now - (verified[key] or -math.huge) < Relay.DEAD_FOR then return end
	if pinged[key] then return end
	pinged[key] = now
	ns.Comm.Whisper(relay, "RL~P~RP~", "relay ping", true)
	ns.After(Relay.PING_WAIT, "relay ping", function()
		if pinged[key] == now and now - (verified[key] or -math.huge) >= Relay.DEAD_FOR then
			pinged[key] = nil
			LeaveOut(relay, "no answer to the ping")
		end
	end)
end

-- Hop 1: what a module said "on the channel" goes to our relay. parts: the message's pieces as the
-- channel would carry them (each one whisper). Returns true when handed to the queue.
function Relay.Out(parts, logged, done, key, urgent, options)
	local relay = Relay.Pick()
	if not relay then return false end
	local flag = logged and "L" or "P"
	-- Our own client the relay: handed to it here, whole (a whisper to oneself is never delivered).
	if relay:lower() == ns.ShortName(ns.me or ""):lower() then
		stats.out = stats.out + 1
		for _, p in ipairs(parts) do Relay.HandleIn("WHISPER", ns.me, "RL~" .. flag .. "~" .. p) end
		if done then ns.SafeCall("relay done", done, true) end
		return true
	end
	local pieces = {}
	for _, p in ipairs(parts) do
		for _, e in ipairs(Envelope("RL", "RL~" .. flag .. "~" .. p)) do pieces[#pieces + 1] = e end
	end
	if #pieces == 0 or #pieces > ns.Codec.MAX_CHUNKS then return false end
	Ping(relay)
	stats.out = stats.out + 1
	local pass = options and { owner = options.owner, guard = options.guard, guardKey = options.guardKey, permit = options.permit } or nil
	if #pieces == 1 then
		return ns.Comm.Whisper(relay, pieces[1], key, urgent, logged, done, pass) ~= false
	end
	return ns.Comm.SendBatch("WHISPER", pieces, key, relay, urgent, done, pass) ~= false
end

-- The reporter's registration (Comm.MaybeBroadcast, every REGISTER_EVERY while elected).
local lastRegister = -math.huge
function Relay.Register(force)
	if not Relay.On() then return false end
	local now = Now()
	if not force and now - lastRegister < Relay.REGISTER_EVERY then return false end
	local guild = GetGuildInfo and GetGuildInfo("player")
	if type(guild) ~= "string" or guild == "" then return false end
	lastRegister = now
	return Relay.Out({ "RR~" .. guild }, false, nil, "relay register", false)
end

-- Taken once: a message by its origin and text (the relay's copy and the guild's count once).
local function Seen(origin, text)
	local now = Now()
	local key = Lower(origin) .. "|" .. text
	if seen[key] and now - seen[key] < Relay.SEEN_FOR then return true end
	if seenCount >= Relay.SEEN_MAX then
		for k, t in pairs(seen) do
			if now - t >= Relay.SEEN_FOR then seen[k] = nil seenCount = seenCount - 1 end
		end
		if seenCount >= Relay.SEEN_MAX then wipe(seen) seenCount = 0 end
	end
	if not seen[key] then seenCount = seenCount + 1 end
	seen[key] = now
	return false
end

-- The last hop on this client: the message as if it had come on the channel from its origin.
local function Deliver(origin, text, logged)
	if Seen(origin, text) then return false end
	stats.delivered = stats.delivered + 1
	ns.Comm.Inject("CHANNEL", origin, text, logged)
	return true
end

-- A reporter hands a message to its guild once (hop 3).
local function ToGuild(flag, origin, text)
	if not IsInGuild() then return false end
	local pieces = Envelope("RG", "RG~" .. flag .. "~" .. origin .. "~" .. text)
	if #pieces == 1 then return ns.Comm.Send("GUILD", pieces[1], nil, false, false) ~= false end
	return ns.Comm.SendBatch("GUILD", pieces, nil, nil, false) ~= false
end

-- Hop 1 heard (we are a relay): a ping is answered, a registration kept, anything else forwarded
-- to every guild's reporter (ours included: delivered here and handed to our guild).
function Relay.HandleIn(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local flag, body = tostring(text):match("^RL~([LP])~(.*)$")
	if not flag then return false end
	if not Relay.IsRelay(ns.me) then return false end -- (only a relay's client answers hop 1)
	local now = Now()
	if body == "RP~" then
		if ns.FullName(sender) ~= ns.me then ns.Comm.Whisper(sender, "RY~", "relay ack:" .. sender, true) end
		return true
	end
	local guild = body:match("^RR~(.+)$")
	if guild then
		local had = reporters[guild:lower()]
		reporters[guild:lower()] = { name = ns.FullName(sender), t = now, guild = guild }
		stats.registered = stats.registered + 1
		if not had or had.name ~= ns.FullName(sender) then ns.Log("relay: %s's reporter is %s", guild, tostring(sender)) end
		return true
	end
	local origin = ns.FullName(sender)
	local pieces
	for g, r in pairs(reporters) do
		if now - r.t > Relay.REPORTER_FOR then
			reporters[g] = nil
		elseif r.name == ns.me then
			if Deliver(origin, body, flag == "L") then ToGuild(flag, origin, body) end
		else
			pieces = pieces or Envelope("RM", "RM~" .. flag .. "~" .. origin .. "~" .. body)
			stats.forwarded = stats.forwarded + 1
			if #pieces == 1 then ns.Comm.Whisper(r.name, pieces[1], nil, false, false)
			else ns.Comm.SendBatch("WHISPER", pieces, nil, r.name, false) end
		end
	end
	-- A relay in a guild whose reporter is elsewhere, or none: it hears the message itself too.
	local n = 0
	for _ in pairs(reporters) do n = n + 1 end
	if not seen[Lower(origin) .. "|" .. body] then ns.Log("relay: %s's word (%s) to %d reporters", tostring(sender), body:sub(1, 2), n) end
	Deliver(origin, body, flag == "L")
	return true
end

-- Hop 2 heard (we are a reporter): from a relay alone; delivered here and handed to our guild.
function Relay.HandleRelayed(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local flag, origin, body = tostring(text):match("^RM~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	if not Relay.IsRelay(sender) then stats.dropped = stats.dropped + 1 return false end
	verified[ns.ShortName(sender):lower()] = Now()
	if not seen[Lower(origin) .. "|" .. body] then ns.Log("relay: %s's word (%s) by %s", tostring(origin), body:sub(1, 2), tostring(sender)) end
	if Deliver(origin, body, flag == "L") then ToGuild(flag, origin, body) end
	return true
end

-- Hop 3 heard (a guildmate's hand-over): delivered here once.
function Relay.HandleGuild(dist, sender, text)
	if dist ~= "GUILD" or not Relay.On() then return false end
	local flag, origin, body = tostring(text):match("^RG~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	Deliver(origin, body, flag == "L")
	return true
end

-- The relay's answer to our ping.
function Relay.HandleAck(dist, sender, text)
	if dist ~= "WHISPER" or tostring(text) ~= "RY~" then return false end
	local key = ns.ShortName(sender):lower()
	if not verified[key] then ns.Log("relay: %s answers", tostring(sender)) end
	verified[key] = Now()
	pinged[key] = nil
	offline[key] = nil
	return true
end

-- The server's "No player named X is currently playing": a relay named is offline now.
function Relay.NotFound(text)
	local T = ns.Treasury
	local pattern = type(T) == "table" and type(T.NotFoundPattern) == "function" and T.NotFoundPattern()
	local who = type(pattern) == "string" and type(text) == "string" and text:match(pattern)
	if type(who) ~= "string" then return false end
	who = who:gsub("^'", ""):gsub("'$", "")
	if not Relay.IsRelay(who) then return false end
	LeaveOut(who, "offline")
	return true
end

ns.Comm.Handle("RL", function(...) Relay.HandleIn(...) end)
ns.Comm.Handle("RM", function(...) Relay.HandleRelayed(...) end)
ns.Comm.Handle("RG", function(...) Relay.HandleGuild(...) end)
ns.Comm.Handle("RY", function(...) Relay.HandleAck(...) end)
ns.Comm.RelayPieces({ RL = true, RM = true, RG = true })

ns.On("LOGIN", function()
	if not Relay.On() then return end
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) ns.SafeCall("relay not found", Relay.NotFound, text) end)
end)

-- Tests: a clean slate.
function Relay.Reset()
	wipe(offline); wipe(verified); wipe(pinged); wipe(reporters); wipe(seen)
	seenCount, lastRegister = 0, -math.huge
	for k in pairs(stats) do stats[k] = 0 end
end
