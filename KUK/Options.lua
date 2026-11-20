-- [Soeta's] Kjapp Utsendelse av Kolli: settings
-- Two pages, "General" and "QuickAttach buttons". They're listed in the game's
-- options (Esc > Options > AddOns) and also open in their own small window from
-- /kuk, the minimap button or the gear button under the QuickAttach buttons.
-- That window doesn't close the mailbox, which the game's options screen might.
-- Text uses the same font and colors as the other [Soeta's] addons.

KUK = KUK or {}
local PO = KUK

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local C = {
	accent = { 0.38, 0.56, 1.00, 1 },
	text   = { 0.93, 0.94, 0.96, 1 },
	muted  = { 0.57, 0.60, 0.67, 1 },
	line   = { 1, 1, 1, 0.06 },
}

local function DB()
	KUKDB = KUKDB or {}
	return KUKDB
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PO.TITLE .. ": " .. msg)
end

local general = CreateFrame("Frame", "KUKOptions")
general:Hide()
local quick = CreateFrame("Frame", "KUKQuickAttachOptions")
quick:Hide()
local widgets = {}
local Refresh

---------------------------------------------------------------------------
-- Text in the [Soeta's] style
---------------------------------------------------------------------------

local function Text(parent, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size or 12, "")
	fs:SetTextColor(unpack(color or C.text))
	fs:SetJustifyH(justify or "LEFT")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 0.6)
	return fs
end

local function Title(parent, text)
	local fs = Text(parent, 18)
	fs:SetPoint("TOPLEFT", 16, -16)
	fs:SetText(text)
	return fs
end

-- Small blue capitals with a thin line under them.
local function Heading(parent, text, anchor, y)
	local fs = Text(parent, 10, C.accent)
	fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -18)
	fs:SetText(text:upper())
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(unpack(C.line))
	line:SetHeight(1)
	line:SetWidth(540)
	line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -5)
	fs.line = line
	return fs
end

local function Note(parent, text, anchor, y)
	local fs = Text(parent, 11, C.muted)
	fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -4)
	fs:SetWidth(540)
	fs:SetWordWrap(true)
	fs:SetText(text)
	return fs
end

local function CheckBox(parent, label, onClick)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	cb.label = Text(cb, 12)
	cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
	cb.label:SetText(label or "")
	cb:SetScript("OnClick", function(self)
		onClick(self:GetChecked() and true or false, self)
		Refresh()
	end)
	return cb
end

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", function()
		onClick()
		Refresh()
	end)
	return b
end

