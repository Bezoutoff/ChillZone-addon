local ADDON, ns = ...

-- 1.5.0 (2026-11-05, the dev's ask after the launch): the Olympus chats as the game's own text.
-- WoW: Forever delivers nothing an addon says on a chat channel (Relay.lua), but a line a player
-- types in a channel it delivers to everyone in it, across every sub-realm (measured on
-- 2026-11-05: a player-made channel, two sub-realms, the line arrived). So where names split
-- (Forever), a chat line leaves as the player's own text in the hidden Olympus channel Comm.lua
-- already joins (its lane, its key as the password when sealed), written exactly as the hidden
-- message would be (Codec.EncodeChat: M1~tier~guild~id~class~text), and every client reads the
-- channel's text and takes such a line as it takes the hidden one (Channels.Receive: the same
-- rooms, mutes, ids, our own echo once). The channel stays off the game's chat windows (Comm's
-- HideChannelFromChat), so nobody sees the raw lines. The send is the player's Enter in the
-- Olympus box (a hardware event): where the realm refuses it all the same, no echo comes back
-- within ECHO_WAIT and the line goes the hidden way, by the relay, as 1.4.x sent it. With the
-- gamepad UI nothing here runs (the chat box gate): the hidden way as before.
local Hall = {}
ns.ChatHall = Hall
Hall.ECHO_WAIT = 3
local pending = {} -- msg -> { at, done, line, guard }: sent as text, its echo awaited
local stats = { sent = 0, echoed = 0, fallen = 0, heard = 0 }
function Hall.Stats() return { sent = stats.sent, echoed = stats.echoed, fallen = stats.fallen, heard = stats.heard, on = Hall.On() } end

function Hall.On() -- gp:chat-box
	if not ns.Gate.Allowed("chat-box") then return false end
	if ns.splitNames ~= true or not ns.Comm or type(ns.Comm.ChannelIndex) ~= "function" then return false end
	if (ns.Comm.ChannelIndex() or 0) <= 0 then return false end
	if type(ns.GamepadUI) == "function" and ns.GamepadUI() then return false end
	return type(SendChatMessage) == "function" -- gp:chat-box
end

-- A chat line (the hidden message's text) as the player's own text in the channel. True when
-- handed to the game; its echo settles it (OnChannel), and no echo within ECHO_WAIT sends it the
-- hidden way with the same callback.
function Hall.Send(msg, done, line, guard) -- gp:chat-box
	if not ns.Gate.Allowed("chat-box") then return false end
	if not Hall.On() or type(msg) ~= "string" or msg == "" or #msg > 255 then return false end
	local index = ns.Comm.ChannelIndex()
	pending[msg] = { at = ns.Now(), done = done, line = line, guard = guard }
	local ok = pcall(SendChatMessage, msg, "CHANNEL", nil, index) -- gp:chat-box
	if not ok then pending[msg] = nil return false end
	stats.sent = stats.sent + 1
	ns.After(Hall.ECHO_WAIT, "chat hall echo", function()
		local p = pending[msg]
		if not p then return end
		pending[msg] = nil
		stats.fallen = stats.fallen + 1
		ns.Comm.SendChat(msg, p.done, p.line, p.guard, true) -- (hidden: never back here)
	end)
	return true
end

-- The channel's text heard (CHAT_MSG_CHANNEL): a chat line written as the hidden message, in
-- our channel, taken as the hidden one is; our own echo settles its send.
function Hall.OnChannel(text, sender, _, _, _, _, _, _, baseName)
	local joined = ns.Comm and ns.Comm.ChannelName and ns.Comm.ChannelName()
	if type(joined) ~= "string" or type(baseName) ~= "string" or baseName:lower() ~= joined:lower() then return false end
	-- (Any chat kind: the Olympus tiers' M1, the role rooms', the arena's: whatever Comm.SendChat
	-- carries, by its type, to its own handler as Comm.Inject hands a relayed line.)
	if type(text) ~= "string" or not text:match("^%u%w~") or #text > 255 then return false end
	local p = pending[text]
	if p then
		pending[text] = nil
		stats.echoed = stats.echoed + 1
		if p.done then ns.SafeCall("chat hall done", p.done, true) end
	end
	stats.heard = stats.heard + 1
	if type(ns.Comm.Inject) == "function" then ns.SafeCall("chat hall line", ns.Comm.Inject, "CHANNEL", sender, text, true) end
	return true
end

ns.On("LOGIN", function()
	if ns.splitNames ~= true then return end
	pcall(ns.RegisterEvent, "CHAT_MSG_CHANNEL", function(...) ns.SafeCall("chat hall", Hall.OnChannel, ...) end)
end)

function Hall.Reset() wipe(pending); for k in pairs(stats) do stats[k] = 0 end end
