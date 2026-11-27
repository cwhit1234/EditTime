-- Health Bar Color for the Player, Target, Focus, Target of Target and Focus Target frames: Default (Blizzard's
-- green bar) or Class / Reaction (players in their class color, everyone else by how they feel about you).
-- Each frame has its own setting, saved per layout.
--
-- These health bars have lockColor set, so Blizzard never colors them itself. EditTime desaturates the bar
-- texture and tints it after every UnitFrameHealthBar_Update, which Blizzard calls whenever the unit or its
-- health changes. Color and desaturation are plain widget calls that are allowed in combat, so the color keeps
-- up with target changes during a fight. Default puts the texture back exactly as Blizzard drew it.
local _, ns = ...

local Systems, Layouts, Movers = ns.Systems, ns.Layouts, ns.Movers
local L = ns.L

local FIELD = "healthColor"
local DEFAULT, CLASS = "DEFAULT", "CLASS"

local SYS = Enum.EditModeSystem or {}
local UNIT_INDICES = Enum.EditModeUnitFrameSystemIndices or {}

local ipairs, type = ipairs, type
local UnitExists, UnitIsConnected, UnitIsPlayer, UnitClass = UnitExists, UnitIsConnected, UnitIsPlayer, UnitClass
local UnitIsTapDenied, UnitSelectionColor = UnitIsTapDenied, UnitSelectionColor
local UnitTreatAsPlayerForDisplay = UnitTreatAsPlayerForDisplay

-- A value is only used when it's a plain (non secret) value.
local function Plain(value)
	if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
	return value
end

local function IsColorableSystem(system)
	if system.system ~= SYS.UnitFrame then return false end
	local index = system.systemIndex
	return index ~= nil and (index == UNIT_INDICES.Player or index == UNIT_INDICES.Target or index == UNIT_INDICES.Focus)
end

-- Colors -------------------------------------------------------------------------------------------------------------

-- The same greys Blizzard's nameplates and raid frames use.
local GREY, TAPPED = 0.5, 0.9

local function ClassColor(unit)
	local _, classToken = UnitClass(unit)
	classToken = Plain(classToken)
	if type(classToken) ~= "string" then return nil end
	local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classToken)
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken])
	if color then return color.r, color.g, color.b end
	return nil
end

-- Returns r, g, b for the unit, or nil to leave the bar alone.
local function UnitHealthColor(unit)
	if type(unit) ~= "string" or Plain(UnitExists(unit)) ~= true then return nil end

	if Plain(UnitIsConnected(unit)) == false then
		return GREY, GREY, GREY
	end

	local isPlayer = Plain(UnitIsPlayer(unit)) == true
		or (UnitTreatAsPlayerForDisplay and Plain(UnitTreatAsPlayerForDisplay(unit)) == true)
	if isPlayer then
		local r, g, b = ClassColor(unit)
		if r then return r, g, b end
	end

	if Plain(UnitIsTapDenied(unit)) == true then
		return TAPPED, TAPPED, TAPPED
	end

	-- The selection color, as Blizzard's nameplates and the Target Frame's name background use.
	local r, g, b = UnitSelectionColor(unit)
	if Plain(r) and Plain(g) and Plain(b) then return r, g, b end
	return nil
end

-- Bars ---------------------------------------------------------------------------------------------------------------

local classBars = setmetatable({}, { __mode = "k" }) -- [health bar] = true while set to Class / Reaction
local tinted = setmetatable({}, { __mode = "k" })    -- [health bar] = true while EditTime has changed its look

local function Tint(bar)
	local r, g, b = UnitHealthColor(bar.unit)
	if not r then return end
	bar:SetStatusBarDesaturated(true)
	bar:SetStatusBarColor(r, g, b)
	tinted[bar] = true
end

local function Untint(bar)
	if not tinted[bar] then return end
	bar:SetStatusBarDesaturated(false)
	bar:SetStatusBarColor(1, 1, 1)
	tinted[bar] = nil
end

local function OnHealthBarUpdated(bar)
	if bar and classBars[bar] then
		Tint(bar)
	end
end

-- Movers (Target of Target, Focus Target) attach their health bar here: list of { def, getBar }.
local moverBars = {}

local function ApplyBar(bar, mode)
	if not (bar and bar.SetStatusBarDesaturated) then return end
	if mode == CLASS then
		classBars[bar] = true
		Tint(bar)
	else
		classBars[bar] = nil
		Untint(bar)
	end
end

local function Refresh()
	for _, system in ipairs(Systems.GetRegistered()) do
		if IsColorableSystem(system) then
			ApplyBar(system.healthbar, Layouts.Get(Systems.KeyFor(system), FIELD))
		end
	end
	for _, entry in ipairs(moverBars) do
		ApplyBar(entry.getBar(), Movers.Get(entry.def, FIELD))
	end
end

ns.RegisterRefresher(Refresh)

ns.OnReady(function()
	if type(UnitFrameHealthBar_Update) == "function" then
		hooksecurefunc("UnitFrameHealthBar_Update", OnHealthBarUpdated)
	end
end)

-- Options ------------------------------------------------------------------------------------------------------------

local function Choices()
	return {
		{ value = DEFAULT, text = _G.DEFAULT or L.HEALTH_COLOR_DEFAULT },
		{ value = CLASS, text = L.HEALTH_COLOR_CLASS },
	}
end

local function Label()
	return L.HEALTH_BAR_COLOR
end

ns.RegisterOption({
	kind = "dropdown",
	order = 70,
	appliesTo = function(system)
		return IsColorableSystem(system) and system.healthbar ~= nil
	end,
	label = Label,
	get = function(system)
		return Layouts.Get(Systems.KeyFor(system), FIELD) == CLASS and CLASS or DEFAULT
	end,
	set = function(system, value)
		Layouts.Set(Systems.KeyFor(system), FIELD, value == CLASS and CLASS or nil)
		ns.RequestRefresh()
	end,
	choices = Choices,
})

-- The same dropdown for a mover definition (Features/ExtraMovers.lua). getBar() returns the frame's health bar.
function ns.HealthBarColorMoverOption(def, getBar)
	moverBars[#moverBars + 1] = { def = def, getBar = getBar }
	return {
		kind = "dropdown",
		label = Label,
		get = function()
			return Movers.Get(def, FIELD) == CLASS and CLASS or DEFAULT
		end,
		set = function(_, value)
			Movers.Set(def, FIELD, value == CLASS and CLASS or nil)
			ns.RequestRefresh()
		end,
		choices = Choices,
	}
end
