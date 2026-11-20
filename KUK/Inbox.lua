-- [Soeta's] Kjapp Utsendelse av Kolli: inbox grouping
-- Letters from the same sender with the same subject (ignoring a "(2/3)" style
-- suffix) and the same text are shown as one inbox row. Opening the row shows
-- a "Combined letter" panel with every attachment from all of its letters.
--
-- How: while the inbox list is drawn, the inbox query functions are swapped for
-- versions that describe groups instead of letters. Afterwards every row is
-- pointed back at its real first letter, and the row actions that work on
-- letter numbers (Postal's Select checkboxes and DoNotWant button, shift-click)
-- are translated so they act on the right letters.

local INBOX_ROWS = INBOXITEMS_TO_DISPLAY or 7
local MAX_RECEIVE = ATTACHMENTS_MAX_RECEIVE or 16
local COLS, VISIBLE_ROWS, SIZE, GAP, PAD = 6, 6, 37, 4, 12

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
local panel, statusText, moneyText, takeAllButton
local buttons, entries, scrollRow = {}, {}, 0

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
	local Select = Postal and Postal.GetModule and Postal:GetModule("Select", true)
	local selected = Select and Select.GetSelectedMail and Select:GetSelectedMail()
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

			local cb = _G["PostalInboxCB" .. i]
			if cb and cb:IsShown() then
				local all = selected ~= nil
				for _, m in ipairs(g.members) do
					if not (selected and selected[m]) then all = false end
				end
				cb:SetChecked(all)
				if cb.text then cb.text:SetText(g.members[1]) end
			end

			-- Postal's DoNotWant deletes or returns one letter; don't offer it for a group.
			local expire = _G["MailItem" .. i .. "ExpireTime"]
			if expire and expire.returnicon and #g.members > 1 then
				expire.returnicon:Hide()
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
	for _, i in ipairs(g.members) do
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
-- Combined letter panel (next to an open letter)
---------------------------------------------------------------------------

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

local function MaxScroll()
	return math.max(0, math.ceil(#entries / COLS) - VISIBLE_ROWS)
end

local UpdateCombined

local function CreateSlot(i)
	local b = CreateFrame("Button", nil, panel)
	b:SetSize(SIZE, SIZE)
	local row, col = math.floor((i - 1) / COLS), (i - 1) % COLS
	b:SetPoint("TOPLEFT", PAD + col * (SIZE + GAP), -62 - row * (SIZE + GAP))
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnEnter", function(self)
		local e = entries[self.entry]
		if not e then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetInboxItem(e.mail, e.att)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", function(self)
		local e = entries[self.entry]
		if e then TakeInboxItem(e.mail, e.att) end
	end)
	buttons[i] = b
	return b
end

function UpdateCombined()
	if not panel then return end
	local g = OpenGroup()
	if not g then
		panel:Hide()
		return
	end
	wipe(entries)
	local money = 0
	for _, i in ipairs(g.members) do
		local _, _, _, _, m = real.GetInboxHeaderInfo(i)
		money = money + (m or 0)
		for a = 1, MAX_RECEIVE do
			local name, _, texture, count = real.GetInboxItem(i, a)
			if name or texture then
				entries[#entries + 1] = { mail = i, att = a, icon = texture, count = count or 1 }
			end
		end
	end
	scrollRow = math.min(scrollRow, MaxScroll())
	local shown = math.min(math.max(math.ceil(#entries / COLS), 1), VISIBLE_ROWS) * COLS
	for i = 1, VISIBLE_ROWS * COLS do
		local b = buttons[i] or CreateSlot(i)
		local index = scrollRow * COLS + i
		local e = entries[index]
		b.entry = index
		if e and i <= shown then
			b.icon:SetTexture(e.icon)
			b.count:SetText(e.count > 1 and e.count or "")
			b:Show()
		else
			b:Hide()
		end
	end
	statusText:SetText(("%d letters, %d items"):format(#g.members, #entries))
	moneyText:SetText(money > 0 and GetCoinTextureString(money) or "")
	takeAllButton:SetEnabled(not looting and (#entries > 0 or money > 0))
	panel:SetHeight(62 + (shown / COLS) * (SIZE + GAP) + 34)
	panel:Show()
end

local function CreateCombinedPanel()
	panel = CreateFrame("Frame", "KUKCombinedFrame", OpenMailFrame, "BackdropTemplate")
	panel:SetWidth(PAD * 2 + COLS * (SIZE + GAP) - GAP)
	panel:SetPoint("TOPLEFT", OpenMailFrame, "TOPRIGHT", 2, 0)
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	panel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
	panel:EnableMouse(true)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		scrollRow = math.max(0, math.min(MaxScroll(), scrollRow - delta))
		UpdateCombined()
	end)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", PAD, -12)
	title:SetText("Combined letter")

	statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", PAD, -29)

	moneyText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	moneyText:SetPoint("TOPLEFT", PAD, -44)

	takeAllButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	takeAllButton:SetSize(100, 22)
	takeAllButton:SetPoint("BOTTOMRIGHT", -PAD + 2, 10)
	takeAllButton:SetText("Take all")
	takeAllButton:SetScript("OnClick", function()
		TakeAll(OpenGroup())
		UpdateCombined()
	end)

	panel:Hide()
	OpenMailFrame:HookScript("OnShow", function()
		scrollRow = 0
		UpdateCombined()
	end)
	hooksecurefunc(OpenMailFrame, "Update", function()
		UpdateCombined()
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

local function WrapGlobal(name)
	if hooked[name] or type(_G[name]) ~= "function" then return end
	local orig = _G[name]
	_G[name] = function(...) return Virtually(orig, ...) end
	hooked[name] = true
end

local function WrapMethod(obj, method, tag)
	if not obj or hooked[tag] or type(obj[method]) ~= "function" then return end
	local orig = obj[method]
	obj[method] = function(...) return Virtually(orig, ...) end
	hooked[tag] = true
end

local function WrapRowClicks()
	-- Shift-click (Blizzard's auto-loot click, and Postal's Express) on a group row takes everything.
	for _, name in ipairs({ "InboxFrame_OnClick", "InboxFrame_OnModifiedClick" }) do
		if not hooked[name] and type(_G[name]) == "function" then
			local orig = _G[name]
			_G[name] = function(self, index, ...)
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

	local base = function() return ((InboxFrame.pageNum or 1) - 1) * INBOX_ROWS end
	for i = 1, INBOX_ROWS do
		-- Postal Select checkboxes: tick every letter in the row's group.
		local cb = _G["PostalInboxCB" .. i]
		if cb and not cb.kukWrapped then
			local orig = cb:GetScript("OnClick")
			cb:SetScript("OnClick", function(self, ...)
				local row = self:GetID()
				local g = rowGroup[row]
				if not g then return orig(self, ...) end
				local list = (IsShiftKeyDown() or IsControlKeyDown()) and { g.members[1] } or g.members
				for _, m in ipairs(list) do
					self:SetID(m - base())
					orig(self, ...)
				end
				self:SetID(row)
				InboxFrame:Update()
			end)
			cb.kukWrapped = true
		end

		-- Postal DoNotWant button: act on the row's real letter.
		local expire = _G["MailItem" .. i .. "ExpireTime"]
		local icon = expire and expire.returnicon
		if icon and not icon.kukWrapped then
			local orig = icon:GetScript("OnClick")
			icon:SetScript("OnClick", function(self, ...)
				local row = i
				local g = rowGroup[row]
				if not g then return orig(self, ...) end
				if #g.members > 1 then return end
				local saved = self.id
				self.id = g.members[1] - base()
				orig(self, ...)
				self.id = saved
			end)
			icon.kukWrapped = true
		end
	end
end

local function InstallHooks(atMailbox)
	if InboxFrame then
		WrapMethod(InboxFrame, "Update", "InboxFrame:Update")
	end
	WrapGlobal("InboxFrame_Update")
	local Select = Postal and Postal.GetModule and Postal:GetModule("Select", true)
	local DoNotWant = Postal and Postal.GetModule and Postal:GetModule("DoNotWant", true)
	WrapMethod(Select, "InboxFrame_Update", "Select")
	WrapMethod(DoNotWant, "InboxFrame_Update", "DoNotWant")
	-- Row-click wrappers go on last, on top of Postal's own hooks (made at login),
	-- so a shift-click on a group row reaches this addon first.
	if atMailbox then WrapRowClicks() end
	if not panel and OpenMailFrame then CreateCombinedPanel() end
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
		if panel and panel:IsShown() or (OpenMailFrame and OpenMailFrame:IsShown()) then UpdateCombined() end
	elseif event == "MAIL_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and IsMailPane(...)) then
		looting = nil
	elseif event == "UI_ERROR_MESSAGE" then
		local _, msg = ...
		if looting and (msg == ERR_INV_FULL or msg == ERR_ITEM_MAX_COUNT) then
			StopLooting("Your bags are full, so the rest stays in the mail.")
		end
	end
end)

-- Used by the options panel.
KUK = KUK or {}
function KUK.SetGroupingOff(off)
	KUKDB = KUKDB or {}
	KUKDB.groupingOff = off and true or false
	if InboxFrame and InboxFrame:IsVisible() then InboxFrame:Update() end
end
