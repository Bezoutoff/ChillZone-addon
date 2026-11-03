-- 1.3.4: the launch identities. On a launch realm group the King, the Treasurer and the author are
-- whom the author's signed titles list names (Core.lua: ns.ReadPins, ns.SignedPins), never a name in
-- the code; the code's pins stay the beta's. Also ns.RealmInfo, the author's rotation of the army's
-- key (Keys.lua) and the channel's protected names (Comm.lua). Invented names only.
-- A throwaway key made with scripts/council-sign.py for these tests (its private half was not kept)
-- signed these titles lists, each naming Test Councillor (Council Speaker) outside any department:
--   OLD         realm group "Realm" (the harness's): nothing else, a list as before 1.3.4
--   REALM_PINS  "Realm": Other Crown-Realm the Alliance King, Other Coin-Realm its Treasurer
--   LAUNCH_A    "Launchrealm+Launchtwo": a Steward and an approved guild as before 1.3.4, then
--               Crown Owl-Launchrealm the Alliance King, Tusk Crown-Launchrealm the Horde's, Ledger
--               Wren-Launchrealm the Alliance Treasurer with Ledger Post-Launchrealm his mail
--               character, Quill Maker-Launchrealm (Alliance) and Quill Horde-Launchrealm (Horde) the
--               author's characters, Launchrealm a PvP realm of NA and Launchtwo an RP-PvP one of EU
--   LAUNCH_B    newer, the same group: the Treasurer and Launchrealm alone (no King, no author)
--   FAR         "Farrealm": Crown Owl-Farrealm the Alliance King, Quill Maker-Farrealm the author
local ns, test, eq, h = ...
local L = ns.L

local KEY_N = "f5cbbb0c181b3ebb169b825e0597ef6df8a7b9227f8cce0a7bde42a97c396edbf831cf6b3a7e406b2a8ab0a78c07a4476b0b07f6978be53e4273edda5df30051f3e4dd2d85ea7ae980e96b89bf38018c252dbe11cbf1691fb5bc73f33e8bca69e01f6fba9f36055fdc220343ad18e4a084db4d8fda79781afe3a2c940e1b8a9997975c547388bb6012b6e0b3278344ab9d841a5d147c5fcc6bf090fb908aec56fd300988923e73a38c55d3055c0e9d7fda27080909d5b65f0e76ed6e6dafa8c18877b1eda86b395a278f663f1966f9c181bc8038306ac3c2e40b59322cc0b4042ebed9f37daea35b09f1c91e14218d556c617db67458c0003f56dfc7d3de89ab"
local KEY_MU = "10aa0b7a25d7c910dd40aa3303aaedd1a76109f0f8c7110fb1151cdb1bd9f897c521fa8875c6a5d0a32088943ac911848e8342024200c44b18584fd0d927d499208f1f533570e339f5959f4c352eac59f5a4829635039f4f77002160407c2f1abd1b6fadf1a18a5286dfb267b0f1b1e7e2e90d7d0241b8ac4cc01ff88e25c7984ffc6d05542c0849994e7241c804d2fb98c36cee65b206702bda1bd8804b99944598c1d068e86fad948250c8c829e41afe42e6090a59820e94d5554eb4958ba9c8096084b245e2a73ef096dcc944717c2df4ef1089d06e23f30e0ca6f8cbb6a1ed79fb063365c6f0c7af9108afb13b887228b586874522e211854c1ed2d51173b37f36906"
local OLD = "HT1~1793722474~Realm~0~^^Test Councillor=Council Speaker~d6eabd41b7eccdfa67793892310a8ec0f870dfc282eaa10dd2b79a02c8eeee9fd02e0f1e8666135f6a3b4f242d701baae1cc6c1588259504b3106196e36c97de9977cc21c666685b8d87dc773aa255cfaae860512b67bd461ce4c1112f978246c92124a1a128a03bced94db093bcb26f1382074a430f244566ae6f448521310328c4387595b74ca12a35e8e60fd444aa7d6f38fbdd58d22ee36bba2db9f8b7826f15bef1adadd75aa8ed7098348eb4eb6b26d4bf3785f69f144ea6f7c8b57c494b6b1f8605cc07fdfb8f48d56790db4e09874165409bcaf5b658f5e27cc8f10f5bc71a1dce11c2dfa4e004b7474d99ba1b797ff49789b1094ad53983eb63d212"
local REALM_PINS = "HT1~1793722476~Realm~0~^^Test Councillor=Council Speaker;^king^Alliance^Other Crown-Realm;^treasurer^Alliance^Other Coin-Realm~ba368a77ed11f7b28686420e46f10eeca42f83f593be2316bb407c4bc45bf458b588ab9e242fef3185c6072ce77939051bcf083a3d205d1fe9b981cc3cac41e41769ffed59def32f9f1b5504a8d3dc43dbb3553fed7d1b18251967ccc043658e6971115dc9a22755dff84a10d50ec49b797e885516710e1a6d932ff4ff9bef9850957ec64d64d7b6aaaf1d4e93454a3e4f50344df8a31051badf0156bd894f0789edca1584ce68a8d06ac811a13eb50ef35b872a65d29d0d6676b0dcb6031672ace8585a2d0aea69ec1a2d300bf941e026030e49354ba3027215f53b24ac0b5143448a7ac45972f716fd24b116d2d98ed4b5273cd0da3369fa3112a453ff2cee"
local LAUNCH_A = "HT1~1793722478~Launchrealm+Launchtwo~0~^^Test Councillor=Council Speaker;^steward^Alliance^Hand Steward-Launchrealm;^guilds^Alliance^Owl Legion;^king^Alliance^Crown Owl-Launchrealm;^king^Horde^Tusk Crown-Launchrealm;^treasurer^Alliance^Ledger Wren-Launchrealm,Ledger Post-Launchrealm;^author^Alliance^Quill Maker-Launchrealm;^author^Horde^Quill Horde-Launchrealm;^realms^NA^Launchrealm=pvp;^realms^EU^Launchtwo=rppvp~8f2c11c6809e5a2f2f1e9bc0fb30d2f87e8e6f8a56e7a28f75cfee3097602efdb9fb9eeb0f2f250e37bf97971811ef8182c8d981633fd21c0dc2d4a28fa597fa7458845cde7ee8839093ca8ca642798ad51a757c779c8b063d6505e657ba6964d0c45f42219637c4c80401cf270ce164c245d1e78464acd9a3fd7bffb263aae208bbea9152b15bae1d9c3f519182a38cc6ec6e22f7cdb42d039e25ca4577163d509bd1aece3a85bbceac8e8521a8d8fe20c6099dbd24f10b2b43ef4df9c378cdd8798b7d378a83c120f6b34e3467d31ba08f7b1b141a472bcca733ed181c0f40c4c64ad695ca245e81f6fdbf8e8e3b75b3804233b4884f1759212d7d1806b85b"
local LAUNCH_B = "HT1~1793722480~Launchrealm+Launchtwo~0~^^Test Councillor=Council Speaker;^treasurer^Alliance^Ledger Wren-Launchrealm,Ledger Post-Launchrealm;^realms^NA^Launchrealm=pvp~3bdc078aa3460f718dbf9a14e523655a500e072295a4263f61d2679318f84e5e00b90c78e723bc7595faa2346f57dd8c9ca6214f90df71c12efbfccfecf47e6a161a182ae0427b40c8ea987c1bab3f4caf0d7575606beaf1ac7103fec84cf5d2eb05401869140d43578cc1f115fcea7da598cedbf5dc2bdb25cc398f70971c9a2281b65fa5518393457a254a0c8305421bee3d4436675ecba83487db425a47e80d8c88ac240c8742dabea57bb674242480c6983e85c6f32969526cc4df59349bc4de522e3caf75197b029b23dd822dea42d96517aa621cb38bc4cac4a7e701bb86b36634275a4be279ea33a04ec7387a3ab13be5da55c3f04c3b44a215af75bc"
local FAR = "HT1~1793722482~Farrealm~0~^^Test Councillor=Council Speaker;^king^Alliance^Crown Owl-Farrealm;^author^Alliance^Quill Maker-Farrealm~c28cf7f9afcbd89d9030d05dc7e708019cedd63c8f30209d7d32b71372bd3657eb14d3900d16673e282dfd9c2d2508ae68266c2435c60e5c28e61f1d5fb03a13ef141dec58fa8f66c3ad6b0286d32e69e2f42c5a39249e956c87a9e5fc93c4556bbfb7aec477967fe7d8d0f9aaf9ee620b6087f6a8cfa3819b0f4e3a80915e5d53ac4ee542572534b26b7cefdfbdfd6a932d74c361875294f13ab2cae165b8c803de6daccdfad212a492244c34ad80b09b5d47f1fcd9ac1c684c1961630ed3bd5bbb9d729a343904c2cf05580789d27a7eee0ca255fcda1e6b3b37101a045c963ed1b91b1544184d25a6585d4176a3695478989f034922f2d1c8e9be36be69a2"

local AUTHOR, KING, TREASURER, MAIL = "Quill Maker-Launchrealm", "Crown Owl-Launchrealm", "Ledger Wren-Launchrealm", "Ledger Post-Launchrealm"

if not ns.Keys then assert(loadfile(h.ADDON_DIR .. "Keys.lua"))("Olympus", ns) end

-- The test key in place of the author's while fn runs (a list's signature is checked then).
local function Signed(fn) ns.Sign.WithKey(KEY_N, KEY_MU, 86, fn) end

