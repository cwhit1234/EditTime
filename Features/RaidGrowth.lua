-- Raid Frame growth: keep a chosen point of the raid frames fixed (e.g. the center) as the roster grows or shrinks,
-- instead of Blizzard's fixed top-left corner.
--
-- How it lines up with Edit Mode: in Edit Mode the raid frames show at their preview size, anchored by Blizzard at
-- the saved TOPLEFT. EditTime records that size (the "reference size") and works out where the chosen growth point
-- sits on that preview box. Outside Edit Mode it anchors the container by that point instead. With the same
-- number of frames as the preview, the frames are exactly where they were placed. With more or fewer, they grow
-- or shrink around that point.
--
-- The container's SetPoint/ClearAllPoints are Edit Mode overrides that write Edit Mode state. EditTime uses the
-- original widget methods (SetPointBase / ClearAllPointsBase) so nothing Blizzard reads is tainted. The container
-- holds secure unit buttons, so it can't be moved in combat. The anchor set before combat keeps working through
-- it, because it's anchored by the growth point.
local _, ns = ...

local Systems, Layouts, Combat = ns.Systems, ns.Layouts, ns.Combat
local L = ns.L

local RaidGrowth = {}
ns.RaidGrowth = RaidGrowth

local FIELD_H, FIELD_V, FIELD_REF = "growthH", "growthV", "growthRef"
local MIN_REF, MAX_REF = 20, 2500

local hooksecurefunc, InCombatLockdown, ipairs, type, select = hooksecurefunc, InCombatLockdown, ipairs, type, select

-- Point fractions: how far across (x, 0 = left) and down (y, 0 = top) the growth point sits on the frame.
local H_FRACTION = { LEFT = 1, CENTER = 0.5, RIGHT = 0 }  -- "LEFT" growth = anchored by the right edge
local V_FRACTION = { UP = 1, CENTER = 0.5, DOWN = 0 }     -- "UP" growth = anchored by the bottom edge

local H_POINT = { [0] = "LEFT", [0.5] = "", [1] = "RIGHT" }
local V_POINT = { [0] = "TOP", [0.5] = "", [1] = "BOTTOM" }

local POINT_FRACTIONS = {
	TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 },
	LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
	BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 },
}

local editModeActive = false
local anchoredByUs = false

local function Container()
	return CompactRaidFrameContainer
end

local function GetGrowth(key)
	return Layouts.Get(key, FIELD_H) or "RIGHT", Layouts.Get(key, FIELD_V) or "DOWN"
end

local function IsDefaultGrowth(h, v)
	return h == "RIGHT" and v == "DOWN"
end

local function ValidSize(w, h)
	return w and h and w > MIN_REF and h > MIN_REF and w < MAX_REF and h < MAX_REF
end

-- Records the container's current size as the reference size. Only while Edit Mode shows the preview.
local function RecordReference(container)
	if not (editModeActive and container:IsShown()) then return end
	local w, h = container:GetSize()
	if ValidSize(w, h) then
		Layouts.Set(Systems.KeyFor(container), FIELD_REF, { w = w, h = h })
	end
end

-- Blizzard's saved anchor for the container, in the container's own coordinates (as ApplySystemAnchor uses it).
local function SavedAnchor(container)
	local info = container.systemInfo and container.systemInfo.anchorInfo
	if not info or (container.systemInfo.anchorInfo2 and container.systemInfo.anchorInfo2.point) then
		return nil -- not set yet, or a two-point anchor (not something the raid container uses)
	end
	local scale = container:GetScale()
	local relativeTo = _G[info.relativeTo] or UIParent
	return info.point, relativeTo, info.relativePoint, info.offsetX / scale, info.offsetY / scale
end

local function SetSingleAnchor(container, point, relativeTo, relativePoint, x, y)
	local clear = container.ClearAllPointsBase or container.ClearAllPoints
	local setPoint = container.SetPointBase or container.SetPoint
	clear(container)
	setPoint(container, point, relativeTo, relativePoint, x, y)
end

-- Where the growth point is, as an anchor: point name on the container plus offsets from the saved relative point.
local function GrowthAnchor(container)
	local key = Systems.KeyFor(container)
	local h, v = GetGrowth(key)
	if IsDefaultGrowth(h, v) then return nil end

	local savedPoint, relativeTo, relativePoint, x, y = SavedAnchor(container)
	if not savedPoint then return nil end

	local ref = Layouts.Get(key, FIELD_REF)
	if not (ref and ValidSize(ref.w, ref.h)) then return nil end

	local saved = POINT_FRACTIONS[savedPoint]
	if not saved then return nil end

	local gx, gy = H_FRACTION[h], V_FRACTION[v]
	local point = V_POINT[gy] .. H_POINT[gx]
	if point == "" then point = "CENTER" end

	-- Offset from the saved point to the growth point on the reference-size box (y grows downward on screen).
	local dx = (gx - saved[1]) * ref.w
	local dy = -(gy - saved[2]) * ref.h
	return point, relativeTo, relativePoint, x + dx, y + dy, gx, gy
