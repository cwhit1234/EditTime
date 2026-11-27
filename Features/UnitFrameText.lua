-- Text options for the Player, Target and Focus frames:
--   * Hide Portrait Combat Text (Player Frame): the damage, heal and miss numbers Blizzard flashes over the
--     player's portrait.
--   * Hide Player Name (Player Frame).
--   * Status Text: the same setting as Options > Interface > Status Text, brought into Edit Mode. It is a CVar,
--     so it applies to every unit frame and isn't saved per layout, exactly as in Blizzard's options.
--   * Level Scale (Player, Target and Focus Frames): the round level badge.
--   * Class icon portraits: Blizzard's Interface options, on the frames they change.
--
-- The combat text and name are hidden with alpha on a region Blizzard never fades, shows or hides. For the combat text that's its
-- container: Blizzard keeps animating the text's own alpha, so the text itself can't be faded.
local _, ns = ...

local Systems, Layouts, Combat = ns.Systems, ns.Layouts, ns.Combat
local L = ns.L

local FIELD_HIT_TEXT, FIELD_NAME = "hidePortraitCombatText", "hidePlayerName"

local SYS = Enum.EditModeSystem or {}
local UNIT_INDICES = Enum.EditModeUnitFrameSystemIndices or {}

local GetCVar, SetCVar = C_CVar and C_CVar.GetCVar or GetCVar, SetCVar

local function IsUnitFrame(system, index)
	return system.system == SYS.UnitFrame and index ~= nil and system.systemIndex == index
end

local function IsPlayerFrame(system)
	return IsUnitFrame(system, UNIT_INDICES.Player)
end

-- Portrait combat text and name ----------------------------------------------------------------------------------

local function GetHitIndicator()
	local content = PlayerFrame and PlayerFrame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	return main and main.HitIndicator
end

local function GetPlayerName()
	return PlayerFrame and PlayerFrame.name or PlayerName
end

local function PlayerFrameSystem()
	for _, system in ipairs(Systems.GetRegistered()) do
		if IsPlayerFrame(system) then return system end
	end
	return nil
end

-- field -> { get = function returning the region, label = locale key, order }
local HIDEABLE = {
	[FIELD_HIT_TEXT] = { get = GetHitIndicator, label = "HIDE_PORTRAIT_COMBAT_TEXT", order = 74 },
	[FIELD_NAME] = { get = GetPlayerName, label = "HIDE_PLAYER_NAME", order = 75 },
}

local hidden = {} -- [field] = true while EditTime has that region faded

local function RefreshHidden()
	local system = PlayerFrameSystem()
	if not system then return end
	local key = Systems.KeyFor(system)

	for field, info in pairs(HIDEABLE) do
		local region = info.get()
		local hide = Layouts.Get(key, field) == true
		if region and hide ~= (hidden[field] == true) then
			hidden[field] = hide or nil
			Combat.Run(region, function()
				region:SetAlpha(hidden[field] and 0 or 1)
			end, region)
		end
	end
end

ns.RegisterRefresher(RefreshHidden)

for field, info in pairs(HIDEABLE) do
	ns.RegisterOption({
		kind = "checkbox",
		order = info.order,
		appliesTo = function(system)
			return IsPlayerFrame(system) and info.get() ~= nil
		end,
		label = function() return L[info.label] end,
		get = function(system)
			return Layouts.Get(Systems.KeyFor(system), field) == true
		end,
		set = function(system, value)
			Layouts.Set(Systems.KeyFor(system), field, value or nil)
			ns.RequestRefresh()
		end,
	})
end

-- Status text -----------------------------------------------------------------------------------------------------

-- The values and order of Blizzard's own Status Text dropdown (Blizzard_SettingsDefinitions_Frame/Interface.lua).
local NUMERIC, PERCENT, BOTH, NONE_VALUE = "NUMERIC", "PERCENT", "BOTH", "NONE"

local function GetStatusText()
	if GetCVar("statusText") ~= "1" then return NONE_VALUE end
	local display = GetCVar("statusTextDisplay")
	if display == NUMERIC or display == PERCENT or display == BOTH then
		return display
	end
	return NONE_VALUE
