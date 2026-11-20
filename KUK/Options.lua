-- [Soeta's] Kjapp Utsendelse av Kolli: settings window
-- Same look and widgets as the other [Soeta's] addons (Swingline's settings kit):
-- a dark window with a sidebar, opened with /kuk, the minimap button, the gear
-- button under the QuickAttach buttons, or Esc > Options > AddOns.

KUK = KUK or {}
local PO = KUK

local O = {}
PO.Options = O

local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FONT  = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local floor, max, min = math.floor, math.max, math.min

local C = {
	bg       = { 0.071, 0.075, 0.090, 0.98 },
	side     = { 0.052, 0.055, 0.067, 1 },
	input    = { 0.125, 0.130, 0.155, 1 },
	hover    = { 0.175, 0.182, 0.215, 1 },
	menu     = { 0.105, 0.110, 0.132, 1 },
	border   = { 1, 1, 1, 0.07 },
	line     = { 1, 1, 1, 0.06 },
	accent   = { 0.38, 0.56, 1.00, 1 },
	accentBg = { 0.16, 0.23, 0.42, 1 },
	text     = { 0.93, 0.94, 0.96, 1 },
	muted    = { 0.57, 0.60, 0.67, 1 },
	off      = { 0.24, 0.25, 0.29, 1 },
	danger   = { 0.95, 0.36, 0.36, 1 },
}

local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

local function DB()
	KUKDB = KUKDB or {}
	return KUKDB
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PO.TITLE .. ": " .. msg)
end

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------
local function Color(t, c) t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end

local function Text(parent, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size or 12, "")
	fs:SetTextColor(unpack(color or C.text))
	fs:SetJustifyH(justify or "LEFT")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 0.6)
	fs:SetWordWrap(false)
	return fs
end

local function Panel(parent, bg, edge, frameType, name)
	local f = CreateFrame(frameType or "Frame", name, parent, "BackdropTemplate")
	f:SetBackdrop(BACKDROP)
	f:SetBackdropColor(unpack(bg))
	f:SetBackdropBorderColor(unpack(edge or C.border))
	return f
end

local function Round(t, owner)
	local m = owner:CreateMaskTexture()
	m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	m:SetAllPoints(t)
	t:AddMaskTexture(m)
	return m
end

-- Shared disabled-state handling: dims the widget and eats its clicks.
local function Base(w, disabledFn)
	w.disabledFn = disabledFn
	w.blocker = CreateFrame("Frame", nil, w)
	w.blocker:SetAllPoints()
	w.blocker:SetFrameLevel(w:GetFrameLevel() + 20)
	w.blocker:EnableMouse(true)
	w.blocker:Hide()
	function w:UpdateDisabled()
		local d = self.disabledFn and self.disabledFn() or false
		self:SetAlpha(d and 0.35 or 1)
		self.blocker:SetShown(d)
	end
end

-- The round on/off switch used by toggles.
local function Switch(parent)
	local track = CreateFrame("Frame", nil, parent)
	track:SetSize(34, 18)
	local l = track:CreateTexture(nil, "ARTWORK"); l:SetTexture(WHITE); l:SetSize(18, 18); l:SetPoint("LEFT"); Round(l, track)
	local r = track:CreateTexture(nil, "ARTWORK"); r:SetTexture(WHITE); r:SetSize(18, 18); r:SetPoint("RIGHT"); Round(r, track)
	local m = track:CreateTexture(nil, "ARTWORK"); m:SetTexture(WHITE); m:SetPoint("TOPLEFT", 9, 0); m:SetPoint("BOTTOMRIGHT", -9, 0)
	local knob = track:CreateTexture(nil, "OVERLAY"); knob:SetTexture(WHITE); knob:SetSize(12, 12); Round(knob, track)
	function track:SetOn(on)
		local c = on and C.accent or C.off
		for _, t in ipairs({ l, r, m }) do t:SetVertexColor(c[1], c[2], c[3], 1) end
		knob:ClearAllPoints()
		knob:SetPoint("CENTER", track, on and "RIGHT" or "LEFT", on and -9 or 9, 0)
		knob:SetVertexColor(1, 1, 1, 1)
	end
	return track
end

local function Chevron(parent, dir, x)
	-- dir: "down" (dropdowns), "up" or "down" arrows for the order rows
	local a = parent:CreateTexture(nil, "OVERLAY")
	Color(a, C.muted); a:SetSize(7, 2)
	local b = parent:CreateTexture(nil, "OVERLAY")
	Color(b, C.muted); b:SetSize(7, 2)
	local up = dir == "up"
	if x then
		a:SetPoint("CENTER", -2, 0); b:SetPoint("CENTER", 2, 0)
	else
		a:SetPoint("RIGHT", -13, -1); b:SetPoint("RIGHT", -9, -1)
	end
	a:SetRotation(math.rad(up and 45 or -45))
	b:SetRotation(math.rad(up and -45 or 45))
	return a, b