-- This client on `realm` (its own realm group), of `faction`, holding `blob` (nil: no titles list);
-- every store it touches put back after.
local function WithWorld(realm, faction, blob, fn)
	local saved = { realm = ns.realm, group = ns.group, me = ns.me, faction = ns.faction, titles = ns.rdb.councilTitles,
		council = ns.rdb.council, kingRealmHorde = ns.rdb.kingRealmHorde, guild = GetGuildInfo, print = ns.Print }
	local ok, err = pcall(function()
		ns.realm, ns.group, ns.faction = realm, realm, faction or "Alliance"
		ns.me = "Some Body-" .. realm
		ns.rdb.councilTitles, ns.rdb.kingRealmHorde = nil, nil
		ns.Workshop.ResetVerify()
		ns.Print = function() end
		if blob then Signed(function() assert(ns.Workshop.TakeTitles(blob), "the test key's list") end) end
		fn()
	end)
	ns.realm, ns.group, ns.me, ns.faction = saved.realm, saved.group, saved.me, saved.faction
	ns.rdb.councilTitles, ns.rdb.council, ns.rdb.kingRealmHorde = saved.titles, saved.council, saved.kingRealmHorde
	GetGuildInfo, ns.Print = saved.guild, saved.print
	ns.Workshop.ResetVerify()
	if not ok then error(err, 0) end
