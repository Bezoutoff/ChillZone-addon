-- Production Data -> Comm chunk queue -> Relay envelopes -> native send API.
local ns, test, eq, extra = ...

test("census scope relay: count snapshots and portable observations drain through the actual relay while revoked capabilities stop", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "ChillZone II", "Member", 3 end
		local O, deliver, sent, _, pump = extra.RelayWorld("Original-Realm", "ChillZone II")
		local relay = O.Relay.Pick()
		deliver("WHISPER", relay .. "-Realm", "RY~")
		O.group, O.faction, O.db = "ForeverPvP", "Alliance", {}
		O.rdb.guilds, O.rdb.seen = {}, {}
		local trusted = true
		O.Church = { IsLedgerRelay = function() return trusted end }
		O.QuietPresence = function() return false end
		assert(loadfile(extra.addon .. "Data.lua"))("ChillZone", O)
		O.rdb.guilds["ChillZone Dawn"] = { total = 640, online = 40, t = O.clock, from = "CAMWOWUS1Realm8PvP" }
		local function Contains(needle, since)
			for i = (since or 0) + 1, #sent do
				if sent[i].msg:find(needle, 1, true) then
					eq(sent[i].dist, "WHISPER"); eq(sent[i].target, relay)
					return true
				end
			end
			return false
		end
		assert(O.Data.SendGlobalCensus())
		pump(100)
		assert(Contains("CG~2~S~"), "accepted global snapshot must actually leave the native whisper API")
		assert(O.Data.RecordGroupCensus())
		O.group = "ForeverPvE" -- a carried PvP observation is sent after travelling to another origin
		assert(O.Data.SayGroupCensus())
		pump(100)
		assert(Contains("CX~3~S~"), "portable observation must leave through the same guarded relay route")
		O.group = "ForeverPvP"
		O.db.groupDetails["Alliance|Other"] = { group = "Other", faction = "Alliance", observed = O.clock,
			rows = { dawn = { name = "ChillZone Dawn", total = 640, online = 40, avg10 = 300, observed = O.clock } } }
		assert(O.Data.SayGroupDetails())
		pump(100)
		assert(Contains("CX~2~S~"), "compatible detail transport also retains its logical channel capability")
		local before = #sent
		assert(O.Data.SendGlobalCensus())
		trusted = false
		pump(100)
		eq(Contains("CG~2~S~", before), false, "losing original trust cancels the queued snapshot")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

local function ScheduledCarry(rejectFirst)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo, random = math.random }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "ChillZone II", "Member", 3 end
		local O, deliver, sent, _, pump = extra.RelayWorld("Carrier-Realm", "ChillZone II")
		local relay = O.Relay.Pick()
		deliver("WHISPER", relay .. "-Realm", "RY~")
		local timers, init, start, stamped = {}, {}, O.clock, 0
		O.group, O.faction, O.db = "ForeverPvE", "Alliance", { blocked = {} }
		O.rdb.guilds, O.rdb.seen = {}, {}
		O.Church = { IsLedgerRelay = function() return false end }
		O.QuietPresence = function() return false end
		O.On = function(event, fn) if event == "INIT" then init[#init + 1] = fn end end
		O.After = function(delay, label, fn)
			if label == "census groups" then timers[#timers + 1] = { at = O.clock + delay, fn = fn } end
		end
		O.Every = function(delay, label, fn)
			if label == "census groups" then timers[#timers + 1] = { at = O.clock + delay, fn = fn, every = delay } end
		end
		assert(loadfile(extra.addon .. "Data.lua"))("ChillZone", O)
		for _, rules in ipairs({ "PvE", "PvP", "RP" }) do
			O.group, O.me = "Forever" .. rules, "Observer" .. rules .. "-Realm"
			O.rdb.guilds = { ["ChillZone " .. rules] = { total = 100, online = 10, t = O.clock - 60,
				from = "CAMWOWUS1Realm1" .. rules } }
			assert(O.Data.RecordGroupCensus())
		end
		O.group, O.me, O.rdb.guilds = "ForeverPvE", "Carrier-Realm", {}
		math.random = function(a, b) return b or a end -- latest allowed first send
		local attempts, refused = {}, 0
		local send = O.Comm.SendChunked
		O.Comm.SendChunked = function(payload, ...)
			if payload:match("^CX~3~") then
				attempts[#attempts + 1] = payload
				if rejectFirst and refused == 0 then refused = 1; return false end
			end
			return send(payload, ...)
		end
		for _, fn in ipairs(init) do fn() end
		local function Advance(to)
			while true do
				table.sort(timers, function(a, b) return a.at < b.at end)
				local t = timers[1]
				if not t or t.at > to then break end
				table.remove(timers, 1); O.clock = t.at; t.fn()
				if t.every then t.at = O.clock + t.every; timers[#timers + 1] = t end
				pump(100)
				for i = stamped + 1, #sent do sent[i].at = O.clock end
				stamped = #sent
			end
			O.clock = to
		end
		Advance(start + 40)
		eq(#attempts, 1, "INIT attempts the first foreign origin within 40 seconds")
		assert(not attempts[1]:find("~ForeverPvE~", 1, true), "the local origin never consumes the first slot")
		Advance(start + (rejectFirst and 170 or 105))
		eq(#attempts, rejectFirst and 3 or 2, "foreign origins drain at 65-second intervals")
		if rejectFirst then eq(attempts[1], attempts[2], "a rejected queue admission does not skip the origin") end
		local last = #attempts
		Advance(start + 1799)
		eq(#attempts, last, "unchanged origins are not repeated within their 30-minute window")
		Advance(start + 2000)
		assert(#attempts > last, "the next bounded window permits a refresh")
		-- Feed actual native packets through the relay into a client that never visited either origin.
		local R, rdeliver, rsent, _, rpump = extra.RelayWorld(relay .. "-Realm", "ChillZone Relay")
		rdeliver("WHISPER", "Late-Realm", "RL~P~RR~ChillZone Late")
		for _, p in ipairs(sent) do
			if p.target == relay and p.at and p.at <= start + 170 and p.msg:find("CX~3~", 1, true) then
				R.clock = p.at; rdeliver("WHISPER", "Carrier-Realm", p.msg); rpump(100)
			end
		end
		local L, ldeliver = extra.RelayWorld("Late-Realm", "ChillZone Late")
		L.group, L.faction, L.db = "ForeverPvE", "Alliance", { blocked = {} }
		L.rdb.guilds, L.rdb.seen = {}, {}
		assert(loadfile(extra.addon .. "Data.lua"))("ChillZone", L)
		L.Comm.Handle("CX", L.Data.ReceiveGroupCensus)
		for _, p in ipairs(rsent) do if p.target == "Late" then ldeliver("WHISPER", R.me, p.msg) end end
		local all = L.Data.Groups()
		eq(#all.rows, 2, "both never-visited origins arrive through the actual relay")
		for _, row in ipairs(all.rows) do
			eq(row.characters, 100); eq(row.observed, start - 60); eq(row.counted, false)
		end
		eq(L.Data.Summary().characters, 0, "foreign observations never change local authority or current census")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo, math.random =
		saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat, saved.random
	if not ok then error(err, 0) end
end

test("census carry schedule: INIT delivers two foreign origins promptly without repeating unchanged observations", function()
	ScheduledCarry(false)
end)
test("census carry schedule: rejected admission retries the same origin before progressing without a send storm", function()
	ScheduledCarry(true)
end)

test("census scope relay: two large ordinary-origin observations cross the same reporter budget as complete atomic aggregates", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "ChillZone II", "Member", 3 end
		local function Census(N)
			N.group, N.faction, N.db = "ForeverPvP", "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = function() return false end }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("ChillZone", N)
			N.Comm.Handle("CX", N.Data.ReceiveGroupCensus)
		end
		local carrier = "Carrier" .. string.rep("x", 70) .. "-Realm"
		local O, odeliver, osent, _, opump = extra.RelayWorld(carrier, "ChillZone II")
		local relay = O.Relay.Pick()
		odeliver("WHISPER", relay .. "-Realm", "RY~")
		Census(O)
		for _, rules in ipairs({ "PvE", "RP" }) do
			O.group, O.me = "Forever" .. rules, "Observer" .. rules .. "-Realm"
			for i = 1, 20 do
				O.rdb.guilds["ChillZone Lengthy Guild " .. i] = { total = 50, online = 10, t = O.clock - 60,
					from = "CAMWOWUS1Realm1" .. rules }
			end
			assert(O.Data.RecordGroupCensus())
			local fullBytes = 0
			for _, guild in ipairs(O.Data.GroupGuilds(O.group)) do fullBytes = fullBytes + #guild.name + 24 end
			assert(fullBytes > 4 * O.Codec.CHUNK, "the full detail source originally exceeds the ordinary trickle")
		end
		O.group, O.me = "ForeverPvP", carrier
		for _ = 1, 2 do
			assert(#O.Data.PortablePayload() <= O.Codec.CHUNK, "complete aggregate and partial detail must fit one logical chunk")
		end
		assert(O.Data.SayGroupCensus()); assert(O.Data.SayGroupCensus()); opump(100)
		local R, rdeliver, rsent, _, rpump = extra.RelayWorld(relay .. "-Realm", "ChillZone Relay")
		Census(R)
		rdeliver("WHISPER", "Late-Realm", "RL~P~RR~ChillZone Late")
		for _, packet in ipairs(osent) do if packet.target == relay then rdeliver("WHISPER", O.me, packet.msg) end end
		rpump(100)
		local L, ldeliver = extra.RelayWorld("Late-Realm", "ChillZone Late")
		Census(L)
		local pieces = 0
		for _, packet in ipairs(rsent) do
			if packet.target == "Late" then pieces = pieces + 1; ldeliver("WHISPER", R.me, packet.msg) end
		end
		eq(pieces, R.Relay.REPORTER_RATE, "both two-envelope origins fit the unchanged four-piece budget")
		local all = L.Data.Groups()
		eq(#all.rows, 2, "the second origin cannot strand the first observation mid-transfer")
		for _, row in ipairs(all.rows) do
			eq(row.characters, 1000); eq(row.guilds, 20); eq(row.observed, O.clock - 60)
			eq(row.counted, false, "carriers do not manufacture authenticated originals")
			assert(#L.Data.GroupGuilds(row.group) < 20, "only explicitly partial guild details fit beside the full aggregate")
		end
		eq(L.Data.Summary().characters, 0)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

test("census scope relay: a multi-part scoped snapshot survives the relay fanout and restores an empty reporter", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "ChillZone II", "Member", 3 end
		local function Census(N)
			N.group, N.faction, N.db = "ForeverPvP", "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = function() return true end }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("ChillZone", N)
			N.Comm.Handle("CG", N.Data.ReceiveGlobalCensus)
		end
		local O, odeliver, osent, _, opump = extra.RelayWorld("Original-Realm", "ChillZone II")
		local relay = O.Relay.Pick()
		odeliver("WHISPER", relay .. "-Realm", "RY~")
		Census(O)
		local total = 0
		for i = 1, 12 do
			O.rdb.guilds["ChillZone Origin Guild " .. i] = { total = 50 + i, online = 10, t = O.clock - 60, from = "CAMWOWUS1Realm8PvP" }
			total = total + 50 + i
		end
		assert(#O.Data.GlobalCensusPayload() > O.Codec.CHUNK, "exercise several independently relayed chunks")
		assert(O.Data.SendGlobalCensus()); opump(100)
		local R, rdeliver, rsent, _, rpump = extra.RelayWorld(relay .. "-Realm", "ChillZone Relay")
		Census(R)
		for _, packet in ipairs(osent) do
			if packet.target == relay then rdeliver("WHISPER", O.me, packet.msg) end
		end
		eq(R.Data.Summary().characters, total, "the receiving relay assembles every original count")
		rdeliver("WHISPER", "Late-Realm", "RL~P~RR~ChillZone Late")
		assert(R.Data.SendGlobalCensus()); rpump(100)
		local L, ldeliver = extra.RelayWorld("Late-Realm", "ChillZone Late")
		Census(L)
		L.Comm.loginAt = L.clock
		for _, packet in ipairs(rsent) do
			if packet.target == "Late" then ldeliver("WHISPER", R.me, packet.msg) end
		end
		eq(L.Data.Summary().characters, total, "all parts reach the reporter before any local rebuild")
		eq(#L.Data.Summary().guilds, 12); eq(next(L.rdb.guilds), nil)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)