end

---------------------------------------------------------------------------
-- Dropdown menu (shared)
---------------------------------------------------------------------------
local Menu

local function GetMenu()
	if Menu then return Menu end
	Menu = Panel(UIParent, C.menu, { 1, 1, 1, 0.10 })
	Menu:SetFrameStrata("FULLSCREEN_DIALOG")
	Menu:SetClampedToScreen(true)
	Menu:EnableMouse(true)
	Menu:Hide()
	Menu.items = {}

	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN")
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", function() Menu:Hide() end)
	catcher:Hide()
	Menu.catcher = catcher
	Menu:SetScript("OnHide", function() catcher:Hide() end)
	return Menu
end

local function OpenMenu(owner, options, current, onPick)
	local m = GetMenu()
	local ITEM = 24
	for i, opt in ipairs(options) do
		local b = m.items[i]
		if not b then
			b = CreateFrame("Button", nil, m)
			b:SetHeight(ITEM)
			b.hl = b:CreateTexture(nil, "BACKGROUND")
			b.hl:SetAllPoints(); Color(b.hl, C.hover); b.hl:Hide()
			b.mark = b:CreateTexture(nil, "ARTWORK")
			Color(b.mark, C.accent); b.mark:SetSize(3, 12); b.mark:SetPoint("LEFT", 6, 0)
			b.text = Text(b, 12)
			b.text:SetPoint("LEFT", 16, 0); b.text:SetPoint("RIGHT", -8, 0)
			b:SetScript("OnEnter", function(self) self.hl:Show() end)
			b:SetScript("OnLeave", function(self) self.hl:Hide() end)
			b:SetScript("OnClick", function(self) m:Hide(); m.onPick(self.value) end)
			m.items[i] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ITEM)
		b:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * ITEM)
		b.value = opt.value
		b.text:SetText(opt.text)
		local sel = opt.value == current
		b.mark:SetShown(sel)
		b.text:SetTextColor(unpack(sel and C.text or C.muted))
		b:Show()
	end
	for i = #options + 1, #m.items do m.items[i]:Hide() end
	m.onPick = onPick
	m:SetSize(max(owner:GetWidth(), 140), #options * ITEM + 8)
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -3)
	m.catcher:Show()
	m:Show()
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local W = {}

function W.Header(parent, o)
	local w = CreateFrame("Frame", nil, parent)
	w:SetHeight(26)
	local t = Text(w, 10, C.accent)
	t:SetPoint("BOTTOMLEFT", 0, 7)
	t:SetText(o.label:upper())
	local line = w:CreateTexture(nil, "ARTWORK")
	Color(line, C.line)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
	w.Refresh = function() end
	return w
end

function W.Note(parent, o)
	local w = CreateFrame("Frame", nil, parent)
	w:SetHeight(o.height or 32)
	local t = Text(w, 11, C.muted)
	t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMRIGHT")
	t:SetWordWrap(true)
	t:SetJustifyV("TOP")
	t:SetText(o.text or "")
	w.text = t
	w.Refresh = function(self)
		if o.textFn then self.text:SetText(o.textFn()) end
	end
	return w
end

