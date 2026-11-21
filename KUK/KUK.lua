-- [Soeta's] Kjapp Utsendelse av Kolli (K.U.K., "quick dispatch of parcels")
-- Gives the Send Mail window more attachment slots than the game's 12 (36 by
-- default, set in the options). The extra slots continue the game's own grid in
-- reading order (top left is first, new rows underneath), every item stays in the
-- slot you put it in, and the grid scrolls once it has more rows than fit. The
-- window can be made taller from its bottom-right corner to show more rows.
-- When the letter is sent, the extra items follow to the same recipient in
-- letters of up to 12, because the game itself only allows 12 per letter.

KUK = KUK or {}
local PO = KUK
KUK.NAME = "Kjapp Utsendelse av Kolli"
KUK.TITLE = "|cffc27dff[Soeta's]|r |cff33ff99Kjapp Utsendelse av Kolli|r"
KUK.ICON = "Interface/Icons/INV_Crate_04"

local MAX = ATTACHMENTS_MAX_SEND or 12     -- real slots per letter
local PER_ROW = ATTACHMENTS_PER_ROW_SEND or 7
local DEFAULT_ITEMS, MAX_ITEMS = 36, 120   -- slot limit: default (3 letters of 12) and highest allowed
local EXTRA_CAP = MAX_ITEMS - MAX          -- highest extra slot that can ever exist
local SUBJECT_MAX = 64

local extra = {}        -- extra[n] = { bag, slot, link, count, icon } or nil (empty slot)
local run               -- multi-letter send in progress, or nil
local attaching = false -- true while this addon attaches items itself
local sending = false   -- true while this addon calls SendMail itself
local autoBlocked = false -- the game refused to move items outside a click
local lastPick          -- { bag, slot } of the last item picked up from the bags
local panel, nextButton
local UpdatePanel, RevealPosition

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(KUK.TITLE .. ": " .. msg)
end
PO.Print = Print

local function DB()
	KUKDB = KUKDB or {}
	return KUKDB
end
PO.DB = DB

local function LastBag()
	return (NUM_BAG_FRAMES or 4) + (NUM_REAGENTBAG_FRAMES or 0)
end

local function SendTabOpen()
	return SendMailFrame and SendMailFrame:IsVisible()
end

-- Total number of attachment slots in the window (12 real ones plus the extras).
local function MaxItems()
	local n = math.floor(tonumber(DB().maxItems) or DEFAULT_ITEMS)
	return math.max(MAX, math.min(MAX_ITEMS, n))
end

local function ExtraMax()
	return MaxItems() - MAX
end

local function AttachedCount()
	local n = 0
	for i = 1, MAX do
		if HasSendMailItem(i) then n = n + 1 end
	end
	return n
end

local function ExtraCount()
	local n = 0
	for p = 1, EXTRA_CAP do
		if extra[p] then n = n + 1 end
	end
	return n
end

local function LastUsedExtra()
	for p = EXTRA_CAP, 1, -1 do
		if extra[p] then return p end
	end
	return 0
end

local function FirstFreeExtra()
	for p = 1, ExtraMax() do
		if not extra[p] then return p end
	end
end

local function FindQueued(bag, slot)
	for p = 1, EXTRA_CAP do
		local e = extra[p]
		if e and e.bag == bag and e.slot == slot then return p end
	end
end

local function FullMessage()
	Print(("All %d attachment slots are full. You can raise the limit with /kuk."):format(MaxItems()))
end

-- Find where an item is in the bags now, in case it was moved. False if it's gone.
local function ResolveEntry(e, claimed)
	claimed = claimed or {}
	local function matches(bag, slot)
		if claimed[bag * 1000 + slot] then return false end
		local info = C_Container.GetContainerItemInfo(bag, slot)
		return info and not info.isLocked and info.hyperlink == e.link and info.stackCount == e.count
	end
	if not matches(e.bag, e.slot) then
		local found = false
		for bag = 0, LastBag() do
			for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
				if matches(bag, slot) then
					e.bag, e.slot, found = bag, slot, true
					break
				end
			end
			if found then break end
		end
		if not found then return false end
	end
	claimed[e.bag * 1000 + e.slot] = true
	return true
end

-- Empty any extra slot whose item is gone (sold, used, attached by hand).
local function Resolve()
	local claimed, lost = {}, 0
	for p = 1, EXTRA_CAP do
		if extra[p] and not ResolveEntry(extra[p], claimed) then
			extra[p] = nil
			lost = lost + 1
		end
	end
	return lost
end

-- Put a bag item in an extra slot: the given one, or the first empty one.
local function AddToQueue(bag, slot, quiet, pos)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.hyperlink then return false end
	if info.isBound then
		if not quiet then Print(info.hyperlink .. " is soulbound and can't be mailed.") end
		return false
	end
	local existing = FindQueued(bag, slot)
	if existing and not pos then return false end
	pos = pos or FirstFreeExtra()
	if not pos then
		if not quiet then FullMessage() end
		return false
	end
	if existing then extra[existing] = nil end
	extra[pos] = {
		bag = bag, slot = slot,
		link = info.hyperlink, count = info.stackCount or 1, icon = info.iconFileID,
	}
	return pos
