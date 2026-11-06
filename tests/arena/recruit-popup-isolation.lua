-- Forever 70790: GuildControlUI_OnEvent(GUILD_RANKS_UPDATE_ACTIVE_PLAYER)
-- calls SetupSelected -> StaticPopup_Hide even with the guild window closed,
-- then its Discord pane calls Blizzard-only functions. The live RP report named
-- those calls immediately after CHILLZONE_RECRUIT opened as a native popup.
-- LuaJIT has no native taint engine: assert the real recruit flow never writes
-- that shared popup state, and that its own dialog still sends/cancels normally.
local H = ...
local ns, test, eq = H.ns, H.test, H.eq

for _, pad in ipairs({ false, true }) do
	test("recruit popup isolation: " .. (pad and "gamepad" or "mouse") .. " request stays off native popups before guild rank events", function()
		H.WithUI(function()
			H.WithGamepadUI(pad, function(game)
				local R = ns.Recruit
				local saved = { guild = GetGuildInfo, inGuild = IsInGuild, level = UnitLevel, class = UnitClass,
					time = GetTime, send = SendChatMessage, outside = ns.Comm.WhisperOutside }
				local ok, err = pcall(function()
					R.ResetForTests(); ns.Dialog.Reset()
					GetGuildInfo = function() return nil end
					IsInGuild = function() return false end
					UnitLevel = function() return 1 end
					UnitClass = function() return "Mage", "MAGE", 8 end
					GetTime = function() return 1000 end
					local said, outside = {}, {}
					SendChatMessage = function(text, kind, _, target) said[#said + 1] = { text = text, kind = kind, target = target } end
					ns.Comm.WhisperOutside = function(target, text) outside[#outside + 1] = { target = target, text = text }; return true end
					local contact = { name = "Captain-Realm", guild = "ChillZone II" }
					R.Prompt(contact)
					eq(#game.shown, 0, "no native popup state for the asynchronous guild-rank handler to read")
					local f = assert(ns.Dialog.Find("CHILLZONE_RECRUIT"), "ChillZone's editable confirmation")
					eq(f:IsShown(), true); eq(f.data, contact)
					eq(f.editBox:GetText(), R.Message(contact))
					eq(f.escapes == true, not pad, "mouse Escape retained without borrowing it in gamepad mode")
					f.buttons[2]:Click()
					eq(f:IsShown(), false); eq(#said, 0, "Cancel sends no request")
					R.Prompt(contact)
					f = assert(ns.Dialog.Find("CHILLZONE_RECRUIT"))
					f.editBox:SetText("I'd like to join, please.")
					f.buttons[1]:Click()
					eq(f:IsShown(), false); eq(#said, 1)
					eq(said[1].text, "I'd like to join, please."); eq(said[1].kind, "WHISPER"); eq(said[1].target, "Captain")
					eq(outside[#outside].text, "J3~ChillZone II~1~MAGE")
					local other = { name = "Other-Realm", guild = "ChillZone II" }
					R.Prompt(other)
					f = assert(ns.Dialog.Find("CHILLZONE_RECRUIT"))
					eq(R.OnRoute(other.name, R.DNC_ANSWER), true)
					eq(f:IsShown(), false, "do-not-contact closes the same window before sending")
					eq(#said, 1); eq(#game.shown, 0)
				end)
				ns.Dialog.Reset(); R.ResetForTests()
				GetGuildInfo, IsInGuild, UnitLevel, UnitClass, GetTime, SendChatMessage, ns.Comm.WhisperOutside =
					saved.guild, saved.inGuild, saved.level, saved.class, saved.time, saved.send, saved.outside
				if not ok then error(err, 0) end
			end)
		end)
	end)
end