end

test("1.3.4 launch identities: on a launch realm group the signed list names the King, the Treasurer and the author; namesakes elsewhere and the code's beta pins are nobody there", function()
	WithWorld("Launchrealm", "Alliance", LAUNCH_A, function()
		-- The King of our side, on his realm group alone.
		eq(ns.KingCharacter(), "Crown Owl"); eq(ns.KingRealm(), "Launchrealm"); eq((ns.KingFullName()), KING)
		eq(ns.IsKingCharacter(KING), true); eq(ns.IsKingCharacter("Crown Owl"), true, "a name without a realm is ours")
		eq(ns.IsKingCharacter("Crown Owl-Launchtwo"), false, "a namesake on another realm group")
		eq(ns.IsKingCharacter(ns.KING_CHARACTER.Alliance .. "-Launchrealm"), false, "the code's King is the beta's")
		-- The Treasurer (in the guild Olympus alone) and his mail character (any guild).
		eq(ns.TreasurerFull(), TREASURER); eq(ns.TreasurerName(), "Ledger Wren"); eq(ns.TreasurerRealm(), "Launchrealm")
		eq(ns.IsTreasurer(TREASURER, "Olympus"), true); eq(ns.IsTreasurer(TREASURER, "Olympus II"), false)
		eq(ns.IsTreasurer("Ledger Wren-Launchtwo", "Olympus"), false, "a namesake on another realm group")
		eq(ns.IsTreasurer(ns.TREASURER .. "-Launchrealm", "Olympus"), false, "the code's Treasurer is the beta's")
		eq(ns.IsTreasurerMail(MAIL), true); eq(ns.IsTreasurerMail(TREASURER), false)
		eq(ns.IsTreasurerCharacter(MAIL), true); eq(ns.IsTreasurerCharacter(TREASURER), true)
		eq(ns.IsTreasurerCharacter("Ledger Post-Launchtwo"), false)
		eq(ns.Treasury.TreasurerPin(TREASURER), 1); eq(ns.Treasury.TreasurerPin("ledger post-Launchrealm"), 2, "whatever the case of the name")
		eq(ns.Dues.MailTo(), MAIL, "the dues' mail goes to his mail character")
		-- The author's characters, both sides' (a name is one per realm group whatever the side).
		local W = ns.Workshop
		eq(W.IsAuthorName(AUTHOR), true); eq(W.IsAuthorName("Quill Horde-Launchrealm"), true)
		eq(W.IsAuthorName("Quill Maker-Launchtwo"), false, "a namesake on another realm group")
		eq(W.IsAuthorName(ns.AUTHOR .. "-" .. ns.AUTHOR_REALM), false, "the code's author is no author where the list names his characters")
		eq(W.IsAuthor(), false)
		ns.me = AUTHOR
		eq(W.IsAuthor(), true, "his own client")
		-- ...the dev alone: never the King, a councillor or a Steward.
		eq(ns.IsKingCharacter(AUTHOR), false); eq(ns.IsHighCouncillor(AUTHOR), false); eq(ns.IsSteward(AUTHOR), false)
		-- The Horde's King, from the same list; no Horde Treasurer named: the code's, on the beta's group alone.
		ns.faction = "Horde"
		eq(ns.KingCharacter(), "Tusk Crown"); eq(ns.IsKingCharacter("Tusk Crown-Launchrealm"), true)
		eq(ns.IsKingCharacter(KING), false, "the Alliance's King is not the Horde's")
		eq(ns.TreasurerRealm(), ns.TREASURER_REALM)
		eq(ns.IsTreasurer(TREASURER, "Olympus"), false)
		eq(W.IsAuthorName(AUTHOR), true, "the author's characters whatever our side")
		-- /oly status: where each comes from, no name.
		ns.faction = "Alliance"
		local status = ns.PinsStatus()
		assert(status:find("King signed", 1, true) and status:find("Treasurer signed (2)", 1, true)
			and status:find("author signed (2, this character: yes)", 1, true) and status:find("realms 2", 1, true), status)
		assert(not status:find("Crown Owl", 1, true) and not status:find("Ledger", 1, true) and not status:find("Quill", 1, true), status)
	end)
	-- On the other realm group the list names: the same list, another King's realm: nobody there.
	WithWorld("Launchtwo", "Alliance", LAUNCH_A, function()
		eq(ns.KingCharacter(), nil, "the King is of Launchrealm's group")
		eq(ns.IsKingCharacter("Crown Owl-Launchtwo"), false)
		eq(ns.KingUnpinned(), false, "the list reaches here: no guild master stands for him")
		eq(ns.Workshop.IsAuthorName(AUTHOR), true, "his character, as anyone may name it")
		eq(ns.Workshop.IsAuthorName("Quill Maker-Launchtwo"), false)
	end)
end)