end

-- The bag slot of the item currently on the cursor, if it came from the bags.
local function CursorBagSlot()
	local kind, itemID = GetCursorInfo()
	if kind ~= "item" or not lastPick then return end
	local info = C_Container.GetContainerItemInfo(lastPick[1], lastPick[2])
	if info and info.isLocked and info.itemID == itemID then
		return lastPick[1], lastPick[2]
	end
end

-- Put the item on the cursor into the first empty extra slot.
local function QueueCursorItem()
	local bag, slot = CursorBagSlot()
	if not bag then return end
	if not FirstFreeExtra() then return FullMessage() end
	ClearCursor()
	local pos = AddToQueue(bag, slot)
	if pos then RevealPosition(MAX + pos) end
	UpdatePanel()
end

-- Put the item on the cursor into extra slot p. If p holds an item, the two swap
-- and the old one ends up on the cursor, like the game's own attachment slots.
local function PlaceCursorAt(p)
	local bag, slot = CursorBagSlot()
	if not bag then return end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if info and info.isBound then
		Print((info.hyperlink or "That item") .. " is soulbound and can't be mailed.")
		return
	end
	local old = extra[p]
	if old and old.bag == bag and old.slot == slot then
		ClearCursor()
		return
	end
	ClearCursor()
	extra[p] = nil
	if not AddToQueue(bag, slot, false, p) then
		extra[p] = old
		return
	end
	if old and ResolveEntry(old) then C_Container.PickupContainerItem(old.bag, old.slot) end
	UpdatePanel()
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- Attach the next items waiting to be sent into the free real slots.
local function AttachNext()
	if GetCursorInfo() then return 0 end
	local n, claimed = 0, {}
	attaching = true
	for i = 1, MAX do
		if #run.pending == 0 then break end
		if not HasSendMailItem(i) then
			local e = table.remove(run.pending, 1)
			if ResolveEntry(e, claimed) then
				C_Container.PickupContainerItem(e.bag, e.slot)
				local picked = GetCursorInfo() == "item"
				if picked then ClickSendMailItemButton(i) end
				if HasSendMailItem(i) then
					n = n + 1
				elseif picked then
					-- Picked up but the mail refused it: it can't be mailed.
					ClearCursor()
					Print("Couldn't attach " .. e.link .. ", so it was left out.")
				else
					-- The game didn't let us pick it up outside a click. Try again from a click.
					table.insert(run.pending, 1, e)
					autoBlocked = true
					break
				end
			else
				run.lost = (run.lost or 0) + 1
			end
		end
	end
	attaching = false
	return n
end

