-- [Soeta's] Kjapp Utsendelse av Kolli: address book
-- Remembers your characters (alts), who you mailed recently and a contacts list,
-- and adds a menu button beside the To field with alts, recently mailed,
-- contacts, friends and guild members. Names are always the plain character
-- name, without a realm.

KUK = KUK or {}
local PO = KUK

local RECENT_MAX = 20
local Book = {}
PO.Book = Book

local function DB()
	KUKDB = KUKDB or {}
	return KUKDB
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PO.TITLE .. ": " .. msg)
end

-- Just the character's name: anything after a "-" (a realm) is dropped.
local function Short(name)
	if type(name) ~= "string" then return end
	name = strtrim(name:match("^([^%-]+)") or name)
	return name ~= "" and name or nil
end
Book.Short = Short

local function Lists()
	local db = DB()
	if type(db.alts) ~= "table" then db.alts = {} end
	if type(db.recent) ~= "table" then db.recent = {} end
	if type(db.contacts) ~= "table" then db.contacts = {} end
	return db
end

---------------------------------------------------------------------------
-- Alts
---------------------------------------------------------------------------

local function RememberMe()
	local name, faction = UnitName("player"), UnitFactionGroup("player")
	if not name or not faction then return end
	local _, class = UnitClass("player")
	local alts = Lists().alts
	local entry
	for _, a in ipairs(alts) do
		if a.name == name and a.faction == faction then entry = a end
	end
	if not entry then
		entry = { name = name, faction = faction }
		alts[#alts + 1] = entry
		table.sort(alts, function(x, y) return x.name < y.name end)
	end
	entry.level, entry.class = UnitLevel("player"), class
end

-- Your other characters of the same faction.
function Book.Alts()
	local me, faction = UnitName("player"), UnitFactionGroup("player")
	local list = {}
	for _, a in ipairs(Lists().alts) do
		if a.name ~= me and (not faction or not a.faction or a.faction == faction) then list[#list + 1] = a end
	end
	return list
end

function Book.ForgetAlt(name)
	local alts = Lists().alts
	for i = #alts, 1, -1 do
		if alts[i].name == name then table.remove(alts, i) end
	end
end

---------------------------------------------------------------------------
-- Recently mailed and contacts
---------------------------------------------------------------------------

function Book.Recent()
	local faction = UnitFactionGroup("player")
	local list = {}
	for _, r in ipairs(Lists().recent) do
		if not faction or not r.faction or r.faction == faction then list[#list + 1] = r.name end
	end
	return list
end

local function RememberRecipient(name)
	name = Short(name)
	if not name then return end
	local recent, faction = Lists().recent, UnitFactionGroup("player")
	for i = #recent, 1, -1 do
		if recent[i].name:lower() == name:lower() then table.remove(recent, i) end
	end
	table.insert(recent, 1, { name = name, faction = faction })
	for i = #recent, RECENT_MAX + 1, -1 do recent[i] = nil end
end

function Book.ClearRecent()
	wipe(Lists().recent)
end

function Book.Contacts()
	return Lists().contacts
end

function Book.AddContact(name)
	name = Short(name)
	if not name then return false end
	local contacts = Lists().contacts
	for _, c in ipairs(contacts) do
		if c:lower() == name:lower() then return false end
	end
	contacts[#contacts + 1] = name
	table.sort(contacts)
	return true
end

function Book.RemoveContact(name)
	local contacts = Lists().contacts
	for i = #contacts, 1, -1 do
		if contacts[i]:lower() == (name or ""):lower() then table.remove(contacts, i) end
	end
end

---------------------------------------------------------------------------
-- Friends and guild
---------------------------------------------------------------------------

-- Friends list (online first), then Battle.net friends playing this game.
function Book.Friends()
	local online, offline, seen = {}, {}, {}
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			local name = info and Short(info.name)
			if name and not seen[name] then
				seen[name] = true
				table.insert(info.connected and online or offline, name)
			end
		end
	end
	if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		for i = 1, BNGetNumFriends() or 0 do
			local account = C_BattleNet.GetFriendAccountInfo(i)
			local game = account and account.gameAccountInfo
			local name = game and game.isOnline ~= false and game.clientProgram == BNET_CLIENT_WOW
				and (not game.wowProjectID or game.wowProjectID == WOW_PROJECT_ID) and Short(game.characterName)
			if name and not seen[name] then
				seen[name] = true
				online[#online + 1] = name
			end
		end
	end
	return online, offline
end

-- Guild members (online first), without yourself.
function Book.Guild()
	local online, offline = {}, {}
	if not IsInGuild() then return online, offline end
	local me = UnitName("player")
	for i = 1, GetNumGuildMembers() or 0 do
		local full, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
		local name = Short(full)
		if name and name ~= me then table.insert(isOnline and online or offline, name) end
	end
	table.sort(online)
	table.sort(offline)
	return online, offline
end

function Book.RequestLists()
	if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
	if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
end

---------------------------------------------------------------------------
-- Bringing over Postal's lists, once
---------------------------------------------------------------------------

local function ImportPostal()
	local db = Lists()
	if db.importedPostal then return end
	local ace = LibStub and LibStub("AceAddon-3.0", true)
	local postal = ace and ace:GetAddon("Postal", true)
	local pdb = postal and postal.db
	if not pdb then return end
	local alts = pdb.global and pdb.global.BlackBook and pdb.global.BlackBook.alts
	for _, entry in ipairs(type(alts) == "table" and alts or {}) do
		local p, _, f, l, c = strsplit("|", entry)
		local name = Short(p)
		if name then
			local found = false
			for _, a in ipairs(db.alts) do
				if a.name == name and a.faction == f then found = true end
			end
			if not found then db.alts[#db.alts + 1] = { name = name, faction = f, level = tonumber(l), class = c } end
		end
	end
	table.sort(db.alts, function(x, y) return x.name < y.name end)
	local bb = pdb.profile and pdb.profile.BlackBook
	for i = 1, #(bb and bb.recent or {}) do
		local p, _, f = strsplit("|", bb.recent[i])
		local name = Short(p)
		if name then
			local recent = db.recent
			local dup = false
			for _, r in ipairs(recent) do if r.name == name then dup = true end end
			if not dup and #recent < RECENT_MAX then table.insert(recent, { name = name, faction = f }) end
		end
	end
	for _, c in ipairs(bb and bb.contacts or {}) do Book.AddContact(c) end
	db.importedPostal = true
end

---------------------------------------------------------------------------
-- The menu button beside the To field
---------------------------------------------------------------------------

local function SetTo(name)
	if not SendMailNameEditBox then return end
	SendMailNameEditBox:SetText(name)
	SendMailNameEditBox:SetCursorPosition(#name)
	if SendMailSubjectEditBox then SendMailSubjectEditBox:SetFocus() end
end

local function ClassColored(a)
	local c = a.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[a.class]
	local name = c and ("|c" .. (c.colorStr or "ffffffff") .. a.name .. "|r") or a.name
	return a.level and (name .. " |cff999999" .. a.level .. "|r") or name
end

local function AddNames(menu, names)
	for _, name in ipairs(names) do
		menu:CreateButton(name, function() SetTo(name) end)
	end
end

local function BuildMenu(_, root)
	root:CreateTitle(PO.NAME)

	local alts = Book.Alts()
	local altMenu = root:CreateButton(("Alts (%d)"):format(#alts))
	for _, a in ipairs(alts) do
		altMenu:CreateButton(ClassColored(a), function() SetTo(a.name) end)
	end
	if #alts > 0 then
		altMenu:CreateDivider()
		local forget = altMenu:CreateButton("Forget an alt")
		for _, a in ipairs(alts) do
			forget:CreateButton(a.name, function()
				Book.ForgetAlt(a.name)
				Print(a.name .. " was removed from your alts.")
			end)
		end
	end

	local recent = Book.Recent()
	local recentMenu = root:CreateButton(("Recently mailed (%d)"):format(#recent))
	AddNames(recentMenu, recent)
	if #recent > 0 then
		recentMenu:CreateDivider()
		recentMenu:CreateButton("Clear the list", function() Book.ClearRecent() end)
	end

	local contacts = Book.Contacts()
	local contactMenu = root:CreateButton(("Contacts (%d)"):format(#contacts))
	AddNames(contactMenu, contacts)
	contactMenu:CreateDivider()
	local typed = Short(SendMailNameEditBox and SendMailNameEditBox:GetText())
	if typed then
		contactMenu:CreateButton("Add " .. typed, function()
			if Book.AddContact(typed) then Print(typed .. " was added to your contacts.") end
		end)
	end
	if #contacts > 0 then
		local remove = contactMenu:CreateButton("Remove a contact")
		for _, c in ipairs(contacts) do
			remove:CreateButton(c, function() Book.RemoveContact(c) end)
		end
	end

	local online, offline = Book.Friends()
	local friendMenu = root:CreateButton(("Friends (%d online)"):format(#online))
	AddNames(friendMenu, online)
	if #offline > 0 then
		local off = friendMenu:CreateButton(("Offline (%d)"):format(#offline))
		AddNames(off, offline)
	end

	if IsInGuild() then
		local gOnline, gOffline = Book.Guild()
		local guildMenu = root:CreateButton(("Guild (%d online)"):format(#gOnline))
		AddNames(guildMenu, gOnline)
		if #gOffline > 0 then
			local off = guildMenu:CreateButton(("Offline (%d)"):format(#gOffline))
			for i = 1, math.min(#gOffline, 40) do
				local name = gOffline[i]
				off:CreateButton(name, function() SetTo(name) end)
			end
		end
	end
end

local function CreateMenuButton()
	if PO.ToMenuButton or not SendMailNameEditBox then return end
	local b = CreateFrame("Button", "KUKToMenuButton", SendMailFrame)
	b:SetSize(25, 25)
	b:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", -2, 2)
	b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round", "ADD")
	b:SetScript("OnClick", function(self)
		Book.RequestLists()
		if MenuUtil and MenuUtil.CreateContextMenu then
			MenuUtil.CreateContextMenu(self, BuildMenu)
		else
			Print("This game version has no menus for the address book.")
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Address book", 1, 1, 1)
		GameTooltip:AddLine("Alts, recently mailed, contacts, friends and guild.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	-- Postal has its own button in the same spot; show only one.
	if _G.Postal_BlackBookButton and _G.Postal_BlackBookButton:IsShown() then b:Hide() end
	PO.ToMenuButton = b
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local lastRecipient

hooksecurefunc("SendMail", function(recipient) lastRecipient = recipient end)

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "MAIL_SEND_SUCCESS" }) do
	if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
		pcall(events.RegisterEvent, events, event)
	end
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Lists()
		ImportPostal()
		RememberMe()
		if SendMailFrame then
			SendMailFrame:HookScript("OnShow", function()
				CreateMenuButton()
				RememberMe()
			end)
		end
	elseif event == "PLAYER_LEVEL_UP" then
		C_Timer.After(1, RememberMe)
	elseif event == "MAIL_SEND_SUCCESS" then
		if lastRecipient then RememberRecipient(lastRecipient) end
	end
end)
