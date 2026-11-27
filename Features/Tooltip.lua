-- HUD Tooltip options:
--   * Anchor: Edit Mode Position (Blizzard) or Cursor, with an X / Y offset from the cursor.
--   * Hide Health Bar: the bar under unit tooltips.
--   * Instant Fade: hide the tooltip right away when the mouse leaves a unit or object, instead of fading it.
--
-- Anchor: only the tooltips Blizzard would put at the HUD Tooltip's Edit Mode position are moved: the ones placed by
-- GameTooltip_SetDefaultAnchor (units in the world, unit frames, action buttons and so on). Tooltips that
-- something anchors to itself are left alone. After Blizzard's own anchor, EditTime re-anchors the tooltip to
-- the cursor and keeps it there while it's shown. Tooltips aren't protected, so this works in combat too.
local _, ns = ...

local Systems, Layouts = ns.Systems, ns.Layouts
local L = ns.L

local FIELD_ANCHOR, FIELD_X, FIELD_Y, FIELD_HIDE_BAR = "tooltipAnchor", "cursorX", "cursorY", "hideHealthBar"
local FIELD_INSTANT_FADE = "instantFade"
local DEFAULT, CURSOR = "DEFAULT", "CURSOR"
local OFFSET_MIN, OFFSET_MAX, OFFSET_STEP = -300, 300, 1

local SYS = Enum.EditModeSystem or {}

local type, hooksecurefunc = type, hooksecurefunc
local GetCursorPosition = GetCursorPosition

local function IsTooltipSystem(system)
	return SYS.HudTooltip ~= nil and system.system == SYS.HudTooltip
end

local function TooltipSystem()
	for _, system in ipairs(Systems.GetRegistered()) do
		if IsTooltipSystem(system) then return system end
	end
	return nil
end

local function GetField(system, field)
	return Layouts.Get(Systems.KeyFor(system), field)
end

local function GetOffset(system, field)
	local value = GetField(system, field)
	return type(value) == "number" and value or 0
end

-- The active layout's setting, refreshed with everything else.
local atCursor, offsetX, offsetY = false, 0, 0

-- Following ------------------------------------------------------------------------------------------------------------

local following = setmetatable({}, { __mode = "k" }) -- [tooltip] = the owner it was shown for
local hooked = setmetatable({}, { __mode = "k" })

local function Place(tooltip)
	local x, y = GetCursorPosition()
	local scale = tooltip:GetEffectiveScale()
	if not (x and y and scale and scale > 0) then return end
	tooltip:ClearAllPoints()
	tooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + offsetX, y / scale + offsetY)
end

local function Follow(tooltip)
	local owner = following[tooltip]
	if not owner then return end
	-- Stop once the tooltip is reused for something else or the setting changes.
	if not atCursor or tooltip:GetOwner() ~= owner
		or (tooltip.GetAnchorType and tooltip:GetAnchorType() ~= "ANCHOR_NONE") then
		following[tooltip] = nil
		return
	end
	Place(tooltip)
end

local function StopFollowing(tooltip)
	following[tooltip] = nil
end

local function OnDefaultAnchor(tooltip, parent)
	if not (atCursor and parent and type(tooltip) == "table" and tooltip.HookScript) then return end
	if not hooked[tooltip] then
		hooked[tooltip] = true
		tooltip:HookScript("OnUpdate", Follow)
		tooltip:HookScript("OnHide", StopFollowing)
	end
	following[tooltip] = parent
	Place(tooltip)
end

ns.OnReady(function()
	if type(GameTooltip_SetDefaultAnchor) == "function" then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", OnDefaultAnchor)
	end
end)

-- Health bar -----------------------------------------------------------------------------------------------------------
-- Blizzard shows and hides the bar for every unit tooltip (and keeps its health updates in secure code), so it's
-- faded instead. Blizzard never changes its alpha, and it hangs below the tooltip, so nothing else moves.

local barHidden = false

local function ApplyHealthBar(hide)
	local bar = GameTooltip and GameTooltip.StatusBar
	if not bar or hide == barHidden then return end
	barHidden = hide
	bar:SetAlpha(hide and 0 or 1)
