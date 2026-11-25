-- Movers: Edit Mode style selection boxes for frames Blizzard's Edit Mode doesn't know about.
--
-- Blizzard's Edit Mode can't be given new systems without writing into EditModeManagerFrame's tables and layout
-- data, which would taint it (and through it the action bars). So EditTime draws its own selection boxes while
-- Edit Mode is open. They use Blizzard's selection nine-slice, label and tooltip behaviour, and a settings dialog in
-- the same style. Positions are saved per Edit Mode layout in EditTimeDB.
--
-- Snapping: when Edit Mode's "Snap" option is on, a dragged box snaps exactly like a Blizzard system. Blizzard's
-- own EditModeMagnetismManager does the math (grid lines, screen edges and center, other frames' edges and
-- corners): its queries are read-only, and each box answers the geometry questions it asks with copies of
-- EditModeSystemMixin's methods. The snap is then applied to the box, and the same red preview lines are drawn
-- while dragging. EditTime's boxes are not registered as snap targets for Blizzard's frames: that would mean
-- writing into the magnetism manager.
--
-- Mover definition (ns.Movers.Register):
--   key            unique id; saved under the system key "mover:<key>"
--   label          display name
--   isAvailable()  false hides the mover (frame not loaded / not used in this game mode)
--   anchorBox(box) places the selection box over the frame (it may be hidden)
--   onDrag(box)    the box was moved by the player: move the frame to match, return the position to save
--   apply(pos)     place the frame at a saved position (pos is nil for Blizzard's default)
--   options        optional list of setting rows for the dialog (UI/Rows.lua fields; context = the definition)
--   install()      optional, called once: hooks that call ns.RequestRefresh() when Blizzard re-places the frame
local _, ns = ...

local Layouts, Combat = ns.Layouts, ns.Combat

local Movers = {}
ns.Movers = Movers

local ipairs, pairs, hooksecurefunc = ipairs, pairs, hooksecurefunc

local defs = {}
local boxes = {}       -- [def] = selection box
local selected         -- the selected def, if any
local dialog
local editModeActive = false

local function SystemKey(def)
	return "mover:" .. def.key
end

function Movers.Get(def, field)
	return Layouts.Get(SystemKey(def), field)
end

function Movers.Set(def, field, value)
	Layouts.Set(SystemKey(def), field, value)
end

function Movers.GetPosition(def)
	return Movers.Get(def, "pos")
end

-- Apply ---------------------------------------------------------------------------------------------------------------

local function ApplyDef(def)
	if not def.isAvailable() then return end
	-- Some of these frames are secure (Target of Target): positions change out of combat only.
	Combat.Run(def, function()
		def.apply(Movers.GetPosition(def))
	end)
end

function Movers.Apply(def)
	ApplyDef(def)
	local box = boxes[def]
	if box and box:IsShown() and not box.dragging then
		def.anchorBox(box)
	end
end

ns.RegisterRefresher(function()
	for _, def in ipairs(defs) do
		ApplyDef(def)
	end
end)

-- Geometry, as EditModeSystemMixin answers it -------------------------------------------------------------------------
-- The box is its own "Selection": it covers exactly the frame it moves.

local SELECTION_PADDING = 2 -- EditModeSystemTemplates.lua

local Geometry = {}

function Geometry:HasValidSelectionRect()
	return self:GetRect() ~= nil
end

function Geometry:GetScaledSelectionCenter()
	local x, y = self:GetCenter()
	local scale = self:GetScale()
	return x * scale, y * scale
end
Geometry.GetScaledCenter = Geometry.GetScaledSelectionCenter

function Geometry:GetScaledSelectionSides()
	local left, bottom, width, height = self:GetRect()
	local scale = self:GetScale()
	return left * scale, (left + width) * scale, bottom * scale, (bottom + height) * scale
end

function Geometry:IsToTheLeftOfFrame(other)
	local _, myRight = self:GetScaledSelectionSides()
	local otherLeft = other:GetScaledSelectionSides()
	return myRight < otherLeft
end

function Geometry:IsToTheRightOfFrame(other)
	local myLeft = self:GetScaledSelectionSides()
	local _, otherRight = other:GetScaledSelectionSides()
	return myLeft > otherRight
end

function Geometry:IsAboveFrame(other)
	local _, _, myBottom = self:GetScaledSelectionSides()
	local _, _, _, otherTop = other:GetScaledSelectionSides()
	return myBottom > otherTop
end

function Geometry:IsBelowFrame(other)
	local _, _, _, myTop = self:GetScaledSelectionSides()
	local _, _, otherBottom = other:GetScaledSelectionSides()
	return myTop < otherBottom
end

function Geometry:IsVerticallyAlignedWithFrame(other)
	local _, _, myBottom, myTop = self:GetScaledSelectionSides()
	local _, _, otherBottom, otherTop = other:GetScaledSelectionSides()
	return myTop >= otherBottom and myBottom <= otherTop
end

function Geometry:IsHorizontallyAlignedWithFrame(other)
	local myLeft, myRight = self:GetScaledSelectionSides()
	local otherLeft, otherRight = other:GetScaledSelectionSides()
	return myRight >= otherLeft and myLeft <= otherRight
end

function Geometry:IsFrameAnchoredToMe(frame)
	for i = 1, frame:GetNumPoints() do
		local _, relativeTo = frame:GetPoint(i)
		if not relativeTo then return false end
		if relativeTo == self or self:IsFrameAnchoredToMe(relativeTo) then return true end
	end
	return false
end

function Geometry:GetFrameMagneticEligibility(other)
	if other == self or self:IsFrameAnchoredToMe(other) then return nil end
	if not (other.HasValidSelectionRect and other:HasValidSelectionRect()) then return nil end

	local horizontal = self:IsVerticallyAlignedWithFrame(other) and (self:IsToTheLeftOfFrame(other) or self:IsToTheRightOfFrame(other))
	local vertical = self:IsHorizontallyAlignedWithFrame(other) and (self:IsAboveFrame(other) or self:IsBelowFrame(other))
	return horizontal, vertical
end

-- Selection sides relative to the frame itself: the box is the frame, so only Blizzard's padding remains.
function Geometry:GetSelectionOffset(point, forYOffset)
	local offset
	if point == "LEFT" then
		offset = -SELECTION_PADDING
	elseif point == "RIGHT" then
		offset = SELECTION_PADDING
	elseif point == "TOP" then
		offset = SELECTION_PADDING
	elseif point == "BOTTOM" then
		offset = -SELECTION_PADDING
	elseif point == "TOPLEFT" then
		offset = forYOffset and SELECTION_PADDING or -SELECTION_PADDING
	elseif point == "TOPRIGHT" then
		offset = SELECTION_PADDING
	elseif point == "BOTTOMLEFT" then
		offset = -SELECTION_PADDING
	elseif point == "BOTTOMRIGHT" then
		offset = forYOffset and -SELECTION_PADDING or SELECTION_PADDING
	else
		offset = 0
	end
	return offset * self:GetScale()
end

function Geometry:GetCombinedSelectionOffset(frameInfo, forYOffset)
	local offset
	if frameInfo.frame.GetSelectionOffset then
		offset = -self:GetSelectionOffset(frameInfo.point, forYOffset) + frameInfo.frame:GetSelectionOffset(frameInfo.relativePoint, forYOffset) + frameInfo.offset
	else
		offset = -self:GetSelectionOffset(frameInfo.point, forYOffset) + frameInfo.offset
	end
	return offset / self:GetScale()
end

function Geometry:GetCombinedCenterOffset(frame)
	local x, y = self:GetScaledCenter()
	local fx, fy
	if frame.GetScaledCenter then
		fx, fy = frame:GetScaledCenter()
	else
		fx, fy = frame:GetCenter()
	end
	local scale = self:GetScale()
	return (x - fx) / scale, (y - fy) / scale
end

function Geometry:GetSnapOffsets(frameInfo)
	local x, y
	if frameInfo.isCornerSnap then
		x = self:GetCombinedSelectionOffset(frameInfo, false)
		y = self:GetCombinedSelectionOffset(frameInfo, true)
	else
		x, y = self:GetCombinedCenterOffset(frameInfo.frame)
		if frameInfo.isHorizontal then
			x = self:GetCombinedSelectionOffset(frameInfo, false)
		else
			y = self:GetCombinedSelectionOffset(frameInfo, true)
		end
	end
	return x, y
end

-- Snapping ------------------------------------------------------------------------------------------------------------

local previewLines -- line pool, created on first use

local function IsSnapEnabled()
	local manager = EditModeManagerFrame
	return manager and manager.IsSnapEnabled and manager:IsSnapEnabled() and EditModeMagnetismManager ~= nil
end

local function GetSnaps(box)
	if not IsSnapEnabled() then return nil end
	local ok, infos = pcall(EditModeMagnetismManager.GetMagneticFrameInfos, EditModeMagnetismManager, box)
	return ok and infos or nil
end

local linesContainer
local function HidePreviewLines()
	if previewLines then previewLines:ReleaseAll() end
end

local function ShowPreviewLines(box)
	HidePreviewLines()
	local infos = GetSnaps(box)
	if not infos then return end

	if not previewLines then
		linesContainer = CreateFrame("Frame", nil, UIParent)
		linesContainer:SetAllPoints()
		linesContainer:SetFrameStrata("HIGH")
		previewLines = EditModeUtil.CreateLinePool(linesContainer, "MagnetismPreviewLineTemplate")
	end
	for _, info in ipairs(infos) do
		for _, lineAnchor in ipairs(EditModeMagnetismManager:GetPreviewLineAnchors(info)) do
			previewLines:Acquire():Setup(info, lineAnchor)
		end
	end
end

-- EditModeSystemMixin:SnapToFrame, applied to the box.
local function ApplySnaps(box)
	local infos = GetSnaps(box)
	if not infos then return end
	for _, info in ipairs(infos) do
		local x, y = box:GetSnapOffsets(info)
		box:ClearAllPoints()
		box:SetPoint(info.point, info.frame, info.relativePoint, x, y)
	end
end

-- Selection box -------------------------------------------------------------------------------------------------------

-- Copy of the local EditModeSystemSelectionLayout in Blizzard_EditMode's EditModeSystemTemplates.lua.
local SELECTION_LAYOUT = {
	["TopRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	["TopLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	["BottomLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	["BottomRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	["TopEdge"] = { atlas = "_%s-NineSlice-EdgeTop" },
	["BottomEdge"] = { atlas = "_%s-NineSlice-EdgeBottom" },
	["LeftEdge"] = { atlas = "!%s-NineSlice-EdgeLeft" },
	["RightEdge"] = { atlas = "!%s-NineSlice-EdgeRight" },
	["Center"] = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local HIGHLIGHT_KIT, SELECTED_KIT = "editmode-actionbar-highlight", "editmode-actionbar-selected"

local function UpdateLabel(box)
	local isSelected = selected == box.def
	if isSelected then
		box.Label:SetText(box.def.label)
	else
		box.Label:SetText(HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT or "")
	end
	box.Label:SetShown(isSelected or box.hovered)
end

local function SetBoxSelected(box, isSelected)
	local kit = isSelected and SELECTED_KIT or HIGHLIGHT_KIT
	if box.kit ~= kit then
		NineSliceUtil.ApplyLayout(box, SELECTION_LAYOUT, kit)
		box.kit = kit
	end
	UpdateLabel(box)
end

local ShowDialog, HideDialog

local function Select(def)
	if selected == def then return end
	local previous = selected
	selected = def
	if previous and boxes[previous] then SetBoxSelected(boxes[previous], false) end
	if def and boxes[def] then SetBoxSelected(boxes[def], true) end

	if def then
		-- Deselect Blizzard's system. Out of combat this runs through Blizzard's secure delegate.
		if EditModeSystemSettingsDialog and EditModeSystemSettingsDialog:IsShown() then
			EditModeManagerFrame:ClearSelectedSystem()
		end
		ShowDialog(def)
	else
		HideDialog()
	end
end

local function Box_OnEnter(box)
	box.hovered = true
	box.MouseOverHighlight:Show()
	UpdateLabel(box)
	if selected ~= box.def then
		GameTooltip:SetOwner(box, "ANCHOR_CURSOR")
		GameTooltip:SetText(box.def.label)
		GameTooltip:Show()
	end
end

local function Box_OnLeave(box)
	box.hovered = false
	box.MouseOverHighlight:Hide()
	UpdateLabel(box)
	if GameTooltip:GetOwner() == box then
		GameTooltip:Hide()
	end
end

local function Box_OnMouseDown(box)
	Select(box.def)
	GameTooltip:Hide()
end

local function FollowBox(box)
	local pos = box.def.onDrag(box)
	if pos then box.pendingPos = pos end
end

local function Box_OnUpdate(box)
	FollowBox(box)
	ShowPreviewLines(box)
end

local function Box_OnDragStart(box)
	if selected ~= box.def then Select(box.def) end
	box.dragging = true
	box.pendingPos = nil
	box:StartMoving()
	box:SetScript("OnUpdate", Box_OnUpdate)
end

local function Box_OnDragStop(box)
	box:StopMovingOrSizing()
	box:SetScript("OnUpdate", nil)
	HidePreviewLines()
	ApplySnaps(box)
	FollowBox(box)
	box.dragging = false

	if box.pendingPos then
		Movers.Set(box.def, "pos", box.pendingPos)
		box.pendingPos = nil
	end
	box.def.anchorBox(box)
	if dialog and dialog:IsShown() then dialog:Refresh() end
end

local function CreateBox(def)
	local box = CreateFrame("Frame", nil, UIParent, "NineSliceCodeTemplate")
	Mixin(box, Geometry)
	box.def = def
	box:SetFrameStrata("MEDIUM")
	box:SetFrameLevel(1000)
	box:SetToplevel(true)
	box:SetMovable(true)
	box:SetClampedToScreen(true)
	box:SetDontSavePosition(true)
	box:EnableMouse(true)
	box:RegisterForDrag("LeftButton")
	box:SetIgnoreParentAlpha(true)

	box.MouseOverHighlight = CreateFrame("Frame", nil, box, "NineSliceCodeTemplate")
	box.MouseOverHighlight:SetAllPoints()
	box.MouseOverHighlight:SetAlpha(0.4)
	box.MouseOverHighlight:Hide()
	NineSliceUtil.ApplyLayout(box.MouseOverHighlight, SELECTION_LAYOUT, HIGHLIGHT_KIT)
	box.MouseOverHighlight:SetBlendMode("ADD")

	box.Label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	box.Label:SetAllPoints()
	box.Label:SetIgnoreParentScale(true)
	if ShrinkUntilTruncateFontStringMixin then
		Mixin(box.Label, ShrinkUntilTruncateFontStringMixin)
		box.Label:SetFontObjectsToTry("GameFontHighlightLarge", "GameFontHighlightMedium", "GameFontHighlightSmall")
	end
	box.Label:Hide()

	box:SetScript("OnEnter", Box_OnEnter)
	box:SetScript("OnLeave", Box_OnLeave)
	box:SetScript("OnMouseDown", Box_OnMouseDown)
	box:SetScript("OnDragStart", Box_OnDragStart)
	box:SetScript("OnDragStop", Box_OnDragStop)

	SetBoxSelected(box, false)
	box:Hide()
	return box
end

local function ShowBoxes()
	for _, def in ipairs(defs) do
		if def.isAvailable() then
			local box = boxes[def] or CreateBox(def)
			boxes[def] = box
			def.anchorBox(box)
			SetBoxSelected(box, false)
			box:Show()
		end
	end
end

local function HideBoxes()
	Select(nil)
	HidePreviewLines()
	for _, box in pairs(boxes) do
		box:Hide()
	end
end

-- Dialog (same look as EditModeSystemSettingsDialog) -----------------------------------------------------------------

local function CreateDialog()
	local f = CreateFrame("Frame", nil, UIParent, "ResizeLayoutFrame")
	f.widthPadding = 40
	f.heightPadding = 40
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(200)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:SetDontSavePosition(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	-- Blizzard's default spot for its settings dialog (EditModeSystemMixin:SetupSettingsDialogAnchor).
	f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -250, 200)

	f.Border = CreateFrame("Frame", nil, f, "DialogBorderTranslucentTemplate")
	f.Border.ignoreInLayout = true

	f.Title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	f.Title:SetPoint("TOP", 0, -15)

	f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.CloseButton.ignoreInLayout = true
	f.CloseButton:SetPoint("TOPRIGHT")
	f.CloseButton:SetScript("OnClick", function() Select(nil) end)

	f.Settings = CreateFrame("Frame", nil, f, "VerticalLayoutFrame")
	f.Settings.spacing = 2
	f.Settings:SetPoint("TOP", f.Title, "BOTTOM", 0, -12)
	f.rows = ns.Rows.CreateSet(f.Settings)

	f.ResetButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.ResetButton:SetSize(ns.Rows.WIDTH, 28)
	f.ResetButton:SetText(HUD_EDIT_MODE_RESET_POSITION or RESET_TO_DEFAULT)
	f.ResetButton:SetScript("OnClick", function()
		local def = f.def
		if not def then return end
		Movers.Set(def, "pos", nil)
		Movers.Apply(def)
		f:Refresh()
	end)

	function f:Refresh()
		local def = self.def
		if not def then return end
		self.Title:SetText(def.label)

		local numRows = self.rows:Show(def.options or {}, def)
		self.ResetButton:ClearAllPoints()
		if numRows > 0 then
			self.Settings:Show()
			self.Settings:Layout()
			self.ResetButton:SetPoint("TOP", self.Settings, "BOTTOM", 0, -12)
		else
			self.Settings:Hide()
			self.ResetButton:SetPoint("TOP", self.Title, "BOTTOM", 0, -12)
		end
		self.ResetButton:SetEnabled(Movers.GetPosition(def) ~= nil)
		self:Layout()
	end

	f:Hide()
	return f
end

function ShowDialog(def)
	dialog = dialog or CreateDialog()
	dialog.def = def
	dialog:Show()
	dialog:Refresh()
end

function HideDialog()
	if dialog then
		dialog.def = nil
		dialog:Hide()
	end
end

-- Registration and hooks ----------------------------------------------------------------------------------------------

function Movers.Register(def)
	defs[#defs + 1] = def
end

ns.OnReady(function()
	for _, def in ipairs(defs) do
		if def.install then
			local ok, err = pcall(def.install)
			if not ok then geterrorhandler()(err) end
		end
	end

	local manager = EditModeManagerFrame
	if not manager then return end
	editModeActive = manager.IsEditModeActive and manager:IsEditModeActive() or false

	-- Clicking a Blizzard system deselects EditTime's mover.
	hooksecurefunc(manager, "SelectSystem", function()
		if selected then Select(nil) end
	end)

	EventRegistry:RegisterCallback("EditMode.Enter", function()
		editModeActive = true
		ShowBoxes()
	end, Movers)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		editModeActive = false
		HideBoxes()
	end, Movers)

	-- A layout switch while Edit Mode is open moves everything: put the boxes back over their frames.
	ns.RegisterRefresher(function()
		if not editModeActive then return end
		for def, box in pairs(boxes) do
			if box:IsShown() and not box.dragging then def.anchorBox(box) end
		end
		if dialog and dialog:IsShown() and not dialog.rows:IsMenuOpen() then dialog:Refresh() end
	end)
end)