test("1.3.4 launch identities: an unsigned, changed or other realm group's list names nobody; nor does a list we hold once we are elsewhere", function()
	WithWorld("Launchrealm", "Alliance", nil, function()
		local W = ns.Workshop
		local text, sig = LAUNCH_A:match("^(.*)~(%x+)$")
		Signed(function()
			eq(W.TakeTitles(text .. "~" .. ("ab"):rep(256), "Relay1-Launchrealm"), false, "unsigned")
			eq(W.TakeTitles((text:gsub("Crown Owl", "Fake Owl")) .. "~" .. sig, "Relay2-Launchrealm"), false, "a name changed")
			eq(W.TakeTitles((text:gsub("Quill Maker", "Quill Faker")) .. "~" .. sig, "Relay3-Launchrealm"), false, "the author changed")
			eq(W.TakeTitles(FAR, "Relay4-Launchrealm"), false, "another realm group's")
		end)
		eq(ns.rdb.councilTitles, nil)
		eq(ns.KingCharacter(), nil); eq(ns.IsKingCharacter("Fake Owl-Launchrealm"), false)
		eq(W.IsAuthorName("Quill Faker-Launchrealm"), false); eq(W.IsAuthorName(AUTHOR), false)
		eq(ns.TreasurerRealm(), ns.TREASURER_REALM, "no Treasurer here but the code's, the beta's")
		eq(ns.KingUnpinned(), true, "no list here at all: as wherever no King was pinned before")
		eq(ns.RealmInfo("Launchrealm"), nil)
	end)
	WithWorld("Farrealm", "Alliance", FAR, function()
		eq(ns.KingCharacter(), "Crown Owl"); eq(ns.IsKingCharacter("Crown Owl-Farrealm"), true)
		eq(ns.Workshop.IsAuthorName("Quill Maker-Farrealm"), true)
		-- The same saved list, our character now on another realm group: not ours, nobody's.
		ns.realm, ns.group, ns.me = "Launchrealm", "Launchrealm", "Some Body-Launchrealm"
		eq(ns.CouncilTitles(), nil)
		eq(ns.KingCharacter(), nil); eq(ns.IsKingCharacter("Crown Owl-Launchrealm"), false)
		eq(ns.Workshop.IsAuthorName("Quill Maker-Launchrealm"), false)
	end)
end)

