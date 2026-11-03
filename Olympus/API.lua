local ADDON, ns = ...
local L = ns.L

-- The Olympus API for other addons (1.2.4, Daniel: an API inside the addon "for anyone to integrate
-- with what can be integrated, with what the permissions allow", each seeing only what that player
-- sees; his worry, someone using it to mine data). docs/API.md is its page for addon authors.
--
-- What it is, and what it never is:
--   - Read-only ordinary data. Its getters send no chat line, decree, whisper or other message and
--     change no Olympus data. Network actions are separately feature-detected: the request-bound
--     player-sighting search is a verified operator's explicit Start/Cancel, or a
--     bounded rotation while a visible session the operator explicitly started remains on, with
--     the observer consent, short life, audience and last-seen semantics below; the bounded
--     profile-presentation session is host-owned, self-only and fixed-style. A registered addon
--     may also contribute one page to the Olympus window; Olympus still owns its lifecycle.
--     1.2 (the Board's groups, "groups.manage"): the player's own listing acted on as the Board's
--     own buttons do (an applicant or a flag's player invited by the game's invite, an applicant
--     declined, a member's role set, the listing lowered), and Olympus's own card, composer and
--     flag dialog opened, where he posts and applies himself: never a listing posted, an
--     application sent or a word written for him. And "ui.board-groups": one companion panel in
--     place of the Board's Your group, an Olympus-owned frame the player can switch back from.
--   - Only what this player already sees on Olympus's own pages, at no more detail: the Wanted list
--     and its bounties (the Wanted tab's rows), the public rankings (the Slayers boards of the Wanted
--     tab and the signed top three, the donors' top three while the King shows the army the
--     Treasury's ranking (Donors below), the Church's public top three, and each game's ranking the
--     King made public: never a staff view), the player's own frame and title, his own Olympus
--     guild, rank and role, and the leader's presence as the King's lines on the Census and the
--     Realm, his crown and the Realm tab's layer list show it (LeaderPresence below); (1.4.0) and
--     whether a player the game shows him right now is in an Olympus guild (IsOlympusMember below:
--     a live unit token's guild, as the game gives it, and Olympus's own rule). Never the
--     census, another player's private data, the Wanted page's victims or stored sightings, a
--     movement history, a staff view or a secret (a key, sealed channel name, signature or private
--     list). The Board's groups (1.2, Groups.lua) as its sections show them: the listings (how many
--     are in a group by class and role, never their names; no time of anyone's), the players
--     looking, and the player's own listing's applications and his own group; on the King's screen
--     the words the Board hides stay out. The optional search returns only a fresh native
--     observation or bounded memory-only recent observation: the target's game-reported unit point
--     when available, its matching group-unit point when it is in the observer's party/raid,
--     otherwise the observer's encounter point. Each row is labelled with that distinction and
--     goes only to the verified request's owner.
--     Each row is built field by field, so what a module adds later never reaches an addon by itself.
--   - Asked, one addon at a time. OlympusAPI.Register("TheirAddon") gives that addon its handle and
--     a line of its own on the privacy page (Consent.lua): explicit, so nothing comes back before
--     its own Yes or the page's clearly labelled Authorize all. The page opens by itself for it once
--     (Consent.Ask). Nothing comes back before
--     the player's Yes, nor after his No; the answer is kept for the account (ns.db.apiAddons) and
--     asked again when what the API gives changes (API.CONSENT_VERSION). Outside an Olympus guild a
--     granted addon learns that the player is in none, and nothing else.
--   - Copies. Every table returned (and each callback's) is built fresh for that call: an addon that
--     changes it changes its own copy, never Olympus's state nor another addon's.
--   - Versioned and pushed: OlympusAPI.VERSION and OlympusAPI.Has(feature) say what this build gives;
--     handle:On(event, fn) tells of a change (WANTED_CHANGED, RANKINGS_CHANGED, PROFILE_CHANGED,
--     GROUPS_CHANGED, LOOKING_CHANGED, MY_GROUP_CHANGED,
--     LEADER_CHANGED, SIGHTING_CHANGED for a search that same handle owns,
--     PROFILE_EFFECT_SESSION_CHANGED for the sanitized host-owned profile session,
--     QUIET_PRESENCE_CHANGED for the quiet presence, and PERMISSION_CHANGED when the player answers), once
--     a burst settles (DISPATCH_DELAY, never in combat), and only when what that
--     call would return changed: nobody needs to poll.
--   - Bounded. RATE_MAX data calls a RATE_WINDOW per addon, MAX_ADDONS addons a session, MAX_CALLBACKS
--     callbacks per event. A callback runs protected: its error is logged with the addon's name
--     (never Olympus's error report) and never stops Olympus or the other callbacks; one that keeps
--     failing (CALLBACK_FAILS) is dropped.
--   - Reserved (Daniel, 2026-10-19: no third-party addon may keep a log of where the King has been).
--     The leader's presence, the sightings searches, the quiet presence and the profile presentation
--     answer only the addons the Olympus team authorized (API.AUTHORIZED: a digest of each one's
--     folded name, so the list names nobody). Any other addon gets "unauthorized" from those methods
--     (RESERVED_METHODS), cannot listen to their events (RESERVED_EVENTS), and its privacy line says
--     only what it may read (API_CONSENT_TEXT_BASIC). OlympusAPI.Has still says what this build has.
-- A handle is the addon's own: Register gives it once a session for a name, to the first caller
-- (a second Register for that name gets nil, "taken"), and only for an addon the game has installed
-- (its TOC's Title, which the privacy line shows). That is a courtesy boundary, not a lock: every
-- addon runs in the same Lua as Olympus and can read its saved variables directly. The API gives
-- honest addons a supported, consented path, so that Olympus itself never hands anything out
-- unasked.
-- Its own file, loaded after the boards it reads (the TOC): a file the TOC adds loads only once the
-- game restarts, so after the update to 1.2.4 OlympusAPI is nil until then (docs/API.md says to
-- check for it). No game event, no frame and no timer of its own while nobody listens.
-- The mods' OlympusBridge (Bridge.lua) is another door, for their companion: unchanged.

local API = {}
ns.API = API

API.VERSION = 1
-- Version 8 bounds hostile-area rotation to one live area per handle, no faster than once a minute,
-- and only the player's current map or a fresh exact result map already owned by that handle. A
-- visible user-started consumer session must still declare the chosen/configured names or list
-- sources it includes. Every older Yes must be asked again even though the compatible API version
-- stays 1.
-- Version 9 adds the leader's presence (GetLeaderPresence, LEADER_CHANGED) and the wider "outsiders"
-- area scope: what a Yes gives grew, so it is asked again.
-- Version 10 (1.4.0) adds the Board's groups: their reads (the listings, the players looking, the
-- player's own listing's applications and group) and the actions on his own listing (invite,
-- decline, roles, lower) with Olympus's own dialogs opened; and IsOlympusMember (whether a player a
-- live unit token names is in an Olympus guild). What a Yes gives grew again (one step for both,
-- the same release), and the line says so (both texts, Locales/APIText.lua): every addon is asked
-- again.
API.CONSENT_VERSION = 10
API.MAX_ADDONS = 16       -- addons registered in one session
API.SURFACE_LIMIT = 1     -- one client-owned page in the shared tab rail per session
API.RATE_MAX = 20         -- data calls one addon makes...
API.RATE_WINDOW = 10      -- ...in this many seconds
API.UNIT_RATE_MAX = 80    -- (1.4.0) IsOlympusMember calls one addon makes a RATE_WINDOW: a raid of 40 twice,
                          -- on a budget of its own, so a raid check neither starves nor is starved by the reads
API.MAX_CALLBACKS = 4     -- one addon's callbacks for one event
API.CALLBACK_FAILS = 3    -- a callback that failed this many times is dropped
API.DISPATCH_DELAY = 2    -- a change is told this long after it, a burst of them once
API.COMBAT_RETRY = 5      -- in combat, looked at again this long after
API.AREA_ROTATE_MIN = 60  -- minimum seconds between successful area starts by one handle
API.AREA_PROOF_MAX = 64   -- fresh exact result maps retained by one handle until those rows expire
API.MAX_ROWS = 50         -- rows of one Slayers board
API.MAX_WANTED = 200      -- Wanted rows (Wanted.MAX_TARGETS)
API.MAX_LEADER_LAYERS = 16 -- layers of the leader's zone (the Realm tab's list)
API.TITLE_MAX = 40        -- the addon's title on the privacy page
API.MAX_GROUPS = 200      -- listings of GetGroups (Groups.MAX others, and ours)
API.MAX_LOOKING = 200     -- rows of GetLooking (Board.MAX flags, each in the sections it names)
API.MAX_APPLICANTS = 30   -- GetMyGroup's applications (Groups.APPLICANTS_MAX)
API.MAX_MEMBERS = 39      -- GetMyGroup's members (a raid of 40, the player aside)
API.GROUP_FRESH = 5 * 60  -- a listing up for less than this is `fresh` (no time of it leaves)
API.MANAGE_MAX = 6        -- own-group actions one addon makes...
API.MANAGE_WINDOW = 10    -- ...in this many seconds (a rate of their own)
API.PANEL_LABEL_MAX = 48  -- a group panel's label, on the Board's switch
API.EVENTS = { "WANTED_CHANGED", "RANKINGS_CHANGED", "PROFILE_CHANGED", "LEADER_CHANGED", "SIGHTING_CHANGED",
	"PROFILE_EFFECT_SESSION_CHANGED", "QUIET_PRESENCE_CHANGED", "GROUPS_CHANGED", "LOOKING_CHANGED", "MY_GROUP_CHANGED",
	"PERMISSION_CHANGED" }
API.DATA_EVENTS = { "WANTED_CHANGED", "RANKINGS_CHANGED", "PROFILE_CHANGED", "LEADER_CHANGED", "PROFILE_EFFECT_SESSION_CHANGED",
	"QUIET_PRESENCE_CHANGED", "GROUPS_CHANGED", "LOOKING_CHANGED", "MY_GROUP_CHANGED" }
API.GROUP_KINDS = { dungeon = "D", raid = "R", pvp = "P", quest = "Q" }
API.AREA_SCOPES = { hostile = true, outsiders = true }
API.RANKINGS = { "slayers", "donors", "church", "games" }

-- The reserved features (the header's Reserved): their methods, with the "no" an addon that is not
-- authorized gets, as each method says no itself ("nil" for a read and a search's start, "false" for
-- a setter, the profile session's start and stop, a cancel or a map call), and their events.
-- A method a reserved feature adds later belongs here too (the tests look for it).
API.RESERVED_METHODS = {
	GetLeaderPresence = "nil", StartPlayerSearch = "nil", GetPlayerSearch = "nil", GetPlayerSearches = "nil",
	StartAreaSearch = "nil", GetAreaSearch = "nil", GetAreaSearches = "nil",
	CancelPlayerSearch = "false", CancelAreaSearch = "false", ShowAreaSearchOnMap = "false", ClearAreaSearchMap = "false",
	SetSightingPins = "false", ClearSightingPins = "false",
	-- The quiet presence and the profile presentation: authorized addons only, as the leader's presence.
	SetQuietPresence = "false", GetQuietPresence = "nil",
	StartProfileSession = "false", StopProfileSession = "false", SetProfileEffect = "false", GetProfileSession = "nil",
}
API.RESERVED_EVENTS = { LEADER_CHANGED = true, SIGHTING_CHANGED = true, QUIET_PRESENCE_CHANGED = true, PROFILE_EFFECT_SESSION_CHANGED = true }
-- The authorized addons, each as API.AuthorizedKey(its name) gives it.
API.AUTHORIZED = {
	["2def22f6a5e0801fa6e2de4a41ff7be28858d142b209b6c180ebb930ce2cd7dc94aebbc21f452ab7d36e8cc0b2ad61285561c4bd29089f30dfd48e78a77ea072"] = true,
}

local IS_EVENT = {}
for _, e in ipairs(API.EVENTS) do IS_EVENT[e] = true end

local clients = {} -- [folded addon name] = this session's client
local order = {}   -- the clients, in the order they registered
local pending = {} -- [event] = true: a change not looked at yet
local pendingSightings = {} -- [request id] = true: one request/result changed
local scheduled = false

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Secret(value)
	if type(issecretvalue) ~= "function" then return false end
	local ok, secret = pcall(issecretvalue, value)
	return not ok or secret == true
end

-- A module of the addon this build has (not a stand-in for a file the game has not loaded yet,
-- Core.lua's StandIn), with that function.
local function Has(key, fn)
	local m = ns[key]
	return type(m) == "table" and not m.missing and type(m[fn]) == "function"
end

-- That module's function, protected: its results, or nothing when it is missing or failed.
local function Call(key, fn, ...)
	if not Has(key, fn) then return nil end
	local ok, a, b = pcall(ns[key][fn], ...)
	if not ok then return nil end
	return a, b
end

-- A plain string for another addon: no colour, texture, atlas or link codes, no control
-- characters, max bytes at most (never half a letter); nil when nothing is left.
local function Plain(v, max)
	if Secret(v) or type(v) ~= "string" then return nil end
	v = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
		:gsub("|H.-|h(.-)|h", "%1"):gsub("|", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if v == "" then return nil end
	return ns.Cut(v, max or 96)
end

-- A finite number, whole when whole is asked; nil otherwise.
local function Num(v, whole)
	if Secret(v) then return nil end
	local ok, value = pcall(tonumber, v)
	if not ok or Secret(value) then return nil end
	v = value
	if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
	if whole then v = math.floor(v + 0.5) end
	return v
end

-- A fresh copy of plain data (strings, numbers, booleans and tables of them).
local function Copy(v, depth)
	if Secret(v) then return nil end
	if type(v) ~= "table" then
		if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then return v end
		return nil
	end
	depth = depth or 0
	if depth > 6 then return nil end
	local out = {}
	for k, x in pairs(v) do
		if type(k) == "string" or type(k) == "number" then out[k] = Copy(x, depth + 1) end
	end
	return out
end

-- The same text for the same data, whatever order pairs walks it in: what a callback was last told.
local function Signature(v)
	if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) < type(b) end
		return a < b
	end)
	local out = {}
	for i, k in ipairs(keys) do out[i] = tostring(k) .. "=" .. Signature(v[k]) end
	return "{" .. table.concat(out, ",") .. "}"
end

local function Member() return ns.IsMember and ns.IsMember() == true end

local function Busy() return InCombatLockdown and InCombatLockdown() and true or false end

-- An addon's digest on API.AUTHORIZED: SHA-512 (Ed25519.lua's, loaded before this file) of
-- "olympus-api-authorized:" and its folded name, in hex; nil without the hash, so nobody is
-- authorized then.
function API.AuthorizedKey(name)
	if type(name) ~= "string" or not Has("Ed25519", "SHA512") then return nil end
	local ok, digest = pcall(ns.Ed25519.SHA512, "olympus-api-authorized:" .. ns.Fold(name))
	if not ok or type(digest) ~= "string" then return nil end
	return (digest:gsub(".", function(ch) return string.format("%02x", ch:byte()) end))
end

local function Authorized(c) return c.authKey ~= nil and API.AUTHORIZED[c.authKey] == true end

---------------------------------------------------------------------------
-- What an addon may read: each built from the page's own functions, field by field
---------------------------------------------------------------------------

-- The Wanted tab's list: its entries in its order (Wanted.Targets, "listed": 1.2.4, a Horde player
-- with a bounty or a kill of ours, never one with 0 points and 0 kills), each with what its row
-- shows (the name, the bounty and the kills) and the cycle its page shows; the Horde player's GUID,
-- which is who he is on the list (Wanted.lua). Never the victims, the claims, the sightings, who
-- added or took off an entry, nor any time.
function API.Wanted()
	local out = {}
	for i, t in ipairs(Call("Wanted", "Targets", "listed") or {}) do
		if #out >= API.MAX_WANTED then break end
		if type(t) == "table" and t.active == true then
			out[#out + 1] = { place = i, name = Plain(t.name, 72), guid = Plain(t.guid, 64),
				bounty = Num(t.current, true) or 0, kills = Num(t.lifetimeKills, true) or 0, cycle = Num(t.cycle, true) or 1 }
		end
	end
	return out
end

-- A Slayers board as the Wanted tab lists it: place, name, points and claims.
local function SlayerRows(rows)
	local out = {}
	for i, r in ipairs(type(rows) == "table" and rows or {}) do
		if #out >= API.MAX_ROWS then break end
		if type(r) == "table" then
			out[#out + 1] = { place = Num(r.place, true) or i, name = Plain(r.name, 72),
				points = Num(r.points, true) or 0, claims = Num(r.claims, true) or 0 }
		end
	end
	return out
end

-- The Wanted tab's boards: this month's and all time's (what this client observed), and the
-- signed top three it holds, by the names its boards know for those GUIDs (the GUIDs stay here).
local function Slayers()
	if not Has("Wanted", "Rankings") then return nil end
	local rank = Call("Wanted", "Rankings")
	if type(rank) ~= "table" then return nil end
	local out = { month = SlayerRows(rank.month), all = SlayerRows(rank.all), signed = nil }
	local g = Call("Wanted", "GlobalSnapshot")
	if type(g) == "table" and type(g.rows) == "table" then
		local names = {}
		for _, r in ipairs(type(rank.all) == "table" and rank.all or {}) do
			if type(r) == "table" and type(r.guid) == "string" and type(r.name) == "string" then names[r.guid] = r.name end
		end
		out.signed = {}
		for i, r in ipairs(g.rows) do
			if type(r) == "table" and i <= 3 then
				out.signed[#out.signed + 1] = { place = i, name = Plain(names[r.guid], 72),
					points = Num(r.points, true) or 0, claims = Num(r.claims, true) or 0 }
			end
		end
	end
	return out
end

local function Names(list, max)
	local out = {}
	for _, n in ipairs(type(list) == "table" and list or {}) do
		if #out >= (max or 3) then break end
		local name = Plain(n, 72)
		if name then out[#out + 1] = name end
	end
	return out
end

-- The donors' top three, only where every member's own screen shows them (review of 1.2.4: they
-- came back whatever the King's switch, names no page showed). The names the Treasurer's word gives
-- every client (HonorsNet.Donors), names alone, as the word:
--   - nil unless the King shows the army the Treasury's ranking (Treasury.PublicShows("ranking"):
--     his own switch as every client keeps it, off by default; never the keepers' or the King's
--     own view, nor the author's preview, as the games are never a staff view). Off, no page lists
--     the donors, and a portrait's frame tells of one donor at a time, to whoever looks at him.
--   - all: the all-time top three, which head that ranking on the Treasury tab.
--   - month: the month's three only in a build that wears their koi frame (Honors.FrameShipped);
--     1.2.4 does (the borders lane released the koi); a build without it lists them nowhere: nil.
local function Donors()
	if not Has("HonorsNet", "Donors") then return nil end
	if Call("Treasury", "PublicShows", "ranking") ~= true then return nil end
	local d = Call("HonorsNet", "Donors")
	d = type(d) == "table" and d or {}
	local out = { all = Names(d.all) }
	if Call("Honors", "FrameShipped", { family = "donor-month" }) == true then out.month = Names(d.month) end
	return out
end

-- The Church's public top three (HonorsNet.ChurchTop: nil while its public ranking is closed).
local function Church()
	if not Has("HonorsNet", "ChurchTop") then return nil end
	local t = Call("HonorsNet", "ChurchTop")
	if type(t) ~= "table" then return nil end
	return { missionaries = Names(t.missionaries), apostles = Names(t.apostles) }
end

-- Each game's ranking the King made public (ArenaHome.RankingsPublic: the one everybody's Games tab
-- shows), as that tab shows it; a game kept to the staff is not there, whoever this player is.
local function Games()
	if not Has("ArenaHome", "RankingsPublic") then return nil end
	local out = {}
	if Call("ArenaHome", "RankingsPublic", "arena") == true then
		local rows = {}
		local view = Call("ArenaLedger", "RankingView", "all", "A", 1, { mode = "L" })
		for i, x in ipairs(type(view) == "table" and type(view.rows) == "table" and view.rows or {}) do
			if type(x) == "table" then
				rows[#rows + 1] = { place = Num(x.rank, true) or i, name = Plain(x.name, 72), rating = Num(x.rating, true),
					wins = Num(x.wins, true) or 0, losses = Num(x.losses, true) or 0 }
			end
		end
		out.arena = rows
	end
	if Call("ArenaHome", "RankingsPublic", "bones") == true then
		local rows = {}
		for i, x in ipairs(Call("FarkleTable", "Best", "L") or {}) do
			if i > 10 then break end
			if type(x) == "table" then
				rows[#rows + 1] = { place = Num(x.place, true) or i, name = Plain(x.name, 72),
					games = Num(x.games, true) or 0, won = Num(x.won, true) or 0 }
			end
		end
		out.bones = rows
	end
	-- Lottery's saved winners are private history, even with an older game's publish word.
	return out
end

local RANKING = { slayers = Slayers, donors = Donors, church = Church, games = Games }

-- Every public ranking (kind nil), or one: "slayers", "donors", "church" or "games". A kind this
-- build lacks (no arena: no games, no donors) is nil.
function API.Rankings(kind)
	if kind ~= nil then
		local fn = RANKING[kind]
		return fn and fn() or nil
	end
	local out = {}
	for _, k in ipairs(API.RANKINGS) do out[k] = RANKING[k]() end
	return out
end

-- The player's own role in Olympus, the highest he holds: "king", "councillor" (the signed High
-- Council), "steward", "treasurer" (his characters), "guildmaster", "officer" (his guild's officer
-- ranks) or "member".
local function Role(rankIndex)
	if Call("King", "IsKing") == true then return "king" end
	local me = ns.me
	if type(me) == "string" and me ~= "" then
		if type(ns.IsHighCouncillor) == "function" and select(2, pcall(ns.IsHighCouncillor, me)) == true then return "councillor" end
		if type(ns.IsSteward) == "function" and select(2, pcall(ns.IsSteward, me)) == true then return "steward" end
		if type(ns.IsTreasurerCharacter) == "function" and select(2, pcall(ns.IsTreasurerCharacter, me)) == true then return "treasurer" end
	end
	if rankIndex == 0 then return "guildmaster" end
	if Call("Roster", "IsOfficer") == true then return "officer" end
	return "member"
end

-- The player himself: whether he is in an Olympus guild, and there his guild, its rank's name and
-- index (0 its master), his role, and the frame and title his profile shows (HonorsNet.Verified:
-- the frame an honour key, "rank" his rank's or "none"; the title its words, or nil).
function API.Profile()
	if not Member() then return { member = false } end
	local guild, rankName, rankIndex
	if GetGuildInfo then guild, rankName, rankIndex = GetGuildInfo("player") end
	rankIndex = Num(rankIndex, true)
	local out = { member = true, name = Plain(ns.me, 72), guild = Plain(guild, 64), rank = Plain(rankName, 64), rankIndex = rankIndex,
		role = Role(rankIndex), frame = "rank", title = nil }
	local v = type(ns.me) == "string" and Call("HonorsNet", "Verified", ns.me) or nil
	if type(v) == "table" then
		out.frame = Plain(v.frame, 48) or "rank"
		if type(v.title) == "string" then out.title = Plain(Call("HonorsNet", "TitleText", v.title), 64) end
	end
	return out
end

-- (1.4.0) The game's own unit tokens IsOlympusMember takes, lower-cased: player, target, focus,
-- mouseover, party1-4, raid1-40 and nameplateN, each alone or followed by "target" once
-- (targettarget, party1target). Never a name: a player's name holds no digit, and the game's
-- UnitExists would also take a group member's name, so a name would let an addon ask about someone
-- the game is not showing this player. The game numbers nameplate tokens as it hands them out: the
-- bound is wide, and a token never names more than the plate it is.
API.NAMEPLATE_MAX = 200
local function BaseToken(u)
	if u == "player" or u == "target" or u == "focus" or u == "mouseover" then return true end
	local kind, digits = u:match("^(%a+)([1-9]%d*)$")
	local n = tonumber(digits)
	if not n then return false end
	return (kind == "party" and n <= 4) or (kind == "raid" and n <= 40) or (kind == "nameplate" and n <= API.NAMEPLATE_MAX)
end
function API.UnitToken(unit)
	if Secret(unit) or type(unit) ~= "string" or #unit > 24 then return nil end
	local u = unit:lower()
	if BaseToken(u) then return u end
	local inner = u:match("^(.+)target$")
	if inner and BaseToken(inner) then return u end
	return nil
end

-- The game's answer to a unit question, protected: nil when the client has no such function, the
-- call failed or the value is secret.
local function Ask(fn, unit)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, unit)
	if not ok or Secret(v) then return nil end
	return v
end

-- (1.4.0, promised to an addon author: a safe eligibility check) Whether the player a live unit
-- token names is in an Olympus guild, as this client counts Olympus guilds (ns.IsFederation: the
-- name rule, the King's guild, the signed approved and removed lists): true or false, or nil when
-- this client cannot tell. What it reads is the game's for that unit now (UnitExists, UnitIsPlayer,
-- UnitFactionGroup, GetGuildInfo) and Olympus's guild rule: no census, roster, sighting, sanction
-- (a net-off is never told) or stored list of people, and nothing is kept. nil:
--   - the game shows nothing for that token now, or a value it keeps secret;
--   - another faction's player: Olympus's lists here are this faction's (the Horde has its own);
--   - no guild from the game: a player in none and one whose guild the game has not given yet look
--     the same (GetGuildInfo gives nil for both), so neither is called "not a member".
-- false: a unit that is no player (a creature, a pet), or a player of a guild that is not Olympus's.
function API.IsOlympusMember(unit)
	unit = API.UnitToken(unit)
	if not unit or not Ask(UnitExists, unit) then return nil end
	local player = Ask(UnitIsPlayer, unit)
	if player == nil then return nil end
	if not player then return false end
	local mine, theirs = Ask(UnitFactionGroup, "player"), Ask(UnitFactionGroup, unit)
	if type(mine) ~= "string" or mine == "" or theirs ~= mine then return nil end
	local guild = Ask(GetGuildInfo, unit)
	if type(guild) ~= "string" or guild == "" or type(ns.IsFederation) ~= "function" then return nil end
	local ok, yes = pcall(ns.IsFederation, guild)
	if not ok then return nil end
	return yes == true
end

-- The current host-owned profile-presentation session, without its internal issuer, grant id,
-- transport epoch or caption. The remaining lifetime is deliberately approximate and bounded by
-- the host module; callers should use PROFILE_EFFECT_SESSION_CHANGED instead of polling it.
function API.ProfileSession()
	if not Has("ProfileEffects", "Session") then return nil end
	local state = Call("ProfileEffects", "Session")
	if type(state) ~= "table" then return nil end
	local style, expiresIn = Plain(state.style, 32), Num(state.expiresIn, false)
	if not style or not expiresIn or expiresIn < 0 or expiresIn > 3600 then return nil end
	return { style = style, expiresIn = expiresIn }
end

-- The leader's presence, as this player's own pages show it, field by field (review: nothing the
-- lines do not say, nothing guessed):
--   - name, online: the King's lines on the Census and the Realm (Hop.KingLines: Hop.King, the name
--     those lines give him). Not online: { online = false } alone. The King himself: isYou.
--   - Barred from locations (WatchChat.Barred, as King.Location and Hop.KingLines): no field of
--     where he is.
--   - otherRealm (and then realm): Hop.KingOtherRealm, which those lines say.
--   - mapID, mapName: the zone those lines name (his announced layer's), else his crown's.
--   - position: his crown on the map (King.Location: only while he shares it), in thousandths.
--   - onYourLayer: the line "on the King's layer" (Hop.OnKingLayer, strict as the line).
--   - layers, layer: only while this player is in that zone, the Realm tab's list of its layers
--     (Layers.ForMap, Layers.Name, its "~N with Olympus" count, a sample), and the name of his.
-- Never a population (the game gives none), the census, or a member's name beyond the layer
-- names the Realm tab already shows.
local function LeaderZone(mapID)
	local name = Plain(Call("Hop", "ZoneName", mapID), 64)
	return name ~= "?" and name or nil
end

function API.LeaderPresence()
	if not Has("Hop", "King") then return nil end
	local k = Call("Hop", "King")
	if type(k) ~= "table" then return { online = false } end
	local out = { name = Plain(k.name, 72), online = true }
	if Call("King", "IsKing") == true then out.isYou = true return out end
	if Call("WatchChat", "Barred", "locations") then return out end
	local away = Call("Hop", "KingOtherRealm", k) == true
	out.otherRealm = away
	if away then out.realm = Plain(k.realm, 64) end
	local zoneUID, kingMap = Num(k.zoneUID, true), Num(k.mapID, true)
	local at = Call("King", "Location")
	at = type(at) == "table" and at or nil
	local mapID = (not away and zoneUID and kingMap) or (at and Num(at.mapID, true)) or nil
	if mapID and mapID > 0 then out.mapID, out.mapName = mapID, LeaderZone(mapID) end
	if at then
		local am, ax, ay, seenAt = Num(at.mapID, true), Num(at.x), Num(at.y), Num(at.t, true)
		if am and am > 0 and ax and ay and ax >= 0 and ax <= 1 and ay >= 0 and ay <= 1 then
			out.position = { mapID = am, x = math.floor(ax * 1000 + 0.5), y = math.floor(ay * 1000 + 0.5), seenAt = seenAt }
		end
	end
	out.onYourLayer = not away and Call("Hop", "OnKingLayer", true) == true or false
	local here = Num(Call("Layers", "CurrentMap"), true)
	if not away and here and mapID == here then
		local mine = Call("Layers", "Mine")
		local his = (zoneUID and kingMap == here) and zoneUID
			or (out.onYourLayer and type(mine) == "table" and Num(mine.zoneUID, true)) or nil
		out.layers = {}
		for _, layer in ipairs(Call("Layers", "ForMap", here) or {}) do
			if #out.layers >= API.MAX_LEADER_LAYERS then break end
			if type(layer) == "table" then
				local count, name = Num(layer.count, true), Plain(Call("Layers", "Name", layer), 72)
				if count and count > 0 and name then
					local leader = his ~= nil and Num(layer.zoneUID, true) == his
					out.layers[#out.layers + 1] = { name = name, olympus = count, yours = layer.mine == true, leader = leader }
					if leader then out.layer = name end
				end
			end
		end
	end
	return out
end

-- 1.2.5.1, the quiet presence (Core.lua: ns.QuietPresenceState): { on, since }, since (ns.Now) only
-- while it is on. Never who turned it on.
function API.QuietPresence()
	if type(ns.QuietPresenceState) ~= "function" then return nil end
	local ok, state = pcall(ns.QuietPresenceState)
	if not ok or type(state) ~= "table" then return { on = false } end
	local on = state.on == true
	return { on = on, since = on and Num(state.since, true) or nil }
end

-- One short, request-bound search owned by this client. PlayerSightings keeps the transport,
-- authority, consent, expiry and observation rules; the API only copies the already-normalized
-- public result. "exact-unit" and "exact-group" are native map/world unit points; "nearby" is the
-- observer's encounter point. Missing kinds from the pre-release transport remain nearby.
function API.PlayerSearch(id)
	if not Has("PlayerSightings", "Session") then return nil end
	local state = Call("PlayerSightings", "Session", id)
	if type(state) ~= "table" or state.mode == "area" then return nil end
	local rawStatus = state.status or state.phase
	local status = (rawStatus == "sending" or rawStatus == "waiting") and "searching"
		or ({ searching = true, cancelled = true, expired = true, complete = true })[rawStatus] and rawStatus
		or "searching"
	local out = {
		id = Plain(type(state.id) == "number" and tostring(state.id) or state.id, 64), mode = "player",
		target = Plain(state.target, 72), status = status,
		createdAt = Num(state.createdAt, true) or 0, expiresAt = Num(state.expiresAt, true) or 0,
		sightings = {},
	}
	local observers = {}
	for _, row in ipairs(type(state.sightings) == "table" and state.sightings
		or type(state.results) == "table" and state.results or {}) do
		if #out.sightings >= 16 then break end
		if type(row) == "table" then
			local observer = Plain(row.observer or row.reporter, 72)
			local mapID, x, y = Num(row.mapID, true), Num(row.x, true), Num(row.y, true)
			local at = Num(row.seenAt or row.at, true)
			local receivedAt, expiresAt = Num(row.receivedAt, true), Num(row.expiresAt, true)
			local rawKind, kind = row.kind, nil
			if rawKind == nil or rawKind == "seen-nearby" or rawKind == "nearby" then kind = "nearby"
			elseif rawKind == "exact-group" or rawKind == "exact-unit" then kind = rawKind end
			local accuracy = Num(row.accuracyYards, true)
			local validAccuracy = accuracy == nil or accuracy >= 0 and accuracy <= 100000
				and (kind ~= "exact-group" and kind ~= "exact-unit" or accuracy == 0)
			if observer and kind and validAccuracy and mapID and mapID > 0 and x and x >= 0 and x <= 1000
				and y and y >= 0 and y <= 1000 and at then
				local sighting = {
					target = Plain(row.target or state.target, 72), observer = observer,
					observerGuild = Plain(row.observerGuild or row.guild, 64), seenAt = at,
					mapID = mapID, x = x, y = y, layer = Num(row.layer, true) or 0, kind = kind,
				}
				if receivedAt and receivedAt >= at then sighting.receivedAt = receivedAt end
				if expiresAt and expiresAt >= at then sighting.expiresAt = expiresAt end
				if accuracy ~= nil then sighting.accuracyYards = accuracy end
				out.sightings[#out.sightings + 1] = sighting
				observers[ns.Fold(observer)] = true
			end
		end
	end
	local count = 0
	for _ in pairs(observers) do count = count + 1 end
	out.observers, out.confirmed = count, count >= 2
	return out.id and out.target and out or nil
end

-- A hostile-area session is deliberately a smaller public shape than an exact-name search: rows
-- identify the directly observed hostile player and the labelled last-seen point, never the member
-- whose client observed it. The internal transport still verifies that member before accepting it.
function API.AreaSearch(id)
	if not Has("PlayerSightings", "AreaSession") then return nil end
	local state = Call("PlayerSightings", "AreaSession", id)
	if type(state) ~= "table" or state.mode ~= "area" then return nil end
	local rawStatus = state.status or state.phase
	local status = (rawStatus == "sending" or rawStatus == "waiting") and "searching"
		or ({ searching = true, cancelled = true, expired = true, complete = true })[rawStatus] and rawStatus
		or "searching"
	local out = {
		id = Plain(type(state.id) == "number" and tostring(state.id) or state.id, 64), mode = "area",
		scope = state.scope == "outsiders" and "outsiders" or "hostile", mapID = Num(state.mapID, true), status = status,
		createdAt = Num(state.createdAt, true) or 0, expiresAt = Num(state.expiresAt, true) or 0,
		sightings = {},
	}
	local targets = {}
	for _, row in ipairs(type(state.sightings) == "table" and state.sightings
		or type(state.results) == "table" and state.results or {}) do
		if #out.sightings >= 48 then break end
		if type(row) == "table" then
			local target = Plain(row.target, 72)
			local mapID, x, y = Num(row.mapID, true), Num(row.x, true), Num(row.y, true)
			local at = Num(row.seenAt or row.at, true)
			local receivedAt, expiresAt = Num(row.receivedAt, true), Num(row.expiresAt, true)
			local rawKind, kind = row.kind, nil
			if rawKind == nil or rawKind == "seen-nearby" or rawKind == "nearby" then kind = "nearby"
			elseif rawKind == "exact-group" or rawKind == "exact-unit" then kind = rawKind end
			local accuracy = Num(row.accuracyYards, true)
			local validAccuracy = accuracy == nil or accuracy >= 0 and accuracy <= 100000
				and (kind ~= "exact-group" and kind ~= "exact-unit" or accuracy == 0)
			local key = target and ns.Fold(target)
			-- A not-hostile row only in the wider scope that asked for it.
			local hostile = row.hostile ~= false
			if key and not targets[key] and kind and validAccuracy and mapID == out.mapID
				and (hostile or out.scope == "outsiders")
				and x and x >= 0 and x <= 1000 and y and y >= 0 and y <= 1000 and at
				and expiresAt and expiresAt >= at then
				local sighting = { target = target, seenAt = at, expiresAt = expiresAt,
					mapID = mapID, x = x, y = y, layer = Num(row.layer, true) or 0, kind = kind, hostile = hostile }
				if receivedAt and receivedAt >= at then sighting.receivedAt = receivedAt end
				if accuracy ~= nil then sighting.accuracyYards = accuracy end
				-- This client's own observation (no other member's identity in it).
				if row.own == true then sighting.own = true end
				out.sightings[#out.sightings + 1], targets[key] = sighting, true
			end
		end
	end
	return out.id and out.mapID and out or nil
end

local function AnySearch(id)
	return API.PlayerSearch(id) or API.AreaSearch(id)
end

-- Ownership is tied to the exact session, not merely its small transport id. PlayerSightings may
-- reuse an id after a request is gone; a stale handle must never inherit another addon's later
-- request with that id. The target and creation time are both public, immutable session fields.
local function SearchFingerprint(state)
	if type(state) ~= "table" or type(state.createdAt) ~= "number" then return nil end
	if state.mode == "area" and type(state.mapID) == "number" then
		return "area\0" .. tostring(state.mapID) .. "\0" .. tostring(state.createdAt)
	end
	if type(state.target) ~= "string" then return nil end
	return "player\0" .. state.target .. "\0" .. tostring(state.createdAt)
end

local ClearAreaMap, DrawAreaMap
local HideSightingPins -- (the sighting pins, defined beside the methods)

-- A consumer may rotate an exact-name request before it rotates its hostile-area coverage. Keep
-- only the already-sanitized exact target/map binding until that result's own expiry; cancellation
-- of the transport request does not turn the point into a live tracker. The cache belongs to one
-- API handle, is bounded, and is discarded on permission loss or UI reload.
local function PruneAreaProofs(c, now)
	c.areaProofs = type(c.areaProofs) == "table" and c.areaProofs or {}
	local count = 0
	for key, proof in pairs(c.areaProofs) do
		if type(proof) ~= "table" or type(proof.expiresAt) ~= "number" or proof.expiresAt <= now then
			c.areaProofs[key] = nil
		else
			count = count + 1
		end
	end
	while count > API.AREA_PROOF_MAX do
		local oldestKey, oldestAt
		for key, proof in pairs(c.areaProofs) do
			if oldestAt == nil or proof.expiresAt < oldestAt then oldestKey, oldestAt = key, proof.expiresAt end
		end
		if not oldestKey then break end
		c.areaProofs[oldestKey] = nil
		count = count - 1
	end
	return c.areaProofs
end

local function EachExactAreaProof(state, now, take)
	now = type(now) == "number" and now or ns.Now and ns.Now() or 0
	if type(state) ~= "table" or state.mode ~= "player" then return end
	local target = type(state.target) == "string" and ns.Fold(state.target) or nil
	if not target then return end
	for _, row in ipairs(type(state.sightings) == "table" and state.sightings or {}) do
		local rowTarget = type(row.target) == "string" and ns.Fold(row.target) or nil
		local exact = row.kind == "exact-unit" or row.kind == "exact-group"
		local mapID, expiresAt = row.mapID, row.expiresAt
		if exact and rowTarget == target and type(mapID) == "number" and mapID > 0
			and mapID == math.floor(mapID) and type(expiresAt) == "number" and expiresAt > now then
			local key = table.concat({ target, tostring(mapID), row.kind }, "\031")
			take(key, { target = target, mapID = mapID, kind = row.kind, expiresAt = expiresAt })
		end
	end
end

local function RetainAreaProofs(c, state, now)
	now = type(now) == "number" and now or ns.Now and ns.Now() or 0
	PruneAreaProofs(c, now)
	EachExactAreaProof(state, now, function(key, proof)
		local old = c.areaProofs[key]
		if not old or proof.expiresAt > old.expiresAt then c.areaProofs[key] = proof end
	end)
	return PruneAreaProofs(c, now)
end

local function ForgetSearch(c, id)
	if c.areaMapID == id and ClearAreaMap then ClearAreaMap(c) end
	c.searches[id] = nil
	c.sightingTold[id] = nil
end

local function OwnedSearch(c, id, mode)
	if Secret(id) then return nil end
	local fingerprint = type(id) == "string" and c.searches[id] or nil
	if type(fingerprint) ~= "string" then return nil end
	local state = AnySearch(id)
	if not state or SearchFingerprint(state) ~= fingerprint then
		ForgetSearch(c, id)
		return nil
	end
	if mode and state.mode ~= mode then return nil end
	return state
end

-- A handle can choose not to subscribe and never call GetPlayerSearches. Prune its small ownership
-- index whenever it starts another request so completed/expired transport sessions cannot build up
-- for the rest of the UI session. PlayerSightings itself keeps at most eight current sessions.
local function PruneOwnedSearches(c, mode)
	local ids, out = {}, {}
	for id in pairs(c.searches) do ids[#ids + 1] = id end
	for _, id in ipairs(ids) do
		local state = OwnedSearch(c, id)
		if state and (not mode or state.mode == mode) then out[#out + 1] = state end
	end
	return out
end

-- Area coverage may follow only evidence the same handle already owns. This is deliberately
-- narrower than accepting any map id from a consumer: the player's current map is explicit at the
-- time of the click, and another map must come from an unexpired native point in one of this
-- handle's exact-name searches. Nearby encounter points do not authorize a different area.
local function CurrentMapID()
	if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
	local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = ok and Num(mapID, true) or nil
	return mapID and mapID > 0 and mapID or nil
end

local function AreaMapAllowed(c, mapID, now)
	if CurrentMapID() == mapID then return true end
	for _, search in ipairs(PruneOwnedSearches(c, "player")) do
		if search.status ~= "cancelled" and search.status ~= "expired" then
			local found = false
			EachExactAreaProof(search, now, function(_, proof)
				if proof.mapID == mapID then found = true end
			end)
			if found then return true end
		end
	end
	for _, proof in pairs(PruneAreaProofs(c, now)) do
		if proof.mapID == mapID then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- The Board's groups (1.2, Groups.lua): what its sections show this player, field by field
---------------------------------------------------------------------------

local KIND_NAME = { D = "dungeon", R = "raid", P = "pvp", Q = "quest" }
local ROLE_NAME = { T = "tank", H = "healer", D = "damage" }
local ROLE_CODE = { tank = "T", healer = "H", damage = "D" }

local function HasGroups()
	return Has("Groups", "List") and Has("Groups", "Looking") and Has("Groups", "OwnEntry") and Has("Groups", "Applicants")
		and Has("Groups", "GroupMembers") and Has("Groups", "WithLog")
end

local function ClassCode(v)
	if Secret(v) or type(v) ~= "string" then return nil end
	return v:match("^%u%u$")
end

-- What a listing still needs, as its row says it: how many of each role (one that takes any number
-- counts as 1, at least one), `any` when one of them takes any number, `anyNumber` which.
local function GroupNeed(need)
	need = type(need) == "string" and need:match("^[0-9+][0-9+][0-9+]$") or "000"
	local out = { any = false, anyNumber = {} }
	for i, code in ipairs({ "T", "H", "D" }) do
		local role, c = ROLE_NAME[code], need:sub(i, i)
		if c == "+" then
			out[role], out.anyNumber[role], out.any = 1, true, true
		else
			out[role], out.anyNumber[role] = tonumber(c) or 0, false
		end
	end
	return out
end

-- A listing as its row, tooltip and card show it (Groups.Card, ListingTip): where (a place's key
-- this version knows, the name the row shows, a quest's ID, its title and zone only as the Board
-- shows them, the King's screen's rule), its leader as the server stamped him, his guild, class
-- and level, the minimum level, the group's size, what it needs, how many others are in it by
-- class and role, the note while the Board shows notes; whether it is ours, our application to
-- it, and `fresh` instead of any time. The id is opaque (OpenGroup takes it).
local function GroupRow(e, now)
	if type(e) ~= "table" then return nil end
	local kind = KIND_NAME[e.kind]
	local id = type(e.id) == "string" and type(e.sender) == "string" and Plain(e.id .. ":" .. e.sender, 96) or nil
	if not kind or not id then return nil end
	local shown = Plain(Call("Groups", "Target", e.kind, e.target, e.title), 64)
	local row = { id = id, kind = kind, placeName = shown, leader = Plain(e.sender, 72), guild = Plain(e.guild, 64),
		class = ClassCode(e.class), level = Num(e.level, true), minLevel = Num(e.min, true), size = Num(e.size, true),
		need = GroupNeed(e.need), members = {}, own = e.mine == true }
	if e.kind == "Q" then
		local quest = Num(e.target, true)
		row.questID = quest and quest > 0 and quest or nil
		if shown and shown ~= Plain(L.GROUPS_QUEST_UNNAMED, 64) then row.questTitle = shown end
		row.zone = Plain(Call("Groups", "ShownZone", e), 64)
	elseif Call("Groups", "KnownPlace", e.kind, e.target) == true then
		row.place = Plain(e.target, 8)
	end
	for _, c in ipairs(type(e.counts) == "table" and e.counts or {}) do
		if #row.members >= API.MAX_MEMBERS then break end
		local n = type(c) == "table" and Num(c.count, true) or nil
		if n and n > 0 then row.members[#row.members + 1] = { class = ClassCode(c.class), role = ROLE_NAME[c.role], count = n } end
	end
	if type(e.note) == "string" and e.note ~= "" and not ns.KingsScreen() then row.note = Plain(e.note, 64) end
	local raised = Num(e.raisedAt)
	row.fresh = raised ~= nil and now - raised < API.GROUP_FRESH
	if not row.own then
		local a = Call("Groups", "Applied", e.sender)
		if type(a) == "table" and a.id == e.id then row.applied = a.state == "invited" and "invited" or "waiting" end
	end
	return row
end

-- The listings of a kind's section (every section's, in the strip's order, without one), in the
-- Board's order: ours first in its section, then as Groups.List sorts them (a quest of our log
-- first). The quest log read once for them all.
function API.Groups(kind)
	if not HasGroups() then return nil end
	local now = ns.Now and ns.Now() or 0
	return Call("Groups", "WithLog", function()
		local out, mine = {}, ns.Groups.OwnEntry()
		for _, k in ipairs(kind and { kind } or { "D", "R", "P", "Q" }) do
			if #out < API.MAX_GROUPS and type(mine) == "table" and mine.kind == k then out[#out + 1] = GroupRow(mine, now) end
			for _, e in ipairs(ns.Groups.List(k) or {}) do
				if #out >= API.MAX_GROUPS then break end
				out[#out + 1] = GroupRow(e, now)
			end
		end
		return out
	end) or {}
end

-- A section's Players looking (Groups.Looking: the flags that name its kind, the ones fitting our
-- listing first): who, their guild, class and level, the roles their flag says, where it names in
-- that kind ("any", or the places' keys), and whether it fits our listing. Never its note or zone.
local function LookingRow(e, k)
	if type(e) ~= "table" then return nil end
	local name = Plain(e.sender, 72)
	if not name then return nil end
	local roles = Call("Board", "CleanRoles", e.roles) or ""
	local pick, places = Call("Groups", "FlagPickOf", e, k), "any"
	if type(pick) == "table" and not pick.any then
		places = {}
		for _, key in ipairs(type(pick.keys) == "table" and pick.keys or {}) do
			local place = Plain(key, 8)
			if place and #places < 8 then places[#places + 1] = place end
		end
	end
	return { kind = KIND_NAME[k], name = name, guild = Plain(e.guild, 64), class = ClassCode(e.class), level = Num(e.level, true),
		roles = { tank = roles:find("T", 1, true) ~= nil, healer = roles:find("H", 1, true) ~= nil, damage = roles:find("D", 1, true) ~= nil },
		places = places, fits = Call("Groups", "Fits", e) == true, own = false }
end

-- The player's own flag in that kind, as the Board's flags page shows it (own = true, never fits his
-- own listing): his name, guild, class and level from the game. (1.2, Daniel's test of a companion:
-- its list of players looking had every flag but his own.)
local function OwnLookingRow(k)
	local mine = Call("Board", "Mine")
	if type(mine) ~= "table" then return nil end
	local classFile = UnitClass and select(2, UnitClass("player")) or nil
	local e = { sender = ns.me, flag = mine.flag, roles = mine.roles, picks = mine.picks,
		guild = GetGuildInfo and (GetGuildInfo("player")) or nil,
		class = Call("Roster", "ClassCode", classFile), level = UnitLevel and UnitLevel("player") or nil }
	if not Call("Groups", "FlagPickOf", e, k) then return nil end
	local row = LookingRow(e, k)
	if row then row.own, row.fits = true, false end
	return row
end

-- A kind's Players looking (each section's, dungeons, raids and PvP in turn, without one: a
-- player whose flag names two kinds is in both, as on the Board). No flag looks for a quest.
function API.Looking(kind)
	if not HasGroups() then return nil end
	local out = {}
	for _, k in ipairs(kind and { kind } or { "D", "R", "P" }) do
		local own = OwnLookingRow(k)
		if own and #out < API.MAX_LOOKING then out[#out + 1] = own end
		for _, e in ipairs(Call("Groups", "Looking", k) or {}) do
			if #out >= API.MAX_LOOKING then break end
			out[#out + 1] = LookingRow(e, k)
		end
	end
	return out
end

-- The player's own group as Your group shows it: his listing (GetGroups' row), the applications
-- to it while it is up (who, their guild, role, level, class, note as the Board shows it, waiting
-- or invited) and the others in his party or raid (the game's own names, levels and classes, with
-- the roles as he set them or the invites said).
function API.MyGroup()
	if not HasGroups() then return nil end
	local now = ns.Now and ns.Now() or 0
	local out = { applicants = {}, members = {} }
	local mine = Call("Groups", "OwnEntry")
	if type(mine) == "table" then
		out.listing = Call("Groups", "WithLog", GroupRow, mine, now)
		for _, a in ipairs(Call("Groups", "Applicants") or {}) do
			if #out.applicants >= API.MAX_APPLICANTS then break end
			local name = type(a) == "table" and Plain(a.name, 72) or nil
			if name and ROLE_NAME[a.role] then
				out.applicants[#out.applicants + 1] = { name = name, guild = Plain(a.guild, 64), role = ROLE_NAME[a.role], level = Num(a.level, true),
					class = ClassCode(a.class), state = a.state == "invited" and "invited" or "waiting",
					note = type(a.note) == "string" and a.note ~= "" and not ns.KingsScreen() and Plain(a.note, 64) or nil }
			end
		end
	end
	for _, m in ipairs(Call("Groups", "GroupMembers") or {}) do
		if #out.members >= API.MAX_MEMBERS then break end
		local name = type(m) == "table" and Plain(m.name, 72) or nil
		if name then out.members[#out.members + 1] = { name = name, class = ClassCode(m.class), level = Num(m.level, true), role = ROLE_NAME[m.role] } end
	end
	return out
end

-- What each data event's callback is given: what its call returns.
local BUILD = {
	WANTED_CHANGED = function() return Member() and API.Wanted() or nil end,
	RANKINGS_CHANGED = function() return Member() and API.Rankings() or nil end,
	PROFILE_CHANGED = function() return API.Profile() end,
	LEADER_CHANGED = function() return Member() and API.LeaderPresence() or nil end,
	PROFILE_EFFECT_SESSION_CHANGED = function() return Member() and API.ProfileSession() or nil end,
	QUIET_PRESENCE_CHANGED = function() return API.QuietPresence() end,
	GROUPS_CHANGED = function() return Member() and API.Groups() or nil end,
	LOOKING_CHANGED = function() return Member() and API.Looking() or nil end,
	MY_GROUP_CHANGED = function() return Member() and API.MyGroup() or nil end,
}

local NIL_DATA_EVENT = { PROFILE_EFFECT_SESSION_CHANGED = true }

---------------------------------------------------------------------------
-- The addons, their answers and their handles
---------------------------------------------------------------------------

local function Answers(make)
	if type(ns.db) ~= "table" then return nil end
	if type(ns.db.apiAddons) ~= "table" then
		if not make then return nil end
		ns.db.apiAddons = {}
	end
	return ns.db.apiAddons
end

-- The player's answer for this addon: true, false, or nil (never asked, or asked about less than
-- this version gives).
local function Answer(c)
	local all = Answers(false)
	local e = all and all[c.key]
	if type(e) ~= "table" or e.v ~= API.CONSENT_VERSION then return nil end
	if e.on == true then return true end
	if e.on == false then return false end
	return nil
end

local function Granted(c) return Answer(c) == true end

local function Status(c)
	local a = Answer(c)
	return a == true and "granted" or a == false and "refused" or "pending"
end

-- This handle turned the quiet presence on (Core.lua), and it is still on.
local function QuietOwned(c)
	return type(ns.QuietPresenceOwnedBy) == "function" and ns.QuietPresenceOwnedBy(c.quietOwner) == true
end

local function Listens(c, event)
	return type(c.callbacks[event]) == "table" and #c.callbacks[event] > 0
end

-- The addon's callbacks for the event, each protected; one that keeps failing goes.
local function Tell(c, event, payload)
	if API.RESERVED_EVENTS[event] and not Authorized(c) then return end
	local list = c.callbacks[event]
	if type(list) ~= "table" then return end
	local now = {}
	for i, fn in ipairs(list) do now[i] = fn end
	for _, fn in ipairs(now) do
		local ok, err = pcall(fn, event, Copy(payload))
		if not ok then
			c.fails[fn] = (c.fails[fn] or 0) + 1
			ns.Log("api: %s's %s callback failed (%d): %s", c.name, event, c.fails[fn], ns.Cut(tostring(err), 200))
			if c.fails[fn] >= API.CALLBACK_FAILS then
				for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
				c.fails[fn] = nil
				ns.Log("api: %s's %s callback dropped after %d errors", c.name, event, API.CALLBACK_FAILS)
			end
		end
	end
end

local Dispatch, Mark

-- The leader's crown leaves the map on its own (King.LOCATION_EXPIRE after his last word) with no
-- event of Olympus's: while a built presence holds a position, one timer looks again just after it
-- would expire. Never while nobody listens (only a built LEADER_CHANGED arms it), one at a time.
local leaderTimer = false
local function WatchLeaderExpiry(data)
	if leaderTimer or not ns.After or type(data) ~= "table" or type(data.position) ~= "table" then return end
	local seenAt = data.position.seenAt
	local life = Has("King", "Location") and tonumber(ns.King.LOCATION_EXPIRE) or nil
	if type(seenAt) ~= "number" or not life then return end
	local now = ns.Now and ns.Now() or 0
	leaderTimer = true
	ns.After(math.max(1, seenAt + life + 1 - now), "api leader expiry", function()
		leaderTimer = false
		Mark("LEADER_CHANGED")
	end)
end

-- What a data event would give this addon now becomes what it was last told (no call when it
-- listens to nothing: nothing is built).
local function Baseline(c, event)
	local build = BUILD[event]
	if not build or not Listens(c, event) or not Granted(c) then return end
	local data = build()
	if event == "LEADER_CHANGED" then WatchLeaderExpiry(data) end
	if data ~= nil or NIL_DATA_EVENT[event] then c.told[event] = Signature(data) end
end

local function Schedule(delay)
	if scheduled or not ns.After then return end
	scheduled = true
	ns.After(delay or API.DISPATCH_DELAY, "api dispatch", function() Dispatch() end)
end

-- A change Olympus saw: looked at once the burst settles, only for events a granted addon listens
-- to (nobody listening: nothing is built and no timer starts).
Mark = function(...)
	local any = false
	for i = 1, select("#", ...) do
		local event = select(i, ...)
		for _, c in ipairs(order) do
			if Listens(c, event) and Granted(c) then pending[event], any = true, true break end
		end
	end
	if any then Schedule() end
end

-- Builds each pending event's data once and tells each granted addon that listens, when it is not
-- what that addon was last told. In combat, waits.
Dispatch = function()
	scheduled = false
	if next(pending) == nil and next(pendingSightings) == nil then return end
	if Busy() then Schedule(API.COMBAT_RETRY) return end
	local events = pending
	pending = {}
	for _, event in ipairs(API.DATA_EVENTS) do
		if events[event] then
			local data = BUILD[event]()
			if event == "LEADER_CHANGED" then WatchLeaderExpiry(data) end
			if data ~= nil or NIL_DATA_EVENT[event] then
				local sig = Signature(data)
				for _, c in ipairs(order) do
					if Listens(c, event) and Granted(c) and c.told[event] ~= sig then
						c.told[event] = sig
						Tell(c, event, data)
					end
				end
			end
		end
	end
	local sightings = pendingSightings
	pendingSightings = {}
	for id in pairs(sightings) do
		local state = AnySearch(id)
		for _, c in ipairs(order) do
			local terminal = c.sightingEnded[id]
			if terminal then
				c.sightingEnded[id] = nil
				if c.areaMapID == id then ClearAreaMap(c) end
				if Granted(c) and Listens(c, "SIGHTING_CHANGED") then Tell(c, "SIGHTING_CHANGED", terminal) end
			elseif c.searches[id] and SearchFingerprint(state) ~= c.searches[id] then
				-- Gone, or the bounded transport id now names a different session. End only the
				-- old handle's view. Validate this before drawing so a replacement session is never
				-- copied into stale map-pin frames, even briefly, across handles.
				ForgetSearch(c, id)
				if Granted(c) and Listens(c, "SIGHTING_CHANGED") then
					Tell(c, "SIGHTING_CHANGED", { id = id, status = "ended" })
				end
			else
				if c.areaMapID == id then
					if c.searches[id] and state and state.mode == "area" and state.status == "searching" and Granted(c) then
						DrawAreaMap(c, state, false)
					else
						ClearAreaMap(c)
					end
				end
				if c.searches[id] and Granted(c) and Listens(c, "SIGHTING_CHANGED") then
					local sig = Signature(state)
					if c.sightingTold[id] ~= sig then
						c.sightingTold[id] = sig
						Tell(c, "SIGHTING_CHANGED", state)
					end
				end
			end
		end
	end
end

local function MarkSighting(id)
	if type(id) == "number" then id = tostring(id) end
	if type(id) ~= "string" or id == "" then return end
	for _, c in ipairs(order) do
		if c.searches[id] and Granted(c) and (Listens(c, "SIGHTING_CHANGED") or c.areaMapID == id) then
			pendingSightings[id] = true
			Schedule()
			return
		end
	end
end

-- The player answered on the privacy page: kept for the account, the addon told (PERMISSION_CHANGED,
-- at once, protected) and, on a Yes, what it listens to now taken as what it was told.
local function SetAnswer(c, on)
	local all = Answers(true)
	if not all then return end
	-- Revocation is active, not merely a read gate: stop every request this handle started before
	-- saving the No. PlayerSightings also withdraws any live observer evidence when its own sharing
	-- permission is revoked.
	if not on then
		-- Release both sides of this handle's host-owned presentation before the saved answer changes.
		-- Close/disable are safe after a No as well, but doing them here guarantees that revocation is
		-- an active boundary rather than waiting for the short network leases to expire.
		if Has("ProfileEffects", "CloseSession") then pcall(ns.ProfileEffects.CloseSession, c.profileOwner) end
		if Has("ProfileEffects", "DisableOwner") then pcall(ns.ProfileEffects.DisableOwner, c.profileOwner) end
		-- The quiet presence this handle turned on ends with its No, as its profile session does.
		if QuietOwned(c) then pcall(ns.SetQuietPresence, false, c.quietOwner) end
		local ids = {}
		for id in pairs(c.searches) do ids[#ids + 1] = id end
		if Has("PlayerSightings", "Cancel") then
			for _, id in ipairs(ids) do
				-- The bounded transport may already have reused this id. Only cancel the exact
				-- session this handle started; a stale handle must not stop its replacement.
				if OwnedSearch(c, id) then pcall(ns.PlayerSightings.Cancel, id, "permission") end
			end
		end
		c.searches = {}
		c.sightingEnded = {}
		c.areaProofs = {}
		c.areaStartedAt = nil
		ClearAreaMap(c)
		HideSightingPins(c)
	end
	all[c.key] = { on = on and true or false, v = API.CONSENT_VERSION, at = ns.Now and ns.Now() or 0 }
	c.told = {}
	c.sightingTold = {}
	if on then for _, event in ipairs(API.DATA_EVENTS) do Baseline(c, event) end end
	ns.Log("api: %s %s", c.name, on and "granted" or "refused")
	-- (1.2: its group panel shows only while it is Yes: the Board redrawn with it or without it.)
	if c.panelRegistered and Has("UI", "Refresh") then pcall(ns.UI.Refresh) end
	Tell(c, "PERMISSION_CHANGED", Status(c))
end

-- The addon's line on the privacy page (Consent.lua): its own Yes and No, or the page's deliberately
-- labelled Authorize all. A new
-- question, never one of the lines 1.2.1 and 1.2.2 showed at every login (adopt = false: review of
-- 1.2.4, an account updating from 1.2.2 straight to 1.2.4 had it taken as asked, and the page never
-- opened by itself for it).
local function Line(c)
	if not Has("Consent", "Register") then return false end
	return ns.Consent.Register({
		key = c.consentKey,
		label = function() return L.API_CONSENT_LABEL:format(c.title) end,
		-- An addon that is not authorized is asked only about what it can read (the header's Reserved).
		text = Authorized(c) and "API_CONSENT_TEXT" or "API_CONSENT_TEXT_BASIC",
		explicit = true,
		adopt = false,
		version = API.CONSENT_VERSION,
		get = function() return Answer(c) end,
		set = function(on) SetAnswer(c, on) end,
	}) == true
end

-- The installed addon's title (its TOC's, plain), its name when it has none but the game has it
-- loaded, or nil: a name the game knows nothing of gets no line on the privacy page.
local function Installed(name)
	local AO = C_AddOns
	if type(AO) ~= "table" then return nil end
	local title, loaded
	if type(AO.GetAddOnMetadata) == "function" then
		local ok, t = pcall(AO.GetAddOnMetadata, name, "Title")
		if ok then title = Plain(t, API.TITLE_MAX) end
	end
	if not title and type(AO.IsAddOnLoaded) == "function" then
		local ok, yes = pcall(AO.IsAddOnLoaded, name)
		loaded = ok and yes and true or false
	end
	if title then return title end
	if loaded then return Plain(name, API.TITLE_MAX) end
	return nil
end

-- A method of the handle, for handle:Method(...) and handle.Method(...) alike.
local function Method(c, fn)
	return function(first, ...)
		if first == c.handle then return fn(c, ...) end
		return fn(c, first, ...)
	end
end

-- A data call: the player's Yes, an Olympus guild (where asked), and the addon within its rate.
-- Past it, said in the log once a session for that addon (review of 1.2.4: once a window filled the
-- log's ring, and the 25 lines /oly bug copies, with one addon polling). (1.4.0) unit: an
-- IsOlympusMember call, on its own budget (UNIT_RATE_MAX), said once a session too.
local function Spend(c, unit)
	local now = ns.Now and ns.Now() or 0
	local r, max = c.rate, API.RATE_MAX
	if unit then r, max = c.unitRate, API.UNIT_RATE_MAX end
	if now - r.at >= API.RATE_WINDOW or now < r.at then r.at, r.n = now, 0 end
	if r.n >= max then
		if not r.said then
			r.said = true
			ns.Log("api: %s asked more than %d %s in %d s (said once a session)", c.name, max,
				unit and "membership checks" or "times", API.RATE_WINDOW)
		end
		return false
	end
	r.n = r.n + 1
	return true
end
local function Read(c, needsGuild, build, ...)
	if not Granted(c) then return nil, Status(c) end
	if needsGuild and not Member() then return nil, "guild" end
	if not Spend(c) then return nil, "busy" end
	return build(...)
end

local function SightingRead(c, build, ...)
	if not Has("PlayerSightings", "Session") then return nil, "unavailable" end
	return Read(c, true, build, ...)
end

local function ProfileAction(c, fn, ...)
	if not Has("ProfileEffects", fn) then return false, "unavailable" end
	if not Granted(c) then return false, Status(c) end
	if not Member() then return false, "guild" end
	if not Spend(c) then return false, "busy" end
	local ok, result, why = pcall(ns.ProfileEffects[fn], ...)
	if not ok then return false, "failed" end
	return result == true, why
end

-- Stop/disable remain available after revocation because they can only remove this handle's own
-- bounded state. The internal owner check prevents one API handle from changing another's state.
local function ProfileRelease(c, fn, ...)
	if not Has("ProfileEffects", fn) then return false, "unavailable" end
	local ok, result, why = pcall(ns.ProfileEffects[fn], ...)
	if not ok then return false, "failed" end
	return result == true, why
end

local function AreaPin(row) -- gp:worldmap-icons
	if not ns.Gate.Allowed("worldmap-icons") then return nil end
	if UIParent == nil then return nil end
	-- An unskinned map marker, not a standalone window. Keep the optional
	-- template explicit so the window-style guard can verify that invariant.
	local frame = CreateFrame("Frame", nil, UIParent, nil)
	frame:SetSize(18, 18)
	local icon = frame:CreateTexture(nil, "OVERLAY")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
	frame.row = Copy(row)
	frame:SetScript("OnEnter", function(self) -- gp:worldmap-icons
		if not ns.Gate.Allowed("worldmap-icons") then return end
		if type(GameTooltip) ~= "table" or type(GameTooltip.SetOwner) ~= "function" then return end
		if type(self.row) ~= "table" then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.row.target or "", 1, 0.82, 0)
		local line = self.row.kind == "nearby" and (L.API_AREA_NEARBY or "Seen nearby")
			or (L.API_AREA_EXACT or "Exact last-seen point")
		if self.row.hostile == false then line = line .. "\n" .. (L.API_AREA_OUTSIDER or "Not hostile, outside Olympus's guilds") end
		GameTooltip:AddLine(line, 0.75, 0.75, 0.75, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() -- gp:worldmap-icons
		if not ns.Gate.Allowed("worldmap-icons") then return end
		if GameTooltip then GameTooltip:Hide() end
	end)
	frame:Hide()
	return frame
end

-- HereBeDragons owns the anchors, while Olympus owns a bounded pool of the frames it gives the
-- library. WoW frames cannot be destroyed, so keep at most the 48 frames one area result can use
-- and reuse them on every refresh instead of orphaning another set after each network answer.
local function HideAreaPins(c) -- gp:worldmap-icons!undo
	local P = ns.Pins and ns.Pins()
	if ns.Gate.Allowed("worldmap-icons") and P and type(P.RemoveAllWorldMapIcons) == "function" and c.areaMapOwner then
		pcall(P.RemoveAllWorldMapIcons, P, c.areaMapOwner)
	end
	for _, frame in ipairs(c.areaMapFrames or {}) do
		frame.row = nil
		pcall(frame.Hide, frame)
	end
end

ClearAreaMap = function(c, expected)
	if Secret(expected) then return false, "unknown" end
	if expected ~= nil and c.areaMapID ~= expected then return false, "unknown" end
	HideAreaPins(c)
	c.areaMapID = nil
	return true
end

DrawAreaMap = function(c, state, open) -- gp:worldmap-icons
	if not ns.Gate.Allowed("worldmap-icons") then ClearAreaMap(c) return false, "unsupported" end
	if type(state) ~= "table" or state.mode ~= "area" then return false, "unknown" end
	if state.status ~= "searching" then ClearAreaMap(c) return false, "ended" end
	local P = ns.Pins and ns.Pins()
	if not P or type(P.AddWorldMapIconMap) ~= "function" or type(P.RemoveAllWorldMapIcons) ~= "function"
		or type(ns.WorldMapIcons) ~= "function" then ClearAreaMap(c) return false, "unavailable" end
	local okWorld, world = pcall(ns.WorldMapIcons, P, c.areaMapOwner)
	if not okWorld or world ~= true then ClearAreaMap(c) return false, "unsupported" end
	local watched = c.areaMapID == state.id
	HideAreaPins(c)
	local now = ns.Now and ns.Now() or 0
	local used = 0
	for _, row in ipairs(state.sightings or {}) do
		if used >= 48 then break end
		if type(row) == "table" and row.mapID == state.mapID and type(row.x) == "number" and type(row.y) == "number"
			and type(row.expiresAt) == "number" and row.expiresAt > now then
			used = used + 1
			local frame = c.areaMapFrames[used]
			if not frame then
				frame = AreaPin(row)
				c.areaMapFrames[used] = frame
			else
				frame.row = Copy(row)
			end
			if not frame then ClearAreaMap(c) return false, "unavailable" end
			local ok, added = pcall(P.AddWorldMapIconMap, P, c.areaMapOwner, frame, row.mapID,
				row.x / 1000, row.y / 1000, HBD_PINS_WORLDMAP_SHOW_PARENT or 1)
			if not ok or added ~= true then ClearAreaMap(c) return false, "failed" end
			if type(frame.Show) == "function" then pcall(frame.Show, frame) end
		end
	end
	if used == 0 then
		-- A map the player already opened remains armed across a temporarily empty result set. A later
		-- sighting can therefore restore its pins without forcing the consumer to subscribe to events
		-- or ask the player to click Show again. A first empty Show still fails closed and opens nothing.
		c.areaMapID = watched and state.id or nil
		return false, "empty"
	end
	c.areaMapID = state.id
	if open then
		if type(WorldMapFrame) ~= "table" or type(WorldMapFrame.SetMapID) ~= "function"
			or type(ShowUIPanel) ~= "function" then ClearAreaMap(c) return false, "unavailable" end
		local shown = pcall(ShowUIPanel, WorldMapFrame)
		local focused = shown and pcall(WorldMapFrame.SetMapID, WorldMapFrame, state.mapID)
		if not focused then ClearAreaMap(c) return false, "failed" end
	end
	return true
end

-- Surface ownership is deliberately separate from the addon's name and consent key. UI.lua sees
-- only this session-local slot, so its page context and lifecycle logs do not identify the caller.
local function SurfaceCall(fn, owner, ...)
	if not Has("UI", fn) then return false, "unavailable" end
	local ok, result, why = pcall(ns.UI[fn], owner, ...)
	if not ok then return false, "failed" end
	return result, why
end

local function RegisteredSurfaceCall(c, fn, ...)
	if not c.surfaceRegistered then return false, "unregistered" end
	return SurfaceCall(fn, c.surfaceOwner, ...)
end

local METHODS = {}
function METHODS.Status(c) return Status(c) end
function METHODS.Name(c) return c.name end
function METHODS.GetWanted(c) return Read(c, true, API.Wanted) end
function METHODS.GetRankings(c, kind)
	if kind ~= nil and not RANKING[kind] then return nil, "kind" end
	return Read(c, true, API.Rankings, kind)
end
function METHODS.GetProfile(c) return Read(c, false, API.Profile) end
-- (1.4.0) true or false, or nil and why: "unit" (not a unit token it takes, checked first and free),
-- the usual "pending", "refused", "guild" and "busy" (its own budget, UNIT_RATE_MAX), or "unknown"
-- (API.IsOlympusMember's nil: this client cannot tell).
function METHODS.IsOlympusMember(c, unit)
	local token = API.UnitToken(unit)
	if not token then return nil, "unit" end
	if not Granted(c) then return nil, Status(c) end
	if not Member() then return nil, "guild" end
	if not Spend(c, true) then return nil, "busy" end
	local yes = API.IsOlympusMember(token)
	if yes == nil then return nil, "unknown" end
	return yes
end
function METHODS.GetLeaderPresence(c)
	if not Has("Hop", "King") then return nil, "unavailable" end
	return Read(c, true, API.LeaderPresence)
end
function METHODS.StartProfileSession(c, style)
	style = Plain(style, 32)
	if not style then return false, "style" end
	return ProfileAction(c, "OpenSession", c.profileOwner, style)
end
function METHODS.StopProfileSession(c)
	return ProfileRelease(c, "CloseSession", c.profileOwner)
end
function METHODS.SetProfileEffect(c, style, enabled, caption)
	style = Plain(style, 32)
	if not style then return false, "style" end
	if enabled ~= true and enabled ~= false then return false, "state" end
	if enabled then
		if Secret(caption) or type(caption) ~= "string" then return false, "caption" end
		return ProfileAction(c, "Set", c.profileOwner, style, true, caption)
	end
	return ProfileRelease(c, "Set", c.profileOwner, style, false)
end
function METHODS.GetProfileSession(c)
	if not Has("ProfileEffects", "Session") then return nil, "unavailable" end
	return Read(c, true, function()
		local state = API.ProfileSession()
		return state, state and nil or "none"
	end)
end
-- 1.2.5.1: the quiet presence (Core.lua). Self only, for this session: on, this client sends
-- nothing that says the player is online or where he is; reads go on. Only the King, a High
-- Councillor (a current signed issuer) or the addon's author may turn it on ("authority"; "guild"
-- outside an Olympus guild). The handle that turned it on may always turn it off; another handle
-- gets "owner". Never saved: a /reload or a logout ends it.
function METHODS.SetQuietPresence(c, on)
	if on ~= true and on ~= false then return false, "state" end
	if type(ns.SetQuietPresence) ~= "function" then return false, "unavailable" end
	if on == false and QuietOwned(c) then
		local ok, done, why = pcall(ns.SetQuietPresence, false, c.quietOwner)
		if not ok then return false, "failed" end
		return done == true, why
	end
	if not Granted(c) then return false, Status(c) end
	if not Member() then return false, "guild" end
	if not Spend(c) then return false, "busy" end
	local ok, done, why = pcall(ns.SetQuietPresence, on, c.quietOwner)
	if not ok then return false, "failed" end
	return done == true, why
end
function METHODS.GetQuietPresence(c)
	if type(ns.QuietPresenceState) ~= "function" then return nil, "unavailable" end
	return Read(c, false, API.QuietPresence)
end
function METHODS.StartPlayerSearch(c, target)
	if not Has("PlayerSightings", "Start") then return nil, "unavailable" end
	local state, why = SightingRead(c, function() return Call("PlayerSightings", "Start", target) end)
	-- The internal transport returns true plus its opaque id; keep accepting a table too so this
	-- adapter remains stable if the internal module later returns its initial snapshot directly.
	if state == true and (type(why) == "string" or type(why) == "number") then
		local id = why
		state, why = API.PlayerSearch(id), nil
	end
	if type(state) == "table" and type(state.id) == "string" and state.id ~= "" then
		PruneOwnedSearches(c)
		c.sightingEnded[state.id] = nil
		c.searches[state.id] = SearchFingerprint(state)
		c.sightingTold[state.id] = Signature(state)
		return Copy(state)
	end
	return nil, why or "failed"
end
function METHODS.CancelPlayerSearch(c, id)
	local state = OwnedSearch(c, id, "player")
	if not state then return false, "unknown" end
	if not Has("PlayerSightings", "Cancel") then return false, "unavailable" end
	-- This method has no read-permission gate because cancellation can only reduce disclosure. A No
	-- already cancels and forgets every owned request in SetAnswer above.
	local ok, result, why = pcall(ns.PlayerSightings.Cancel, id, "api")
	if not ok then return false, "failed" end
	if result == true then
		RetainAreaProofs(c, state)
		ForgetSearch(c, id)
		if Granted(c) and Listens(c, "SIGHTING_CHANGED") then
			c.sightingEnded[id] = { id = id, status = "cancelled" }
			pendingSightings[id] = true
			Schedule()
		end
	elseif why == "not-found" then
		ForgetSearch(c, id)
	end
	return result == true, why
end
function METHODS.GetPlayerSearch(c, id)
	return SightingRead(c, function()
		local state = OwnedSearch(c, id, "player")
		return state, state and nil or "unknown"
	end)
end
function METHODS.GetPlayerSearches(c)
	return SightingRead(c, function()
		local out = PruneOwnedSearches(c, "player")
		table.sort(out, function(a, b)
			local aa, bb = tonumber(a.createdAt) or 0, tonumber(b.createdAt) or 0
			if aa ~= bb then return aa > bb end
			return tostring(a.id or "") < tostring(b.id or "")
		end)
		return out
	end)
end
function METHODS.StartAreaSearch(c, mapID, scope)
	if not Has("PlayerSightings", "StartArea") then return nil, "unavailable" end
	return SightingRead(c, function()
		if Secret(mapID) then return nil, "map" end
		mapID = Num(mapID, false)
		if not mapID or mapID <= 0 or mapID ~= math.floor(mapID) then return nil, "map" end
		-- "hostile" (also nil: the original contract) or "outsiders", which this build's transport
		-- must list too.
		if Secret(scope) then return nil, "scope" end
		if scope == nil then scope = "hostile" end
		local scopes = ns.PlayerSightings.AREA_SCOPES
		if type(scope) ~= "string" or not API.AREA_SCOPES[scope]
			or (scope ~= "hostile" and not (type(scopes) == "table" and scopes[scope] == true)) then
			return nil, "scope"
		end
		for _, search in ipairs(PruneOwnedSearches(c, "area")) do
			if search.status == "searching" then return nil, "active" end
		end
		local now = ns.Now and ns.Now() or 0
		if c.areaStartedAt ~= nil and now - c.areaStartedAt < API.AREA_ROTATE_MIN then
			return nil, "cooldown"
		end
		if not AreaMapAllowed(c, mapID, now) then return nil, "map" end
		local state, why
		if scope == "hostile" then state, why = Call("PlayerSightings", "StartArea", mapID)
		else state, why = Call("PlayerSightings", "StartArea", mapID, scope) end
		if state == true and (type(why) == "string" or type(why) == "number") then
			local id = why
			state, why = API.AreaSearch(id), nil
		end
		if type(state) == "table" and type(state.id) == "string" and state.id ~= "" then
			PruneOwnedSearches(c)
			c.sightingEnded[state.id] = nil
			c.searches[state.id] = SearchFingerprint(state)
			c.sightingTold[state.id] = Signature(state)
			c.areaStartedAt = now
			return Copy(state)
		end
		return nil, why or "failed"
	end)
end
function METHODS.CancelAreaSearch(c, id)
	if not OwnedSearch(c, id, "area") then return false, "unknown" end
	if not Has("PlayerSightings", "CancelArea") then return false, "unavailable" end
	local ok, result, why = pcall(ns.PlayerSightings.CancelArea, id, "api")
	if not ok then return false, "failed" end
	if result == true then
		ClearAreaMap(c, id)
		ForgetSearch(c, id)
		if Granted(c) and Listens(c, "SIGHTING_CHANGED") then
			c.sightingEnded[id] = { id = id, mode = "area", status = "cancelled" }
			pendingSightings[id] = true
			Schedule()
		end
	elseif why == "not-found" then
		ForgetSearch(c, id)
	end
	return result == true, why
end
function METHODS.GetAreaSearch(c, id)
	return SightingRead(c, function()
		local state = OwnedSearch(c, id, "area")
		return state, state and nil or "unknown"
	end)
end
function METHODS.GetAreaSearches(c)
	return SightingRead(c, function()
		local out = PruneOwnedSearches(c, "area")
		table.sort(out, function(a, b)
			local aa, bb = tonumber(a.createdAt) or 0, tonumber(b.createdAt) or 0
			if aa ~= bb then return aa > bb end
			return tostring(a.id or "") < tostring(b.id or "")
		end)
		return out
	end)
end
function METHODS.ShowAreaSearchOnMap(c, id)
	local state, why = SightingRead(c, function() return OwnedSearch(c, id, "area") end)
	if not state then return false, why or "unknown" end
	return DrawAreaMap(c, state, true)
end
function METHODS.ClearAreaSearchMap(c, id)
	if Secret(id) then return false, "unknown" end
	if id ~= nil and type(id) ~= "string" then return false, "unknown" end
	return ClearAreaMap(c, id)
end
-- Sighting pins: the rows a visible, player-started monitoring session chose to keep in sight, as
-- host-owned dots on the world map (mouse and keyboard only: ns.WorldMapIcons) and on the minimap,
-- each coloured by a fixed category. Olympus writes the tooltip from the pin's own checked fields:
-- the name, its category (or the consumer's own short name for it), the consumer's short marks (a list's name, at most three), how long ago
-- it was seen (Olympus's own clock, the rows' seenAt) and how precise the point is. It never opens
-- the map. Each call replaces this handle's whole set; permission loss, ClearSightingPins, a
-- /reload and Olympus hiding locations from this player remove it. A pin past its own expiresAt is
-- not drawn, and a drawn one goes by itself once past it (TickSightingPins).
API.PIN_MAX = 96
API.PIN_LIFETIME_MAX = 15 * 60 -- no dot may outlive the sighting result it represents
API.PIN_CATEGORIES = {
	hostile = { 0.92, 0.18, 0.14 },   -- red
	marked = { 1, 0.62, 0.05 },       -- orange
	outsider = { 0.3, 0.62, 1 },      -- blue
}
local PIN_LABEL = { hostile = "API_PIN_HOSTILE", marked = "API_PIN_MARKED", outsider = "API_PIN_OUTSIDER" }

local function PinRow(raw, now)
	if type(raw) ~= "table" or Secret(raw.category) or not API.PIN_CATEGORIES[raw.category] then return nil end
	local target = Plain(raw.target, 72)
	local mapID, x, y = Num(raw.mapID, true), Num(raw.x), Num(raw.y)
	local seenAt, expiresAt = Num(raw.seenAt), Num(raw.expiresAt)
	if not target or not mapID or mapID <= 0 or mapID > 9999999 or not x or x < 0 or x > 1000 or not y or y < 0 or y > 1000
		or not seenAt or not expiresAt or expiresAt <= now or expiresAt <= seenAt
		or expiresAt > seenAt + API.PIN_LIFETIME_MAX or seenAt > now + 60 then return nil end
	local kind = raw.kind
	if kind ~= "exact-unit" and kind ~= "exact-group" then kind = "nearby" end
	local yards = kind == "nearby" and Num(raw.accuracyYards) or nil
	if yards and (yards < 1 or yards > 100000) then yards = nil end
	local marks = {}
	for _, mark in ipairs(type(raw.marks) == "table" and raw.marks or {}) do
		if #marks >= 3 then break end
		local text = Plain(mark, 24)
		if text then marks[#marks + 1] = text end
	end
	return { target = target, category = raw.category, label = Plain(raw.label, 32), mapID = mapID, x = x, y = y,
		seenAt = seenAt, expiresAt = expiresAt, kind = kind, accuracyYards = yards, own = raw.own == true, marks = marks }
end

local function PinTooltip(self) -- gp:minimap
	local row = self.pinRow
	if type(row) ~= "table" or type(GameTooltip) ~= "table" or type(GameTooltip.SetOwner) ~= "function" then return end
	local c = API.PIN_CATEGORIES[row.category] or { 1, 1, 1 }
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(row.target, c[1], c[2], c[3])
	GameTooltip:AddLine(row.label or L[PIN_LABEL[row.category]] or row.category, 0.85, 0.85, 0.85)
	if #row.marks > 0 then
		GameTooltip:AddLine((L.API_PIN_MARKS or "Marked: %s"):format(table.concat(row.marks, ", ")), 1, 0.82, 0)
	else
		GameTooltip:AddLine(L.API_PIN_UNMARKED or "Not marked", 0.6, 0.6, 0.6)
	end
	GameTooltip:AddLine((L.API_PIN_SEEN or "Seen %s"):format(ns.Ago(row.seenAt)), 0.85, 0.85, 0.85)
	local precision
	if row.kind ~= "nearby" then precision = L.API_AREA_EXACT or "Exact last-seen point"
	elseif row.accuracyYards then precision = (L.API_PIN_YARDS or "Nearby, within about %d yards"):format(math.floor(row.accuracyYards + 0.5))
	else precision = L.API_PIN_NEARBY or "Nearby: where the observer stood" end
	GameTooltip:AddLine(precision, 0.75, 0.75, 0.75, true)
	if row.own then GameTooltip:AddLine(L.API_PIN_OWN or "Seen by you", 0.5, 0.9, 0.5) end
	GameTooltip:Show()
end

local function PinDot(size) -- gp:minimap
	-- Loaded in WoW after the frame API exists; UIParent is the compatibility
	-- guard, as it is for the world-map marker above. Avoid passing CreateFrame
	-- around as a value, which would make the window-style audit unverifiable.
	if UIParent == nil then return nil end
	-- An unskinned map marker, not a standalone window. Keep the optional
	-- template explicit so the window-style guard can verify that invariant.
	local f = CreateFrame("Frame", nil, UIParent, nil)
	f.olympus = true
	f:SetSize(size, size)
	f.edge = f:CreateTexture(nil, "BACKGROUND")
	f.edge:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	f.edge:SetVertexColor(0, 0, 0, 0.9)
	f.edge:SetAllPoints()
	f.dot = f:CreateTexture(nil, "ARTWORK")
	f.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	f.dot:SetPoint("TOPLEFT", 1.5, -1.5)
	f.dot:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
	if f.EnableMouse then f:EnableMouse(true) end
	f:SetScript("OnEnter", PinTooltip)
	f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end) -- gp:minimap
	f:Hide()
	return f
end

-- An older sighting fades: full under two minutes, then three quarters, then half from five.
local function PinAlpha(row, now)
	local age = now - row.seenAt
	if age < 120 then return 1 end
	if age < 300 then return 0.75 end
	return 0.5
end

-- While Olympus hides locations from this player (WatchChat.Barred "locations", as the guildmates'
-- dots, the King's crown and the Wanted pins), none of these dots either. A check that fails hides.
local function LocationsBarred()
	if not Has("WatchChat", "Barred") then return false end
	local ok, barred = pcall(ns.WatchChat.Barred, "locations")
	if not ok then return true end
	return barred ~= nil and barred ~= false
end

-- Whether this handle may keep its dots up: its Yes, a member, locations not hidden from him.
local function PinsAllowed(c)
	return Granted(c) and Member() and not LocationsBarred()
end

-- A slot's two frames, off every map and with no row. Their anchors go too: a frame the library no
-- longer places never shows where it last stood (the library shows a minimap dot itself, only in
-- the player's own zone, and hides it when it takes it off).
local function ResetPinPair(pair)
	pair.row, pair.onWorld, pair.onMini, pair.placed = nil, nil, nil, nil
	for _, frame in ipairs({ pair.world, pair.mini }) do
		frame.pinRow = nil
		pcall(frame.Hide, frame)
		if type(frame.ClearAllPoints) == "function" then pcall(frame.ClearAllPoints, frame) end
	end
end

-- One slot's dots taken off the maps (the world map's only while the gate allows: at a switch to
-- the gamepad UI ns.WorldMapIcons or the gate's park took them off already).
local function UnplacePin(P, c, pair) -- gp:worldmap-icons!undo
	if P and pair.onWorld and ns.Gate.Allowed("worldmap-icons") and type(P.RemoveWorldMapIcon) == "function" then
		pcall(P.RemoveWorldMapIcon, P, c.pinOwner, pair.world)
	end
	if P and pair.onMini and type(P.RemoveMinimapIcon) == "function" then pcall(P.RemoveMinimapIcon, P, c.pinOwner, pair.mini) end -- gp:minimap
	ResetPinPair(pair)
end

HideSightingPins = function(c) -- gp:worldmap-icons!undo
	local P = ns.Pins and ns.Pins()
	if P and c.pinOwner then
		if ns.Gate.Allowed("worldmap-icons") and type(P.RemoveAllWorldMapIcons) == "function" then
			pcall(P.RemoveAllWorldMapIcons, P, c.pinOwner)
		end
		if type(P.RemoveAllMinimapIcons) == "function" then pcall(P.RemoveAllMinimapIcons, P, c.pinOwner) end -- gp:minimap
	end
	for _, pair in ipairs(c.pinFrames or {}) do ResetPinPair(pair) end
	c.pinCount = 0
end

-- Every PIN_TICK seconds while a handle has dots: a dot past its row's expiresAt goes, the others fade
-- with age (their alpha alone: nothing is placed again), and all go once the handle's Yes, the
-- membership or the player's locations do. One pending timer per handle at most (ns.After, as the
-- leader's expiry: no ticker), and none once its dots are gone.
API.PIN_TICK = 15
local TickSightingPins
local function SchedulePinTick(c)
	if c.pinTickPending or not ns.After then return end
	c.pinTickPending = true
	ns.After(API.PIN_TICK, "api sighting pins", function()
		c.pinTickPending = nil
		if (c.pinCount or 0) > 0 then TickSightingPins(c) end
	end)
end
TickSightingPins = function(c)
	if not PinsAllowed(c) then HideSightingPins(c) return end
	local P = ns.Pins and ns.Pins()
	-- With the gamepad UI the gate's park took the world map's dots off: placed again on a later Set
	-- once it allows them.
	local worldOff = not ns.Gate.Allowed("worldmap-icons")
	local now = ns.Now and ns.Now() or 0
	local count = 0
	for _, pair in ipairs(c.pinFrames) do
		if worldOff then pair.onWorld = nil end
		local row = pair.row
		if row then
			if row.expiresAt <= now then
				UnplacePin(P, c, pair)
			else
				count = count + 1
				local alpha = PinAlpha(row, now)
				for _, frame in ipairs({ pair.world, pair.mini }) do
					if frame.SetAlpha then frame:SetAlpha(alpha) end
				end
			end
		end
	end
	c.pinCount = count
	if count == 0 then HideSightingPins(c) else SchedulePinTick(c) end
end

-- The world map's dots only with mouse and keyboard (ns.WorldMapIcons), the minimap's always, as
-- Positions.lua draws guildmates. The pin library shows, places and hides every dot itself (Wanted's
-- pins too): Olympus never shows one. A slot whose row stands where it stood keeps its dots (no
-- blink, nothing rebuilt), only its tooltip row, colour and alpha change; a row the library cannot
-- place (a map it does not know) is not drawn and not counted.
local function DrawSightingPins(c, list)
	local P = ns.Pins and ns.Pins()
	if not P or type(P.AddMinimapIconMap) ~= "function" then return false, "unavailable" end
	local world = type(ns.WorldMapIcons) == "function" and ns.WorldMapIcons(P, c.pinOwner) == true -- gp:worldmap-icons
	-- A library without the single-icon removals: every dot off and placed again, as before.
	if type(P.RemoveMinimapIcon) ~= "function" or type(P.RemoveWorldMapIcon) ~= "function" then HideSightingPins(c) end
	local now = ns.Now and ns.Now() or 0
	local used = 0
	-- The public contract is the first PIN_MAX rows, not PIN_MAX valid rows after walking an
	-- arbitrarily large hostile table supplied by another addon.
	for i = 1, math.min(#list, API.PIN_MAX) do
		local raw = list[i]
		local row = PinRow(raw, now)
		if row then
			local pair = c.pinFrames[used + 1]
			if not pair then
				local w, m = PinDot(12), PinDot(10)
				if not w or not m then HideSightingPins(c) return false, "unavailable" end
				pair = { world = w, mini = m }
				c.pinFrames[used + 1] = pair
			end
			-- (Without the world map, ns.WorldMapIcons took this handle's dots there off already.)
			if not world then pair.onWorld = nil end
			local spot = row.mapID .. ":" .. row.x .. ":" .. row.y
			if pair.placed ~= spot then
				UnplacePin(P, c, pair)
				local ok, added = pcall(P.AddMinimapIconMap, P, c.pinOwner, pair.mini, row.mapID, row.x / 1000, row.y / 1000, false, false) -- gp:minimap
				if ok and added == true then pair.onMini, pair.placed = true, spot end
			end
			if pair.placed == spot then
				used = used + 1
				if world and not pair.onWorld and ns.Gate.Allowed("worldmap-icons") then
					-- gp:worldmap-icons
					local ok, added = pcall(P.AddWorldMapIconMap, P, c.pinOwner, pair.world, row.mapID, row.x / 1000, row.y / 1000,
						HBD_PINS_WORLDMAP_SHOW_PARENT or 1)
					pair.onWorld = ok and added == true or nil
				end
				pair.row = row
				local color, alpha = API.PIN_CATEGORIES[row.category], PinAlpha(row, now)
				for _, frame in ipairs({ pair.world, pair.mini }) do
					frame.pinRow = row
					frame.dot:SetVertexColor(color[1], color[2], color[3])
					if frame.SetAlpha then frame:SetAlpha(alpha) end
				end
			end -- (else the slot, reset by UnplacePin, waits for the next row)
		end
	end
	for i = used + 1, #c.pinFrames do
		local pair = c.pinFrames[i]
		if pair.row or pair.placed or pair.onWorld then UnplacePin(P, c, pair) end
	end
	c.pinCount = used
	if used == 0 then HideSightingPins(c) else SchedulePinTick(c) end
	return true, used
end

function METHODS.SetSightingPins(c, list)
	if Secret(list) or type(list) ~= "table" then return false, "invalid" end
	local ok, why = SightingRead(c, function() return true end)
	if not ok then return false, why or "unknown" end
	if LocationsBarred() then HideSightingPins(c) return false, "barred" end
	return DrawSightingPins(c, list)
end
function METHODS.ClearSightingPins(c)
	HideSightingPins(c)
	return true
end

local GUILD_TOOL_SECTIONS = { desk = true, reports = true, cases = true, chat = true, justice = true, profile = true }

local function ShowGuildToolsSection(section, target)
	if section == "profile" then return ns.Watch.OpenMember(target) end
	ns.Watch.Show(section == "desk" and nil or section)
	return true
end

local function RestoreGuildToolsSection(page)
	if type(page) ~= "string" then return end
	local kind, key = page:match("^(case):(.*)$")
	if not kind then kind, key = page:match("^(profile):(.*)$") end
	pcall(ns.Watch.Show, kind or page == "desk" and nil or page, key)
end

-- Opens only Olympus-owned Watch UI. The caller receives success/failure, never the page's
-- records. A named profile is resolved and access-checked by Watch.OpenMember itself.
function METHODS.OpenGuildTools(c, section, target)
	section = section == nil and "desk" or section
	if Secret(section) or type(section) ~= "string" or not GUILD_TOOL_SECTIONS[section] then
		return false, "section"
	end
	if section == "profile" and (Secret(target) or type(target) ~= "string" or target == "") then
		return false, "target"
	end
	if not Member() then return false, "guild" end
	if not Has("UI", "SelectTab") or not Has("Watch", "Show") or not Has("Watch", "PageId")
		or (section == "profile" and not Has("Watch", "OpenMember")) then
		return false, "unavailable"
	end

	local priorOK, prior = pcall(ns.Watch.PageId)
	if not priorOK or type(prior) ~= "string" then return false, "failed" end
	local okShow, shown, showWhy = pcall(ShowGuildToolsSection, section, target)
	local pageOK, page = pcall(ns.Watch.PageId)
	local pageMatches = section == "profile" and type(page) == "string" and page:match("^profile:.+$") ~= nil
		or section ~= "profile" and page == section
	if not okShow or shown ~= true or not pageOK or not pageMatches then
		RestoreGuildToolsSection(prior)
		if not okShow or not pageOK then return false, "failed" end
		return false, showWhy or "access"
	end

	local ok, selected, why = pcall(ns.UI.SelectTab, "watch")
	if not ok or selected ~= true then
		RestoreGuildToolsSection(prior)
		return false, ok and (why or "failed") or "failed"
	end
	return true
end
function METHODS.RegisterSurface(c, spec)
	if c.surfaceRegistered then return false, "registered" end
	local ok, why = SurfaceCall("RegisterAPISurface", c.surfaceOwner, spec)
	if ok == true then c.surfaceRegistered = true end
	return ok, why
end
function METHODS.OpenSurface(c) return RegisteredSurfaceCall(c, "OpenAPISurface") end
function METHODS.ToggleSurface(c) return RegisteredSurfaceCall(c, "ToggleAPISurface") end
function METHODS.RefreshSurface(c) return RegisteredSurfaceCall(c, "RefreshAPISurface") end
function METHODS.IsSurfaceOpen(c) return RegisteredSurfaceCall(c, "IsAPISurfaceOpen") end
-- 1.2, the Board's groups ("groups"): reads like GetWanted's (Yes, an Olympus guild, the rate).
local function GroupKind(kind)
	if kind == nil then return true, nil end
	if Secret(kind) or type(kind) ~= "string" or not API.GROUP_KINDS[kind] then return false end
	return true, API.GROUP_KINDS[kind]
end
function METHODS.GetGroups(c, kind)
	if not HasGroups() then return nil, "unavailable" end
	local ok, code = GroupKind(kind)
	if not ok then return nil, "kind" end
	return Read(c, true, API.Groups, code)
end
function METHODS.GetLooking(c, kind)
	if not HasGroups() then return nil, "unavailable" end
	local ok, code = GroupKind(kind)
	if not ok then return nil, "kind" end
	return Read(c, true, API.Looking, code)
end
function METHODS.GetMyGroup(c)
	if not HasGroups() then return nil, "unavailable" end
	return Read(c, true, API.MyGroup)
end

-- 1.2, the player's own group ("groups.manage"): each action is the Board's own (Groups.lua's
-- function its button runs, with its checks and the gamepad gate's roster-actions path for the
-- game's invite: the companion's click is the player's), after the Yes, an Olympus guild, out of
-- combat and within a small rate of its own. `true`, or `false` and why.
local MANAGE = { "Invite", "Decline", "SetMemberRole", "InviteFlag", "InviteRoles", "Close", "Mine", "Pending", "Wants",
	"OpenListing", "OpenComposer", "OpenFlagComposer" }
local function HasManage()
	if not HasGroups() then return false end
	for _, fn in ipairs(MANAGE) do if not Has("Groups", fn) then return false end end
	return true
end
local function SpendManage(c)
	local now = ns.Now and ns.Now() or 0
	local r = c.manageRate
	if now - r.at >= API.MANAGE_WINDOW or now < r.at then r.at, r.n = now, 0 end
	if r.n >= API.MANAGE_MAX then return false end
	r.n = r.n + 1
	return true
end
local function Manage(c, fn)
	if not HasManage() then return false, "unavailable" end
	if not Granted(c) then return false, Status(c) end
	if not Member() then return false, "guild" end
	if Busy() then return false, "combat" end
	if not SpendManage(c) then return false, "busy" end
	local ok, done, why = pcall(fn, ns.Groups)
	if not ok then
		ns.Log("api: %s's group action failed: %s", c.name, ns.Cut(tostring(done), 200))
		return false, "failed"
	end
	if done == true then return true end
	return false, why or "failed"
end
-- A name as the Board keys it ("Name-Realm"; one without a realm is of ours).
local function Who(name)
	if Secret(name) or type(name) ~= "string" then return nil end
	name = name:match("^%s*(.-)%s*$")
	if name == "" or #name > 72 then return nil end
	return ns.FullName(name)
end
local function RoleCode(role)
	if Secret(role) or type(role) ~= "string" then return nil end
	return ROLE_CODE[role]
end
local function Applicant(G, name)
	local key = Who(name)
	for _, a in ipairs(G.Applicants()) do if key and a.name == key then return a end end
	return nil
end
-- The game's invite's answer, as the API says it.
local function Invited(ok, why)
	if ok == true then return true end
	return false, why == "leader" and "not-leader" or why or "failed"
end
function METHODS.InviteApplicant(c, name, role)
	return Manage(c, function(G)
		local own = G.Mine()
		if not own then return false, "unknown" end
		local a = Applicant(G, name)
		if not a then return false, "unknown" end
		local code = RoleCode(role)
		if not code or a.role ~= code or not G.Wants(own.need, code) then return false, "role" end
		if G.Pending()[a.name] then return false, "invited" end
		return Invited(G.Invite(a.name))
	end)
end
function METHODS.DeclineApplicant(c, name)
	return Manage(c, function(G)
		if not G.Mine() then return false, "unknown" end
		local a = Applicant(G, name)
		if not a then return false, "unknown" end
		return G.Decline(a.name) == true, "failed"
	end)
end
-- A member's role as the Board's roster row sets it: "tank", "healer", "damage", or nil for none.
function METHODS.SetMemberRole(c, name, role)
	return Manage(c, function(G)
		local code = RoleCode(role)
		if role ~= nil and not code then return false, "role" end
		local key = Who(name)
		for _, m in ipairs(G.GroupMembers()) do
			if key and m.name == key then
				G.SetMemberRole(m.name, code, true)
				return true
			end
		end
		return false, "unknown"
	end)
end
-- The Board's Invite as under Players looking: our listing's section, a role its flag names (any,
-- when it names none) that the listing still wants (Groups.InviteRoles).
function METHODS.InviteLooking(c, name, role)
	return Manage(c, function(G)
		local own = G.Mine()
		if not own then return false, "unknown" end
		local key, flag = Who(name), nil
		for _, e in ipairs(G.Looking(own.kind)) do if key and e.sender == key then flag = e end end
		if not flag then return false, "unknown" end
		local code, fits = RoleCode(role), false
		for _, r in ipairs(G.InviteRoles(flag)) do if r == code then fits = true end end
		if not fits then return false, "role" end
		if G.Pending()[flag.sender] then return false, "invited" end
		return Invited(G.InviteFlag(flag.sender, code))
	end)
end
-- Our listing taken down for everyone (/oly group off).
function METHODS.LowerListing(c)
	return Manage(c, function(G)
		if not G.Mine() then return false, "unknown" end
		return G.Close() == true, "failed"
	end)
end
-- Olympus's own: a listing's card (GetGroups' id), the composer of a listing ([kind]; ours
-- when we have one), the flag for several places ([kind], not a quest).
function METHODS.OpenGroup(c, id)
	return Manage(c, function(G)
		if Secret(id) or type(id) ~= "string" then return false, "unknown" end
		local listing, leader = id:match("^([0-9a-z][0-9a-z]?):(.+)$")
		if not listing then return false, "unknown" end
		return G.OpenListing(leader, listing)
	end)
end
function METHODS.OpenListingDialog(c, kind)
	local ok, code = GroupKind(kind)
	if not ok then return false, "kind" end
	return Manage(c, function(G) return G.OpenComposer(code or "D") end)
end
function METHODS.OpenFlagDialog(c, kind)
	local ok, code = GroupKind(kind)
	if not ok or code == "Q" then return false, "kind" end
	return Manage(c, function(G) return G.OpenFlagComposer(code) end)
end

-- 1.2, the Board's group panel ("ui.board-groups"): one companion panel a session in place of Your
-- group, as RegisterSurface's page (no data by itself; registered while the answer is pending too,
-- shown only while it is Yes). Groups.lua owns the frame, the switch and the player's choice.
function METHODS.RegisterGroupPanel(c, spec) -- gp:board-panel
	if not Has("Groups", "RegisterPanel") then return false, "unavailable" end
	if c.panelRegistered then return false, "registered" end
	if type(spec) ~= "table" then return false, "invalid-spec" end
	local raw = spec.label
	if Secret(raw) or type(raw) ~= "string" or #raw > API.PANEL_LABEL_MAX then return false, "invalid-label" end
	local label = Plain(raw, API.PANEL_LABEL_MAX)
	if not label then return false, "invalid-label" end
	local build, refresh = spec.build, spec.refresh
	if type(build) ~= "function" then return false, "invalid-build" end
	if refresh ~= nil and type(refresh) ~= "function" then return false, "invalid-refresh" end
	local ok, done, why = pcall(ns.Groups.RegisterPanel, c.panelOwner, { label = label, build = build, refresh = refresh,
		allowed = function() return Granted(c) end })
	if not ok then return false, "failed" end
	if done ~= true then return false, why or "failed" end
	c.panelRegistered = true
	return true
end
function METHODS.UnregisterGroupPanel(c)
	if not c.panelRegistered then return false, "unregistered" end
	if Has("Groups", "UnregisterPanel") then pcall(ns.Groups.UnregisterPanel, c.panelOwner) end
	c.panelRegistered = false
	return true
end
function METHODS.RefreshGroupPanel(c)
	if not c.panelRegistered then return false, "unregistered" end
	if Call("Groups", "PanelShown") == true and Has("UI", "Refresh") then pcall(ns.UI.Refresh) end
	return true
end
function METHODS.IsGroupPanelShown(c)
	if not c.panelRegistered then return false, "unregistered" end
	return Call("Groups", "PanelShown") == true
end
function METHODS.On(c, event, fn)
	if not IS_EVENT[event] or type(fn) ~= "function" then return false end
	if API.RESERVED_EVENTS[event] and not Authorized(c) then return false end
	local list = c.callbacks[event] or {}
	for _, f in ipairs(list) do if f == fn then return true end end
	if #list >= API.MAX_CALLBACKS then return false end
	list[#list + 1] = fn
	c.callbacks[event] = list
	if c.told[event] == nil then Baseline(c, event) end
	return true
end
function METHODS.Off(c, event, fn)
	local list = c.callbacks[event]
	if type(list) ~= "table" then return false end
	for i = #list, 1, -1 do
		if list[i] == fn or fn == nil then table.remove(list, i) end
	end
	return true
end

local function ReadOnly(_, k) error("OlympusAPI: read-only (" .. tostring(k) .. ")", 2) end

local function NewClient(name, key, title, slot)
	local c = { name = name, key = key, title = title, consentKey = "api:" .. key, callbacks = {}, told = {}, fails = {},
		rate = { at = -math.huge, n = 0 }, unitRate = { at = -math.huge, n = 0 }, surfaceOwner = "api-surface:" .. tostring(slot), searches = {}, sightingTold = {}, sightingEnded = {},
		areaMapOwner = {}, areaMapFrames = {}, pinOwner = {}, pinFrames = {}, pinCount = 0, areaProofs = {}, profileOwner = "api-profile:" .. tostring(slot),
		quietOwner = "api-quiet:" .. tostring(slot), panelOwner = "api-panel:" .. tostring(slot), manageRate = { at = -math.huge, n = 0 },
		authKey = API.AuthorizedKey(key) }
	local methods = {}
	for k, fn in pairs(METHODS) do
		local no = API.RESERVED_METHODS[k]
		if no then
			local inner = fn
			fn = function(client, ...)
				if not Authorized(client) then
					if no == "false" then return false, "unauthorized" end
					return nil, "unauthorized"
				end
				return inner(client, ...)
			end
		end
		methods[k] = Method(c, fn)
	end
	c.handle = setmetatable({}, { __index = methods, __newindex = ReadOnly, __metatable = false })
	return c
end

-- OlympusAPI.Register: the handle of a named, installed addon, once a session; nil and why else
-- ("name", "self", "taken", "full", "unknown", "consent").
function API.Register(name)
	if type(name) ~= "string" then return nil, "name" end
	name = name:match("^%s*(.-)%s*$")
	if name == "" or #name > 64 or name:find("[%c|]") then return nil, "name" end
	local key = ns.Fold(name)
	if key == "olympus" or key == "olympus_arena" then return nil, "self" end
	if clients[key] then return nil, "taken" end
	if #order >= API.MAX_ADDONS then return nil, "full" end
	local title = Installed(name)
	if not title then return nil, "unknown" end
	local c = NewClient(name, key, title, #order + 1)
	if not Line(c) then return nil, "consent" end
	clients[key] = c
	order[#order + 1] = c
	ns.Log("api: %s registered (%s)", name, Status(c))
	return c.handle
end

-- What this build gives: a feature ("wanted", "rankings", "rankings.<kind>", "profile", "leader",
-- "callbacks", "network.sightings", "network.sightings.area-scope", "presence.quiet", "ui.guild-tools", "ui.surface",
-- and 1.4.0's "groups", "groups.manage", "ui.board-groups" and "unit.member") or an event's name.
local function SightingsComplete()
	for _, fn in ipairs({ "Start", "Cancel", "Session", "StartArea", "CancelArea", "AreaSession" }) do
		if not Has("PlayerSightings", fn) then return false end
	end
	return true
end
local FEATURES = {
	wanted = function() return Has("Wanted", "Targets") end,
	rankings = function() return true end,
	["rankings.slayers"] = function() return Has("Wanted", "Rankings") end,
	["rankings.donors"] = function() return Has("HonorsNet", "Donors") end,
	["rankings.church"] = function() return Has("HonorsNet", "ChurchTop") end,
	["rankings.games"] = function() return Has("ArenaHome", "RankingsPublic") end,
	profile = function() return true end,
	["unit.member"] = function() return type(ns.IsFederation) == "function" end,
	leader = function() return Has("Hop", "King") and Has("King", "Location") and Has("Layers", "ForMap") end,
	callbacks = function() return true end,
	["network.sightings"] = SightingsComplete,
	["network.sightings.area-scope"] = function()
		if not SightingsComplete() then return false end
		local scopes = ns.PlayerSightings.AREA_SCOPES
		return type(scopes) == "table" and scopes.outsiders == true
	end,
	["network.profile-effects"] = function()
		for _, fn in ipairs({ "OpenSession", "CloseSession", "Set", "DisableOwner", "Session" }) do
			if not Has("ProfileEffects", fn) then return false end
		end
		return true
	end,
	["presence.quiet"] = function()
		return type(ns.SetQuietPresence) == "function" and type(ns.QuietPresenceState) == "function"
			and type(ns.QuietPresenceOwnedBy) == "function"
	end,
	["ui.guild-tools"] = function()
		return Has("UI", "SelectTab") and Has("Watch", "Show") and Has("Watch", "PageId")
			and Has("Watch", "OpenMember")
	end,
	["ui.surface"] = function()
		for _, fn in ipairs({ "RegisterAPISurface", "OpenAPISurface", "ToggleAPISurface", "RefreshAPISurface", "IsAPISurfaceOpen" }) do
			if not Has("UI", fn) then return false end
		end
		return true
	end,
	groups = HasGroups,
	["groups.manage"] = HasManage,
	["ui.board-groups"] = function()
		for _, fn in ipairs({ "RegisterPanel", "UnregisterPanel", "PanelShown", "PanelLines", "DrawPanel" }) do
			if not Has("Groups", fn) then return false end
		end
		return Has("Views", "Render")
	end,
}
for _, e in ipairs(API.EVENTS) do FEATURES[e] = FEATURES.callbacks end
function API.Has(feature)
	local fn = type(feature) == "string" and FEATURES[feature]
	if not fn then return false end
	local ok, yes = pcall(fn)
	return ok and yes == true
end

---------------------------------------------------------------------------
-- The global other addons see: OlympusAPI.VERSION, .Has, .Register (read-only)
---------------------------------------------------------------------------

local public = { VERSION = API.VERSION, SURFACE_LIMIT = API.SURFACE_LIMIT, Has = API.Has, Register = API.Register }
OlympusAPI = setmetatable({}, { __index = public, __newindex = ReadOnly, __metatable = false })

---------------------------------------------------------------------------
-- What tells of a change (Olympus's own events: none of the game's)
---------------------------------------------------------------------------

-- Wanted's list and its Slayers boards (and the signed top three).
ns.On("WANTED_CHANGED", function() Mark("WANTED_CHANGED", "RANKINGS_CHANGED") end)
-- An honour, a pick (the profile's frame and title), the donors' word (HonorsNet).
ns.On("HONORS_CHANGED", function() Mark("RANKINGS_CHANGED", "PROFILE_CHANGED") end)
-- The Church's top three, or its public ranking's switch.
ns.On("CHURCH_TOP_CHANGED", function() Mark("RANKINGS_CHANGED") end)
ns.On("CHURCH_PUBLIC_CHANGED", function() Mark("RANKINGS_CHANGED") end)
-- The King's switch of the Treasury's ranking, which the donors' top three follow (looked at only
-- when it turned: the treasury changes often, and nothing else of it is read here).
local rankingShown
ns.On("TREASURY_CHANGED", function()
	local shown = Call("Treasury", "PublicShows", "ranking") == true
	if shown ~= rankingShown then
		rankingShown = shown
		Mark("RANKINGS_CHANGED")
	end
end)
-- The games: a result, a ranking made public or kept to the staff (ArenaRoles: Arena.Changed).
ns.On("ARENA_CHANGED", function() Mark("RANKINGS_CHANGED") end)
ns.On("LOTTERY_RESULT", function() Mark("RANKINGS_CHANGED") end)
-- A guild joined or left, a rank (Roster.lua: DATA_CHANGED), the signed lists (the role); the census
-- that names the leader online.
ns.On("DATA_CHANGED", function() Mark("PROFILE_CHANGED", "LEADER_CHANGED", "GROUPS_CHANGED", "LOOKING_CHANGED", "MY_GROUP_CHANGED") end)
-- (1.2.5.1) The Olympus Accord accepted or asked again (Accord.lua): every read's answer changed
-- (Member, "guild").
ns.On("ACCORD_CHANGED", function() Mark(unpack(API.DATA_EVENTS)) end)
-- 1.4.0, the Board's groups: a listing, a flag, an application or an answer (BOARD_CHANGED, the Board's
-- and Groups.lua's own), and the player's own group's roster (GROUPS_ROSTER).
ns.On("BOARD_CHANGED", function() Mark("GROUPS_CHANGED", "LOOKING_CHANGED", "MY_GROUP_CHANGED") end)
ns.On("GROUPS_ROSTER", function() Mark("MY_GROUP_CHANGED", "GROUPS_CHANGED") end)
-- The leader's crown, the layers announced, a local layer sighting (HOP_CHANGED) and a sanction on
-- locations (WATCHCHAT_CHANGED): what his lines and the Realm tab's layers show.
for _, event in ipairs({ "KING_LOCATION_CHANGED", "LAYERS_CHANGED", "HOP_CHANGED", "WATCHCHAT_CHANGED" }) do
	ns.On(event, function() Mark("LEADER_CHANGED") end)
end
-- Locations hidden from this player (a sanction: WATCHCHAT_CHANGED; a net-off word: NETOFF_CHANGED),
-- or the Accord asked again: every handle's sighting dots go at once, as the Wanted pins do, not on
-- their next tick.
for _, event in ipairs({ "WATCHCHAT_CHANGED", "NETOFF_CHANGED", "ACCORD_CHANGED" }) do
	ns.On(event, function()
		for _, c in ipairs(order) do
			if (c.pinCount or 0) > 0 and not PinsAllowed(c) then HideSightingPins(c) end
		end
	end)
end
-- A request started by one handle changed or received a fresh, normalized observation. Only the
-- handle that owns that opaque request id is told; the event never exposes another addon's search.
ns.On("PLAYER_SIGHTINGS_CHANGED", function(id) MarkSighting(id) end)
-- The profile module owns the issuer, grant and transport. The public event rebuilds only its
-- sanitized style and remaining lease, including nil when the session closes or expires.
ns.On("PROFILE_EFFECT_SESSION_CHANGED", function() Mark("PROFILE_EFFECT_SESSION_CHANGED") end)
-- The quiet presence turned on or off (Core.lua), by whichever handle.
ns.On("QUIET_PRESENCE_CHANGED", function() Mark("QUIET_PRESENCE_CHANGED") end)
