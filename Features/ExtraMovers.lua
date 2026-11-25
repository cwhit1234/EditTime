-- Frames Blizzard's Edit Mode can't move, made movable through EditTime's movers (UI/Movers.lua):
--   * Target of Target and Focus Target: kept as an offset from their Target/Focus frame, so they still follow it.
--   * Toasts (AlertFrame): the anchor every toast and alert stacks from; can grow up (Blizzard) or down.
--   * Loot Rolls: the group loot roll windows; can grow up (Blizzard) or down.
--
-- Only widget calls are used (SetPoint / ClearAllPoints). No Blizzard Lua that writes shared state is called: the
-- loot roll container sits in the bottom managed-frame layout next to protected frames (extra action buttons),
-- so the container itself is never moved or hidden. Only the roll windows it places are.
local _, ns = ...

local Movers = ns.Movers
local L = ns.L

local hooksecurefunc, ipairs, type = hooksecurefunc, ipairs, type
local InCombatLockdown = InCombatLockdown

local UP, DOWN = "UP", "DOWN"

local function BoxCenterX(box, s)
	local left, right = box:GetLeft(), box:GetRight()
	if not (left and right) then return nil end
	return (left + right) / 2 * s
end

-- Scale from a box's coordinates to UIParent's.
local function ToUIParent(box)
	return box:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function GrowthOption(def)
	return {
		kind = "dropdown",
		label = function() return L.GROWTH_DIRECTION end,
		get = function() return Movers.Get(def, "growth") or UP end,
		set = function(_, value)
			Movers.Set(def, "growth", value ~= UP and value or nil)
			Movers.Apply(def)
			ns.RequestRefresh()
		end,
		choices = function()
			return {
				{ value = UP, text = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_UP or L.GROWTH_UP },
				{ value = DOWN, text = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_DOWN or L.GROWTH_DOWN },
			}
		end,
	}
end

local function Growth(def)
	return Movers.Get(def, "growth") or UP
end

-- Target of Target / Focus Target ------------------------------------------------------------------------------------
-- Blizzard anchors the frame's TOPRIGHT to its parent's BOTTOMRIGHT (and only ever sets that one point), so an
-- offset on the same point replaces Blizzard's, and Blizzard's own re-anchor replaces EditTime's (then re-applied).

local function RegisterToT(key, label, parentName, defaultOffsets)
	local movedByUs = false

	local function Parts()
		local parent = _G[parentName]
		return parent, parent and parent.totFrame
	end

	local function SetOffsets(x, y)
		local parent, tot = Parts()
		if parent and tot and not InCombatLockdown() then
			tot:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", x, y)
		end
	end

	Movers.Register({
		key = key,
		label = label,
		isAvailable = function()
			local parent, tot = Parts()
			return parent ~= nil and tot ~= nil
		end,
		anchorBox = function(box)
			local _, tot = Parts()
			box:ClearAllPoints()
			box:SetAllPoints(tot)
		end,
		onDrag = function(box)
			local parent, tot = Parts()
			local right, top = box:GetRight(), box:GetTop()
			local parentRight, parentBottom = parent:GetRight(), parent:GetBottom()
			if not (right and top and parentRight and parentBottom) then return nil end

			-- Offsets are in the ToT frame's own scale.
			local boxScale, parentScale, totScale = box:GetEffectiveScale(), parent:GetEffectiveScale(), tot:GetEffectiveScale()
			local x = (right * boxScale - parentRight * parentScale) / totScale
			local y = (top * boxScale - parentBottom * parentScale) / totScale
			SetOffsets(x, y)
			movedByUs = true
			return { x = x, y = y }
		end,
		apply = function(pos)
			if pos then
				SetOffsets(pos.x, pos.y)
				movedByUs = true
			elseif movedByUs then
				SetOffsets(defaultOffsets())
				movedByUs = false
			end
		end,
		install = function()
			local parent = _G[parentName]
			-- FocusFrameMixin:SetSmallSize re-anchors the Focus Target when the frame size setting changes.
			if parent and type(parent.SetSmallSize) == "function" then
				hooksecurefunc(parent, "SetSmallSize", ns.RequestRefresh)
			end
		end,
	})
end

-- TargetofTargetFrameTemplate's XML anchor, and FocusFrameMixin:SetSmallSize's two variants.
RegisterToT("targettarget", L.TARGET_OF_TARGET, "TargetFrame", function()
	return 12, 10
end)
RegisterToT("focustarget", L.FOCUS_TARGET, "FocusFrame", function()
	local focus = FocusFrame
	if focus and focus.smallSize then
		return 20, 8
	end
	return 12, 10
end)

