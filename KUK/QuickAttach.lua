-- [Soeta's] Kjapp Utsendelse av Kolli: QuickAttach buttons
-- A column of buttons beside the Send Mail window, one per kind of trade goods
-- (Cloth, Leather, Herb and so on). Left-click attaches every matching item from
-- your bags: the 12 real slots first, then the extra slots. Right-click sets a
-- default recipient for that button. Which buttons show is kept in profiles that
-- each character picks. The gear button at the bottom opens the settings.

KUK = KUK or {}
local PO = KUK

local TRADE_GOODS = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
local ICONS = "Interface\\Icons\\"

-- notInForever: trade goods from later expansions, hidden unless a profile shows them.
local KINDS = {
	{ key = "cloth",         sub = 5,  label = "Cloth",             icon = "INV_Fabric_Linen_01" },
	{ key = "leather",       sub = 6,  label = "Leather",           icon = "INV_Misc_LeatherScrap_03" },
	{ key = "metal",         sub = 7,  label = "Metal & Stone",     icon = "INV_Ore_Copper_01" },
	{ key = "cooking",       sub = 8,  label = "Cooking",           icon = "INV_Misc_Food_02" },
	{ key = "herb",          sub = 9,  label = "Herb",              icon = "INV_Misc_Herb_10" },
	{ key = "elemental",     sub = 10, label = "Elemental",         icon = "INV_Elemental_Primal_Air" },
	{ key = "enchanting",    sub = 12, label = "Enchanting",        icon = "INV_Enchant_DustArcane" },
	{ key = "parts",         sub = 1,  label = "Parts",             icon = "INV_Gizmo_FelIronCasing" },
	{ key = "devices",       sub = 3,  label = "Devices",           icon = "INV_Gizmo_GoblingTonkController" },
	{ key = "explosives",    sub = 2,  label = "Explosives",        icon = "INV_Misc_Ammo_Gunpowder_01" },
	{ key = "other",         sub = 11, label = "Other",             icon = "INV_Misc_Rune_09" },
	{ key = "jewelcrafting", sub = 4,  label = "Jewelcrafting",     icon = "INV_Misc_Gem_01",              notInForever = true },
	{ key = "inscription",   sub = 16, label = "Inscription",       icon = "INV_Inscription_Tradeskill01", notInForever = true },
	{ key = "optional",      sub = 18, label = "Optional Reagents", icon = "INV_Bijou_Green",              notInForever = true },
	{ key = "all",           sub = -1, label = "All trade goods",   icon = "Ability_Ensnare" },
}

local buttons = {}       -- key -> button
local settingsButton, qaToggle, recipientBox

local function DB()
	KUKDB = KUKDB or {}
	return KUKDB
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PO.TITLE .. ": " .. msg)
end

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
-- Which buttons show lives in named profiles. Each character picks one;
-- characters that never picked one use "Default".

local ApplyVisibility

local function CharKey()
	return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

local function QAProfiles()
	local db = DB()
	if type(db.qaProfiles) ~= "table" then
		db.qaProfiles = { Default = { hideAll = db.hideQuickAttach or nil } }
		db.hideQuickAttach, db.qaHidden = nil, nil
	end
	if type(db.qaProfiles.Default) ~= "table" then db.qaProfiles.Default = {} end
	if type(db.qaProfileByChar) ~= "table" then db.qaProfileByChar = {} end
	return db.qaProfiles
end

function PO.GetQAProfileName()
	local profiles = QAProfiles()
	local name = DB().qaProfileByChar[CharKey()]
	if not name or type(profiles[name]) ~= "table" then name = "Default" end
	return name
end

local function QAProfile()
	return QAProfiles()[PO.GetQAProfileName()]
end