test("1.3.4 launch identities: the code's pins keep working on their own realm group; a signed list there names others in their place", function()
	-- (The harness pins the code's King and Treasurer on "Realm"; the code's author is on the beta's.)
	WithWorld("Realm", "Alliance", OLD, function()
		eq(ns.KingCharacter(), ns.KING_CHARACTER.Alliance)
		eq(ns.IsKingCharacter(ns.KING_CHARACTER.Alliance .. "-Realm"), true)
		eq(ns.IsTreasurer(ns.TREASURER .. "-Realm", "Olympus"), true)
		eq(ns.TreasurerFull(), ns.TREASURER .. "-Realm")
		eq(ns.Workshop.IsAuthorName(ns.AUTHOR .. "-" .. ns.AUTHOR_REALM), true)
		local status = ns.PinsStatus()
		assert(status:find("King code", 1, true) and status:find("author code (1", 1, true), status)
	end)
	WithWorld("Realm", "Alliance", REALM_PINS, function()
		eq(ns.KingCharacter(), "Other Crown")
		eq(ns.IsKingCharacter("Other Crown-Realm"), true)
		eq(ns.IsKingCharacter(ns.KING_CHARACTER.Alliance .. "-Realm"), false, "the signed King in the code's place")
		eq(ns.IsTreasurer("Other Coin-Realm", "Olympus"), true)
		eq(ns.IsTreasurer(ns.TREASURER .. "-Realm", "Olympus"), false, "the signed Treasurer in the code's place")
		eq(ns.IsTreasurerMail(ns.TREASURER_CHARACTERS[2] .. "-Realm"), false, "his mail character with him")
		eq(ns.Dues.MailTo(), "Other Coin-Realm", "no mail character signed: the Treasurer himself")
		eq(ns.Workshop.IsAuthorName(ns.AUTHOR .. "-" .. ns.AUTHOR_REALM), true, "no author's character signed: the code's")
	end)
end)

-- (A regression: the code's Horde King, his realm not known, counted on every realm group, so a
-- namesake on a launch realm would have been the Horde's King there, the author's list or not.)
test("1.3.4 launch identities: the code's Horde King, his realm not known, is nobody's King where the author's launch list reaches another realm group; his realm is still learned on his own", function()
	-- (REALM_PINS: a launch list for the code's own realm group, naming no Horde King.)
	WithWorld("Realm", "Horde", REALM_PINS, function()
		local pin = ns.KING_CHARACTER.Horde
		eq(ns.KingCharacter(), pin)
		eq(ns.IsKingCharacter(pin .. "-Realm"), true)
		eq(ns.IsKingCharacter(pin .. "-Launchrealm"), false, "a namesake on another realm group")
		ns.LearnKingRealm(pin .. "-Realm")
		eq(ns.rdb.kingRealmHorde, "Realm", "learned from his first message")
		eq(ns.KingRealm(), "Realm")
	end)
	WithWorld("Launchrealm", "Horde", LAUNCH_B, function()
		eq(ns.KingCharacter(), nil, "nobody's King on a launch realm group the list reaches")
		eq(ns.IsKingCharacter(ns.KING_CHARACTER.Horde .. "-Launchrealm"), false)
		ns.LearnKingRealm(ns.KING_CHARACTER.Horde .. "-Launchrealm")
		eq(ns.rdb.kingRealmHorde, nil, "no realm learned from a namesake")
		eq(ns.KingUnpinned(), false, "nor its guild master")
	end)
	-- Before a launch list reaches a realm group, as before 1.3.4 (his name anywhere, until his realm
	-- is learned); a list of before 1.3.4 is no launch list.
	WithWorld("Launchrealm", "Horde", nil, function()
		eq(ns.IsKingCharacter(ns.KING_CHARACTER.Horde .. "-Launchrealm"), true)
	end)
	WithWorld("Realm", "Horde", OLD, function()
		eq(ns.LaunchListHeld(), false)
		eq(ns.IsKingCharacter(ns.KING_CHARACTER.Horde .. "-Launchrealm"), true)
	end)
end)

-- (A regression: where no King was pinned, the guild master of a guild of the King's guild's name was
-- the King, as on a launch realm group whoever founds <Olympus> first.)
test("1.3.4 launch identities: where the signed list reaches and names no King for our side, the guild master of the King's guild is not the King", function()
	local function AsMaster(name)
		GetGuildInfo = function() return "Olympus", "Guild Master", 0 end
		ns.me = name
	end
	WithWorld("Launchrealm", "Alliance", LAUNCH_B, function()
		AsMaster("First Founder-Launchrealm")
		eq(ns.King.IsKing(), false, "founding the guild makes nobody King")
		eq(ns.KingCharacter(), nil); eq(ns.KingUnpinned(), false)
	end)
	WithWorld("Launchrealm", "Alliance", LAUNCH_A, function()
		AsMaster("First Founder-Launchrealm")
		eq(ns.King.IsKing(), false, "not the King the list names")
		AsMaster(KING)
		eq(ns.King.IsKing(), true, "the King the list names, guild master of his guild")
	end)
	-- Where no list reaches (no King pinned and nothing signed for that realm group): as before.
	WithWorld("Launchrealm", "Alliance", nil, function()
		AsMaster("First Founder-Launchrealm")
		eq(ns.KingUnpinned(), true); eq(ns.King.IsKing(), true)
	end)
end)

test("1.3.4 launch identities: ns.RealmInfo reads the signed realms; anything the grammar leaves out is refused", function()
	WithWorld("Launchrealm", "Alliance", LAUNCH_A, function()
		local info = ns.RealmInfo("Launchrealm")
		eq(info.kind, "pvp"); eq(info.region, "NA")
		eq(ns.RealmInfo("launchrealm").kind, "pvp", "whatever its case")
		eq(ns.RealmInfo("Launch realm").region, "NA", "as the game shows it, its spaces left out")
		eq(ns.RealmInfo("Launchtwo").kind, "rppvp"); eq(ns.RealmInfo("Launchtwo").region, "EU")
		eq(ns.RealmInfo("Nowhere"), nil); eq(ns.RealmInfo(nil), nil); eq(ns.RealmInfo(42), nil); eq(ns.RealmInfo(""), nil)
		info.kind = "changed"
		eq(ns.RealmInfo("Launchrealm").kind, "pvp", "a copy: the list's own stays")
	end)
	WithWorld("Launchrealm", "Alliance", LAUNCH_B, function()
		eq(ns.RealmInfo("Launchtwo"), nil, "a newer list without it")
	end)
	local p = ns.ReadPins(table.concat({
		"^realms^OCE^Faraway=pvp", "^realms^NA^Good=pvp,Bad Space=pvp,Wrong=pvp2,Upper=PVP,Kel'thas=hardcore,Good=pve,"
			.. ("x"):rep(41) .. "=pve", "^realms^EU^Other=rp",
		"^king^Alliance^No Realm", "^king^Neutral^Side Less-Realm", "^king^Horde^First King-Realm,Second King-Realm",
		"^treasurer^Alliance^A Aa-R,B Bb-R,C Cc-R,D Dd-R,E Ee-R", "^treasurer^Horde^Bad-Name-R",
		"^author^Alliance^Three Word Name-R,Digit5 Name-R,Fine Name-R,fine name-R", "^author^Horde^",
		"Department of War^^Test Councillor=Speaker", "^steward^Alliance^Test Steward-R",
	}, ";"))
	eq(p.realms.good.kind, "pvp", "the first of a realm named twice"); eq(p.realms.good.region, "NA")
	eq(p.realms["kel'thas"].kind, "hardcore"); eq(p.realms.other.region, "EU")
	eq(p.realms.faraway, nil, "no such region"); eq(p.realms["bad space"], nil); eq(p.realms.wrong, nil, "no such kind")
	eq(p.realms.upper, nil, "kinds in lower case"); eq(p.realms[("x"):rep(41)], nil, "a realm over 40 bytes")
	eq(p.king.Alliance, nil, "a name without its realm"); eq(p.king.Neutral, nil)
	eq(#p.king.Horde, 1, "one King a side"); eq(p.king.Horde[1], "First King-Realm")
	eq(#p.treasurer.Alliance, 4, "the Treasurer and three mail characters at most"); eq(p.treasurer.Alliance[1], "A Aa-R")
	eq(p.treasurer.Horde, nil); eq(p.author.Horde, nil)
	eq(#p.author.Alliance, 1); eq(p.author.Alliance[1], "Fine Name-R", "once, whatever the case")
	-- The older entries are read by their own readers, as before (and the new ones are left out by them).
	eq(ns.ReadStewards("^steward^Alliance^Test Steward-R;^king^Alliance^Crown Owl-R").Alliance[1], "Test Steward-R")
	eq(ns.ReadStewards("^king^Alliance^Crown Owl-R;^author^Alliance^Quill Maker-R").Alliance, nil)
	eq(ns.ReadApprovedGuilds("^realms^NA^Good=pvp;^king^Alliance^Crown Owl-R").Alliance, nil)
end)

test("1.3.4 launch identities: a launch list is taken, shown and passed on as before: its departments, Steward and approved guilds unchanged, its text byte for byte", function()
	WithWorld("Launchrealm", "Alliance", LAUNCH_A, function()
		local t = ns.rdb.councilTitles
		eq(#t.depts, 1, "the new entries are no department (clients before 1.3.4 read the same)")
		eq(t.depts[1].name, ""); eq(#t.depts[1].members, 1); eq(t.depts[1].members[1].name, "Test Councillor")
		eq(ns.Stewards()[1], "Hand Steward-Launchrealm"); eq(ns.IsSteward("Hand Steward-Launchrealm"), true)
		local approved = false
		for _, g in ipairs(ns.ApprovedGuilds()) do if g == "Owl Legion" then approved = true end end
		eq(approved, true)
		eq(t.blob, LAUNCH_A, "kept as signed: relayed byte for byte")
		-- Pasted in (/oly approved paste), a newer one replaces it at once.
		local W = ns.Workshop
		local relays, savedCouncil, savedGuild = 0, W.RelayCouncil, W.RelayGuild
		W.RelayCouncil = function() relays = relays + 1 end
		W.RelayGuild = function() relays = relays + 1 end
		local ok, err = pcall(function() Signed(function() eq(W.PasteTitles(LAUNCH_B), true) end) end)
		W.RelayCouncil, W.RelayGuild = savedCouncil, savedGuild
		if not ok then error(err, 0) end
		eq(ns.rdb.councilTitles.blob, LAUNCH_B)
		eq(ns.KingCharacter(), nil, "the newer list names no King: none")
		eq(ns.Workshop.IsAuthorName(AUTHOR), false, "nor the author's characters")
		eq(ns.TreasurerFull(), TREASURER)
	end)
end)

---------------------------------------------------------------------------
-- The army's key (Keys.lua): the author rotates it and hands it out, never as the King or a Steward.
---------------------------------------------------------------------------

local KY = ns.Keys
local function WithKeys(fn)
	h.WithThrone(function(w, K)
		WithWorld("Launchrealm", "Alliance", LAUNCH_A, function()
			local saved = { key = ns.rdb.realmKey, epoch = ns.rdb.keyEpoch, rot = ns.rdb.keyRotation, retired = ns.rdb.keyRetired,
				join = ns.Comm.JoinChannel, seen = ns.rdb.seen, role = ns.ViewAs.Role() }
			local ok, err = pcall(function()
				ns.rdb.realmKey, ns.rdb.keyEpoch, ns.rdb.keyRotation, ns.rdb.keyRetired = nil, nil, nil, nil
				ns.Print = function(m) w.printed[#w.printed + 1] = tostring(m) end -- (the Throne's record, as WithThrone has it)
				KY.Reset()
				w.joined = 0
				ns.Comm.JoinChannel = function() w.joined = w.joined + 1 end
				ns.rdb.seen = { ["Olympus Zeus"] = { online = 5, t = w.clock } }
				ns.rdb.guilds["Olympus Zeus"] = h.Vouched({ total = 100, online = 9, zones = {}, t = w.clock, leader = "Zed",
					leaderOnline = true, realm = "Launchrealm", officers = { { name = "Zeus Cap", online = true, days = 0 } } },
					"W3-Launchrealm", "W4-Launchrealm")
				fn(w, K)
			end)
			ns.rdb.realmKey, ns.rdb.keyEpoch, ns.rdb.keyRotation, ns.rdb.keyRetired = saved.key, saved.epoch, saved.rot, saved.retired
			ns.Comm.JoinChannel, ns.rdb.seen = saved.join, saved.seen
			ns.ViewAs.Set(saved.role)
			KY.Reset()
			if not ok then error(err, 0) end
		end)
	end)
end
local function AsMember(name) GetGuildInfo = function() return "Olympus II", "Member", 3 end; ns.me = name end
local function Printed(w, text)
	for _, p in ipairs(w.printed) do if p:find(text, 1, true) then return true end end
	return false
end
local function Page(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = tostring(l.text) end
	return table.concat(out, "\n")
end

test("1.3.4 the army's key: the author rotates it and hands it out to the Lords and Captains his /who saw, by whisper; anyone else cannot", function()
	WithKeys(function(w, K)
		AsMember("Some Soldier-Launchrealm")
		eq(KY.CanRotate(), false); eq(KY.Rotate(), nil); assert(Printed(w, L.KEY_ROTATE_ONLY_KING))
		-- His own character, neither King nor Steward nor in the King's guild.
		AsMember(AUTHOR)
		eq(K.IsKing(), false); eq(K.IsSteward(), false)
		eq(KY.CanRotate(), true)
		K.Show("home")
		assert(Page((K.Build())):find(L.KEY_ROTATE, 1, true), "on his Throne, in his own view")
		eq(KY.Rotate(), true)
		local rot = KY.Rotation()
		assert(rot and rot.picking and #rot.key == 20, "a new key from his addon")
		eq(#w.whispered, 0, "nothing before he picks")
		KY.Saw("Zed-Launchrealm", "Olympus Zeus") -- (his /who listed the Lord in his guild)
		eq(KY.Start(), true)
		local to = {}
		for _, x in ipairs(w.whispered) do if x.msg:sub(1, 3) == "K3~" then to[#to + 1] = x.to end end
		eq(table.concat(to, ","), "Zed-Launchrealm", "by whisper to the Lord his /who saw")
		for _, x in ipairs(w.sent) do assert(not x.msg:find(rot.key, 1, true), "sent " .. x.dist .. ": " .. x.msg) end
	end)
end)

test("1.3.4 the army's key: a Lord takes the author's whispered key, from his signed character alone", function()
	WithKeys(function(w)
		GetGuildInfo = function() return "Olympus Zeus", "Lord", 0 end
		ns.me = "Zed-Launchrealm"
		local msg = ("K3~%d~authorkey0001"):format(w.clock)
		KY.HandleKey("WHISPER", "Quill Maker-Launchtwo", msg)
		KY.HandleKey("WHISPER", "Some Soldier-Launchrealm", msg)
		KY.HandleKey("WHISPER", ns.AUTHOR .. "-" .. ns.AUTHOR_REALM, msg)
		KY.HandleKey("CHANNEL", AUTHOR, msg)
		eq(ns.rdb.realmKey, nil, "a namesake, anyone else, the code's beta author, the channel: refused")
		KY.HandleKey("WHISPER", AUTHOR, msg)
		eq(ns.rdb.realmKey, "authorkey0001"); eq(KY.Epoch(), w.clock); eq(w.joined, 1)
		local told = false
		for _, x in ipairs(w.whispered) do if x.to == AUTHOR and x.msg:find("^K4~") then told = true end end
		eq(told, true, "the author is told")
	end)
end)

test("1.3.4 the army's key: a preview (Asmon's view, another role's) shows the rotation and starts none; the author's own view starts it", function()
	WithKeys(function(w, K)
		AsMember(AUTHOR)
		eq(ns.ViewAs.Set("king"), true)
		eq(K.Preview(), true); eq(KY.AuthorHere(), false)
		eq(KY.Rotate(), nil); assert(Printed(w, L.THRONE_PREVIEW_NOTE)); eq(KY.Rotation(), nil)
		eq(ns.ViewAs.Set("councillor"), true)
		eq(KY.Rotate(), nil); eq(KY.Rotation(), nil)
		K.Show("home")
		assert(not Page((K.Build())):find(L.KEY_ROTATE, 1, true), "not in another role's preview")
		eq(ns.ViewAs.Set("my"), true)
		eq(KY.AuthorHere(), true); eq(KY.Rotate(), true)
		-- A test build's Asmon's view (not the author's character): nothing.
		KY.Drop()
		ns.me = "Test Build-Launchrealm"
		eq(KY.CanRotate(), false)
	end)
end)

---------------------------------------------------------------------------
-- The channel's protected names (Comm.lua): whoever is banned while our client owns it is let back
-- in, the King, the Treasurer and (1.3.4) the author's characters always.
---------------------------------------------------------------------------

test("1.3.4 channel owner: the author's characters the signed list names are let back in, with its King and Treasurer; never a namesake of another realm group", function()
	local saved = { GetChannelName, JoinChannelByName, LeaveChannelByName, SetChannelPassword, ChannelUnban, ChannelModerate,
		ChannelUnmute, C_ChatInfo, ns.rdb.realmKey, ns.Roster.byName }
	local calls = {}
	local function Rec(what) return function(...) calls[#calls + 1] = what .. " " .. table.concat({ ... }, ",") end end
	local ok, err = pcall(function()
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
		GetChannelName = function() return 5 end
		JoinChannelByName, LeaveChannelByName = Rec("join"), Rec("leave")
		SetChannelPassword, ChannelUnban, ChannelModerate, ChannelUnmute = Rec("password"), Rec("unban"), Rec("moderate"), Rec("unmute")
		ns.rdb.realmKey, ns.Roster.byName = nil, {}
		WithWorld("Launchrealm", "Alliance", LAUNCH_A, function()
			GetGuildInfo = function() return "Olympus II", "Member", 3 end
			local events, login, timers = {}, {}, {}
			local cns = setmetatable({}, { __index = ns })
			cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
			cns.On = function(name, fn) if name == "LOGIN" then table.insert(login, fn) end end
			cns.clock = 100000
			cns.Now = function() return cns.clock end
			cns.After = function(delay, _, fn) timers[#timers + 1] = { at = cns.clock + (delay or 0), fn = fn } end
			cns.Every, cns.Print = function() end, function() end
			assert(loadfile(h.ADDON_DIR .. "Comm.lua"))("Olympus", cns)
			for _, fn in ipairs(login) do fn() end
			local C = cns.Comm
			C.JoinChannel()
			local channel = C.ChannelName()
			local function Notice(event, notice, player)
				for _, fn in ipairs(events[event] or {}) do
					fn(notice, player or "", "", "5. " .. channel, "", "", 0, 5, channel, 0, 0, "", 0, false, false, false, false)
				end
			end
			Notice("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED")
			Notice("CHAT_MSG_CHANNEL_NOTICE_USER", "OWNER_CHANGED", "Some Body")
			cns.clock = cns.clock + 2
			for _ = 1, 20 do
				local due
				for i, t in ipairs(timers) do if t.at <= cns.clock then due = i break end end
				if not due then break end
				table.remove(timers, due).fn()
			end
		end)
	end)
	GetChannelName, JoinChannelByName, LeaveChannelByName, SetChannelPassword, ChannelUnban, ChannelModerate,
		ChannelUnmute, C_ChatInfo, ns.rdb.realmKey, ns.Roster.byName = unpack(saved, 1, 10)
	if not ok then error(err, 0) end
	local all = table.concat(calls, "; ")
	for _, who in ipairs({ "Quill Maker", "Quill Horde", "Crown Owl", "Ledger Wren" }) do
		assert(all:find("unban [^;]*," .. who .. "[;%-]", 1) or all:find("unban [^;]*," .. who .. "$", 1), who .. " let back in: " .. all)
	end
	assert(not all:find(ns.AUTHOR, 1, true), "the code's beta author is not of this realm group: " .. all)
	assert(not all:find(ns.KING_CHARACTER.Alliance, 1, true), "nor the code's King: " .. all)
end)