local function SubjectFor(letter)
	local suffix = (" (%d/%d)"):format(letter, run.total)
	local base = run.subject
	if #base + #suffix > SUBJECT_MAX then
		base = base:sub(1, SUBJECT_MAX - #suffix):gsub("[\192-\255][\128-\191]*$", "")
	end
	return base .. suffix
end

local function SendCurrent()
	run.waiting, run.manual = true, false
	run.sentAt = GetTime()
	local stamp = run.sentAt
	sending = true
	SendMail(run.recipient, SubjectFor(run.letter), run.body)
	sending = false
	UpdatePanel()
	-- If the game ignores a send that wasn't started by a click, fall back to a button.
	C_Timer.After(10, function()
		if run and run.waiting and run.sentAt == stamp then
			run.waiting, run.manual = false, true
			Print(("Letter %d of %d didn't go out on its own. Click \"Send next\" to continue."):format(run.letter, run.total))
			UpdatePanel()
		end
	end)
end

local function Finish(msg)
	if msg then Print(msg) end
	run = nil
	UpdatePanel()
end

local function SendNext()
	if not run then return end
	if not (MailFrame and MailFrame:IsShown()) then
		return Finish(("The mailbox was closed, so %d items weren't sent."):format(#run.pending))
	end
	if GetCursorInfo() then
		C_Timer.After(0.5, SendNext)
		return
	end
	if AttachedCount() == 0 then
		if #run.pending == 0 then
			return Finish(("Done: %d letters sent to %s."):format(run.letter - 1, run.recipient))
		end
		autoBlocked = false
		AttachNext()
		if (run.lost or 0) > 0 then
			Print(run.lost .. " items are no longer in your bags and were skipped.")
			run.lost = 0
		end
		if AttachedCount() == 0 then
			if autoBlocked and #run.pending > 0 then
				-- Only allowed from a click: hand the next step to the "Send next" button.
				run.manual = true
				UpdatePanel()
				return
			end
			if #run.pending == 0 then
				return Finish(("Done: %d letters sent to %s."):format(run.letter - 1, run.recipient))
			end
			return Finish("Couldn't attach the next items, so sending stopped.")
		end
		run.total = math.max(run.total, run.letter + math.ceil(#run.pending / MAX))
	end
	SendCurrent()
end

-- Every letter goes through SendMail, whether from the Send button or this addon.
hooksecurefunc("SendMail", function(recipient, subject, body)
	if sending then return end
	if run then
		-- The player sent the pending letter by hand.
		run.waiting, run.manual = true, false
		run.sentAt = GetTime()
		UpdatePanel()
		return
	end
	if ExtraCount() == 0 then return end
	if GetSendMailCOD and GetSendMailCOD() > 0 then
		Print("Cash-on-delivery letters can't be split, so the extra slots weren't sent.")
		return
	end
	-- From here on the extra items are on their way, in slot order.
	local pending = {}
	for p = 1, EXTRA_CAP do
		if extra[p] then pending[#pending + 1] = extra[p] end
		extra[p] = nil
	end
	run = {
		recipient = recipient, subject = subject or "", body = body or "",
		pending = pending, letter = 1, total = 1 + math.ceil(#pending / MAX),
		waiting = true, sentAt = GetTime(),
	}
	RevealPosition(1)
	UpdatePanel()
end)

---------------------------------------------------------------------------
-- Catching items that don't fit in the 12 real slots
---------------------------------------------------------------------------

hooksecurefunc(C_Container, "PickupContainerItem", function(bag, slot)
	lastPick = { bag, slot }
end)

-- Right-clicking a bag item while the Send Mail tab is open.
hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
	if attaching or run or not SendTabOpen() then return end
	if AttachedCount() < MAX then
		-- The game puts it in a real slot; make sure that slot is in view.
		for i = 1, MAX do
			if not HasSendMailItem(i) then RevealPosition(i) break end
		end
		return
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if info and not info.isLocked then
		local pos = AddToQueue(bag, slot)
		if pos then
			RevealPosition(MAX + pos)
			UpdatePanel()
		end
	end
end)

-- Dropping an item on a full mail, and anything else that attaches through
-- ClickSendMailItemButton.
if ClickSendMailItemButton then
	hooksecurefunc("ClickSendMailItemButton", function()
		if attaching or run or not SendTabOpen() or AttachedCount() < MAX then return end
		QueueCursorItem()
	end)
end

-- Put bag items in the letter: the free real slots first, then the extra slots.
-- Used by the QuickAttach buttons. list = { { bag = b, slot = s }, ... }
function PO.AttachItems(list)
	if run or not SendTabOpen() then return 0, 0 end
	local free = {}
	for i = 1, MAX do
		if not HasSendMailItem(i) then free[#free + 1] = i end
	end
	local attached, queued, lastPos, full = 0, 0, nil, false
	attaching = true
	for _, it in ipairs(list) do
		local info = C_Container.GetContainerItemInfo(it.bag, it.slot)
		if info and not info.isLocked and not info.isBound and not FindQueued(it.bag, it.slot) then
			if #free > 0 and not GetCursorInfo() then
				local index = table.remove(free, 1)
				C_Container.PickupContainerItem(it.bag, it.slot)
				if GetCursorInfo() == "item" then
					ClickSendMailItemButton(index)
					if GetCursorInfo() then ClearCursor() else attached = attached + 1 end
				end
			else
				local pos = AddToQueue(it.bag, it.slot, true)
				if not pos then
					full = true
					break
				end
				queued, lastPos = queued + 1, pos
			end
		end
	end
	attaching = false
	if full then FullMessage() end
	if lastPos then RevealPosition(MAX + lastPos) end
	UpdatePanel()
	return attached, queued
end

PO.SendTabOpen = function() return SendTabOpen() end
PO.LastBag = LastBag

---------------------------------------------------------------------------
-- Subject
---------------------------------------------------------------------------
-- The game only fills in the subject from the first item when cash on delivery is
-- available, which it isn't on Forever. Fill it in here instead, so right-clicking
-- items, typing a name and pressing Send is enough. A subject you type yourself is
-- never changed.

local autoSubject -- the subject this addon last filled in

local function ItemTitle(name, count)
	if count and count > 1 then return name .. " (" .. count .. ")" end
	return name
end

local function UpdateSubject()
	local box = SendMailSubjectEditBox
	if not box or run or DB().autoSubjectOff or not SendTabOpen() then return end
	local current = box:GetText()
	if current ~= "" and current ~= autoSubject then
		autoSubject = nil -- the player's own subject
		return
	end
	local title
	for i = 1, MAX do
		if HasSendMailItem(i) then
			local name, _, _, count = GetSendMailItem(i)
			if name then
				title = ItemTitle(name, count)
				break
			end
		end
	end
	if not title then
		for p = 1, EXTRA_CAP do
			local e = extra[p]
			local name = e and e.link and e.link:match("%[(.-)%]")
			if name then
				title = ItemTitle(name, e.count)
				break
			end
		end
	end
	title = title or ""
	if current ~= title then
		box:SetText(title)
		if SendMailFrame_CanSend then SendMailFrame_CanSend() end
	end
	autoSubject = title ~= "" and title or nil
end

function PO.SetAutoSubject(on)
	DB().autoSubjectOff = not on or nil
	if on then UpdateSubject() end
end

---------------------------------------------------------------------------
-- The attachment grid
---------------------------------------------------------------------------
-- The game puts its 12 slots in rows of 7 at the bottom of the Send Mail frame
-- (SendMailFrame_Update). This addon takes that layout over: always two rows
-- tall, plus one more row for every row the window was made taller, with every
-- slot (the 12 real ones first, then the extra ones) in one grid in reading order.
-- If the grid has more rows than fit, it scrolls. The same spacing numbers as
-- SendMailFrame_Update are used so the slots sit exactly where the game puts them.

local GAP_X_MARGIN, GAP_Y1, GAP_Y2, INDENT_Y = 14, 5, 6, 82
local cells = {}
local topRow = 0         -- first grid row in view
local baseHeight         -- the mail window's own height, before any resizing
local scrollBar, grip, updatingBar

local function Attachment(i)
	return _G["SendMailAttachment" .. i]
		or (SendMailFrame and SendMailFrame.SendMailAttachments and SendMailFrame.SendMailAttachments[i])
end

local function TotalRows()
	return math.ceil(MaxItems() / PER_ROW)
end

-- Rows added to the window by resizing it, limited to rows the grid can use.
local function AddedRows()
	local k = math.floor(tonumber(DB().addedRows) or 0)
	return math.max(0, math.min(k, TotalRows() - 2))
end

local function VisibleRows()
	return 2 + AddedRows()
end

-- Shared with the open-letter grid (Inbox.lua), so both grids look the same.
PO.GridVisibleRows = function() return VisibleRows() end

local function MaxTop()
	return math.max(0, TotalRows() - VisibleRows())
end

-- Row step and column positions, worked out the same way as SendMailFrame_Update.
local function Metrics()
	local a1 = Attachment(1)
	local iconx = (a1 and a1:GetWidth() or 37) + 2
	local icony = (a1 and a1:GetHeight() or 37) + 2
	local areax = SendMailFrame:GetWidth() - GAP_X_MARGIN
	local gapx1 = math.floor((areax - iconx * PER_ROW) / (PER_ROW - 1))
	local gapx2 = math.floor((areax - iconx * PER_ROW - gapx1 * (PER_ROW - 1)) / 2)
	return {
		x = GAP_X_MARGIN + gapx2,
		tabx = iconx + gapx1 - 2,
		y = INDENT_Y + GAP_Y2 + icony,
		taby = icony + GAP_Y1,
		icony = icony,
	}
end

local function RowStep()
	return Metrics().taby
end

local function SetCellItem(b, texture, count, quality, item)
	if texture then
		b:SetNormalTexture(texture)
	elseif b.ClearNormalTexture then
		b:ClearNormalTexture()
	else
		b:SetNormalTexture("")
	end
	SetItemButtonCount(b, count or 0)
	if b.IconBorder then SetItemButtonQuality(b, quality, item) end
end

local function CellOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local e = extra[self.pos]
	if e then
		GameTooltip:SetBagItem(e.bag, e.slot)
	else
		GameTooltip:SetText(ATTACHMENT_TEXT or "Attachment", 1, 1, 1)
	end
	GameTooltip:Show()
end

local function CellOnClick(self, mouse)
	if run then return end
	if GetCursorInfo() then return PlaceCursorAt(self.pos) end
	local e = extra[self.pos]
	if not e then return end
	extra[self.pos] = nil
	if mouse ~= "RightButton" and ResolveEntry(e) then
		-- Pick the item up, the same as clicking an attached item.
		C_Container.PickupContainerItem(e.bag, e.slot)
	end
	UpdatePanel()
	if GameTooltip:IsOwned(self) then CellOnEnter(self) end
end

local function CellOnReceiveDrag(self)
	if not run then PlaceCursorAt(self.pos) end
end

local function Scroll(delta)
	local top = math.max(0, math.min(topRow - delta, MaxTop()))
	if top ~= topRow then
		topRow = top
		UpdatePanel()
	end
end

local function OnWheel(_, delta)
	if SendTabOpen() then Scroll(delta) end
end

local function CreateCell(p)
	local name = "KUKSlot" .. p
	-- Use the game's own attachment-slot template so the slots look the same.
	local ok, b = pcall(CreateFrame, "Button", name, SendMailFrame, "SendMailAttachment")
	if ok and b then
		-- The template adds the button to the game's list of attachment slots; take it out.
		local list = SendMailFrame.SendMailAttachments
		if list and list[#list] == b then list[#list] = nil end
	else
		b = CreateFrame("Button", name, SendMailFrame)
		b:SetSize(37, 37)
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetTexture("Interface\\Buttons\\UI-Slot-Background")
		bg:SetSize(39, 39)
		bg:SetPoint("TOPLEFT", -1, 1)
		bg:SetTexCoord(0, 0.640625, 0, 0.640625)
		b.Count = b:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
		b.Count:SetJustifyH("RIGHT")
		b.Count:SetPoint("BOTTOMRIGHT", -5, 2)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	end
	b.pos = p
	b:SetID(0)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnClick", CellOnClick)
	b:SetScript("OnDragStart", function(self) CellOnClick(self, "LeftButton") end)
	b:SetScript("OnReceiveDrag", CellOnReceiveDrag)
	b:SetScript("OnEnter", CellOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:EnableMouseWheel(true)
	b:SetScript("OnMouseWheel", OnWheel)
	b:Hide()
	cells[p] = b
	return b
end

-- Scroll so that grid position p (1 = top left, real slots are 1-12) is in view.
function RevealPosition(p)
	local row = math.floor((p - 1) / PER_ROW)
	if row < topRow then
		topRow = row
	elseif row >= topRow + VisibleRows() then
		topRow = row - VisibleRows() + 1
	end
	topRow = math.max(0, math.min(topRow, MaxTop()))
end

local function LayoutScrollBar(m, rows)
	if not scrollBar then return end
	local maxTop = MaxTop()
	if maxTop == 0 then
		scrollBar:Hide()
		return
	end
	local height = m.taby * (rows - 1) + m.icony - 2
	scrollBar:ClearAllPoints()
	scrollBar:SetPoint("TOPLEFT", SendMailFrame, "BOTTOMLEFT",
		m.x + m.tabx * (PER_ROW - 1) + m.icony, m.y + m.taby * (rows - 1))
	scrollBar:SetHeight(height)
	scrollBar.thumb:SetHeight(math.max(12, height * rows / TotalRows()))
	updatingBar = true
	scrollBar:SetMinMaxValues(0, maxTop)
	scrollBar:SetValue(topRow)
	updatingBar = false
	scrollBar:Show()
end

local function Layout()
	if not panel or not SendTabOpen() then return end
	local m = Metrics()
	local rows = VisibleRows()
	local total = MaxItems()
	topRow = math.max(0, math.min(topRow, MaxTop()))

	-- The letter text keeps the size the game gives it with two rows of slots;
	-- rows beyond two come from making the window taller.
	local scrollHeight = 249 - (GAP_Y2 * 2 + GAP_Y1 + m.icony * 2)
	SendMailScrollFrame:SetHeight(scrollHeight)
	if SendMailScrollChildFrame then SendMailScrollChildFrame:SetHeight(scrollHeight) end
	local stationery = math.min(scrollHeight, 256)
	for _, t in ipairs({ SendStationeryBackgroundLeft, SendStationeryBackgroundRight }) do
		if t then
			t:SetHeight(stationery)
			t:SetTexCoord(0, 1, 0, stationery / 256)
		end
	end
	if SendMailHorizontalBarLeft2 then
		local areay = GAP_Y2 * 2 + GAP_Y1 * (rows - 1) + m.icony * rows
		SendMailHorizontalBarLeft2:SetPoint("TOPLEFT", SendMailFrame, "BOTTOMLEFT", 2, 96 + areay)
	end

	for p = 1, math.max(total, MAX + #cells) do
		local b
		if p <= MAX then
			b = Attachment(p)
		else
			b = cells[p - MAX] or (p <= total and CreateCell(p - MAX))
		end
		if b then
			local row, col = math.floor((p - 1) / PER_ROW), (p - 1) % PER_ROW
			local inView = p <= total and row >= topRow and row < topRow + rows
			if inView then
				local fromBottom = rows - 1 - (row - topRow)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", SendMailFrame, "BOTTOMLEFT", m.x + m.tabx * col, m.y + m.taby * fromBottom)
				if p > MAX then
					local e = extra[p - MAX]
					if e then
						local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(e.link)
						SetCellItem(b, e.icon, e.count, quality, e.link)
					else
						SetCellItem(b, nil, 0, nil)
					end
				else
					b:Enable()
				end
				b:Show()
				if p > MAX and GameTooltip:IsOwned(b) then CellOnEnter(b) end
			else
				b:Hide()
			end
		end
	end
	LayoutScrollBar(m, rows)
	UpdateSubject()
end

---------------------------------------------------------------------------
-- Making the window taller
---------------------------------------------------------------------------
-- Only the Send Mail tab gets taller. The Inbox always shows 7 letters, so it
-- goes back to its own height. Everything at the bottom of the Send Mail tab is
-- anchored to the bottom and moves down with it; the gap that opens up above the
-- slots is filled with more slot rows.

local function ApplyHeight()
	if not baseHeight or not MailFrame then return end
	local want = baseHeight
	if SendTabOpen() then want = baseHeight + RowStep() * AddedRows() end
	if math.abs(MailFrame:GetHeight() - want) > 0.5 then MailFrame:SetHeight(want) end
end

-- Most rows the window can grow by and still fit on the screen.
local function MaxAddedRows()
	local most = math.max(0, TotalRows() - 2)
	local top = MailFrame and MailFrame:GetTop()
	if top and baseHeight then
		most = math.min(most, math.max(0, math.floor((top - baseHeight - 8) / RowStep())))
	end
	return most
end

function PO.SetAddedRows(k)
	k = math.max(0, math.min(math.floor(k or 0), MaxAddedRows()))
	if k == AddedRows() and k == (tonumber(DB().addedRows) or 0) then return k end
	DB().addedRows = k
	ApplyHeight()
	UpdatePanel()
	if PO.LetterGridRefresh then PO.LetterGridRefresh() end
	return k
end

local function GripOnUpdate(self)
	if not IsMouseButtonDown("LeftButton") or not self.start then
		self:SetScript("OnUpdate", nil)
		self.start = nil
		return
	end
	local _, y = GetCursorPosition()
	y = y / MailFrame:GetEffectiveScale()
	local k = self.start.rows + math.floor((self.start.y - y) / RowStep() + 0.5)
	if k ~= AddedRows() then PO.SetAddedRows(k) end
end

local function GripOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Resize", 1, 1, 1)
	GameTooltip:AddLine("Drag down to show more rows of attachment slots.", nil, nil, nil, true)
	GameTooltip:AddLine("Right-click to go back to the normal size.", nil, nil, nil, true)
	GameTooltip:Show()
end

local function CreateGrip()
	grip = CreateFrame("Button", "KUKResizeGrip", SendMailFrame)
	grip:SetSize(14, 14)
	grip:SetPoint("BOTTOMRIGHT", SendMailFrame, "BOTTOMRIGHT", 7, -7)
	grip:SetFrameLevel(SendMailFrame:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		local _, y = GetCursorPosition()
		self.start = { y = y / MailFrame:GetEffectiveScale(), rows = AddedRows() }
		self:SetScript("OnUpdate", GripOnUpdate)
	end)
	grip:SetScript("OnMouseUp", function(self, button)
		self:SetScript("OnUpdate", nil)
		self.start = nil
		if button == "RightButton" then PO.SetAddedRows(0) end
	end)
	grip:SetScript("OnEnter", GripOnEnter)
	grip:SetScript("OnLeave", GameTooltip_Hide)
end

local function CreateScrollBar()
	scrollBar = CreateFrame("Slider", "KUKSlotScrollBar", SendMailFrame)
	scrollBar:SetOrientation("VERTICAL")
	scrollBar:SetWidth(8)
	local track = scrollBar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.4)
	local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(1, 0.82, 0, 0.75)
	thumb:SetSize(8, 24)
	scrollBar:SetThumbTexture(thumb)
	scrollBar.thumb = thumb
	scrollBar:SetValueStep(1)
	if scrollBar.SetObeyStepOnDrag then scrollBar:SetObeyStepOnDrag(true) end
	scrollBar:SetScript("OnValueChanged", function(_, value)
		if updatingBar then return end
		value = math.floor(value + 0.5)
		if value ~= topRow then
			topRow = value
			UpdatePanel()
		end
	end)
	scrollBar:EnableMouseWheel(true)
	scrollBar:SetScript("OnMouseWheel", OnWheel)
	scrollBar:Hide()
end

-- Change the slot limit. It can't go below the last extra slot in use.
function PO.SetMaxItems(n)
	n = math.floor(tonumber(n) or DEFAULT_ITEMS)
	local lowest = MAX + LastUsedExtra()
	local clamped = math.max(lowest, math.max(MAX, math.min(MAX_ITEMS, n)))
	DB().maxItems = clamped
	ApplyHeight()
	UpdatePanel()
	if PO.LetterGridRefresh then PO.LetterGridRefresh() end
	return clamped, clamped ~= n, lowest
end

function PO.GetMaxItems() return MaxItems() end
PO.MIN_ITEMS, PO.MAX_ITEMS, PO.DEFAULT_ITEMS = MAX, MAX_ITEMS, DEFAULT_ITEMS

---------------------------------------------------------------------------
-- Window tweaks: no "Postage:" label
---------------------------------------------------------------------------

-- Hide the "Postage:" label next to the cost. Only that exact text is touched.
local function HidePostageLabel()
	local wanted = { ["postage"] = true, ["postage:"] = true }
	for _, key in ipairs({ "POSTAGE", "POSTAGE_COLON" }) do
		local s = _G[key]
		if type(s) == "string" then
			s = strtrim(s):lower()
			wanted[s], wanted[s .. ":"] = true, true
		end
	end
	local function scan(frame, depth)
		for _, r in ipairs({ frame:GetRegions() }) do
			if r.GetObjectType and r:GetObjectType() == "FontString" then
				local t = r:GetText()
				if t and wanted[strtrim(t):lower()] then r:SetAlpha(0) end
			end
		end
		if depth > 0 then
			for _, child in ipairs({ frame:GetChildren() }) do scan(child, depth - 1) end
		end
	end
	if SendMailFrame then scan(SendMailFrame, 3) end
end

---------------------------------------------------------------------------
-- Items in the extra slots look attached in the bags too
---------------------------------------------------------------------------
-- The game greys out an item in the bags once it's attached to a letter. Items in
-- the extra slots (and ones still waiting to go out in a follow-up letter) get the
-- same grey look: in Blizzard's bag windows, and in bag add-ons such as Baganator
-- that draw their buttons with the game's own SetItemButtonDesaturated.

local marked = {} -- bag * 1000 + slot of every bag item greyed out by this addon
-- Bag buttons seen being drawn, by bag * 1000 + slot. Bag add-ons reuse buttons
-- for other slots, so every entry is checked again before it's used.
local seen = setmetatable({}, { __mode = "v" })

local function QueuedKeys()
	local keys = {}
	for p = 1, EXTRA_CAP do
		local e = extra[p]
		if e then keys[e.bag * 1000 + e.slot] = true end
	end
	if run then
		for _, e in ipairs(run.pending) do keys[e.bag * 1000 + e.slot] = true end
	end
	return keys
end

-- The bag and slot a bag button shows, or nil if it isn't a button for your bags.
local function ButtonSlot(button)
	if type(button) ~= "table" or type(button.GetBagID) ~= "function" or type(button.GetID) ~= "function" then return end
	local ok, bag = pcall(button.GetBagID, button)
	if not ok or type(bag) ~= "number" or bag < 0 or bag > LastBag() then return end
	local slot = button:GetID()
	if type(slot) ~= "number" or slot < 1 then return end
	return bag, slot
end

-- Every button currently showing this bag slot: Blizzard's and any bag add-on's.
local function BagButtons(bag, slot)
	local list = {}
	if ContainerFrameUtil_GetItemButtonAndContainer then
		local ok, button = pcall(ContainerFrameUtil_GetItemButtonAndContainer, bag, slot)
		if ok and button then list[#list + 1] = button end
	end
	local other = seen[bag * 1000 + slot]
	if other and other ~= list[1] and other:IsVisible() then
		local b, s = ButtonSlot(other)
		if b == bag and s == slot then list[#list + 1] = other end
	end
	return list
end

local function RefreshBagHighlights()
	local now = QueuedKeys()
	for key in pairs(marked) do
		if not now[key] then
			marked[key] = nil
			local bag, slot = math.floor(key / 1000), key % 1000
			local info = C_Container.GetContainerItemInfo(bag, slot)
			for _, button in ipairs(BagButtons(bag, slot)) do
				SetItemButtonDesaturated(button, info and info.isLocked or false)
			end
		end
	end
	for key in pairs(now) do
		marked[key] = true
		for _, button in ipairs(BagButtons(math.floor(key / 1000), key % 1000)) do
			SetItemButtonDesaturated(button, true)
		end
	end
end

-- Bag windows redraw their buttons often and clear the grey look each time; put it
-- back. This is also how buttons from bag add-ons get noticed.
hooksecurefunc("SetItemButtonDesaturated", function(button, desaturated)
	local bag, slot = ButtonSlot(button)
	if not bag then return end
	local key = bag * 1000 + slot
	seen[key] = button
	if not desaturated and marked[key] then SetItemButtonDesaturated(button, true) end
end)

function UpdatePanel()
	RefreshBagHighlights()
	if not panel then return end
	Layout()
	nextButton:SetShown(run and run.manual or false)
	if run then nextButton:SetText(("Send next (%d/%d)"):format(run.letter, run.total)) end
end

local function CreatePanel()
	panel = true
	baseHeight = MailFrame:GetHeight()

	-- The separator above the money area is anchored to the top of the frame. Anchor
	-- it to the bottom instead, at the same spot, so it moves down with the window.
	local bar = SendMailHorizontalBarLeft
	if bar and bar:GetNumPoints() == 1 then
		local point, _, relPoint, x, y = bar:GetPoint(1)
		if point == "TOPLEFT" and relPoint == "TOPLEFT" and x and y then
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", SendMailFrame, "BOTTOMLEFT", x, baseHeight + y)
		end
	end

	-- Only shown if the game won't send the follow-up letters without a click.
	nextButton = CreateFrame("Button", "KUKSendNext", SendMailFrame, "UIPanelButtonTemplate")
	nextButton:SetSize(140, 22)
	nextButton:SetPoint("BOTTOMRIGHT", MailFrame, "TOPRIGHT", 0, 2)
	nextButton:SetScript("OnClick", function()
		if run then
			run.manual = false
			SendNext()
		end
	end)
	nextButton:Hide()
	if PO.QuickAttachCreate then PO.QuickAttachCreate() end
	CreateScrollBar()
	CreateGrip()

	-- The mouse wheel scrolls the grid over the game's own slots too.
	for i = 1, MAX do
		local a = Attachment(i)
		if a then
			a:EnableMouseWheel(true)
			a:HookScript("OnMouseWheel", OnWheel)
		end
	end

	hooksecurefunc("SendMailFrame_Update", Layout)
	SendMailFrame:HookScript("OnShow", function()
		ApplyHeight()
		UpdatePanel()
	end)
	SendMailFrame:HookScript("OnHide", ApplyHeight)
	ApplyHeight()
	if SendMailFrame_Update then SendMailFrame_Update() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local mailOpen = false

local function OnMailOpened()
	if not panel and SendMailFrame and MailFrame then CreatePanel() end
	HidePostageLabel()
	if PO.QuickAttachApply then PO.QuickAttachApply() end
	if not mailOpen then
		mailOpen = true
		autoBlocked = false
		topRow = 0
	end
	ApplyHeight()
	UpdatePanel()
end

local function OnMailClosed()
	if not mailOpen then return end
	mailOpen = false
	if run and #run.pending > 0 then
		Print(("The mailbox was closed, so %d items weren't sent."):format(#run.pending))
	end
	run = nil
	wipe(extra)
	ApplyHeight()
	UpdatePanel()
end

local function IsMailPane(paneType)
	return Enum and Enum.PlayerInteractionType and paneType == Enum.PlayerInteractionType.MailInfo
end

---------------------------------------------------------------------------
-- No "You cannot attach more than 12 items to mail" error
---------------------------------------------------------------------------
-- With all 12 real slots full, the game refuses the next item and shows that
-- error (with its sound) before this addon puts the item in an extra slot. The
-- game's error frame can switch off one kind of error; that's done for this one.

local function HideErrorType(messageType)
	if type(messageType) == "number" and UIErrorsFrame and UIErrorsFrame.SetMessageTypeEnabled then
		UIErrorsFrame:SetMessageTypeEnabled(messageType, false)
	end
end

-- Find the error among the game's error types: an "attach" error about the limit.
local function FindAttachLimitError()
	if DB().attachErrorType then HideErrorType(DB().attachErrorType) end
	if not GetGameMessageInfo then return end
	local limit = tostring(MAX)
	for key, value in pairs(_G) do
		if type(key) == "string" and type(value) == "number" and key:find("^LE_GAME_ERR_") and key:find("ATTACH") then
			local ok, stringId = pcall(GetGameMessageInfo, value)
			local text = ok and type(stringId) == "string" and _G[stringId]
			if type(text) == "string" and (text:find(limit, 1, true) or text:find("%d", 1, true)) then
				HideErrorType(value)
			end
		end
	end
end

-- If it still shows up (for example under another name), recognise it by when it
-- happens: all 12 real slots full, and the limit in the message.
local function CheckError(messageType, message)
	if not (SendTabOpen() and AttachedCount() >= MAX) then return end
	if type(message) ~= "string" or not message:find(tostring(MAX), 1, true) then return end
	HideErrorType(messageType)
	DB().attachErrorType = messageType
	if UIErrorsFrame and UIErrorsFrame.Clear then UIErrorsFrame:Clear() end
end

local events = CreateFrame("Frame")
-- Forever, like Retail, reports the mailbox through PLAYER_INTERACTION_MANAGER_FRAME_*
-- instead of MAIL_SHOW/MAIL_CLOSED. Registering an event the game doesn't have is an
-- error, so only register the ones it knows.
for _, event in ipairs({
	"PLAYER_LOGIN", "MAIL_SHOW", "MAIL_CLOSED",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
	"MAIL_SEND_SUCCESS", "MAIL_FAILED", "MAIL_SEND_INFO_UPDATE", "BAG_UPDATE_DELAYED",
	"UI_ERROR_MESSAGE",
}) do
	if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
		pcall(events.RegisterEvent, events, event)
	end
end
events:SetScript("OnEvent", function(_, event, ...)
	if event == "UI_ERROR_MESSAGE" then
		CheckError(...)
		return
	end
	if event == "PLAYER_LOGIN" then
		pcall(FindAttachLimitError)
		-- Also follow the mail window itself, in case no mailbox event arrives.
		if SendMailFrame then SendMailFrame:HookScript("OnShow", OnMailOpened) end
		if MailFrame then MailFrame:HookScript("OnHide", OnMailClosed) end
	elseif event == "MAIL_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and IsMailPane(...)) then
		OnMailOpened()
	elseif event == "MAIL_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and IsMailPane(...)) then
		OnMailClosed()
	elseif event == "MAIL_SEND_SUCCESS" then
		if run and run.waiting then
			run.waiting = false
			run.letter = run.letter + 1
			C_Timer.After(0.5, SendNext)
		end
		UpdatePanel()
	elseif event == "MAIL_FAILED" then
		if run and run.waiting then
			run.waiting = false
			if run.letter == 1 then
				-- The first letter failed, so nothing went out: put the extra items back.
				for i, e in ipairs(run.pending) do
					if i <= EXTRA_CAP then extra[i] = e end
				end
				run = nil
			else
				run.manual = true
				Print(("Letter %d of %d didn't go through. Fix the problem, then click \"Send next\"."):format(run.letter, run.total))
			end
		end
		UpdatePanel()
	elseif event == "MAIL_SEND_INFO_UPDATE" or event == "BAG_UPDATE_DELAYED" then
		if not attaching and not run and not GetCursorInfo() then Resolve() end
		UpdatePanel()
	end
end)