end

local function RestoreBlizzardAnchor(container)
	if not anchoredByUs then return end
	local point, relativeTo, relativePoint, x, y = SavedAnchor(container)
	if point then
		SetSingleAnchor(container, point, relativeTo, relativePoint, x, y)
	end
	anchoredByUs = false
end

local function Apply()
	local container = Container()
	if not (container and container.systemInfo) then return end

	Combat.Run(container, function()
		if editModeActive then
			RestoreBlizzardAnchor(container)
			return
		end
		local point, relativeTo, relativePoint, x, y = GrowthAnchor(container)
		if point then
			SetSingleAnchor(container, point, relativeTo, relativePoint, x, y)
			anchoredByUs = true
		else
			RestoreBlizzardAnchor(container)
		end
	end, container)
end

-- LayoutFrames sizes the container to 3000x3000 and only shrinks it to fit a frame later. While anchored by
-- the growth point (not the top-left), that would throw the frames off screen for one frame. So the top-left
-- is pinned right away, where it will be once the final size is known. Out of combat only.
local function PinTopLeftDuringLayout()
	local container = Container()
	if not (anchoredByUs and container and not InCombatLockdown()) then return end

	local point, relativeTo, relativePoint, x, y, gx, gy = GrowthAnchor(container)
	if not point then return end

	local minX, maxX, minY, maxY = container:GetBounds()
	local w, h = maxX - minX, maxY - minY
	if not ValidSize(w, h) then return end

	SetSingleAnchor(container, "TOPLEFT", relativeTo, relativePoint, x - gx * w, y + gy * h)
end

-- Options -------------------------------------------------------------------------------------------------------------

function RaidGrowth.Set(container, field, value, default)
	local key = Systems.KeyFor(container)
	-- The reference size is what Edit Mode shows right now.
	RecordReference(container)
	if not Layouts.Get(key, FIELD_REF) then
		local w, h = container:GetSize()
		if ValidSize(w, h) then
			Layouts.Set(key, FIELD_REF, { w = w, h = h })
		end
	end
	Layouts.Set(key, field, value ~= default and value or nil)
	ns.RequestRefresh()
end

local function Choice(value, global, fallback)
	return { value = value, text = _G[global] or fallback }
end

ns.RegisterOption({
	kind = "dropdown",
	order = 50,
	appliesTo = Systems.IsRaidFrames,
	label = function() return L.HORIZONTAL_GROWTH end,
	disabledReason = Systems.BlockedIfManagedInDefaultPosition,
	get = function(system) return (GetGrowth(Systems.KeyFor(system))) end,
	set = function(system, value) RaidGrowth.Set(system, FIELD_H, value, "RIGHT") end,
	choices = function()
		return {
			Choice("RIGHT", "HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_RIGHT", L.GROWTH_RIGHT),
			{ value = "CENTER", text = L.GROWTH_CENTER },
			Choice("LEFT", "HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_LEFT", L.GROWTH_LEFT),
		}
	end,
})

ns.RegisterOption({
	kind = "dropdown",
	order = 51,
	appliesTo = Systems.IsRaidFrames,
	label = function() return L.VERTICAL_GROWTH end,
	disabledReason = Systems.BlockedIfManagedInDefaultPosition,
	get = function(system) return select(2, GetGrowth(Systems.KeyFor(system))) end,
	set = function(system, value) RaidGrowth.Set(system, FIELD_V, value, "DOWN") end,
	choices = function()
		return {
			Choice("DOWN", "HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_DOWN", L.GROWTH_DOWN),
			{ value = "CENTER", text = L.GROWTH_CENTER },
			Choice("UP", "HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_UP", L.GROWTH_UP),
		}
	end,
})

-- Hooks ---------------------------------------------------------------------------------------------------------------

ns.RegisterRefresher(Apply)

ns.OnReady(function()
	local container = Container()
	if not container then return end

	local manager = EditModeManagerFrame
	editModeActive = manager and manager.IsEditModeActive and manager:IsEditModeActive() or false

	-- Blizzard re-anchors the container whenever a layout is applied.
	for _, method in ipairs({ "ApplySystemAnchor", "UpdateSystem" }) do
		if type(container[method]) == "function" then
			hooksecurefunc(container, method, function()
				anchoredByUs = false -- Blizzard's anchor is in place again
				ns.RequestRefresh()
			end)
		end
	end
	if type(container.LayoutFrames) == "function" then
		hooksecurefunc(container, "LayoutFrames", PinTopLeftDuringLayout)
	end
	container:HookScript("OnSizeChanged", function(self)
		if editModeActive then
			RecordReference(self)
		elseif anchoredByUs then
			ns.RequestRefresh()
		end
	end)

	EventRegistry:RegisterCallback("EditMode.Enter", function()
		editModeActive = true
		Apply()
	end, RaidGrowth)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		editModeActive = false
		Apply()
	end, RaidGrowth)
end)
