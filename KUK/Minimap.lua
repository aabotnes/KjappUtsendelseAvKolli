-- Minimap button (same build as the other [Soeta's] addons): left-click opens
-- the settings, right-click opens the QuickAttach page, drag to move it around
-- the minimap. Position and visibility are account-wide.

KUK = KUK or {}
local PO = KUK

local MM = {}
PO.Minimap = MM

local btn

local function Settings()
	KUKDB = KUKDB or {}
	KUKDB.minimap = KUKDB.minimap or { angle = 200, hide = false }
	return KUKDB.minimap
end

local function UpdatePosition()
	local angle = math.rad(Settings().angle or 200)
	local radius = (Minimap:GetWidth() / 2) + 5
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
	Settings().angle = math.deg(atan2(py - my, px - mx))
	UpdatePosition()
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(PO.TITLE)
	if PO.GetMaxItems then
		GameTooltip:AddLine("Attachment slots: |cffffffff" .. PO.GetMaxItems() .. "|r", 1, 0.82, 0)
	end
	if PO.GetQAProfileName then
		GameTooltip:AddLine("QuickAttach profile: |cffffffff" .. PO.GetQAProfileName() .. "|r", 1, 0.82, 0)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Left-click: open settings", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Right-click: QuickAttach buttons", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function Create()
	if btn or not Minimap then return end
	btn = CreateFrame("Button", "KUKMinimapButton", Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetSize(21, 21)
	btn.icon:SetPoint("TOPLEFT", 6, -5)
	btn.icon:SetTexture(PO.ICON)
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the rim inside the round border

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

	btn:SetScript("OnClick", function(_, button)
		GameTooltip:Hide()
		if button == "RightButton" then
			PO.Options:Open("quick")
		else
			PO.Options:Toggle()
		end
	end)
	btn:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	btn:SetScript("OnEnter", ShowTooltip)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	UpdatePosition()
	btn:SetShown(not Settings().hide)
end

function MM:Init() Create() end

function MM:IsShown() return not Settings().hide end

function MM:SetShown(show)
	Settings().hide = not show
	if btn then btn:SetShown(show) end
end

function MM:Toggle()
	self:SetShown(Settings().hide)
	PO.Print(Settings().hide and "minimap button hidden - type /kuk minimap to show it again."
		or "minimap button shown.")
end