function W.Toggle(parent, o)
	local w = CreateFrame("Button", nil, parent)
	w:SetHeight(26)
	local label = Text(w, 12)
	local labelX = 0
	if o.icon then
		w.icon = w:CreateTexture(nil, "ARTWORK")
		w.icon:SetSize(20, 20)
		w.icon:SetPoint("LEFT", 0, 0)
		w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		labelX = 28
	end
	label:SetPoint("LEFT", labelX, 0)
	label:SetPoint("RIGHT", -46, 0)
	label:SetText(o.label or "")
	w.label = label

	local track = Switch(w)
	track:SetPoint("RIGHT", 0, 0)

	function w:Refresh()
		local on = o.get() and true or false
		track:SetOn(on)
		if o.labelFn then label:SetText(o.labelFn()) end
		if self.icon then
			if o.iconFn then self.icon:SetTexture(o.iconFn()) end
			self.icon:SetDesaturated(not on)
		end
		self:UpdateDisabled()
	end

	w:SetScript("OnClick", function() o.set(not o.get()); O:Changed() end)
	w:SetScript("OnEnter", function()
		label:SetTextColor(1, 1, 1)
		if o.tooltip then
			GameTooltip:SetOwner(w, "ANCHOR_RIGHT")
			GameTooltip:SetText(o.tooltip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	w:SetScript("OnLeave", function() label:SetTextColor(unpack(C.text)); GameTooltip:Hide() end)
	Base(w, o.disabled)
	return w
end

function W.Slider(parent, o)
	local w = CreateFrame("Frame", nil, parent)
	w:SetHeight(42)
	local fmt = o.fmt or function(v) return tostring(floor(v + 0.5)) end

	local label = Text(w, 12)
	label:SetPoint("TOPLEFT", 0, -3)
	label:SetText(o.label)

	local box = Panel(w, C.input, C.border, "EditBox")
	box:SetSize(58, 20)
	box:SetPoint("TOPRIGHT", 0, 0)
	box:SetFont(FONT, 11, "")
	box:SetTextColor(unpack(C.text))
	box:SetJustifyH("CENTER")
	box:SetAutoFocus(false)
	box:SetTextInsets(4, 4, 0, 0)

	local s = CreateFrame("Slider", nil, w)
	s:SetOrientation("HORIZONTAL")
	s:SetHeight(16)
	s:SetPoint("BOTTOMLEFT", 0, 0)
	s:SetPoint("BOTTOMRIGHT", 0, 0)
	s:SetMinMaxValues(o.min, o.max)
	s:SetValueStep(o.step)
	s:SetObeyStepOnDrag(true)
	s:SetHitRectInsets(0, 0, -4, -4)

	local track = s:CreateTexture(nil, "BACKGROUND")
	Color(track, C.off)
	track:SetHeight(4)
	track:SetPoint("LEFT", 7, 0); track:SetPoint("RIGHT", -7, 0)

	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(WHITE)
	thumb:SetSize(14, 14)
	Round(thumb, s)
	s:SetThumbTexture(thumb)

	local fill = s:CreateTexture(nil, "ARTWORK")
	Color(fill, C.accent)
	fill:SetHeight(4)
	fill:SetPoint("LEFT", track, "LEFT")
	fill:SetPoint("RIGHT", thumb, "CENTER")

	local function snap(v) return floor(v / o.step + 0.5) * o.step end

	s:SetScript("OnValueChanged", function(_, v)
		if w.updating then return end
		v = snap(v)
		o.set(v)
		box:SetText(fmt(v))
		O:Changed()
	end)
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(_, delta) s:SetValue(s:GetValue() + delta * o.step) end)
	s:SetScript("OnEnter", function() thumb:SetVertexColor(unpack(C.accent)) end)
	s:SetScript("OnLeave", function() thumb:SetVertexColor(1, 1, 1, 1) end)

	box:SetScript("OnEnterPressed", function(self)
		local v = tonumber((self:GetText() or ""):match("-?[%d%.]+"))
		if v then
			v = max(o.min, min(o.max, v))
			o.set(snap(v))
			O:Changed()
		end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)); self:HighlightText() end)
	box:SetScript("OnEditFocusLost", function(self)
		self:SetBackdropBorderColor(unpack(C.border)); self:HighlightText(0, 0); w:Refresh()
	end)

	function w:Refresh()
		self.updating = true
		local v = o.get()
		s:SetValue(max(o.min, min(o.max, v)))
		if not box:HasFocus() then box:SetText(fmt(v)) end
		self.updating = false
		self:UpdateDisabled()
	end
	Base(w, o.disabled)
	return w
end

function W.Dropdown(parent, o)
	local w = CreateFrame("Frame", nil, parent)
	w:SetHeight(46)
	local label = Text(w, 12)
	label:SetPoint("TOPLEFT", 0, -2)
	label:SetText(o.label)
	w.label = label

	local b = Panel(w, C.input, C.border, "Button")
	b:SetHeight(26)
	b:SetPoint("BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT")
	b.text = Text(b, 12)
	b.text:SetPoint("LEFT", 9, 0); b.text:SetPoint("RIGHT", -26, 0)
	Chevron(b, "down")

	local function options() return type(o.options) == "function" and o.options() or o.options end
	b:SetScript("OnClick", function()
		OpenMenu(b, options(), o.get(), function(v) o.set(v); O:Changed() end)
	end)
	b:SetScript("OnEnter", function() b:SetBackdropBorderColor(unpack(C.accent)) end)
	b:SetScript("OnLeave", function() b:SetBackdropBorderColor(unpack(C.border)) end)

	function w:Refresh()
		if o.labelFn then label:SetText(o.labelFn()) end
		local cur, txt = o.get(), nil
		for _, opt in ipairs(options()) do
			if opt.value == cur then txt = opt.text end
		end
		b.text:SetText(txt or o.placeholder or "")
		b.text:SetTextColor(unpack(txt and C.text or C.muted))
		self:UpdateDisabled()
	end
	Base(w, o.disabled)
	return w
end