end

-- Exactly what Blizzard's setting does: the display mode first, then whether status text is on.
local function SetStatusText(value)
	SetCVar("statusTextDisplay", value)
	SetCVar("statusText", value == NONE_VALUE and "0" or "1")
end

ns.RegisterOption({
	kind = "dropdown",
	order = 76,
	appliesTo = function(system)
		return IsUnitFrame(system, UNIT_INDICES.Player) or IsUnitFrame(system, UNIT_INDICES.Target)
			or IsUnitFrame(system, UNIT_INDICES.Focus)
	end,
	label = function() return STATUSTEXT_LABEL or L.STATUS_TEXT end,
	get = function() return GetStatusText() end,
	set = function(_, value)
		SetStatusText(value)
		ns.RequestRefresh()
	end,
	choices = function()
		return {
			{ value = NUMERIC, text = STATUS_TEXT_VALUE or L.STATUS_TEXT_VALUE },
			{ value = PERCENT, text = STATUS_TEXT_PERCENT or L.STATUS_TEXT_PERCENT },
			{ value = BOTH, text = STATUS_TEXT_BOTH or L.STATUS_TEXT_BOTH },
			{ value = NONE_VALUE, text = NONE },
		}
	end,
})

-- Class icon portraits -------------------------------------------------------------------------------------------
-- Blizzard's two Interface options (Replace My Player Portrait / Replace Other Players' Portraits). They are CVars
-- that Blizzard's unit frames already watch, so setting one updates every portrait right away. The "other players"
-- option is also shown on the Target of Target and Focus Target movers (Features/ExtraMovers.lua).

local function CVarExists(cvar)
	return GetCVar(cvar) ~= nil
end

local function PortraitOption(order, cvar, label, fallback)
	return {
		kind = "checkbox",
		order = order,
		label = function() return label or fallback end,
		get = function() return GetCVar(cvar) == "1" end,
		set = function(_, value)
			SetCVar(cvar, value and "1" or "0")
			ns.RequestRefresh()
		end,
		available = function() return CVarExists(cvar) end,
	}
end

local myPortrait = PortraitOption(71, "ReplaceMyPlayerPortrait", REPLACE_MY_PLAYER_PORTRAIT, L.CLASS_ICON_MY_PORTRAIT)
local otherPortraits = PortraitOption(72, "ReplaceOtherPlayerPortraits", REPLACE_OTHER_PLAYER_PORTRAITS,
	L.CLASS_ICON_OTHER_PORTRAITS)
ns.OtherPlayerPortraitsOption = otherPortraits

myPortrait.appliesTo = function(system)
	return IsPlayerFrame(system) and myPortrait.available()
end
otherPortraits.appliesTo = function(system)
	return (IsUnitFrame(system, UNIT_INDICES.Target) or IsUnitFrame(system, UNIT_INDICES.Focus))
		and otherPortraits.available()
end
ns.RegisterOption(myPortrait)
ns.RegisterOption(otherPortraits)

-- Keep the rows in step if these settings are changed in Blizzard's options while Edit Mode is open.
local WATCHED_CVARS = {
	statusText = true, statusTextDisplay = true,
	ReplaceMyPlayerPortrait = true, ReplaceOtherPlayerPortraits = true,
}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CVAR_UPDATE")
eventFrame:SetScript("OnEvent", function(_, _, cvar)
	if WATCHED_CVARS[cvar] then
		ns.RequestRefresh()
	end
end)

-- Level badge scale -----------------------------------------------------------------------------------------------
-- The badge is the circle texture, with the level text (and on Target/Focus the skull for high level units)
-- centered on it. All of them are scaled, and the circle's anchor offset is adjusted so it grows around its
-- center. Blizzard places these regions once, when the frame loads, so the change sticks.

local FIELD_LEVEL_SCALE = "levelScale"
local LEVEL_SCALE_MIN, LEVEL_SCALE_MAX, LEVEL_SCALE_STEP = 50, 200, 5

