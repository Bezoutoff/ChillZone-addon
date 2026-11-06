local ADDON, ns = ...

-- Private presence's word to its own guild (1.4.0, the author's default: it hides the guild
-- leader's online flag while it is on). Quiet presence (Core.lua) stops this client's own presence
-- words, but the census of a guild is made by its members' clients from the game's guild roster:
-- a guild leader or officer online there still crossed into every other guild's census (the
-- report's leaderOnline, Roster.lua). So the built-in switch (ns.SetPrivatePresence, owner
-- ns.PLAYER_QUIET_OWNER) tells its own guild, and only it: PP~1 over GUILD at once, again a little
-- after each login while it is on and every SAY_EVERY; PP~0 when it ends. A guildmate's client
-- takes it only over GUILD and only from a player allowed to use private presence
-- (ns.QuietPresenceAllowed: the King, a signed High Councillor, the author), keeps it KEEP after it
-- last heard it (saved for the realm group, as a cover is), and the census it sends counts that
-- player offline (PrivatePresence.Offline, Roster.lua), as Cover.Offline does. Guildmates on an
-- older ChillZone still count him online. Nothing goes to the ChillZone channel: other guilds learn
-- nothing, not even that he went private. An authorized addon's quiet presence says nothing here.

local PP = {}
ns.PrivatePresence = PP

PP.SAY_EVERY = 300 -- the holder's client says it again this often (its minute's tick)
PP.KEEP = 900      -- a guildmate's client keeps it this long after it last heard it
PP.MAX = 40        -- holders kept at most (the King, the signed council, the author)
PP.LOGIN_SAY = { 3, 15 } -- seconds after login: the guild is known by then

local function Store()
	local r = ns.rdb
	if type(r) ~= "table" then return nil end
	if type(r.privateHeard) ~= "table" then r.privateHeard = {} end
	return r.privateHeard
end

local function Mine()
	return type(ns.QuietPresenceOwnedBy) == "function" and ns.QuietPresenceOwnedBy(ns.PLAYER_QUIET_OWNER) == true
end

-- Drops what lapsed, and the oldest past MAX.
function PP.Prune()
	local s = Store()
	if not s then return end
	local now, n = ns.Now(), 0
	for who, e in pairs(s) do
		if type(e) ~= "table" or now - (tonumber(e.t) or 0) > PP.KEEP then s[who] = nil else n = n + 1 end
	end
	while n > PP.MAX do
		local oldest, at = nil, math.huge
		for who, e in pairs(s) do
			if (tonumber(e.t) or 0) < at then oldest, at = who, tonumber(e.t) or 0 end
		end
		if not oldest then break end
		s[oldest], n = nil, n - 1
	end
end

local lastSaid, saidOn = -math.huge, false
-- The word to our guild: PP~1 while our switch is on (at most every SAY_EVERY unless forced), PP~0
-- once when it ended after we said it. True when it went.
function PP.Say(force)
	if ns.IsMember() ~= true or not (IsInGuild and IsInGuild()) then return false end
	local on = Mine()
	if not on and not saidOn then return false end
	local now = ns.Now()
	if on and saidOn and not force and now - lastSaid < PP.SAY_EVERY then return false end
	lastSaid, saidOn = now, on
	ns.Comm.Send("GUILD", on and "PP~1" or "PP~0", "private presence", true)
	return true
end

function PP.Handle(dist, sender, text)
	if dist ~= "GUILD" or type(sender) ~= "string" or type(text) ~= "string" then return end
	local v = text:match("^PP~([01])$")
	if not v then return end
	local who = ns.FullName(sender)
	if who == ns.FullName(ns.me) then return end
	local s = Store()
	if not s then return end
	if v == "0" then
		s[who] = nil
		return
	end
	if ns.QuietPresenceAllowed(who) ~= true then return end
	s[who] = { t = ns.Now() }
	PP.Prune()
end
ns.Comm.Handle("PP", function(...) PP.Handle(...) end)

-- Counted offline in the census this client sends (Roster.lua): a guildmate whose private presence
-- was heard within KEEP, still one who may use it; never our own name.
function PP.Offline(name)
	if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then return false end
	local s = ns.rdb and ns.rdb.privateHeard
	if type(s) ~= "table" or next(s) == nil then return false end
	local full = ns.FullName(name)
	if full == ns.FullName(ns.me) then return false end
	local e = s[full]
	if type(e) ~= "table" or ns.Now() - (tonumber(e.t) or 0) > PP.KEEP then return false end
	return ns.QuietPresenceAllowed(full) == true
end

-- Tests start from a clean state.
function PP.Reset() lastSaid, saidOn = -math.huge, false end

ns.On("QUIET_PRESENCE_CHANGED", function() PP.Say(true) end)
ns.On("LOGIN", function()
	PP.Prune()
	for _, seconds in ipairs(PP.LOGIN_SAY) do ns.After(seconds, "private presence", function() PP.Say(true) end) end
	ns.Every(60, "private presence", function()
		ns.PrivatePresenceLapse()
		PP.Say()
		PP.Prune()
	end)
end)
