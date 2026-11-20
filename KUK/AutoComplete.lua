-- [Soeta's] Kjapp Utsendelse av Kolli: which names the To field fills in first.
-- Postal's BlackBook fills in the To field as you type. It checks alts first,
-- then recently mailed, contacts, Battle.net friends and the guild, and it never
-- looks at your normal friends list. This replaces that one step with an order
-- you choose in the options (/kuk), and adds the normal friends list.
-- The rest of BlackBook (its menu, recent list, contacts, Blizzard's popup) is
-- unchanged, and Postal's "Use AutoComplete" switch still turns all of it off.

KUK = KUK or {}
local PO = KUK

PO.TO_SOURCES = {
	alts = "Your alts",
	friends = "Friends (character and Battle.net)",
	guild = "Guild members",
	recent = "Recently mailed",
	contacts = "Postal contacts",
}
local DEFAULT_ORDER = { "alts", "friends", "guild", "recent", "contacts" }

local function DB()
	KUKDB = KUKDB or {}
	return KUKDB
end

-- The saved order, cleaned up: known names only, no repeats, missing ones at the end.
function PO.GetToOrder()
	local order, seen = {}, {}
	for _, key in ipairs(type(DB().toOrder) == "table" and DB().toOrder or {}) do
		if PO.TO_SOURCES[key] and not seen[key] then
			order[#order + 1], seen[key] = key, true
		end
	end
	for _, key in ipairs(DEFAULT_ORDER) do
		if not seen[key] then order[#order + 1] = key end
	end
	return order
end

function PO.SetToOrder(order)
	DB().toOrder = order
	return PO.GetToOrder()
end

function PO.ResetToOrder()
	DB().toOrder, DB().toOff = nil, nil
end

function PO.IsToSourceOn(key)
	return not (type(DB().toOff) == "table" and DB().toOff[key])
end

function PO.SetToSourceOn(key, on)
	if type(DB().toOff) ~= "table" then DB().toOff = {} end
	DB().toOff[key] = not on or nil
end

-- Move a source up (-1) or down (+1) in the order.
function PO.MoveToSource(key, dir)
	local order = PO.GetToOrder()
	for i, k in ipairs(order) do
		if k == key then
			local j = i + dir
			if j >= 1 and j <= #order then order[i], order[j] = order[j], order[i] end
			break
		end
	end
	return PO.SetToOrder(order)
end

---------------------------------------------------------------------------
-- Finding a name
---------------------------------------------------------------------------

local function Postal()
	local ace = LibStub and LibStub("AceAddon-3.0", true)
	return ace and ace:GetAddon("Postal", true)
end

local function StartsWith(name, text)
	return name and name ~= "" and strfind(strupper(name), text, 1, true) == 1
end

-- Just the character's name. Forever reports realms like "CAMWOW EU4 Realm 8 PvP",
-- and mail is addressed to the plain name, so anything after a "-" is dropped.
local function Short(name)
	if type(name) ~= "string" then return end
	name = strtrim(name:match("^([^%-]+)") or name)
	return name ~= "" and name or nil
end

local finders = {}

-- Your other characters of the same faction, from Postal's alt list.
function finders.alts(text, me)
	local postal = Postal()
	local alts = postal and postal.db and postal.db.global.BlackBook and postal.db.global.BlackBook.alts
	for _, entry in ipairs(alts or {}) do
		local p, _, f = strsplit("|", entry)
		local name = Short(p)
		if name and name ~= me.name and (not f or not me.faction or f == me.faction) and StartsWith(name, text) then
			return name
		end
	end
end

-- Your friends list (online first), then Battle.net friends playing this game.
function finders.friends(text, me)
	local offline
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			local name = info and Short(info.name)
			if name and name ~= me.name and StartsWith(name, text) then
				if info.connected then return name end
				offline = offline or name
			end
		end
	end
	if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		local total = BNGetNumFriends()
		for i = 1, total or 0 do
			local account = C_BattleNet.GetFriendAccountInfo(i)
			local game = account and account.gameAccountInfo
			local name = game and game.isOnline ~= false and Short(game.characterName)
			if name and game.clientProgram == BNET_CLIENT_WOW
				and (not game.wowProjectID or game.wowProjectID == WOW_PROJECT_ID)
				and name ~= me.name and StartsWith(name, text) then
				return name
			end
		end
	end
	return offline
end

-- Guild members, online first.
function finders.guild(text, me)
	if not IsInGuild() then return end
	local offline
	for i = 1, GetNumGuildMembers() or 0 do
		local full, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
		local name = Short(full)
		if name and name ~= me.name and StartsWith(name, text) then
			if online then return name end
			offline = offline or name
		end
	end
	return offline
end

-- People you mailed recently, from Postal's list.
function finders.recent(text, me)
	local postal = Postal()
	local recent = postal and postal.db and postal.db.profile.BlackBook and postal.db.profile.BlackBook.recent
	for _, entry in ipairs(recent or {}) do
		local p, _, f = strsplit("|", entry)
		local name = Short(p)
		if name and name ~= me.name and (not f or not me.faction or f == me.faction) and StartsWith(name, text) then
			return name
		end
	end
end

function finders.contacts(text, me)
	local postal = Postal()
	local contacts = postal and postal.db and postal.db.profile.BlackBook and postal.db.profile.BlackBook.contacts
	for _, entry in ipairs(contacts or {}) do
		local name = Short(entry)
		if name and StartsWith(name, text) then return name end
	end
end

local function Me()
	return { name = UnitName("player"), faction = UnitFactionGroup("player") }
end

-- The first name that starts with what was typed, going through the sources in order.
function PO.FindRecipient(typed)
	local text = strupper(typed or "")
	if text == "" then return end
	local me = Me()
	for _, key in ipairs(PO.GetToOrder()) do
		if PO.IsToSourceOn(key) then
			local ok, name = pcall(finders[key], text, me)
			if ok and name then return name, key end
		end
	end
end

---------------------------------------------------------------------------
-- Taking over BlackBook's step
---------------------------------------------------------------------------
-- BlackBook hooks the To box's OnChar script by method name, so the hook calls
-- whatever BlackBook.OnChar is at that moment. Replacing that method is enough.

local function OnChar(self, editbox, ...)
	-- Only complete when typing at the end of the text, as BlackBook does.
	if editbox:GetUTF8CursorPosition() ~= strlenutf8(editbox:GetText()) then return end
	local typedLength = strlen(editbox:GetText())
	local name = PO.FindRecipient(editbox:GetText())

	-- Blizzard's own completion and its popup list.
	local original = self.hooks and self.hooks[SendMailNameEditBox] and self.hooks[SendMailNameEditBox].OnChar
	if original then original(editbox, ...) end

	-- Our match wins over Blizzard's.
	if name then
		editbox:SetText(name)
		editbox:HighlightText(typedLength, -1)
		editbox:SetCursorPosition(typedLength)
	end
end

local function BlackBook()
	local postal = Postal()
	return postal and postal.GetModule and postal:GetModule("BlackBook", true)
end

-- Ask the server for a fresh guild list and friends list, so their names can be found.
local function RequestLists()
	if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
	if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
end

local function Install()
	local blackBook = BlackBook()
	if blackBook and blackBook.OnChar ~= OnChar then blackBook.OnChar = OnChar end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Install()
	if MailFrame then MailFrame:HookScript("OnShow", function() Install(); RequestLists() end) end
	if SendMailNameEditBox then SendMailNameEditBox:HookScript("OnEditFocusGained", RequestLists) end
end)

-- /kuk find <letters>: what each source would fill in, and why not.
function PO.DebugFind(typed, say)
	local text = strupper(strtrim(typed or ""))
	local me = Me()
	local blackBook = BlackBook()
	local postal = Postal()
	local db = postal and postal.db
	local bb = db and db.profile and db.profile.BlackBook
	say(("You: %s (%s). Postal BlackBook: %s, its autocomplete: %s, our lookup: %s."):format(
		tostring(me.name), tostring(me.faction),
		blackBook and (blackBook:IsEnabled() and "on" or "off") or "missing",
		bb and (bb.UseAutoComplete and "on" or "off") or "?",
		(blackBook and blackBook.OnChar == OnChar) and "active" or "NOT active"))
	local alts = db and db.global and db.global.BlackBook and db.global.BlackBook.alts or {}
	local guildCount = IsInGuild() and (GetNumGuildMembers() or 0) or 0
	local friendCount = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
	local bnetCount = BNGetNumFriends and BNGetNumFriends() or 0
	say(("Known: %d alts, %d friends, %d Battle.net friends, %d guild members%s."):format(
		#alts, friendCount, bnetCount, guildCount, IsInGuild() and "" or " (not in a guild)"))
	if text == "" then return end
	for _, key in ipairs(PO.GetToOrder()) do
		local ok, name = pcall(finders[key], text, me)
		local result = (not ok) and ("error: " .. tostring(name)) or (name or "no match")
		say(("  %s%s: %s"):format(PO.TO_SOURCES[key], PO.IsToSourceOn(key) and "" or " (off)", result))
	end
end
