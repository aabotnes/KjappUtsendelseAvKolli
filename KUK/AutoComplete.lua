-- [Soeta's] Kjapp Utsendelse av Kolli: filling in the To field
-- While you type a name, the first match from your sources is filled in, in an
-- order you choose: your alts, friends, guild, recently mailed and contacts.
-- Always the full character name ("Giga Dad"), never "Name-Realm".

KUK = KUK or {}
local PO = KUK

PO.TO_SOURCES = {
	alts = "Your alts",
	friends = "Friends (character and Battle.net)",
	guild = "Guild members",
	recent = "Recently mailed",
	contacts = "Contacts",
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

local function StartsWith(name, text)
	return name and name ~= "" and strfind(strupper(name), text, 1, true) == 1
end

local function First(text, ...)
	for i = 1, select("#", ...) do
		for _, name in ipairs(select(i, ...) or {}) do
			if StartsWith(name, text) then return name end
		end
	end
end

local finders = {}

function finders.alts(text)
	for _, a in ipairs(PO.Book.Alts()) do
		if StartsWith(a.name, text) then return a.name end
	end
end

function finders.friends(text)
	return First(text, PO.Book.Friends())
end

function finders.guild(text)
	return First(text, PO.Book.Guild())
end

function finders.recent(text)
	return First(text, PO.Book.Recent())
end

function finders.contacts(text)
	return First(text, PO.Book.Contacts())
end

-- The first name that starts with what was typed, going through the sources in order.
function PO.FindRecipient(typed)
	local text = strupper(typed or "")
	if text == "" then return end
	for _, key in ipairs(PO.GetToOrder()) do
		if PO.IsToSourceOn(key) then
			local ok, name = pcall(finders[key], text)
			if ok and name then return name, key end
		end
	end
end

---------------------------------------------------------------------------
-- The To field
---------------------------------------------------------------------------
-- The game completes names on its own first (with its popup list); this runs
-- right after and puts our match in instead, with the rest highlighted so you
-- can keep typing over it.

local function AfterChar(editbox)
	if DB().toFillOff then return end
	local text = editbox:GetText() or ""
	-- Only complete when typing at the end of what was typed.
	local cursor = editbox:GetCursorPosition()
	-- Text after the cursor is only ours to replace if the game just completed it.
	local gameCompleted = AutoCompleteBox and AutoCompleteBox:IsShown() and AutoCompleteBox.parent == editbox
	if cursor < #text and not gameCompleted then return end
	local typed = text:sub(1, cursor)
	if typed == "" then return end
	local name = PO.FindRecipient(typed)
	if name and name ~= text then
		editbox:SetText(name)
		editbox:HighlightText(#typed, -1)
		editbox:SetCursorPosition(#typed)
	end
end

-- If Postal is installed too, its own completion steps aside so the two don't fight.
local function QuietPostal()
	local ace = LibStub and LibStub("AceAddon-3.0", true)
	local postal = ace and ace:GetAddon("Postal", true)
	local blackBook = postal and postal.GetModule and postal:GetModule("BlackBook", true)
	if blackBook and not blackBook.kukQuiet then
		blackBook.OnChar = function(self, editbox, ...)
			local original = self.hooks and self.hooks[SendMailNameEditBox] and self.hooks[SendMailNameEditBox].OnChar
			if original then return original(editbox, ...) end
		end
		blackBook.kukQuiet = true
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	QuietPostal()
	if SendMailNameEditBox then
		SendMailNameEditBox:HookScript("OnChar", AfterChar)
		SendMailNameEditBox:HookScript("OnEditFocusGained", function() PO.Book.RequestLists() end)
	end
	if MailFrame then
		MailFrame:HookScript("OnShow", function()
			QuietPostal()
			PO.Book.RequestLists()
		end)
	end
end)

-- /kuk find <letters>: what each source would fill in.
function PO.DebugFind(typed, say)
	local text = strupper(strtrim(typed or ""))
	local online, offline = PO.Book.Friends()
	local gOnline, gOffline = PO.Book.Guild()
	say(("You: %s (%s). Known: %d alts, %d friends, %d guild members, %d recently mailed, %d contacts%s."):format(
		tostring(PO.Book.PlayerName()), tostring(UnitFactionGroup("player")),
		#PO.Book.Alts(), #online + #offline, #gOnline + #gOffline, #PO.Book.Recent(), #PO.Book.Contacts(),
		DB().toFillOff and " (filling in is switched off)" or ""))
	if text == "" then return end
	for _, key in ipairs(PO.GetToOrder()) do
		local ok, name = pcall(finders[key], text)
		local result = (not ok) and ("error: " .. tostring(name)) or (name or "no match")
		say(("  %s%s: %s"):format(PO.TO_SOURCES[key], PO.IsToSourceOn(key) and "" or " (off)", result))
	end
end