-- A text box with a button beside it (type a name, press the button or Enter).
function W.InputButton(parent, o)
	local w = CreateFrame("Frame", nil, parent)
	w:SetHeight(46)
	local label = Text(w, 12)
	label:SetPoint("TOPLEFT", 0, -2)
	label:SetText(o.label)

	local btn = Panel(w, C.input, C.border, "Button")
	btn:SetSize(o.buttonWidth or 80, 26)
	btn:SetPoint("BOTTOMRIGHT")
	btn.text = Text(btn, 12, C.text, "CENTER")
	btn.text:SetPoint("CENTER")
	btn.text:SetText(o.button)

	local box = Panel(w, C.input, C.border, "EditBox")
	box:SetHeight(26)
	box:SetPoint("BOTTOMLEFT")
	box:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -8, 0)
	box:SetFont(FONT, 12, "")
	box:SetTextColor(unpack(C.text))
	box:SetAutoFocus(false)
	box:SetTextInsets(9, 9, 0, 0)
	box:SetMaxLetters(o.maxLetters or 40)
	local ph = Text(box, 12, C.muted)
	ph:SetPoint("LEFT", 9, 0)
	ph:SetText(o.placeholder or "")

	local function submit()
		if o.onSubmit(strtrim(box:GetText() or "")) then box:SetText("") end
		box:ClearFocus()
		O:Changed()
	end
	box:SetScript("OnEnterPressed", submit)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
	box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
	box:SetScript("OnTextChanged", function(self) ph:SetShown((self:GetText() or "") == "") end)
	btn:SetScript("OnClick", submit)
	btn:SetScript("OnEnter", function() btn:SetBackdropBorderColor(unpack(C.accent)); btn:SetBackdropColor(unpack(C.hover)) end)
	btn:SetScript("OnLeave", function() btn:SetBackdropBorderColor(unpack(C.border)); btn:SetBackdropColor(unpack(C.input)) end)

	function w:Refresh()
		ph:SetShown((box:GetText() or "") == "")
		self:UpdateDisabled()
	end
	Base(w, o.disabled)
	return w
end