local function ArrowButton(parent, dir, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	local file = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. (dir < 0 and "Up" or "Down") .. "Button-"
	b:SetNormalTexture(file .. "Up")
	b:SetPushedTexture(file .. "Down")
	b:SetDisabledTexture(file .. "Disabled")
	b:SetHighlightTexture(file .. "Highlight", "ADD")
	b:SetScript("OnClick", function()
		onClick()
		Refresh()
	end)
	return b
end

local function SetMax(n)
	local value, adjusted, lowest = PO.SetMaxItems(n)
	if adjusted and tonumber(n) and tonumber(n) < lowest then
		Print(("The limit can't go below %d while an item is in slot %d. Take it out first."):format(lowest, lowest))
	end
	return value
end

---------------------------------------------------------------------------
-- General page
---------------------------------------------------------------------------

local function BuildGeneral()
	local f = general
	local title = Title(f, PO.TITLE)
	local sub = Note(f, "More attachment slots, grouped inbox letters and a To field that finds your own characters first.", title, -6)

	-- Send Mail
	local send = Heading(f, "Send Mail", sub, -18)
	local slotsLabel = Text(f, 12)
	slotsLabel:SetPoint("TOPLEFT", send, "BOTTOMLEFT", 0, -16)
	slotsLabel:SetText("Attachment slots:")

	local minus = Button(f, "-", 26, function() SetMax(PO.GetMaxItems() - (IsShiftKeyDown() and 12 or 1)) end)
	minus:SetPoint("LEFT", slotsLabel, "RIGHT", 10, 0)
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(42, 20)
	box:SetPoint("LEFT", minus, "RIGHT", 10, 0)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(3)
	box:SetJustifyH("CENTER")
	box:SetScript("OnEnterPressed", function(self)
		SetMax(self:GetNumber())
		self:ClearFocus()
		Refresh()
	end)
	box:SetScript("OnEditFocusLost", function() Refresh() end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	local plus = Button(f, "+", 26, function() SetMax(PO.GetMaxItems() + (IsShiftKeyDown() and 12 or 1)) end)
	plus:SetPoint("LEFT", box, "RIGHT", 6, 0)
	local default = Button(f, "Default", 70, function() SetMax(PO.DEFAULT_ITEMS) end)
	default:SetPoint("LEFT", plus, "RIGHT", 10, 0)
	widgets.maxBox = box

	local slotsNote = Note(f, ("From %d to %d (default %d, which is 3 letters of 12). Shift-click - or + for steps of 12. Items past the first 12 are sent as follow-up letters of 12 to the same person."):format(PO.MIN_ITEMS, PO.MAX_ITEMS, PO.DEFAULT_ITEMS), slotsLabel, -10)

	local sizeNote = Note(f, "Drag the bottom-right corner of the Send Mail window down to show more rows of slots. The mouse wheel scrolls the slots when they don't all fit.", slotsNote, -10)
	local resetSize = Button(f, "Normal window size", 150, function() PO.SetAddedRows(0) end)
	resetSize:SetPoint("TOPLEFT", sizeNote, "BOTTOMLEFT", 0, -6)

	widgets.autoSubject = CheckBox(f, "Fill in the subject from the first item when it's empty", function(on)
		PO.SetAutoSubject(on)
	end)
	widgets.autoSubject:SetPoint("TOPLEFT", resetSize, "BOTTOMLEFT", 0, -8)
	widgets.minimap = CheckBox(f, "Show minimap button", function(on)
		if PO.Minimap then PO.Minimap:SetShown(on) end
	end)
	widgets.minimap:SetPoint("TOPLEFT", widgets.autoSubject, "BOTTOMLEFT", 0, -2)

	-- Inbox
	local inbox = Heading(f, "Inbox", widgets.minimap, -14)
	widgets.grouping = CheckBox(f, "Show letters from one sender with the same subject and text as one row", function(on)
		PO.SetGroupingOff(not on)
	end)
	widgets.grouping:SetPoint("TOPLEFT", inbox, "BOTTOMLEFT", 0, -10)

	-- To field
	local to = Heading(f, "To field: fill in names from, in this order", widgets.grouping, -14)
	local toNote = Note(f, "Takes the first match while you type. Unticked sources are skipped. Postal's own \"Use AutoComplete\" switch in its BlackBook menu still turns this off completely.", to, -12)
	widgets.rows = {}
	local prev = toNote
	for i = 1, 5 do
		local row = {}
		row.check = CheckBox(f, nil, function(on) PO.SetToSourceOn(row.key, on) end)
		row.check:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -8 or -2)
		row.up = ArrowButton(f, -1, function() PO.MoveToSource(row.key, -1) end)
		row.up:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
		row.down = ArrowButton(f, 1, function() PO.MoveToSource(row.key, 1) end)
		row.down:SetPoint("LEFT", row.up, "RIGHT", 0, 0)
		row.label = Text(f, 12)
		row.label:SetPoint("LEFT", row.down, "RIGHT", 8, 0)
		widgets.rows[i] = row
		prev = row.check
	end
	local resetOrder = Button(f, "Default order", 120, function() PO.ResetToOrder() end)
	resetOrder:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -8)
end

---------------------------------------------------------------------------
-- QuickAttach buttons page
---------------------------------------------------------------------------

local qaRows = {}

