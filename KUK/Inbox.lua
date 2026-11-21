-- [Soeta's] Kjapp Utsendelse av Kolli: inbox grouping
-- Letters from the same sender with the same subject (ignoring a "(2/3)" style
-- suffix) and the same text are shown as one inbox row. Opening the row shows
-- the gold and every attachment from all of its letters in the letter's grid.
--
-- How: while the inbox list is drawn, the inbox query functions are swapped for
-- versions that describe groups instead of letters. Afterwards every row is
-- pointed back at its real first letter, and row actions (shift-click, the
-- tick boxes and return/delete icons in InboxTools.lua) act on every letter in it.

local INBOX_ROWS = INBOXITEMS_TO_DISPLAY or 7
local MAX_RECEIVE = ATTACHMENTS_MAX_RECEIVE or 16
local PER_ROW = 7

-- The real inbox functions, saved before anything is swapped.
local real = {
	GetInboxNumItems = GetInboxNumItems,
	GetInboxHeaderInfo = GetInboxHeaderInfo,
	GetInboxText = GetInboxText,
	GetInboxItem = GetInboxItem,
	GetInboxItemLink = GetInboxItemLink,
	GetInboxInvoiceInfo = GetInboxInvoiceInfo,
	InboxItemCanDelete = InboxItemCanDelete,
}

local groups = {}       -- current grouping: { members = {real indices}, key, body }
local active = false    -- true while at least one group has more than one letter
local rowGroup = {}     -- inbox row (1-7) -> its group, only while grouping is active
local broken = false    -- the game drew the inbox without our functions; stop grouping
local depth, virtualUsed = 0, false
local swapped = {}
local looting           -- "Take all" in progress

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage((KUK and KUK.TITLE or "Kjapp Utsendelse av Kolli") .. ": " .. msg)
end

local function Enabled()
	return not broken and not (KUKDB and KUKDB.groupingOff)
end

local function BaseSubject(subject)
	return (subject or ""):gsub("%s*%(%d+/%d+%)%s*$", "")
end

---------------------------------------------------------------------------
-- Grouping
---------------------------------------------------------------------------

local function BuildGroups()
	local list, byKey = {}, {}
	local n = real.GetInboxNumItems() or 0
	for i = 1, n do
		local _, _, sender, subject, _, cod, _, _, wasRead, _, _, _, isGM = real.GetInboxHeaderInfo(i)
		if sender and (cod or 0) == 0 and not isGM then
			local key = sender .. "\001" .. BaseSubject(subject)
			-- Reading a letter's text marks it as read, so only compare read letters.
			-- Unread letters join the group optimistically; opening it checks them.
			local body = wasRead and (real.GetInboxText(i) or "") or nil
			local target
			for _, g in ipairs(byKey[key] or {}) do
				if body == nil or g.body == nil or g.body == body then
					target = g
					break
				end
			end
			if target then
				target.members[#target.members + 1] = i
				target.body = target.body or body
			else
				target = { members = { i }, key = key, body = body }
				list[#list + 1] = target
				byKey[key] = byKey[key] or {}
				table.insert(byKey[key], target)
			end
		else
			list[#list + 1] = { members = { i } }
		end
	end
	return list
end

local function AnyMultiple(list)
	for _, g in ipairs(list) do
		if #g.members > 1 then return true end
	end
	return false
end

local function GroupOf(index)
	for _, g in ipairs(groups) do
		for _, m in ipairs(g.members) do
			if m == index then return g end
		end
	end
end

-- Inbox functions that describe groups instead of letters.
local virtual = {}

function virtual.GetInboxNumItems()
	local n, total = real.GetInboxNumItems()
	return #groups, (total or n) - (n - #groups)
end

function virtual.GetInboxHeaderInfo(v)
	virtualUsed = true
	local g = groups[v]
	if not g then return end
	local first = g.members[1]
	if #g.members == 1 then return real.GetInboxHeaderInfo(first) end
	local count = select("#", real.GetInboxHeaderInfo(first))
	local h = { real.GetInboxHeaderInfo(first) }
	local money, items, read, days = 0, 0, true, h[7]
	for _, i in ipairs(g.members) do
		local o = { real.GetInboxHeaderInfo(i) }
		money = money + (o[5] or 0)
		items = items + (o[8] or 0)
		read = read and o[9]
		if o[7] and (not days or o[7] < days) then days = o[7] end
		if not h[15] and o[15] then
			h[1], h[14], h[15] = o[1] or h[1], o[14], o[15]
			count = math.max(count, 15)
		end
	end
	h[4] = BaseSubject(h[4])
	h[5], h[7], h[8], h[9] = money, days, items > 0 and items or nil, read and true or false
	return unpack(h, 1, count)
end

-- Anything else the list asks about a row is answered for the group's first letter.
for _, name in ipairs({ "GetInboxItem", "GetInboxItemLink", "GetInboxInvoiceInfo", "InboxItemCanDelete" }) do
	if real[name] then -- only swap functions this game version has
		virtual[name] = function(v, ...)
			local g = groups[v]
			return real[name](g and g.members[1] or v, ...)
		end
	end
end

local function PostFix()
	wipe(rowGroup)
	if not active or not InboxFrame then return end
	local base = ((InboxFrame.pageNum or 1) - 1) * INBOX_ROWS
	for i = 1, INBOX_ROWS do
		local g = groups[base + i]
		local button = _G["MailItem" .. i .. "Button"]
		if g and button then
			rowGroup[i] = g
			button.index = g.members[1]
			local open = false
			for _, m in ipairs(g.members) do
				if m == InboxFrame.openMailID then open = true end
			end
			button:SetChecked(open)

			if #g.members > 1 then
				local sender = _G["MailItem" .. i .. "Sender"]
				if sender then
					sender:SetText((sender:GetText() or "") .. " |cff33ff99(" .. #g.members .. " letters)|r")
				end
			end

		end
	end
end

-- Run an inbox-drawing function with the group versions of the inbox functions.
local function Virtually(fn, ...)
	if not Enabled() then return fn(...) end
	depth = depth + 1
	if depth == 1 then
		groups = BuildGroups()
		active = AnyMultiple(groups)
		virtualUsed = false
		if active then
			for name, f in pairs(virtual) do
				swapped[name] = _G[name]
				_G[name] = f
			end
		end
	end
	local ok, err = pcall(fn, ...)
	depth = depth - 1
	if depth == 0 then
		for name, f in pairs(swapped) do _G[name] = f end
		wipe(swapped)
		local rowsDrawn = _G.MailItem1Button and MailItem1Button:IsShown() and InboxFrame and InboxFrame:IsVisible()
		if active and not virtualUsed and rowsDrawn then
			-- The game didn't use our functions, so rows can't be remapped safely.
			broken, active = true, false
			Print("Inbox grouping isn't supported by this game version and has been switched off.")
		end
		PostFix()
	end
	if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Taking everything from a group
---------------------------------------------------------------------------

local function GroupRemaining(g)
	local total = 0
	for _, i in ipairs(g.members) do
		local _, _, _, _, money, _, _, itemCount = real.GetInboxHeaderInfo(i)
		total = total + ((money or 0) > 0 and 1 or 0) + (itemCount or 0)
	end
	return total
end

local function FindLootGroup()
	for _, g in ipairs(BuildGroups()) do
		if g.key == looting.key and (looting.body == nil or g.body == nil or g.body == looting.body) then
			return g
		end
	end
end

local function StopLooting(msg)
	if msg then Print(msg) end
	looting = nil
end

local function LootStep()
	if not looting then return end
	if not (MailFrame and MailFrame:IsShown()) then return StopLooting() end
	local g = FindLootGroup()
	if not g or GroupRemaining(g) == 0 then return StopLooting() end
	local remaining = GroupRemaining(g)
	if looting.lastRemaining and remaining >= looting.lastRemaining then
		looting.stalls = looting.stalls + 1
		if looting.stalls > 8 then return StopLooting("Stopped taking items: nothing came out of the mail.") end
	else
		looting.stalls = 0
	end
	looting.lastRemaining = remaining
	for n = #g.members, 1, -1 do
		local i = g.members[n]
		local _, _, _, _, money, _, _, itemCount = real.GetInboxHeaderInfo(i)
		if (money or 0) > 0 or (itemCount or 0) > 0 then
			AutoLootMailItem(i)
			break
		end
	end
	C_Timer.After(0.6, LootStep)
end

local function TakeAll(g)
	if looting or not g or not g.key then return end
	looting = { key = g.key, body = g.body, stalls = 0 }
	LootStep()
end

---------------------------------------------------------------------------
-- The open letter's attachment grid
---------------------------------------------------------------------------
-- An open letter shows its gold and items in the same grid as the Send Mail
-- window: rows of 7 in reading order, as many rows as the Send Mail window shows
-- (more if you made it taller), the same slot limit and a scroll bar past that.
-- A grouped row shows the gold and items of all its letters in this one grid.

local function OpenGroup()
	if depth > 0 then return end -- never regroup in the middle of drawing the list
	if not (Enabled() and InboxFrame and OpenMailFrame and OpenMailFrame:IsShown()) then return end
	local id = InboxFrame.openMailID
	if not id or id == 0 then return end
	groups = BuildGroups()
	local g = GroupOf(id)
	if not g or #g.members == 1 then return end
	-- Opening a group opens all of its letters: read each one (this marks it read)
	-- so letters whose text differs fall out of the group.
	local unread = false
	for _, m in ipairs(g.members) do
		if not select(9, real.GetInboxHeaderInfo(m)) then
			unread = true
			real.GetInboxText(m)
		end
	end
	if unread then
		groups = BuildGroups()
		g = GroupOf(id)
		if not g or #g.members == 1 then return end
	end
	return g
end

local cells, entries = {}, {}
local letterTop = 0         -- first grid row in view
local letterBaseHeight      -- the letter window's own height
local letterBar, takeAllButton, updatingBar
local LayoutLetter

local function BlizzardButtons()
	local list = { OpenMailLetterButton, OpenMailMoneyButton }
	for i = 1, (ATTACHMENTS_MAX or 16) do list[#list + 1] = _G["OpenMailAttachmentButton" .. i] end
	return list
end

-- Same spacing as the game's letter window, and the Send Mail window's row step.
local function Metrics()
	local a1 = OpenMailAttachmentButton1
	local iconx = (a1 and a1:GetWidth() or 37) + 2
	local icony = (a1 and a1:GetHeight() or 37) + 2
	local areax = OpenMailFrame:GetWidth() - 14 - 47
	local gapx1 = math.floor((areax - iconx * PER_ROW) / (PER_ROW - 1))
	local gapx2 = math.floor((areax - iconx * PER_ROW - gapx1 * (PER_ROW - 1)) / 2)
	return { x = 14 + gapx2, tabx = iconx + gapx1 + 6, y = 31 + icony, taby = icony + 5, icony = icony }
end

local function VisibleRows()
	return (KUK.GridVisibleRows and KUK.GridVisibleRows()) or 2
end

local function TotalRows()
	local slots = math.max((KUK.GetMaxItems and KUK.GetMaxItems()) or 36, #entries)
	return math.ceil(slots / PER_ROW)
end

local function MaxTop()
	return math.max(0, TotalRows() - VisibleRows())
end

-- Take the gold from every letter in a group, last letter first.
local function TakeGroupMoney(members)
	local list = {}
	for _, i in ipairs(members) do
		local _, _, _, _, money = real.GetInboxHeaderInfo(i)
		if (money or 0) > 0 then list[#list + 1] = i end
	end
	table.sort(list, function(a, b) return a > b end)
	local function step()
		local i = table.remove(list, 1)
		if not i then return end
		TakeInboxMoney(i)
		if #list > 0 then C_Timer.After(0.4, step) end
	end
	step()
end

local function CellOnEnter(self)
	local e = entries[self.entry]
	if not e then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if e.kind == "item" then
		GameTooltip:SetInboxItem(e.mail, e.att)
		if e.single and OpenMailFrame.cod then
			GameTooltip_AddMoneyLine(GameTooltip, OpenMailFrame.cod, OpenMailFrame.cod > GetMoney())
		end
	elseif e.kind == "money" then
		GameTooltip:SetText(MONEY or "Money", 1, 1, 1)
		GameTooltip:AddLine(GetCoinTextureString(e.money), 1, 1, 1)
	elseif e.kind == "letter" then
		local onEnter = OpenMailLetterButton and OpenMailLetterButton:GetScript("OnEnter")
		if onEnter then return onEnter(OpenMailLetterButton) end
		GameTooltip:SetText(MAIL_LETTER_TOOLTIP or "Take a copy of the letter", 1, 1, 1)
	end
	GameTooltip:Show()
end

local function CellOnClick(self, mouse)
	local e = entries[self.entry]
	if not e then return end
	if e.kind == "item" then
		if IsModifiedClick("CHATLINK") then
			local link = real.GetInboxItemLink and real.GetInboxItemLink(e.mail, e.att)
			if link then HandleModifiedItemClick(link) end
			return
		end
		if e.single then
			-- The game's own click: it asks first for cash-on-delivery letters.
			OpenMailAttachment_OnClick(_G["OpenMailAttachmentButton" .. e.att] or self, e.att)
		else
			TakeInboxItem(e.mail, e.att)
		end
	elseif e.kind == "money" then
		if e.single then OpenMailMoneyButton:Click(mouse) else TakeGroupMoney(e.members) end
	elseif e.kind == "letter" then
		OpenMailLetterButton:Click(mouse)
	end
end

local function Scroll(delta)
	local top = math.max(0, math.min(letterTop - delta, MaxTop()))
	if top ~= letterTop then
		letterTop = top
		LayoutLetter()
	end
end

local function CreateCell(n)
	local ok, b = pcall(CreateFrame, "Button", "KUKLetterSlot" .. n, OpenMailFrame, "ItemButtonTemplate")
	if not ok or not b then
		b = CreateFrame("Button", "KUKLetterSlot" .. n, OpenMailFrame)
		b:SetSize(37, 37)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.Count:SetPoint("BOTTOMRIGHT", -5, 2)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	end
	b.empty = b:CreateTexture(nil, "BACKGROUND")
	b.empty:SetTexture("Interface\\Buttons\\UI-Slot-Background")
	b.empty:SetSize(39, 39)
	b.empty:SetPoint("TOPLEFT", -1, 1)
	b.empty:SetTexCoord(0, 0.640625, 0, 0.640625)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", CellOnClick)
	b:SetScript("OnEnter", CellOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:EnableMouseWheel(true)
	b:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
	cells[n] = b
	return b
end

local function SetCell(b, e)
	b.empty:SetShown(not e)
	if not e then
		SetItemButtonTexture(b, nil)
		SetItemButtonCount(b, 0)
		if b.IconBorder then SetItemButtonQuality(b, nil) end
		return
	end
	SetItemButtonTexture(b, e.icon)
	SetItemButtonCount(b, e.count or 0)
	if b.IconBorder then SetItemButtonQuality(b, e.quality, e.itemID) end
	if e.canUse == false then
		SetItemButtonTextureVertexColor(b, 1.0, 0.1, 0.1)
	else
		SetItemButtonTextureVertexColor(b, 1, 1, 1)
	end
end

-- Everything the open letter (or its group) holds, in order: letter copy, gold, items.
local function CollectEntries()
	wipe(entries)
	local id = InboxFrame and InboxFrame.openMailID
	if not id or id == 0 then return end
	local g = OpenGroup()
	local members = g and g.members or { id }
	local single = #members == 1
	if single and OpenMailLetterButton then
		-- A copy of the letter can be taken, as in the game, when it has text and
		-- hasn't been copied yet.
		local _, _, _, isTakeable = real.GetInboxText(id)
		local _, stationery, _, _, _, _, _, _, _, _, textCreated = real.GetInboxHeaderInfo(id)
		if isTakeable and not textCreated then
			entries[#entries + 1] = { kind = "letter", icon = stationery or "Interface\\Icons\\INV_Misc_Note_01" }
		end
	end
	local money = 0
	for _, i in ipairs(members) do
		local _, _, _, _, m = real.GetInboxHeaderInfo(i)
		money = money + (m or 0)
	end
	if money > 0 then
		entries[#entries + 1] = { kind = "money", money = money, members = members, single = single,
			icon = C_CurrencyInfo and C_CurrencyInfo.GetCoinIcon and C_CurrencyInfo.GetCoinIcon(money) or "Interface\\Icons\\INV_Misc_Coin_01" }
	end
	for _, i in ipairs(members) do
		for a = 1, MAX_RECEIVE do
			if HasInboxItem(i, a) then
				local name, itemID, texture, count, quality, canUse = real.GetInboxItem(i, a)
				entries[#entries + 1] = {
					kind = "item", mail = i, att = a, single = single,
					icon = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
					count = count, quality = quality, itemID = itemID, canUse = canUse,
				}
			end
		end
	end
	return g, members
end

local function CreateLetterBar()
	letterBar = CreateFrame("Slider", "KUKLetterScrollBar", OpenMailFrame)
	letterBar:SetOrientation("VERTICAL")
	letterBar:SetWidth(8)
	local track = letterBar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.4)
	local thumb = letterBar:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(1, 0.82, 0, 0.75)
	thumb:SetSize(8, 24)
	letterBar:SetThumbTexture(thumb)
	letterBar.thumb = thumb
	letterBar:SetValueStep(1)
	if letterBar.SetObeyStepOnDrag then letterBar:SetObeyStepOnDrag(true) end
	letterBar:SetScript("OnValueChanged", function(_, value)
		if updatingBar then return end
		value = math.floor(value + 0.5)
		if value ~= letterTop then
			letterTop = value
			LayoutLetter()
		end
	end)
	letterBar:EnableMouseWheel(true)
	letterBar:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
	letterBar:Hide()

	takeAllButton = CreateFrame("Button", "KUKLetterTakeAll", OpenMailFrame, "UIPanelButtonTemplate")
	takeAllButton:SetSize(84, 20)
	takeAllButton:SetText("Take all")
	takeAllButton:SetScript("OnClick", function()
		local id = InboxFrame and InboxFrame.openMailID
		if not id or id == 0 then return end
		local g = OpenGroup()
		if g then
			TakeAll(g)
		else
			local _, _, _, _, _, cod = real.GetInboxHeaderInfo(id)
			if (cod or 0) > 0 then return Print("Cash-on-delivery letters are taken one item at a time.") end
			AutoLootMailItem(id)
		end
	end)
	takeAllButton:Hide()
end

function LayoutLetter()
	if not (OpenMailFrame and OpenMailFrame:IsShown() and InboxFrame) then return end
	if not letterBar then CreateLetterBar() end
	if not letterBaseHeight then letterBaseHeight = OpenMailFrame:GetHeight() end
	local g, members = CollectEntries()
	local m = Metrics()
	local rows = VisibleRows()
	letterTop = math.max(0, math.min(letterTop, MaxTop()))

	-- The window grows like the Send Mail window; the letter text keeps its two-row size.
	OpenMailFrame:SetHeight(letterBaseHeight + m.taby * (rows - 2))
	local textH = OpenMailAttachmentText and OpenMailAttachmentText:GetHeight() or 12
	local function AreaY(n) return 3 + textH + 3 + m.icony * n + 5 * (n - 1) + 3 end
	local scrollHeight = math.min(256, 305 - AreaY(2))
	OpenMailScrollFrame:SetHeight(scrollHeight)
	if OpenMailScrollChildFrame then OpenMailScrollChildFrame:SetHeight(scrollHeight) end
	for _, t in ipairs({ OpenStationeryBackgroundLeft, OpenStationeryBackgroundRight }) do
		if t then
			t:SetHeight(scrollHeight)
			t:SetTexCoord(0, 1, 0, math.min(scrollHeight, 256) / 256)
		end
	end
	if OpenMailHorizontalBarLeft then
		OpenMailHorizontalBarLeft:SetPoint("TOPLEFT", OpenMailFrame, "BOTTOMLEFT", 2, 39 + AreaY(rows))
	end

	-- The game's own buttons step aside for the grid.
	for _, b in ipairs(BlizzardButtons()) do
		if b then b:Hide() end
	end

	local topY = m.y + m.taby * (rows - 1)
	if OpenMailAttachmentText then
		local n = members and #members or 1
		if #entries == 0 then
			OpenMailAttachmentText:SetText(NO_ATTACHMENTS)
			OpenMailAttachmentText:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
		elseif n > 1 then
			OpenMailAttachmentText:SetText(("%s  |cff33ff99%d letters|r"):format(TAKE_ATTACHMENTS, n))
			OpenMailAttachmentText:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
		else
			OpenMailAttachmentText:SetText(TAKE_ATTACHMENTS)
			OpenMailAttachmentText:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
		end
		OpenMailAttachmentText:ClearAllPoints()
		OpenMailAttachmentText:SetPoint("TOPLEFT", OpenMailFrame, "BOTTOMLEFT", m.x, topY + 3 + textH)
	end
	takeAllButton:ClearAllPoints()
	takeAllButton:SetPoint("BOTTOMRIGHT", OpenMailFrame, "BOTTOMLEFT", m.x + m.tabx * (PER_ROW - 1) + m.icony - 2, topY + 3)
	takeAllButton:SetShown(#entries > 1 or (g ~= nil and #entries > 0))
	takeAllButton:SetEnabled(not looting)

	local total = TotalRows() * PER_ROW
	for n = 1, math.max(total, #cells) do
		local b = cells[n] or (n <= total and CreateCell(n))
		if b then
			local row, col = math.floor((n - 1) / PER_ROW), (n - 1) % PER_ROW
			if n <= total and row >= letterTop and row < letterTop + rows then
				local fromBottom = rows - 1 - (row - letterTop)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", OpenMailFrame, "BOTTOMLEFT", m.x + m.tabx * col, m.y + m.taby * fromBottom)
				b.entry = n
				SetCell(b, entries[n])
				b:Show()
				if GameTooltip:IsOwned(b) then CellOnEnter(b) end
			else
				b:Hide()
			end
		end
	end

	local maxTop = MaxTop()
	if maxTop > 0 then
		local height = m.taby * (rows - 1) + m.icony - 2
		letterBar:ClearAllPoints()
		letterBar:SetPoint("TOPLEFT", OpenMailFrame, "BOTTOMLEFT", m.x + m.tabx * (PER_ROW - 1) + m.icony, topY)
		letterBar:SetHeight(height)
		letterBar.thumb:SetHeight(math.max(12, height * rows / TotalRows()))
		updatingBar = true
		letterBar:SetMinMaxValues(0, maxTop)
		letterBar:SetValue(letterTop)
		updatingBar = false
		letterBar:Show()
	else
		letterBar:Hide()
	end
end

KUK.LetterGridRefresh = function()
	if OpenMailFrame and OpenMailFrame:IsShown() then LayoutLetter() end
end

local function HookLetter()
	OpenMailFrame:HookScript("OnShow", function() letterTop = 0 end)
	hooksecurefunc(OpenMailFrame, "Update", function()
		LayoutLetter()
		-- If the opened row was a group but its letters' texts turned out to
		-- differ, the group has split: redraw the list so the rows match.
		local id = InboxFrame and InboxFrame.openMailID
		if not id or id == 0 or depth > 0 then return end
		for _, g in pairs(rowGroup) do
			if #g.members > 1 and g.members[1] == id then
				if not OpenGroup() then InboxFrame:Update() end
				return
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

local hooked = {}

local function AfterDraw()
	if depth == 0 and KUK.AfterInboxDraw then KUK.AfterInboxDraw() end
end

local function WrapGlobal(name)
	if hooked[name] or type(_G[name]) ~= "function" then return end
	local orig = _G[name]
	_G[name] = function(...)
		Virtually(orig, ...)
		AfterDraw()
	end
	hooked[name] = true
end

local function WrapMethod(obj, method, tag)
	if not obj or hooked[tag] or type(obj[method]) ~= "function" then return end
	local orig = obj[method]
	obj[method] = function(...)
		Virtually(orig, ...)
		AfterDraw()
	end
	hooked[tag] = true
end

local function WrapRowClicks()
	-- Shift-click (the game's take-everything click) on a group row takes everything,
	-- and InboxTools handles its own modified clicks first.
	for _, name in ipairs({ "InboxFrame_OnClick", "InboxFrame_OnModifiedClick" }) do
		if not hooked[name] and type(_G[name]) == "function" then
			local orig = _G[name]
			_G[name] = function(self, index, ...)
				if KUK.InboxRowClick and KUK.InboxRowClick(self, index) then
					if self.SetChecked then self:SetChecked(false) end
					return
				end
				if Enabled() and IsShiftKeyDown() then
					local g = GroupOf(index)
					if g and #g.members > 1 then
						TakeAll(g)
						return
					end
				end
				return orig(self, index, ...)
			end
			hooked[name] = true
		end
	end
end

local function InstallHooks(atMailbox)
	if InboxFrame then
		WrapMethod(InboxFrame, "Update", "InboxFrame:Update")
	end
	WrapGlobal("InboxFrame_Update")
	if atMailbox then WrapRowClicks() end
	if OpenMailFrame and not hooked.letter then
		HookLetter()
		hooked.letter = true
	end
end

---------------------------------------------------------------------------
-- Events and settings
---------------------------------------------------------------------------

local function IsMailPane(paneType)
	return Enum and Enum.PlayerInteractionType and paneType == Enum.PlayerInteractionType.MailInfo
end

local events = CreateFrame("Frame")
-- Only register events this game version has: an unknown event name is an error.
for _, event in ipairs({
	"PLAYER_LOGIN", "MAIL_SHOW", "MAIL_CLOSED",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
	"MAIL_INBOX_UPDATE", "UI_ERROR_MESSAGE",
}) do
	if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
		pcall(events.RegisterEvent, events, event)
	end
end
events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		KUKDB = KUKDB or {}
		InstallHooks()
		-- Also follow the mail window itself, in case no mailbox event arrives.
		if MailFrame then
			MailFrame:HookScript("OnShow", function() InstallHooks(true) end)
			MailFrame:HookScript("OnHide", function() looting = nil end)
		end
	elseif event == "MAIL_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and IsMailPane(...)) then
		InstallHooks(true)
	elseif event == "MAIL_INBOX_UPDATE" then
		if OpenMailFrame and OpenMailFrame:IsShown() then LayoutLetter() end
	elseif event == "MAIL_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and IsMailPane(...)) then
		looting = nil
	elseif event == "UI_ERROR_MESSAGE" then
		local _, msg = ...
		if looting and (msg == ERR_INV_FULL or msg == ERR_ITEM_MAX_COUNT) then
			StopLooting("Your bags are full, so the rest stays in the mail.")
		end
	end
end)

-- Shared with InboxTools.lua.
KUK = KUK or {}
KUK.Inbox = {
	real = real,
	Enabled = function() return Enabled() end,
	-- The real letters behind inbox row 1-7 on the current page.
	RowLetters = function(row)
		local g = rowGroup[row]
		if g then return g.members end
		local button = _G["MailItem" .. row .. "Button"]
		if button and button:IsShown() and button.index then return { button.index } end
	end,
	-- The letters grouped with this one (just itself when it isn't in a group).
	Group = function(index)
		if not Enabled() then return { index } end
		groups = BuildGroups()
		local g = GroupOf(index)
		return g and g.members or { index }
	end,
}

function KUK.SetGroupingOff(off)
	KUKDB = KUKDB or {}
	KUKDB.groupingOff = off and true or false
	if InboxFrame and InboxFrame:IsVisible() then InboxFrame:Update() end
end