function W.Button(parent, o)
	local b = Panel(parent, C.input, C.border, "Button")
	b:SetHeight(28)
	b.text = Text(b, 12, C.text, "CENTER")
	b.text:SetPoint("CENTER")
	b.text:SetText(o.label or "")

	local function idleColors()
		local active = o.active and o.active()
		b:SetBackdropColor(unpack(active and C.accentBg or C.input))
		b:SetBackdropBorderColor(unpack(active and C.accent or C.border))
	end

	b:SetScript("OnEnter", function()
		b:SetBackdropBorderColor(unpack(o.danger and C.danger or C.accent))
		b:SetBackdropColor(unpack(C.hover))
		if o.tooltip then
			GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
			GameTooltip:SetText(o.tooltip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function() idleColors(); GameTooltip:Hide() end)
	b:SetScript("OnClick", function()
		if o.confirm then
			if b.armed then
				b.armed = nil
				b.text:SetText(o.labelFn and o.labelFn() or o.label); b.text:SetTextColor(unpack(C.text))
				o.onClick()
				O:Changed()
			else
				b.armed = true
				b.text:SetText(o.confirm); b.text:SetTextColor(unpack(C.danger))
				C_Timer.After(3, function()
					if b.armed then
						b.armed = nil
						b.text:SetText(o.labelFn and o.labelFn() or o.label); b.text:SetTextColor(unpack(C.text))
					end
				end)
			end
		else
			o.onClick()
			O:Changed()
		end
	end)

	function b:Refresh()
		if o.labelFn and not self.armed then self.text:SetText(o.labelFn()) end
		if not self:IsMouseOver() then idleColors() end
		self:UpdateDisabled()
	end
	Base(b, o.disabled)
	return b
end

-- One line of the To field order: up/down arrows, "1. Your alts", on/off switch.
function W.OrderRow(parent, o)
	local w = CreateFrame("Button", nil, parent)
	w:SetHeight(30)
	local bg = w:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.02)

	local function Arrow(dir, x)
		local b = CreateFrame("Button", nil, w)
		b:SetSize(20, 24)
		b:SetPoint("LEFT", x, 0)
		b.hl = b:CreateTexture(nil, "BACKGROUND")
		b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0)
		b.a, b.b = Chevron(b, dir, true)
		b:SetScript("OnEnter", function(self) if self:IsEnabled() then self.hl:SetColorTexture(1, 1, 1, 0.08) end end)
		b:SetScript("OnLeave", function(self) self.hl:SetColorTexture(1, 1, 1, 0) end)
		b:SetScript("OnClick", function()
			PO.MoveToSource(w.key, dir == "up" and -1 or 1)
			O:Changed()
		end)
		function b:SetUsable(usable)
			self:SetEnabled(usable)
			local c = usable and C.text or C.off
			Color(self.a, c); Color(self.b, c)
		end
		return b
	end
	w.up = Arrow("up", 4)
	w.down = Arrow("down", 26)

	local label = Text(w, 12)
	label:SetPoint("LEFT", 56, 0)
	label:SetPoint("RIGHT", -50, 0)
	local track = Switch(w)
	track:SetPoint("RIGHT", -8, 0)

	w:SetScript("OnClick", function(self)
		PO.SetToSourceOn(self.key, not PO.IsToSourceOn(self.key))
		O:Changed()
	end)
	w:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.05) end)
	w:SetScript("OnLeave", function() bg:SetColorTexture(1, 1, 1, 0.02) end)

	function w:Refresh()
		local order = PO.GetToOrder()
		self.key = order[o.index]
		local on = PO.IsToSourceOn(self.key)
		label:SetText(("%d.  %s"):format(o.index, PO.TO_SOURCES[self.key] or "?"))
		label:SetTextColor(unpack(on and C.text or C.muted))
		track:SetOn(on)
		self.up:SetUsable(o.index > 1)
		self.down:SetUsable(o.index < #order)
		self:UpdateDisabled()
	end
	Base(w, o.disabled)
	return w
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local COL_W, COL1_X, COL2_X, COL_Y = 262, 26, 322, -92

local function NewPage(content)
	local p = CreateFrame("Frame", nil, content)
	p:SetAllPoints()
	p:Hide()
	p.widgets = {}

	function p:Column(x, y, width)
		local col = { y = y, x = x, width = width }
		function col.Add(_, kind, o, gap)
			local w = W[kind](p, o)
			w:SetPoint("TOPLEFT", p, "TOPLEFT", x, col.y)
			w:SetWidth(width)
			col.y = col.y - w:GetHeight() - (gap or 10)
			table.insert(p.widgets, w)
			return w
		end
		return col
	end

	function p:Title(title, subtitle)
		self.title = Text(self, 18)
		self.title:SetPoint("TOPLEFT", 26, -24)
		self.title:SetText(title)
		self.subtitle = Text(self, 11, C.muted)
		self.subtitle:SetPoint("TOPLEFT", 26, -50)
		self.subtitle:SetWidth(540)
		self.subtitle:SetWordWrap(true)
		self.subtitle:SetJustifyV("TOP")
		self.subtitle:SetText(subtitle or "")
	end

	function p:Refresh()
		if self.OnRefresh then self:OnRefresh() end
		for _, w in ipairs(self.widgets) do w:Refresh() end
	end
	return p
end

-- Two half-width buttons side by side at the column's current position.
local function ButtonPair(p, col, a, b)
	local w = (col.width - 8) / 2
	local b1 = W.Button(p, a)
	b1:SetPoint("TOPLEFT", p, "TOPLEFT", col.x, col.y)
	b1:SetWidth(w)
	local b2 = W.Button(p, b)
	b2:SetPoint("TOPLEFT", b1, "TOPRIGHT", 8, 0)
	b2:SetWidth(w)
	table.insert(p.widgets, b1)
	table.insert(p.widgets, b2)
	col.y = col.y - 38
end

local function SetMax(n)
	local value, adjusted, lowest = PO.SetMaxItems(n)
	if adjusted and tonumber(n) and tonumber(n) < lowest then
		Print(("The limit can't go below %d while an item is in slot %d. Take it out first."):format(lowest, lowest))
	end
	return value
end

function O:BuildSend(p)
	p:Title("Send Mail", "More attachment slots than the game's 12. Items past the first 12 go out as follow-up letters of 12 to the same person, with \"(2/3)\" added to the subject.")

	local L = p:Column(COL1_X, COL_Y, COL_W)
	L:Add("Header", { label = "Attachment slots" })
	L:Add("Slider", { label = "Number of slots", min = PO.MIN_ITEMS, max = PO.MAX_ITEMS, step = 1,
		get = function() return PO.GetMaxItems() end, set = function(v) SetMax(v) end }, 6)
	L:Add("Note", { height = 30, text = ("Default %d: three letters of 12. Items in the extra slots look greyed out in your bags, like attached items."):format(PO.DEFAULT_ITEMS) }, 8)
	ButtonPair(p, L,
		{ label = ("Default (%d)"):format(PO.DEFAULT_ITEMS), onClick = function() SetMax(PO.DEFAULT_ITEMS) end },
		{ label = "Normal window size", onClick = function() PO.SetAddedRows(0) end,
			tooltip = "Drag the bottom-right corner of the Send Mail window down to show more rows of slots. This puts it back." })
	L:Add("Note", { height = 44, text = "Drag the bottom-right corner of the Send Mail window down for more rows of slots. The mouse wheel scrolls the slots when they don't all fit." })

	local R = p:Column(COL2_X, COL_Y, COL_W)
	R:Add("Header", { label = "Letter" })
	R:Add("Toggle", { label = "Fill in the subject from the first item",
		tooltip = "When the subject is empty, it becomes the first item's name, like \"Linen Cloth (20)\". A subject you type yourself is never changed.",
		get = function() return not DB().autoSubjectOff end, set = function(v) PO.SetAutoSubject(v) end }, 4)
	R:Add("Header", { label = "Buttons" }, 6)
	R:Add("Toggle", { label = "Show minimap button",
		tooltip = "Left-click opens these settings, right-click opens the QuickAttach page. Drag it around the minimap.",
		get = function() return PO.Minimap and PO.Minimap:IsShown() end,
		set = function(v) if PO.Minimap then PO.Minimap:SetShown(v) end end }, 4)
end

function O:BuildTo(p)
	p:Title("To field", "While you type a name in the To field, the first match from these sources is filled in, top to bottom. Click a row to switch it on or off; use the arrows to move it.")
	local L = p:Column(COL1_X, COL_Y, COL_W * 2 + (COL2_X - COL1_X - COL_W))
	L:Add("Header", { label = "Fill in names from" })
	for i = 1, 5 do L:Add("OrderRow", { index = i }, 4) end
	L.y = L.y - 8
	local reset = W.Button(p, { label = "Default order", onClick = function() PO.ResetToOrder() end })
	reset:SetPoint("TOPLEFT", p, "TOPLEFT", COL1_X, L.y)
	reset:SetWidth(160)
	table.insert(p.widgets, reset)
	L.y = L.y - 40
	L:Add("Note", { height = 44, text = "\"Friends\" covers your friends list and Battle.net friends playing this game, online ones first. Postal's own \"Use AutoComplete\" switch in its BlackBook menu still turns this off completely." })
end

function O:BuildInbox(p)
	p:Title("Inbox", "Letters from the same sender with the same subject and text show as one inbox row, with all their attachments together.")
	local L = p:Column(COL1_X, COL_Y, COL_W)
	L:Add("Header", { label = "Inbox" })
	L:Add("Toggle", { label = "Group matching letters",
		tooltip = "Shift-click a grouped row to take everything from all of its letters.",
		get = function() return not DB().groupingOff end, set = function(v) PO.SetGroupingOff(not v) end }, 4)
end

function O:BuildQuick(p)
	p:Title("QuickAttach", "Which of Postal's QuickAttach buttons (Cloth, Leather and so on) show beside the Send Mail window. Each character picks its own profile. Which bags the buttons take items from is set in Postal's own menu.")

	local L = p:Column(COL1_X, COL_Y, COL_W)
	L:Add("Header", { label = "Profile" })
	L:Add("Dropdown", {
		label = "Profile", labelFn = function() return "Profile for " .. PO.CurrentCharacter() end,
		options = function()
			local list = {}
			for _, name in ipairs(PO.GetQAProfiles()) do list[#list + 1] = { text = name, value = name } end
			return list
		end,
		get = function() return PO.GetQAProfileName() end,
		set = function(v) PO.SetQAProfile(v) end }, 8)
	L:Add("InputButton", { label = "New profile (copy of this one)", button = "Create", placeholder = "Name",
		onSubmit = function(name)
			local ok, err = PO.NewQAProfile(name)
			if not ok then Print(err) end
			return ok
		end }, 8)
	local del = W.Button(p, {
		labelFn = function() return "Delete " .. PO.GetQAProfileName() end, label = "Delete", danger = true,
		confirm = "Click again to delete",
		disabled = function() return PO.GetQAProfileName() == "Default" end,
		onClick = function()
			local name = PO.GetQAProfileName()
			if PO.DeleteQAProfile(name) then Print(("Deleted the QuickAttach profile %s."):format(name)) end
		end })
	del:SetPoint("TOPLEFT", p, "TOPLEFT", L.x, L.y)
	del:SetWidth(COL_W)
	table.insert(p.widgets, del)
	L.y = L.y - 38
	L:Add("Note", { height = 70, textFn = function()
		local name = PO.GetQAProfileName()
		if name == "Default" then
			return "Characters that never picked a profile use Default. A new profile starts as a copy of the one in use, and this character switches to it."
		end
		local users = PO.GetQAProfileUsers(name)
		return "Used by: " .. (#users > 0 and table.concat(users, ", ") or "nobody") .. "."
	end })

	local R = p:Column(COL2_X, COL_Y, COL_W)
	R:Add("Header", { label = "Buttons" })
	R:Add("Toggle", { label = "Show QuickAttach buttons",
		get = function() return not PO.IsQuickAttachHidden() end, set = function(v) PO.SetQuickAttachHidden(not v) end }, 6)
	ButtonPair(p, R,
		{ label = "Tick all", onClick = function() PO.ShowAllQuickAttachButtons() end },
		{ label = "Default", onClick = function() PO.DefaultQuickAttachButtons() end,
			tooltip = "Everything except Jewelcrafting, Inscription and Optional Reagents, which Forever doesn't have." })
	local note = R:Add("Note", { height = 30 }, 4)
	p.qaRows, p.qaColumn, p.qaNote = {}, R, note
	p.qaTop = R.y

	-- One switch per Postal button; made when Postal's buttons exist.
	function p:OnRefresh()
		local list, enabled = PO.GetQuickAttachButtons()
		if #list == 0 or not enabled then
			note.text:SetText(not enabled
				and "Postal's QuickAttach module is turned off, so there are no buttons."
				or "Postal hasn't made its QuickAttach buttons yet. Open the Send Mail tab at a mailbox once.")
		else
			note.text:SetText("")
		end
		for i, item in ipairs(list) do
			local row = self.qaRows[i]
			if not row then
				local index = i
				row = W.Toggle(self, {
					label = "", icon = true,
					labelFn = function()
						local it = self.qaList[index]
						if not it then return "" end
						return it.notInForever and (it.label .. "  |cff8a8f9a(not in Forever)|r") or it.label
					end,
					iconFn = function() local it = self.qaList[index]; return it and it.icon end,
					get = function() local it = self.qaList[index]; return it and it.shown end,
					set = function(v) local it = self.qaList[index]; if it then PO.SetQuickAttachButtonShown(it.key, v) end end,
					disabled = function() return PO.IsQuickAttachHidden() end,
				})
				row:SetPoint("TOPLEFT", self, "TOPLEFT", COL2_X, self.qaTop - (i - 1) * 26)
				row:SetWidth(COL_W)
				self.qaRows[i] = row
				table.insert(self.widgets, row)
			end
			row:Show()
		end
		for i = #list + 1, #self.qaRows do self.qaRows[i]:Hide() end
		self.qaList = list
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function NavButton(parent, id, label)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(30)
	b.id = id
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(1, 1, 1, 0)
	b.ind = b:CreateTexture(nil, "ARTWORK")
	Color(b.ind, C.accent)
	b.ind:SetWidth(3)
	b.ind:SetPoint("TOPLEFT"); b.ind:SetPoint("BOTTOMLEFT")
	b.ind:Hide()
	b.text = Text(b, 12, C.muted)
	b.text:SetPoint("LEFT", 18, 0)
	b.text:SetText(label)
	b.state = Text(b, 9, C.muted, "RIGHT")
	b.state:SetPoint("RIGHT", -14, 0)

	function b:Update(selected)
		self.selected = selected
		self.ind:SetShown(selected)
		if selected then self.bg:SetColorTexture(1, 1, 1, 0.06)
		elseif self:IsMouseOver() then self.bg:SetColorTexture(1, 1, 1, 0.03)
		else self.bg:SetColorTexture(1, 1, 1, 0) end
		self.text:SetTextColor(unpack(selected and C.text or C.muted))
		if self.stateFn then self.state:SetText(self.stateFn()) end
	end
	b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(1, 1, 1, 0.03) end end)
	b:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(1, 1, 1, 0) end end)
	b:SetScript("OnClick", function(self) O:Select(self.id) end)
	return b
end

function O:Build()
	if self.frame then return end

	local f = Panel(UIParent, C.bg, { 0, 0, 0, 1 }, "Frame", "KUKOptionsFrame")
	f:SetSize(800, 560)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:Hide()
	tinsert(UISpecialFrames, "KUKOptionsFrame")
	self.frame = f

	-- soft drop shadow
	for i, a in ipairs({ 0.22, 0.12, 0.06 }) do
		local s = f:CreateTexture(nil, "BACKGROUND", nil, -8)
		s:SetColorTexture(0, 0, 0, a)
		s:SetPoint("TOPLEFT", -i * 3, i * 3)
		s:SetPoint("BOTTOMRIGHT", i * 3, -i * 3)
	end

	-- header
	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
	header:SetHeight(52)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() f:StartMoving() end)
	header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

	local logo = header:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(PO.ICON)
	logo:SetSize(30, 30)
	logo:SetPoint("LEFT", 16, 0)

	local title = Text(header, 15)
	title:SetPoint("LEFT", logo, "RIGHT", 12, 7)
	title:SetText(PO.TITLE)
	local sub = Text(header, 11, C.muted)
	sub:SetPoint("LEFT", logo, "RIGHT", 12, -9)
	sub:SetText("Mail tools for Postal")
	self.headerSub = sub

	local close = CreateFrame("Button", nil, header)
	close:SetSize(30, 30)
	close:SetPoint("RIGHT", -12, 0)
	close.bg = close:CreateTexture(nil, "BACKGROUND")
	close.bg:SetAllPoints(); close.bg:SetColorTexture(1, 1, 1, 0)
	local x1 = close:CreateTexture(nil, "ARTWORK"); Color(x1, C.muted); x1:SetSize(14, 2); x1:SetPoint("CENTER"); x1:SetRotation(math.rad(45))
	local x2 = close:CreateTexture(nil, "ARTWORK"); Color(x2, C.muted); x2:SetSize(14, 2); x2:SetPoint("CENTER"); x2:SetRotation(math.rad(-45))
	close:SetScript("OnEnter", function()
		close.bg:SetColorTexture(C.danger[1], C.danger[2], C.danger[3], 0.18)
		Color(x1, C.text); Color(x2, C.text)
	end)
	close:SetScript("OnLeave", function()
		close.bg:SetColorTexture(1, 1, 1, 0)
		Color(x1, C.muted); Color(x2, C.muted)
	end)
	close:SetScript("OnClick", function() f:Hide() end)

	local version = Text(header, 10, C.muted, "RIGHT")
	version:SetPoint("RIGHT", close, "LEFT", -10, 0)
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
	local ver = getMeta and getMeta("KUK", "Version")
	if not ver or ver:find("^@") then ver = "dev" end
	version:SetText(ver:find("^v") and ver or ("v" .. ver))

	local hline = f:CreateTexture(nil, "ARTWORK")
	Color(hline, C.line)
	hline:SetHeight(1)
	hline:SetPoint("TOPLEFT", 1, -52); hline:SetPoint("TOPRIGHT", -1, -52)

	-- sidebar
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", 1, -53)
	side:SetPoint("BOTTOMLEFT", 1, 1)
	side:SetWidth(196)
	local sbg = side:CreateTexture(nil, "BACKGROUND")
	sbg:SetAllPoints(); Color(sbg, C.side)
	local sline = side:CreateTexture(nil, "ARTWORK")
	Color(sline, C.line); sline:SetWidth(1)
	sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT")

	self.nav = {}
	local y = -14
	local function addNav(id, label)
		local b = NavButton(side, id, label)
		b:SetPoint("TOPLEFT", 0, y); b:SetPoint("TOPRIGHT", -1, y)
		y = y - 30
		self.nav[#self.nav + 1] = b
		return b
	end
	addNav("send", "Send Mail").stateFn = function() return PO.GetMaxItems() .. " SLOTS" end
	addNav("to", "To field")
	addNav("quick", "QuickAttach").stateFn = function() return PO.GetQAProfileName():upper() end
	addNav("inbox", "Inbox").stateFn = function() return DB().groupingOff and "OFF" or "" end

	local hint = Text(side, 10, C.muted)
	hint:SetPoint("BOTTOMLEFT", 18, 16)
	hint:SetText("/kuk")

	-- content
	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", -1, 1)
	self.content = content
	self.pages = {}

	f:SetScript("OnShow", function() O:Refresh() end)
	f:SetScript("OnHide", function() if Menu then Menu:Hide() end end)

	self:Select("send")
end

function O:Select(id)
	self.selected = id
	for _, b in ipairs(self.nav) do b:Update(b.id == id) end
	for _, p in pairs(self.pages) do p:Hide() end
	local p = self.pages[id]
	if not p then
		p = NewPage(self.content)
		if id == "to" then self:BuildTo(p)
		elseif id == "quick" then self:BuildQuick(p)
		elseif id == "inbox" then self:BuildInbox(p)
		else self:BuildSend(p) end
		self.pages[id] = p
	end
	p:Show()
	p:Refresh()
end

function O:Refresh()
	if not (self.frame and self.frame:IsShown()) then return end
	local p = self.pages[self.selected]
	if p then p:Refresh() end
	for _, b in ipairs(self.nav) do b:Update(b.id == self.selected) end
end

-- Called after any setting changes: refresh what's visible.
function O:Changed()
	self:Refresh()
end

function O:Open(id)
	self:Build()
	self.frame:Show()
	if id then self:Select(id) end
end

function O:Toggle()
	self:Build()
	self.frame:SetShown(not self.frame:IsShown())
end

-- Used by the gear button, the minimap button and /kuk.
function PO.OpenOptions(page)
	O:Open(page == "quickattach" and "quick" or page)
end

-- Small entry in Blizzard's Options > AddOns that opens our window.
function O:RegisterBlizzardPanel()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local p = CreateFrame("Frame")
	local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText(PO.TITLE)
	local d = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
	d:SetText("The settings are in their own window.")
	local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	b:SetSize(200, 26)
	b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -14)
	b:SetText("Open settings")
	b:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		O:Open()
	end)
	local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, p, "|cffc27dff[Soeta's]|r " .. PO.NAME)
	if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
end

-- The game's addon compartment (the addons button by the minimap), named in the TOC.
function KUK_OnAddonCompartmentClick()
	O:Toggle()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	O:RegisterBlizzardPanel()
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
		O:Toggle()
	elseif cmd == "qa" or cmd == "quickattach" then
		O:Open("quick")
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
		Print("/kuk group - inbox grouping on or off")
		Print("/kuk icons - show or hide all QuickAttach buttons")
		Print("/kuk minimap - show or hide the minimap button")
		Print("/kuk find gi - what the To field would fill in for gi, and why")
	end
	O:Refresh()
end