local function OpenProfileMenu(owner)
	local names = PO.GetQAProfiles()
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			for _, name in ipairs(names) do
				root:CreateRadio(name,
					function() return PO.GetQAProfileName() == name end,
					function()
						PO.SetQAProfile(name)
						Refresh()
					end)
			end
		end)
	else
		-- No menu available: step to the next profile instead.
		local current, nextName = PO.GetQAProfileName(), names[1]
		for i, name in ipairs(names) do
			if name == current then nextName = names[i % #names + 1] end
		end
		PO.SetQAProfile(nextName)
		Refresh()
	end
end

local function BuildQuick()
	local f = quick
	local title = Title(f, "QuickAttach buttons")
	local note = Note(f, "Choose which of Postal's QuickAttach buttons (Cloth, Leather and so on) are shown down the right side of the Send Mail window. The shown ones close up so there are no gaps, and the gear button under them opens these options. Which bags the buttons take items from is set in Postal's own menu, under QuickAttach.", title, -8)

	-- Profiles
	local profiles = Heading(f, "Profile", note, -16)
	local profileLabel = Text(f, 12)
	profileLabel:SetPoint("TOPLEFT", profiles, "BOTTOMLEFT", 0, -18)
	widgets.profileLabel = profileLabel
	local pick = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	pick:SetSize(170, 22)
	pick:SetPoint("LEFT", profileLabel, "RIGHT", 10, 0)
	pick:SetScript("OnClick", OpenProfileMenu)
	widgets.profilePick = pick
	local delete = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	delete:SetSize(110, 22)
	delete:SetPoint("LEFT", pick, "RIGHT", 8, 0)
	delete:SetScript("OnClick", function(self)
		-- Ask once more before deleting.
		if not self.armed then
			self.armed = true
			self:SetText("Really delete?")
			C_Timer.After(3, function()
				self.armed = false
				Refresh()
			end)
			return
		end
		self.armed = false
		local name = PO.GetQAProfileName()
		if PO.DeleteQAProfile(name) then Print(("Deleted the QuickAttach profile %s."):format(name)) end
		Refresh()
	end)
	widgets.profileDelete = delete

	local newLabel = Text(f, 12)
	newLabel:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -18)
	newLabel:SetText("New profile:")
	local nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	nameBox:SetSize(160, 20)
	nameBox:SetPoint("LEFT", newLabel, "RIGHT", 14, 0)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(40)
	local function Create()
		local ok, err = PO.NewQAProfile(nameBox:GetText())
		if ok then
			nameBox:SetText("")
			nameBox:ClearFocus()
		else
			Print(err)
		end
		Refresh()
	end
	nameBox:SetScript("OnEnterPressed", Create)
	nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	local create = Button(f, "Create", 80, Create)
	create:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
	widgets.profileName = nameBox
	widgets.profileNote = Note(f, "", newLabel, -10)

	-- Buttons
	local buttons = Heading(f, "Buttons", widgets.profileNote, -16)
	widgets.showQA = CheckBox(f, "Show QuickAttach buttons", function(on) PO.SetQuickAttachHidden(not on) end)
	widgets.showQA:SetPoint("TOPLEFT", buttons, "BOTTOMLEFT", 0, -10)
	local all = Button(f, "Tick all", 80, function() PO.ShowAllQuickAttachButtons() end)
	all:SetPoint("LEFT", widgets.showQA.label, "RIGHT", 20, 0)
	local default = Button(f, "Default", 80, function() PO.DefaultQuickAttachButtons() end)
	default:SetPoint("LEFT", all, "RIGHT", 8, 0)
	widgets.qaAnchor = widgets.showQA
	widgets.qaEmpty = Note(f, "", widgets.showQA, -12)
end