-- Shared: the loot roll mover, needed by the toast chain below -------------------------------------------------------

local lootDef

local function IsLootTakenOver()
	return lootDef ~= nil and (Movers.GetPosition(lootDef) ~= nil or Growth(lootDef) == DOWN)
end

-- Toasts --------------------------------------------------------------------------------------------------------------
-- AlertFrame is only positioned by its XML (BOTTOM, 0, 128). Blizzard's AlertContainerMixin:UpdateAnchors chains
-- every toast upward from it: each one's BOTTOM on the previous one's TOP. Growing down, EditTime redoes the same
-- chain mirrored, right after Blizzard's pass (TOP on the previous one's BOTTOM).

local TOAST_BOX_WIDTH, TOAST_BOX_HEIGHT, TOAST_SPACING = 300, 90, 10
local toastDef

local JUSTIFY_SUFFIX = { LEFT = "LEFT", CENTER = "", RIGHT = "RIGHT" }

local function ClearPoints(frame)
	-- Some auto-anchored alerts are Edit Mode systems: use their original widget methods, not Edit Mode's overrides.
	local clear = frame.ClearAllPointsBase or frame.ClearAllPoints
	clear(frame)
end

local function SetPointOn(frame, ...)
	local setPoint = frame.SetPointBase or frame.SetPoint
	setPoint(frame, ...)
end

-- Re-chains every shown toast from the base anchor, in Blizzard's order, growing `direction`.
local function ChainToasts(direction)
	local container = AlertFrame
	if type(container.alertFrameSubSystems) ~= "table" then return end

	local down = direction == DOWN
	local base = container.baseAnchorFrame or container
	local suffix = JUSTIFY_SUFFIX[container.GetJustification and container:GetJustification() or "CENTER"] or ""
	local autoAdjust = AlertFrameAutoAnchoredMixin and AlertFrameAutoAnchoredMixin.AdjustAnchors

	local relative = base
	for _, subSystem in ipairs(container.alertFrameSubSystems) do
		local pool = subSystem.alertFramePool
		local anchorFrame = subSystem.anchorFrame

		if pool and pool.EnumerateActive then
			-- AlertFrameQueueMixin:AdjustAnchors
			for frame in pool:EnumerateActive() do
				ClearPoints(frame)
				if down then
					SetPointOn(frame, "TOP", relative, "BOTTOM", 0, -TOAST_SPACING)
				else
					SetPointOn(frame, "BOTTOM", relative, "TOP", 0, TOAST_SPACING)
				end
				relative = frame
			end
		elseif anchorFrame and subSystem.AdjustAnchors == autoAdjust then
			-- AlertFrameAutoAnchoredMixin:AdjustAnchors. Frames moved in Edit Mode keep their own spot.
			local movedInEditMode = anchorFrame.IsInDefaultPosition and not anchorFrame:IsInDefaultPosition()
			if anchorFrame:IsShown() and not movedInEditMode then
				local first = relative == base
				local point, relativePoint
				if down then
					point = "TOP" .. suffix
					relativePoint = (first and "TOP" or "BOTTOM") .. suffix
				else
					point = "BOTTOM" .. suffix
					relativePoint = (first and "BOTTOM" or "TOP") .. suffix
				end
				ClearPoints(anchorFrame)
				SetPointOn(anchorFrame, point, relative, relativePoint, 0, 0)
				relative = anchorFrame
			end
		elseif anchorFrame and anchorFrame:IsShown() and not down and not (anchorFrame == GroupLootContainer and IsLootTakenOver()) then
			-- Externally anchored (the loot roll container): Blizzard stacks the next toasts on top of it.
			-- Growing down, or with the loot rolls moved away, it's left out of the chain.
			relative = anchorFrame
		end
	end
end

-- After Blizzard's own pass: growing down, or when the loot rolls were moved out from under the toasts.
local function AfterBlizzardToastChain()
	if toastDef and Growth(toastDef) == DOWN then
		ChainToasts(DOWN)
	elseif IsLootTakenOver() and GroupLootContainer and GroupLootContainer:IsShown() then
		ChainToasts(UP)
	end
end

local function PlaceAlertFrame(x, y)
	AlertFrame:ClearAllPoints()
	AlertFrame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, y)
end

