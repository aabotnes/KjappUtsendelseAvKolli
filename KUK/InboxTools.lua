-- [Soeta's] Kjapp Utsendelse av Kolli: inbox tools
--  * A tick box on every inbox row. With letters ticked, "Take ticked" and
--    "Return ticked" take the place of the game's Open All button.
--  * A return (curved arrow) or delete (red X) icon on every row. Delete is only
--    offered for letters with nothing left in them.
--  * Ctrl-click a row to send it back. Shift-click takes everything, as in the game.
--  * The mouse wheel over the inbox turns its pages.
--  * When you close the mailbox, chat says how much gold you collected.
--  * An open letter gets "Forward" and "Copy text" buttons.
-- Grouped rows (see Inbox.lua) act on every letter in the group.

KUK = KUK or {}
local PO = KUK

local ROWS = INBOXITEMS_TO_DISPLAY or 7
local STEP = 0.5 -- seconds between mail actions, so the server keeps up
local RETURN_ICON = "Interface\\PaperDollInfoFrame\\UI-GearManager-Undo"
local DELETE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local selected = {}  -- real letter index -> true
local rows = {}      -- row extras: { check, icon }
local queue          -- letters waiting for an action, highest index first
local lastCount
local takeButton, returnButton, hidOpenAll
local collected, lastMoney, mailOpen = 0, nil, false

local function DB()
	KUKDB = KUKDB or {}
	return KUKDB
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PO.TITLE .. ": " .. msg)
end

local function ToolsOn()
	return not DB().inboxToolsOff
end

local function Header(i)
	-- icon, stationery, sender, subject, money, cod, days, itemCount, read, returned, textCreated, canReply, isGM
	return PO.Inbox.real.GetInboxHeaderInfo(i)
end

-- What can be done with a letter: "return", "delete" or nil.
local function Action(i)
	local _, _, sender, _, money, cod, _, itemCount, _, wasReturned, _, _, isGM = Header(i)
	if not sender or isGM then return end
	if InboxItemCanDelete and InboxItemCanDelete(i) then
		if (money or 0) == 0 and (itemCount or 0) == 0 and (cod or 0) == 0 then return "delete" end
		return
	end
	if not wasReturned then return "return" end
end

local function SameAction(letters)
	local first = letters[1] and Action(letters[1])
	for _, m in ipairs(letters) do
		if Action(m) ~= first then return end
	end
	return first
end

---------------------------------------------------------------------------
-- Doing things to letters, one at a time
---------------------------------------------------------------------------

local UpdateSelection

local function Finish(msg)
	if msg then Print(msg) end
	queue = nil
	wipe(selected)
	if InboxFrame and InboxFrame:IsVisible() then InboxFrame:Update() end
	UpdateSelection()
end