end

-- Instant fade -------------------------------------------------------------------------------------------------------
-- Blizzard fades GameTooltip out (GameTooltip:FadeOut) when the mouse leaves a unit or object in the world, or a
-- unit frame. Every other tooltip is already hidden at once. With Instant Fade on, the fading tooltip is hidden.

local instantFade = false

local function OnFadeOut(tooltip)
	if instantFade and tooltip:IsShown() then
		tooltip:Hide()
	end
end

ns.OnReady(function()
	if GameTooltip and type(GameTooltip.FadeOut) == "function" then
		hooksecurefunc(GameTooltip, "FadeOut", OnFadeOut)
	end
end)

ns.RegisterRefresher(function()
	local system = TooltipSystem()
	instantFade = system ~= nil and GetField(system, FIELD_INSTANT_FADE) == true
	atCursor = system ~= nil and GetField(system, FIELD_ANCHOR) == CURSOR
	offsetX = system and GetOffset(system, FIELD_X) or 0
	offsetY = system and GetOffset(system, FIELD_Y) or 0
	ApplyHealthBar(system ~= nil and GetField(system, FIELD_HIDE_BAR) == true)
end)

-- Options --------------------------------------------------------------------------------------------------------------

ns.RegisterOption({
	kind = "dropdown",
	order = 10,
	appliesTo = IsTooltipSystem,
	label = function() return L.TOOLTIP_ANCHOR end,
	get = function(system)
		return GetField(system, FIELD_ANCHOR) == CURSOR and CURSOR or DEFAULT
	end,
	set = function(system, value)
		Layouts.Set(Systems.KeyFor(system), FIELD_ANCHOR, value == CURSOR and CURSOR or nil)
		ns.RequestRefresh()
	end,
	choices = function()
		return {
			{ value = DEFAULT, text = L.TOOLTIP_ANCHOR_DEFAULT },
			{ value = CURSOR, text = L.TOOLTIP_ANCHOR_CURSOR },
		}
	end,
})

local function OffsetOption(order, field, label)
	return {
		kind = "slider",
		order = order,
		editable = true,
		appliesTo = function(system)
			return IsTooltipSystem(system) and GetField(system, FIELD_ANCHOR) == CURSOR
		end,
		label = function() return L[label] end,
		range = function() return OFFSET_MIN, OFFSET_MAX, OFFSET_STEP end,
		get = function(system) return GetOffset(system, field) end,
		set = function(system, value)
			value = math.floor(value + 0.5)
			Layouts.Set(Systems.KeyFor(system), field, value ~= 0 and value or nil)
			ns.RequestRefresh()
		end,
	}
end

ns.RegisterOption(OffsetOption(11, FIELD_X, "TOOLTIP_OFFSET_X"))
ns.RegisterOption(OffsetOption(12, FIELD_Y, "TOOLTIP_OFFSET_Y"))

ns.RegisterOption({
	kind = "checkbox",
	order = 13,
	appliesTo = function(system)
		return IsTooltipSystem(system) and GameTooltip ~= nil and GameTooltip.StatusBar ~= nil
	end,
	label = function() return L.HIDE_TOOLTIP_HEALTH_BAR end,
	get = function(system) return GetField(system, FIELD_HIDE_BAR) == true end,
	set = function(system, value)
		Layouts.Set(Systems.KeyFor(system), FIELD_HIDE_BAR, value or nil)
		ns.RequestRefresh()
	end,
})

ns.RegisterOption({
	kind = "checkbox",
	order = 14,
	appliesTo = function(system)
		return IsTooltipSystem(system) and GameTooltip ~= nil and type(GameTooltip.FadeOut) == "function"
	end,
	label = function() return L.TOOLTIP_INSTANT_FADE end,
	get = function(system) return GetField(system, FIELD_INSTANT_FADE) == true end,
	set = function(system, value)
		Layouts.Set(Systems.KeyFor(system), FIELD_INSTANT_FADE, value or nil)
		ns.RequestRefresh()
	end,
})