local function RefreshQuick()
	local profile = PO.GetQAProfileName()
	widgets.profileLabel:SetText(("Profile for %s:"):format(PO.CurrentCharacter()))
	widgets.profilePick:SetText(profile)
	if not widgets.profileDelete.armed then widgets.profileDelete:SetText("Delete profile") end
	widgets.profileDelete:SetEnabled(profile ~= "Default")
	local users = PO.GetQAProfileUsers(profile)
	local usedBy = #users > 0 and table.concat(users, ", ") or "nobody picked it yet"
	if profile == "Default" then
		widgets.profileNote:SetText("Each character picks its own profile; characters that never picked one use Default. A new profile starts as a copy of the one in use, and this character switches to it.")
	else
		widgets.profileNote:SetText(("Used by: %s. A new profile starts as a copy of this one, and this character switches to it."):format(usedBy))
	end
	widgets.showQA:SetChecked(not PO.IsQuickAttachHidden())
	local list, enabled = PO.GetQuickAttachButtons()
	if #list == 0 or not enabled then
		widgets.qaEmpty:SetText(not enabled
			and "Postal's QuickAttach module is turned off, so there are no buttons. Turn it on in Postal's menu."
			or "Postal hasn't made its QuickAttach buttons yet. Open the Send Mail tab at a mailbox once, then come back here.")
		widgets.qaEmpty:Show()
	else
		widgets.qaEmpty:Hide()
	end
	local perColumn = math.ceil(#list / 2)
	for i, item in ipairs(list) do
		local row = qaRows[i]
		if not row then
			row = {}
			row.check = CheckBox(quick, nil, function(on) PO.SetQuickAttachButtonShown(row.key, on) end)
			row.icon = quick:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(20, 20)
			row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
			row.check.label:ClearAllPoints()
			row.check.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
			qaRows[i] = row
		end
		local col, line = math.floor((i - 1) / perColumn), (i - 1) % perColumn
		row.check:ClearAllPoints()
		row.check:SetPoint("TOPLEFT", widgets.qaAnchor, "BOTTOMLEFT", col * 270, -12 - line * 28)
		row.key = item.key
		row.icon:SetTexture(item.icon)
		row.check.label:SetText(item.notInForever and (item.label .. "  |cff8a8f9a(not in Forever)|r") or item.label)
		row.check:SetChecked(item.shown)
		local active = enabled and not PO.IsQuickAttachHidden()
		row.check:SetEnabled(active)
		row.icon:SetDesaturated(not (active and item.shown))
		row.check.label:SetTextColor(unpack((active and item.shown) and C.text or C.muted))
		row.check:Show()
		row.icon:Show()
	end
	for i = #list + 1, #qaRows do
		qaRows[i].check:Hide()
		qaRows[i].icon:Hide()
	end
end

---------------------------------------------------------------------------
-- Refresh both pages
---------------------------------------------------------------------------

function Refresh()
	if widgets.maxBox and general:IsVisible() then
		if not widgets.maxBox:HasFocus() then widgets.maxBox:SetNumber(PO.GetMaxItems()) end
		widgets.grouping:SetChecked(not DB().groupingOff)
		widgets.autoSubject:SetChecked(not DB().autoSubjectOff)
		widgets.minimap:SetChecked(PO.Minimap and PO.Minimap:IsShown() or false)
		local order = PO.GetToOrder()
		for i, row in ipairs(widgets.rows) do
			local key = order[i]
			row.key = key
			local on = PO.IsToSourceOn(key)
			row.check:SetChecked(on)
			row.label:SetText(("%d. %s"):format(i, PO.TO_SOURCES[key]))
			row.label:SetTextColor(unpack(on and C.text or C.muted))
			row.up:SetEnabled(i > 1)
			row.down:SetEnabled(i < #order)
		end
	end
	if widgets.showQA and quick:IsVisible() then RefreshQuick() end
end

general:SetScript("OnShow", Refresh)
quick:SetScript("OnShow", Refresh)
BuildGeneral()
BuildQuick()

---------------------------------------------------------------------------
-- The options window
---------------------------------------------------------------------------

local window, tabs

local function ShowPage(page)
	for _, f in ipairs({ general, quick }) do
		f:SetParent(window)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", window, "TOPLEFT", 6, -58)
		f:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -6, 6)
		f:SetShown(f == page)
	end
	for _, tab in ipairs(tabs) do tab:SetEnabled(tab.page ~= page) end
	window.page = page
end

local function CreateWindow()
	local ok
	ok, window = pcall(CreateFrame, "Frame", "KUKOptionsWindow", UIParent, "BasicFrameTemplateWithInset")
	if not ok or not window then
		window = CreateFrame("Frame", "KUKOptionsWindow", UIParent)
		local bg = window:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
		local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 2, 2)
	end
	window:SetSize(600, 740)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	local title = Text(window, 12)
	title:SetPoint("TOP", 0, -5)
	title:SetText(PO.TITLE)
	tabs = {}
	for i, info in ipairs({ { "General", general }, { "QuickAttach buttons", quick } }) do
		local tab = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
		tab:SetSize(150, 22)
		tab:SetPoint("TOPLEFT", 12 + (i - 1) * 156, -30)
		tab:SetText(info[1])
		tab.page = info[2]
		tab:SetScript("OnClick", function(self) ShowPage(self.page) end)
		tabs[i] = tab
	end
	window:SetScript("OnHide", function()
		general:Hide()
		quick:Hide()
	end)
	tinsert(UISpecialFrames, "KUKOptionsWindow") -- Esc closes it
	window:Hide()