local function Step()
	if not queue then return end
	if not (MailFrame and MailFrame:IsShown()) then return Finish() end
	local job = table.remove(queue, 1)
	if not job then return Finish() end
	local _, _, sender, subject, money, cod, _, itemCount = Header(job.index)
	-- The inbox may have changed since the letters were ticked; skip anything that moved.
	if sender == job.sender and subject == job.subject then
		if job.kind == "take" then
			if (cod or 0) == 0 and ((money or 0) > 0 or (itemCount or 0) > 0) then AutoLootMailItem(job.index) end
		elseif job.kind == "return" then
			ReturnInboxItem(job.index)
		elseif job.kind == "delete" then
			DeleteInboxItem(job.index)
		end
	end
	if #queue == 0 then
		C_Timer.After(STEP, function() if queue and #queue == 0 then Finish() end end)
	else
		C_Timer.After(STEP, Step)
	end
end

-- kind: "take", "return" or "delete" (nil = whatever each letter allows).
local function Run(kind, letters)
	if queue then return Print("Still busy with the last ones.") end
	local list = {}
	for _, i in ipairs(letters) do
		local k = kind or Action(i)
		if k == "take" or (k and Action(i) == k) then
			local _, _, sender, subject = Header(i)
			list[#list + 1] = { kind = k, index = i, sender = sender, subject = subject }
		end
	end
	if #list == 0 then return false end
	table.sort(list, function(a, b) return a.index > b.index end)
	queue = list
	Step()
	return true
end

---------------------------------------------------------------------------
-- Ticked letters
---------------------------------------------------------------------------

local function SelectedLetters()
	local list = {}
	for i in pairs(selected) do list[#list + 1] = i end
	return list
end

function UpdateSelection()
	if not takeButton then return end
	local n = #SelectedLetters()
	local show = ToolsOn() and n > 0 and InboxFrame and InboxFrame:IsVisible()
	takeButton:SetShown(show)
	returnButton:SetShown(show)
	if show then
		takeButton:SetText(("Take ticked (%d)"):format(n))
		local canReturn = 0
		for i in pairs(selected) do
			if Action(i) == "return" then canReturn = canReturn + 1 end
		end
		returnButton:SetEnabled(canReturn > 0 and not queue)
		takeButton:SetEnabled(not queue)
	end
	local openAll = InboxFrame and InboxFrame.OpenAllMail
	if openAll then
		if show and openAll:IsShown() then
			openAll:Hide()
			hidOpenAll = true
		elseif not show and hidOpenAll then
			openAll:Show()
			hidOpenAll = false
		end
	end
end

local function CreateSelectButtons()
	takeButton = CreateFrame("Button", "KUKTakeTicked", InboxFrame, "UIPanelButtonTemplate")
	takeButton:SetSize(118, 24)
	takeButton:SetPoint("BOTTOMRIGHT", InboxFrame, "BOTTOM", -2, 14)
	takeButton:SetScript("OnClick", function()
		Run("take", SelectedLetters())
		UpdateSelection()
	end)
	takeButton:Hide()
	returnButton = CreateFrame("Button", "KUKReturnTicked", InboxFrame, "UIPanelButtonTemplate")
	returnButton:SetSize(118, 24)
	returnButton:SetPoint("BOTTOMLEFT", InboxFrame, "BOTTOM", 2, 14)
	returnButton:SetText("Return ticked")
	returnButton:SetScript("OnClick", function()
		Run("return", SelectedLetters())
		UpdateSelection()
	end)
	returnButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Sends the ticked letters back to their senders.", 1, 1, 1, 1, true)
		GameTooltip:AddLine("Letters from the auction house and the game can't be returned and are skipped.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	returnButton:SetScript("OnLeave", GameTooltip_Hide)
	returnButton:Hide()
end

---------------------------------------------------------------------------
-- Row extras
---------------------------------------------------------------------------

local function IconOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local n = self.letters and #self.letters or 1
	if self.action == "return" then
		GameTooltip:SetText(n > 1 and ("Return all %d letters"):format(n) or "Return to sender", 1, 1, 1)
	else
		GameTooltip:SetText(n > 1 and ("Delete all %d letters"):format(n) or "Delete", 1, 1, 1)
		GameTooltip:AddLine("Only offered for letters with nothing left in them.", nil, nil, nil, true)
	end
	GameTooltip:Show()
end

local function CreateRow(i)
	local row = _G["MailItem" .. i]
	if not row then return end
	local r = {}
	r.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	r.check:SetSize(20, 20)
	r.check:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
	r.check:SetScript("OnClick", function(self)
		for _, m in ipairs(r.letters or {}) do selected[m] = self:GetChecked() and true or nil end
		UpdateSelection()
	end)
	r.check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Tick to take or return several letters at once.", 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	r.check:SetScript("OnLeave", GameTooltip_Hide)

	r.icon = CreateFrame("Button", nil, row)
	r.icon:SetSize(16, 16)
	r.icon:SetPoint("RIGHT", r.check, "LEFT", -3, 0)
	r.icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	r.icon:SetScript("OnClick", function(self)
		Run(self.action, self.letters or {})
	end)
	r.icon:SetScript("OnEnter", IconOnEnter)
	r.icon:SetScript("OnLeave", GameTooltip_Hide)

	-- Make room for the two at the end of the subject line.
	local subject = _G["MailItem" .. i .. "Subject"]
	if subject then subject:SetWidth(205) end
	rows[i] = r
	return r
end

-- Called by Inbox.lua after every redraw of the inbox list.
function PO.AfterInboxDraw()
	if not InboxFrame then return end
	local count = PO.Inbox.real.GetInboxNumItems() or 0
	if lastCount and count ~= lastCount and not queue then wipe(selected) end
	lastCount = count
	for i = 1, ROWS do
		local r = rows[i] or CreateRow(i)
		if r then
			local button = _G["MailItem" .. i .. "Button"]
			local letters = ToolsOn() and button and button:IsShown() and PO.Inbox.RowLetters(i)
			r.letters = letters or nil
			if letters then
				local all = true
				for _, m in ipairs(letters) do
					if not selected[m] then all = false end
				end
				r.check:SetChecked(all)
				r.check:Show()
				local action = SameAction(letters)
				r.icon.action, r.icon.letters = action, letters
				if action then
					r.icon:SetNormalTexture(action == "return" and RETURN_ICON or DELETE_ICON)
					r.icon:Show()
				else
					r.icon:Hide()
				end
			else
				r.check:Hide()
				r.icon:Hide()
			end
		end
	end
	UpdateSelection()
end

-- Ctrl-click a row: return its letter (or every letter in its group).
function PO.InboxRowClick(_, index)
	if not ToolsOn() or not IsControlKeyDown() or not index then return false end
	local letters = PO.Inbox.Group(index)
	if not Run("return", letters) then
		Print("That letter can't be returned.")
	end
	return true
end

---------------------------------------------------------------------------
-- Mouse wheel pages, gold collected
---------------------------------------------------------------------------

local function TurnPage(_, delta)
	local b = delta > 0 and _G.InboxPrevPageButton or _G.InboxNextPageButton
	if b and b:IsShown() and b:IsEnabled() then b:Click() end
end

local function MoneyChanged()
	if not mailOpen then return end
	local now = GetMoney()
	if lastMoney and now > lastMoney then collected = collected + (now - lastMoney) end
	lastMoney = now
end

---------------------------------------------------------------------------
-- Forward and copy text
---------------------------------------------------------------------------

local copyFrame

local function OpenLetter()
	local id = InboxFrame and InboxFrame.openMailID
	if not id or id == 0 then return end
	local _, _, sender, subject = Header(id)
	local body = PO.Inbox.real.GetInboxText(id) or ""
	return sender or "", subject or "", body
end

local function Forward()
	local sender, subject, body = OpenLetter()
	if not sender then return end
	if MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
	SendMailNameEditBox:SetText("")
	SendMailSubjectEditBox:SetText("FW: " .. subject)
	SendMailBodyEditBox:SetText(("\n\n--- Letter from %s ---\n%s"):format(sender, body))
	SendMailNameEditBox:SetFocus()
end

local function ShowCopy()
	local sender, subject, body = OpenLetter()
	if not sender then return end
	if not copyFrame then
		local f = CreateFrame("Frame", "KUKCopyFrame", UIParent, "BackdropTemplate")
		f:SetSize(380, 280)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		local title = f:CreateFontString(nil, "OVERLAY")
		title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
		title:SetShadowOffset(1, -1)
		title:SetPoint("TOPLEFT", 12, -12)
		title:SetText("Press Ctrl+C to copy, Esc to close")
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 0, 0)
		local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		if not ok or not scroll then scroll = CreateFrame("ScrollFrame", nil, f) end
		scroll:SetPoint("TOPLEFT", 12, -34)
		scroll:SetPoint("BOTTOMRIGHT", -30, 12)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(330)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(edit)
		f.edit = edit
		tinsert(UISpecialFrames, "KUKCopyFrame")
		copyFrame = f
	end
	copyFrame.edit:SetText(("From: %s\nSubject: %s\n\n%s"):format(sender, subject, body))
	copyFrame:Show()
	copyFrame.edit:SetFocus()
	copyFrame.edit:HighlightText()
end

local function CreateLetterButtons()
	if not OpenMailFrame or _G.KUKForwardButton then return end
	local fwd = CreateFrame("Button", "KUKForwardButton", OpenMailFrame, "UIPanelButtonTemplate")
	fwd:SetSize(74, 22)
	if OpenMailReplyButton then
		fwd:SetPoint("RIGHT", OpenMailReplyButton, "LEFT", 0, 0)
	else
		fwd:SetPoint("BOTTOMLEFT", 8, 4)
	end
	fwd:SetText("Forward")
	fwd:SetScript("OnClick", Forward)
	fwd:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Forward", 1, 1, 1)
		GameTooltip:AddLine("Starts a new letter with this one's subject and text. Attachments don't come along: take them first and attach them.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	fwd:SetScript("OnLeave", GameTooltip_Hide)

	local copy = CreateFrame("Button", "KUKCopyButton", OpenMailFrame)
	copy:SetSize(18, 18)
	local close = OpenMailFrame.CloseButton or _G.OpenMailFrameCloseButton
	if close then
		copy:SetPoint("RIGHT", close, "LEFT", -2, 0)
	else
		copy:SetPoint("TOPRIGHT", -30, -3)
	end
	copy:SetFrameLevel(OpenMailFrame:GetFrameLevel() + 10)
	copy:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
	copy:SetPushedTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Down")
	copy:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	copy:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Copy text", 1, 1, 1)
		GameTooltip:AddLine("Shows the letter's text so you can copy it.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	copy:SetScript("OnLeave", GameTooltip_Hide)
	copy:SetScript("OnClick", ShowCopy)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function IsMailPane(paneType)
	return Enum and Enum.PlayerInteractionType and paneType == Enum.PlayerInteractionType.MailInfo
end

local function Opened()
	if mailOpen then return end
	mailOpen = true
	collected, lastMoney = 0, GetMoney()
	if InboxFrame and not takeButton then
		CreateSelectButtons()
		InboxFrame:EnableMouseWheel(true)
		InboxFrame:HookScript("OnMouseWheel", TurnPage)
		InboxFrame:HookScript("OnHide", UpdateSelection)
	end
	CreateLetterButtons()
end

local function Closed()
	if not mailOpen then return end
	mailOpen = false
	MoneyChanged()
	if collected > 0 then Print("Collected " .. PO.MoneyText(collected) .. " from the mailbox.") end
	collected, lastMoney, queue = 0, nil, nil
	wipe(selected)
end

local events = CreateFrame("Frame")
for _, event in ipairs({
	"PLAYER_LOGIN", "MAIL_SHOW", "MAIL_CLOSED", "PLAYER_MONEY", "UI_ERROR_MESSAGE",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
}) do
	if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
		pcall(events.RegisterEvent, events, event)
	end
end
events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		if MailFrame then
			MailFrame:HookScript("OnShow", Opened)
			MailFrame:HookScript("OnHide", Closed)
		end
	elseif event == "MAIL_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and IsMailPane(...)) then
		Opened()
	elseif event == "MAIL_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and IsMailPane(...)) then
		Closed()
	elseif event == "PLAYER_MONEY" then
		MoneyChanged()
	elseif event == "UI_ERROR_MESSAGE" then
		local _, msg = ...
		if queue and (msg == ERR_INV_FULL or msg == ERR_ITEM_MAX_COUNT) then
			-- Bags full: stop taking items, but keep going with returns and deletes.
			local keep = {}
			for _, job in ipairs(queue) do
				if job.kind ~= "take" then keep[#keep + 1] = job end
			end
			queue = keep
			Print("Your bags are full, so the rest stays in the mail.")
		end
	end
end)

function PO.SetInboxToolsOff(off)
	DB().inboxToolsOff = off and true or nil
	if off then wipe(selected) end
	if InboxFrame and InboxFrame:IsVisible() then InboxFrame:Update() end
end