function PO.GetQAProfiles()
	local names = {}
	for name, p in pairs(QAProfiles()) do
		if type(p) == "table" then names[#names + 1] = name end
	end
	table.sort(names, function(a, b)
		if a == "Default" or b == "Default" then return a == "Default" end
		return a:lower() < b:lower()
	end)
	return names
end

-- Characters that picked a profile.
function PO.GetQAProfileUsers(name)
	QAProfiles()
	local users = {}
	for char, used in pairs(DB().qaProfileByChar) do
		if used == name then users[#users + 1] = char end
	end
	table.sort(users)
	return users
end

function PO.CurrentCharacter()
	return UnitName("player") or "?"
end

function PO.SetQAProfile(name)
	if type(QAProfiles()[name]) ~= "table" then return false end
	DB().qaProfileByChar[CharKey()] = (name ~= "Default") and name or nil
	ApplyVisibility()
	return true
end

-- Make a new profile, starting as a copy of the one this character uses now, and switch to it.
function PO.NewQAProfile(name)
	name = strtrim(name or "")
	if name == "" then return false, "Type a name for the new profile." end
	if #name > 40 then return false, "That name is too long." end
	local profiles = QAProfiles()
	if profiles[name] then return false, ("There's already a profile called %s."):format(name) end
	local current = QAProfile()
	profiles[name] = {
		hideAll = current.hideAll,
		hidden = type(current.hidden) == "table" and CopyTable(current.hidden) or nil,
		recipients = type(current.recipients) == "table" and CopyTable(current.recipients) or nil,
	}
	PO.SetQAProfile(name)
	return true
end

-- Delete a profile. Characters that used it go back to "Default".
function PO.DeleteQAProfile(name)
	if name == "Default" or type(QAProfiles()[name]) ~= "table" then return false end
	QAProfiles()[name] = nil
	for char, used in pairs(DB().qaProfileByChar) do
		if used == name then DB().qaProfileByChar[char] = nil end
	end
	ApplyVisibility()
	return true
end

-- A profile's hidden[key] is true (hidden), false (shown) or unset (the default).
local function KindHidden(kind)
	local hidden = QAProfile().hidden
	local choice = type(hidden) == "table" and hidden[kind.key]
	if choice == nil then return kind.notInForever or false end
	return choice
end

local function Recipient(kind)
	local r = QAProfile().recipients
	return type(r) == "table" and r[kind.key] or nil
end

local function SetRecipient(kind, name)
	local p = QAProfile()
	if type(p.recipients) ~= "table" then p.recipients = {} end
	name = name and strtrim(name) or ""
	p.recipients[kind.key] = name ~= "" and name or nil
end

function PO.IsQuickAttachHidden()
	return QAProfile().hideAll and true or false
end

function PO.SetQuickAttachHidden(hidden)
	QAProfile().hideAll = hidden and true or nil
	ApplyVisibility()
end

function KUK_ToggleQuickAttach()
	PO.SetQuickAttachHidden(not PO.IsQuickAttachHidden())
	return PO.IsQuickAttachHidden()
end

-- For the options: every button with its icon, name and whether it's shown.
function PO.GetQuickAttachButtons()
	local list = {}
	for _, kind in ipairs(KINDS) do
		list[#list + 1] = {
			key = kind.key, label = kind.label, icon = ICONS .. kind.icon,
			shown = not KindHidden(kind), notInForever = kind.notInForever,
		}
	end
	return list, true
end

function PO.SetQuickAttachButtonShown(key, shown)
	local p = QAProfile()
	if type(p.hidden) ~= "table" then p.hidden = {} end
	p.hidden[key] = not shown
	ApplyVisibility()
end

-- Tick every button, including the ones for trade goods Forever doesn't have.
function PO.ShowAllQuickAttachButtons()
	local hidden = {}
	for _, kind in ipairs(KINDS) do hidden[kind.key] = false end
	QAProfile().hidden = hidden
	ApplyVisibility()
end

-- Back to the default: everything except the trade goods Forever doesn't have.
function PO.DefaultQuickAttachButtons()
	QAProfile().hidden = nil
	QAProfile().hideAll = nil
	ApplyVisibility()
end

---------------------------------------------------------------------------
-- Attaching
---------------------------------------------------------------------------

local function Matches(kind, itemID)
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	return classID == TRADE_GOODS and (kind.sub == -1 or subClassID == kind.sub)
end

local function AttachKind(kind)
	if not (PO.SendTabOpen and PO.SendTabOpen()) then return end
	-- Fill in the button's default recipient if the To field is empty.
	local to = Recipient(kind)
	if to and SendMailNameEditBox and strtrim(SendMailNameEditBox:GetText() or "") == "" then
		SendMailNameEditBox:SetText(to)
	end
	local list = {}
	for bag = 0, PO.LastBag() do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.isLocked and not info.isBound and Matches(kind, info.itemID) then
				list[#list + 1] = { bag = bag, slot = slot }
			end
		end
	end
	if #list == 0 then
		Print(("No %s in your bags to attach."):format(kind.label:lower()))
		return
	end
	PO.AttachItems(list)
end

---------------------------------------------------------------------------
-- Default recipient box (right-click a button)
---------------------------------------------------------------------------

local function OpenRecipientBox(button)
	if not recipientBox then
		local f = CreateFrame("Frame", "KUKRecipientBox", UIParent, "BackdropTemplate")
		f:SetSize(240, 92)
		f:SetFrameStrata("DIALOG")
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
		f:EnableMouse(true)
		f.title = f:CreateFontString(nil, "OVERLAY")
		f.title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
		f.title:SetShadowOffset(1, -1)
		f.title:SetPoint("TOPLEFT", 12, -12)
		f.box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
		f.box:SetSize(210, 20)
		f.box:SetPoint("TOPLEFT", 16, -30)
		f.box:SetAutoFocus(true)
		local function save()
			SetRecipient(f.kind, f.box:GetText())
			f:Hide()
		end
		f.box:SetScript("OnEnterPressed", save)
		f.box:SetScript("OnEscapePressed", function() f:Hide() end)
		local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		ok:SetSize(70, 22)
		ok:SetPoint("BOTTOMRIGHT", -10, 10)
		ok:SetText("Save")
		ok:SetScript("OnClick", save)
		local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		clear:SetSize(70, 22)
		clear:SetPoint("RIGHT", ok, "LEFT", -6, 0)
		clear:SetText("Clear")
		clear:SetScript("OnClick", function()
			SetRecipient(f.kind, nil)
			f:Hide()
		end)
		recipientBox = f
	end
	local f = recipientBox
	f.kind = button.kind
	f.title:SetText("Default recipient for " .. button.kind.label)
	f.box:SetText(Recipient(button.kind) or "")
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", button, "TOPRIGHT", 6, 0)
	f:Show()
	f.box:SetFocus()
	f.box:HighlightText()
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

local function KindOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetText(self.kind.label, 1, 1, 1)
	local to = Recipient(self.kind)
	if to then GameTooltip:AddLine("Default recipient: |cffffffff" .. to .. "|r", 1, 0.82, 0) end
	GameTooltip:AddLine("Left-click: attach every matching item", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Right-click: set a default recipient", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function MakeButton(name, icon)
	local ok, b = pcall(CreateFrame, "Button", name, SendMailFrame, "ActionButtonTemplate")
	if not ok or not b then
		b = CreateFrame("Button", name, SendMailFrame)
		b:SetSize(36, 36)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	end
	b:SetScale(0.73)
	if b.icon then b.icon:SetTexture(icon) end
	b:RegisterForClicks("AnyUp")
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:Hide()
	return b
end

local function Place(b, row)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 0, -math.floor(b:GetHeight() + 0.5) * row)
end

-- If Postal is installed too, its QuickAttach buttons would sit on top of these; hide them.
local function HidePostalButtons()
	local i = 1
	while _G["Postal_QuickAttachButton" .. i] do
		local b = _G["Postal_QuickAttachButton" .. i]
		if not b.kukHidden then
			b:HookScript("OnShow", b.Hide)
			b.kukHidden = true
		end
		b:Hide()
		i = i + 1
	end
end

-- Show the chosen buttons in one column without gaps, then the settings button.
function ApplyVisibility()
	HidePostalButtons()
	local row = 0
	local hideAll = PO.IsQuickAttachHidden()
	for _, kind in ipairs(KINDS) do
		local b = buttons[kind.key]
		if b then
			if not hideAll and not KindHidden(kind) then
				Place(b, row)
				b:Show()
				row = row + 1
			else
				b:Hide()
			end
		end
	end
	if settingsButton then
		Place(settingsButton, row)
		settingsButton:Show()
	end
	if qaToggle then
		local file = hideAll and "NextPage" or "PrevPage"
		qaToggle:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. file .. "-Up")
		qaToggle:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. file .. "-Down")
	end
	if PO.Options and PO.Options.Refresh then PO.Options.Refresh() end
end
PO.QuickAttachApply = ApplyVisibility

local function ToggleOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(PO.IsQuickAttachHidden() and "Show QuickAttach buttons" or "Hide QuickAttach buttons", 1, 1, 1)
	GameTooltip:Show()
end

-- Made once, the first time the Send Mail tab opens.
function PO.QuickAttachCreate()
	if settingsButton then return end
	for i, kind in ipairs(KINDS) do
		local b = MakeButton("KUKQuickAttach" .. i, ICONS .. kind.icon)
		b.kind = kind
		b:SetScript("OnClick", function(self, mouse)
			if mouse == "RightButton" then OpenRecipientBox(self) else AttachKind(self.kind) end
		end)
		b:SetScript("OnEnter", KindOnEnter)
		buttons[kind.key] = b
	end

	settingsButton = MakeButton("KUKSettingsButton", "Interface\\Icons\\INV_Misc_Gear_01")
	settingsButton:SetScript("OnClick", function() PO.OpenOptions() end)
	settingsButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(PO.TITLE, 1, 1, 1)
		GameTooltip:AddLine("Settings", 1, 1, 1)
		GameTooltip:AddLine("Slot limit, which QuickAttach buttons to show, To field order and more. Same as /kuk.", nil, nil, nil, true)
		GameTooltip:Show()
	end)

	-- The small arrow above the window's top-right corner shows or hides the column.
	qaToggle = CreateFrame("Button", "KUKQuickAttachToggle", SendMailFrame)
	qaToggle:SetSize(24, 24)
	qaToggle:SetPoint("BOTTOMLEFT", MailFrame, "TOPRIGHT", 0, 2)
	qaToggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	qaToggle:SetScript("OnClick", function(self)
		KUK_ToggleQuickAttach()
		if GameTooltip:IsOwned(self) then ToggleOnEnter(self) end
	end)
	qaToggle:SetScript("OnEnter", ToggleOnEnter)
	qaToggle:SetScript("OnLeave", GameTooltip_Hide)

	ApplyVisibility()
end