end

-- Open the options window, on the QuickAttach page if asked.
function PO.OpenOptions(page)
	if not window then CreateWindow() end
	window:Show()
	ShowPage((page == "quickattach" or page == "quick") and quick or (window.page or general))
	Refresh()
end

-- Used by the minimap button.
PO.Options = {
	Open = function(_, page) PO.OpenOptions(page) end,
	Toggle = function()
		if window and window:IsShown() then window:Hide() else PO.OpenOptions() end
	end,
	Refresh = function() Refresh() end,
}

-- The game's addon compartment (the addons button by the minimap), named in the TOC.
function KUK_OnAddonCompartmentClick()
	PO.Options:Toggle()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	local name = "|cffc27dff[Soeta's]|r " .. PO.NAME
	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(general, name)
		if Settings.RegisterCanvasLayoutSubcategory then
			Settings.RegisterCanvasLayoutSubcategory(category, quick, "QuickAttach buttons")
		end
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		general.name = name
		InterfaceOptions_AddCategory(general)
		quick.name, quick.parent = "QuickAttach buttons", name
		InterfaceOptions_AddCategory(quick)
	end
	if PO.Minimap then PO.Minimap:Init() end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_KUK1 = "/kuk"
SlashCmdList.KUK = function(msg)
	msg = strtrim(msg or ""):lower()
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	if cmd == "" or cmd == "options" or cmd == "config" then
		PO.Options:Toggle()
	elseif cmd == "qa" or cmd == "quickattach" then
		PO.OpenOptions("quickattach")
	elseif cmd == "group" or cmd == "grouping" then
		PO.SetGroupingOff(not DB().groupingOff)
		Print("Inbox grouping is now " .. (DB().groupingOff and "off" or "on") .. ".")
	elseif cmd == "icons" then
		local hidden = KUK_ToggleQuickAttach()
		Print("QuickAttach buttons are now " .. (hidden and "hidden" or "shown") .. ".")
	elseif cmd == "find" then
		PO.DebugFind(rest, Print)
	elseif cmd == "minimap" then
		if PO.Minimap then PO.Minimap:Toggle() end
	elseif cmd == "max" then
		if tonumber(rest) then SetMax(tonumber(rest)) end
		Print(("Attachment slots: %d (from %d to %d)."):format(PO.GetMaxItems(), PO.MIN_ITEMS, PO.MAX_ITEMS))
	elseif cmd == "to" then
		if rest ~= "" then
			-- The sources named come first, in that order, and are switched on; the rest are switched off.
			local order, named = {}, {}
			for word in rest:gmatch("%a+") do
				if PO.TO_SOURCES[word] and not named[word] then
					order[#order + 1], named[word] = word, true
				end
			end
			if #order == 0 then
				Print("Sources: alts, friends, guild, recent, contacts.")
				return
			end
			for key in pairs(PO.TO_SOURCES) do
				PO.SetToSourceOn(key, named[key] or false)
				if not named[key] then order[#order + 1] = key end
			end
			PO.SetToOrder(order)
		end
		local list = {}
		for _, key in ipairs(PO.GetToOrder()) do
			if PO.IsToSourceOn(key) then list[#list + 1] = key end
		end
		Print("To field order: " .. (#list > 0 and table.concat(list, ", ") or "nothing (all switched off)") .. ".")
	else
		Print("/kuk - open the settings")
		Print("/kuk qa - choose which QuickAttach buttons to show")
		Print("/kuk max 36 - number of attachment slots")
		Print("/kuk to alts friends guild recent contacts - To field order (left out = off)")
		Print("/kuk find gi - what the To field would fill in for gi, and why")
		Print("/kuk group - inbox grouping on or off")
		Print("/kuk icons - show or hide all QuickAttach buttons")
		Print("/kuk minimap - show or hide the minimap button")
	end
	Refresh()
end