do
	local movedByUs = false

	toastDef = {
		key = "toasts",
		label = L.TOASTS,
		isAvailable = function()
			return AlertFrame ~= nil
		end,
		-- The box shows where the first toast goes: above the anchor growing up, below it growing down.
		anchorBox = function(box)
			box:ClearAllPoints()
			box:SetSize(TOAST_BOX_WIDTH, TOAST_BOX_HEIGHT)
			if Growth(toastDef) == DOWN then
				box:SetPoint("TOP", AlertFrame, "BOTTOM", 0, 0)
			else
				box:SetPoint("BOTTOM", AlertFrame, "BOTTOM", 0, 0)
			end
		end,
		onDrag = function(box)
			local s = ToUIParent(box)
			local x = BoxCenterX(box, s)
			local edge = Growth(toastDef) == DOWN and box:GetTop() or box:GetBottom()
			if not (x and edge) then return nil end
			PlaceAlertFrame(x, edge * s)
			movedByUs = true
			return { x = x, y = edge * s }
		end,
		apply = function(pos)
			if pos then
				PlaceAlertFrame(pos.x, pos.y)
				movedByUs = true
			elseif movedByUs then
				AlertFrame:ClearAllPoints()
				AlertFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 128)
				movedByUs = false
			end
			-- Re-chain the toasts already showing in the chosen direction.
			ChainToasts(Growth(toastDef))
		end,
		install = function()
			if AlertFrame and type(AlertFrame.UpdateAnchors) == "function" then
				hooksecurefunc(AlertFrame, "UpdateAnchors", AfterBlizzardToastChain)
			end
		end,
	}
	toastDef.options = { GrowthOption(toastDef) }
	Movers.Register(toastDef)
end

-- Loot Rolls ----------------------------------------------------------------------------------------------------------
-- GroupLootContainer_Update places roll window i at ("CENTER", container, "BOTTOM", 0, reservedSize * (i - 0.5)).
-- Once moved or set to grow down, EditTime places them against its own anchor: the bottom of the first slot.

do
	local placedByUs = false
	local anchor = CreateFrame("Frame", nil, UIParent)
	anchor:SetSize(1, 1)

	local function ReservedSize()
		return (GroupLootContainer and GroupLootContainer.reservedSize) or 100
	end

	local function IsGamepadLayout()
		return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
	end

	-- Slot i's center, measured from the bottom of the first slot.
	local function SlotOffset(i, direction)
		local reserved = ReservedSize()
		if direction == DOWN then
			return reserved * (1.5 - i)
		end
		return reserved * (i - 0.5)
	end

	local function PlaceRolls(relativeTo, direction)
		local container = GroupLootContainer
		if not container or type(container.rollFrames) ~= "table" or IsGamepadLayout() then return end
		for i = 1, container.maxIndex or 0 do
			local frame = container.rollFrames[i]
			if frame then
				frame:ClearAllPoints()
				frame:SetPoint("CENTER", relativeTo, "BOTTOM", 0, SlotOffset(i, direction))
			end
		end
	end

	local function PlaceAnchor(pos)
		anchor:ClearAllPoints()
		if pos then
			anchor:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", pos.x, pos.y)
		else
			anchor:SetPoint("BOTTOM", GroupLootContainer, "BOTTOM", 0, 0) -- Blizzard's spot, growing down
		end
	end

	lootDef = {
		key = "lootrolls",
		label = L.LOOT_ROLLS,
		isAvailable = function()
			return GroupLootContainer ~= nil and type(GroupLootContainer_Update) == "function"
		end,
		-- The box is the first roll slot.
		anchorBox = function(box)
			box:ClearAllPoints()
			local sample = GroupLootFrame1
			box:SetSize(sample and sample:GetWidth() or 280, ReservedSize())
			local pos = Movers.GetPosition(lootDef)
			if pos then
				box:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", pos.x, pos.y)
			elseif GroupLootContainer:GetBottom() then
				box:SetPoint("BOTTOM", GroupLootContainer, "BOTTOM", 0, 0)
			else
				box:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 250)
			end
		end,
		onDrag = function(box)
			local s = ToUIParent(box)
			local x, bottom = BoxCenterX(box, s), box:GetBottom()
			if not (x and bottom) then return nil end
			local pos = { x = x, y = bottom * s }
			PlaceAnchor(pos)
			PlaceRolls(anchor, Growth(lootDef))
			return pos
		end,
		apply = function(pos)
			if IsLootTakenOver() then
				PlaceAnchor(pos)
				PlaceRolls(anchor, Growth(lootDef))
				placedByUs = true
			elseif placedByUs then
				PlaceRolls(GroupLootContainer, UP) -- back to Blizzard's placement
				placedByUs = false
			end
			AfterBlizzardToastChain()
		end,
		install = function()
			hooksecurefunc("GroupLootContainer_Update", function()
				if IsLootTakenOver() then
					PlaceRolls(anchor, Growth(lootDef))
					AfterBlizzardToastChain()
				end
			end)
		end,
	}
	lootDef.options = { GrowthOption(lootDef) }
	Movers.Register(lootDef)
end