-- The badge regions of a Player, Target or Focus system frame: circle, then the regions centered on it.
local function GetBadge(system)
	local circle, centered
	if IsUnitFrame(system, UNIT_INDICES.Player) then
		local content = PlayerFrame and PlayerFrame.PlayerFrameContent
		local main = content and content.PlayerFrameContentMain
		circle = main and main.LevelBackgroundCircle
		centered = { PlayerLevelText }
	elseif IsUnitFrame(system, UNIT_INDICES.Target) or IsUnitFrame(system, UNIT_INDICES.Focus) then
		local content = system.TargetFrameContent
		local main = content and content.TargetFrameContentMain
		local contextual = content and content.TargetFrameContentContextual
		circle = main and main.LevelBackgroundCircle
		centered = { main and main.LevelText, contextual and contextual.HighLevelTexture }
	end
	if not (circle and centered[1] and circle.SetScale) then return nil end

	-- Only the round badge look, where the level text sits on the circle's center.
	local _, relativeTo = centered[1]:GetPoint(1)
	if relativeTo ~= circle then return nil end
	return circle, centered
end

-- How far a region's center sits from one of its anchor points, as a fraction of its size.
local POINT_TO_CENTER = {
	TOPLEFT = { 0.5, -0.5 }, TOP = { 0, -0.5 }, TOPRIGHT = { -0.5, -0.5 },
	LEFT = { 0.5, 0 }, CENTER = { 0, 0 }, RIGHT = { -0.5, 0 },
	BOTTOMLEFT = { 0.5, 0.5 }, BOTTOM = { 0, 0.5 }, BOTTOMRIGHT = { -0.5, 0.5 },
}

local originalAnchor = setmetatable({}, { __mode = "k" }) -- [circle] = { point, relativeTo, relativePoint, x, y }
local appliedScale = setmetatable({}, { __mode = "k" })   -- [circle] = scale EditTime last applied

local function ScaleBadge(circle, centered, scale)
	local anchor = originalAnchor[circle]
	if not anchor then
		if circle:GetNumPoints() ~= 1 then return end
		anchor = { circle:GetPoint(1) }
		if not POINT_TO_CENTER[anchor[1]] then return end
		originalAnchor[circle] = anchor
	end

	-- Anchor offsets count in the region's own scale. Keep the center where it is at scale 1:
	-- offset' * scale + toCenter * scale = offset + toCenter.
	local point, relativeTo, relativePoint, x, y = anchor[1], anchor[2], anchor[3], anchor[4], anchor[5]
	local toCenter = POINT_TO_CENTER[point]
	local width, height = circle:GetSize()
	local cx, cy = toCenter[1] * width, toCenter[2] * height

	circle:SetScale(scale)
	circle:SetPoint(point, relativeTo, relativePoint, (x + cx) / scale - cx, (y + cy) / scale - cy)
	for _, region in ipairs(centered) do
		if region and region.SetScale then region:SetScale(scale) end
	end
	appliedScale[circle] = scale
end

local function GetLevelScale(system)
	local value = Layouts.Get(Systems.KeyFor(system), FIELD_LEVEL_SCALE)
	return type(value) == "number" and value or 100
end

local function RefreshLevelBadges()
	for _, system in ipairs(Systems.GetRegistered()) do
		local circle, centered = GetBadge(system)
		if circle then
			local scale = GetLevelScale(system) / 100
			if (appliedScale[circle] or 1) ~= scale then
				Combat.Run(circle, function() ScaleBadge(circle, centered, scale) end, circle:GetParent())
			end
		end
	end
end

ns.RegisterRefresher(RefreshLevelBadges)

ns.RegisterOption({
	kind = "slider",
	order = 73,
	appliesTo = function(system)
		return GetBadge(system) ~= nil
	end,
	label = function() return L.LEVEL_SCALE end,
	range = function() return LEVEL_SCALE_MIN, LEVEL_SCALE_MAX, LEVEL_SCALE_STEP end,
	formatValue = function(value) return string.format("%d%%", math.floor(value + 0.5)) end,
	get = GetLevelScale,
	set = function(system, value)
		value = math.floor(value + 0.5)
		Layouts.Set(Systems.KeyFor(system), FIELD_LEVEL_SCALE, value ~= 100 and value or nil)
		ns.RequestRefresh()
	end,
})
