-- Per-frame options for the raid-style Party Frames and the Raid Frames:
--   * Hide DPS Role Icons: removes the role icon from damage dealers.
--   * Tank & Healer Power Bars Only: removes the power bar from everyone who isn't a tank or healer, and lets the
--     health bar fill the space.
--
-- Both run right after Blizzard updates a frame (hooks on its own update functions) and only change the frame's
-- child regions. Blizzard's option tables are never written, and neither is the power bar height it hands to the
-- private aura system, since that is secure. Because of that, auras keep the position they'd have above a power
-- bar.
--
-- Roles of group members are readable by addons, but they are checked for secret values anyway: if a role is
-- ever secret, the frame is left exactly as Blizzard drew it.
local _, ns = ...

local Systems, Layouts, Combat = ns.Systems, ns.Layouts, ns.Combat
local L = ns.L

local FIELD_ROLE, FIELD_POWER = "hideDamagerRole", "tankHealerPower"

local hooksecurefunc, ipairs, type = hooksecurefunc, ipairs, type
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local issecretvalue = issecretvalue or function() return false end

local GROUP_TYPES = CompactRaidGroupTypeEnum or {}

local powerHidden = setmetatable({}, { __mode = "k" }) -- [frame] = true while EditTime hides its power bar
local roleHidden = setmetatable({}, { __mode = "k" })  -- [frame] = true while EditTime hides its role icon

-- The Edit Mode system whose settings apply to a compact unit frame, by the frame's group type.
local function SystemFor(frame)
	local groupType = frame.groupType
	local test
	if groupType == GROUP_TYPES.Party then
		test = Systems.IsPartyFrames
	elseif groupType == GROUP_TYPES.Raid then
		test = Systems.IsRaidFrames
	else
		return nil -- arena and others aren't touched
	end
	for _, system in ipairs(Systems.GetRegistered()) do
		if test(system) then return system end
	end
	return nil
end

local function IsEnabled(frame, field)
	local system = SystemFor(frame)
	return system ~= nil and Layouts.Get(Systems.KeyFor(system), field) == true
end

-- The unit's assigned role, or nil if it can't be read.
local function GetRole(frame)
	local unit = frame.unit
	if type(unit) ~= "string" then return nil end
	local role = UnitGroupRolesAssigned(unit)
	if issecretvalue(role) then return nil end
	return role
end

-- Power bars ----------------------------------------------------------------------------------------------------------

-- What DefaultCompactUnitFrameSetup does with the power bar shown vs. hidden: the health bar ends 1 pixel above
-- the frame's bottom, or 1 pixel above the 8-pixel power bar.
local function SetPowerBarHidden(frame, hide)
	local powerBar, healthBar = frame.powerBar, frame.healthBar
	if hide then
		powerBar:Hide()
		healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
		powerHidden[frame] = true
	else
		powerBar:Show()
		healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 9)
		powerHidden[frame] = nil
	end
end

local function UpdatePower(frame)
	if not (frame.powerBar and frame.healthBar) then return end

	-- Only a known damage role loses its bar. Unassigned roles (open world groups) keep it, so a healer who
	-- hasn't picked a role still sees their mana.
	local hide = IsEnabled(frame, FIELD_POWER) and GetRole(frame) == "DAMAGER"

	if hide and frame.powerBar:IsShown() then
		-- The bars are plain children of the secure button: allowed in combat unless they're protected.
		Combat.Run(frame.powerBar, function() SetPowerBarHidden(frame, true) end, frame.healthBar)
	elseif not hide and powerHidden[frame] then
		Combat.Run(frame.powerBar, function() SetPowerBarHidden(frame, false) end, frame.healthBar)
	end
end

-- Blizzard just set the frame up from its own options: whatever it decided is the truth now.
local function OnSetup(frame)
	powerHidden[frame] = nil
	UpdatePower(frame)
end

-- Role icons ----------------------------------------------------------------------------------------------------------

local function UpdateRole(frame)
	local icon = frame.roleIcon
	if not icon then return end

	if IsEnabled(frame, FIELD_ROLE) and GetRole(frame) == "DAMAGER" then
		icon:Hide()
		icon:SetWidth(1) -- like Blizzard's hidden icon, so the name doesn't leave room for it
		roleHidden[frame] = true
	elseif roleHidden[frame] then
		roleHidden[frame] = nil
		-- Blizzard's own update redraws it; its role icon code runs as a secure delegate.
		CompactUnitFrame_UpdateRoleIcon(frame)
	end
end

local function OnRoleIconUpdated(frame)
	roleHidden[frame] = nil -- Blizzard redrew it
	UpdateRole(frame)
end

-- Every compact frame of the party and raid frames ------------------------------------------------------------------

local function ForEachFrame(func)
	local seen = {}
	local function Visit(frame)
		if type(frame) == "table" and frame.healthBar and not seen[frame] then
			seen[frame] = true
			func(frame)
		end
	end
	local function VisitGroup(group)
		if group and type(group.memberUnitFrames) == "table" then
			for _, frame in ipairs(group.memberUnitFrames) do Visit(frame) end
		end
	end

	VisitGroup(CompactPartyFrame)
	for i = 1, MAX_RAID_GROUPS or 8 do
		VisitGroup(_G["CompactRaidGroup" .. i])
	end
	local container = CompactRaidFrameContainer
	if container and type(container.flowFrames) == "table" then
		for _, object in ipairs(container.flowFrames) do Visit(object) end
	end
end

local function Refresh()
	ForEachFrame(function(frame)
		if frame:IsShown() then
			UpdatePower(frame)
			UpdateRole(frame)
		end
	end)
end

ns.RegisterRefresher(Refresh)

-- Options -------------------------------------------------------------------------------------------------------------

local function PartyNeedsRaidStyle(system)
	if Systems.IsPartyFrames(system) and not Systems.UsesRaidStylePartyFrames(system) then
		return L.RAID_STYLE_ONLY_TOOLTIP
	end
	return nil
end

local function AppliesToGroupFrames(system)
	return Systems.IsPartyFrames(system) or Systems.IsRaidFrames(system)
end

local function Option(order, field, label)
	ns.RegisterOption({
		kind = "checkbox",
		order = order,
		appliesTo = AppliesToGroupFrames,
		label = function() return label end,
		disabledReason = PartyNeedsRaidStyle,
		get = function(system)
			return Layouts.Get(Systems.KeyFor(system), field) == true
		end,
		set = function(system, value)
			Layouts.Set(Systems.KeyFor(system), field, value or nil)
			ns.RequestRefresh()
		end,
	})
end

Option(70, FIELD_ROLE, L.HIDE_DPS_ROLE_ICONS)
Option(71, FIELD_POWER, L.TANK_HEALER_POWER_BARS)

-- Hooks ---------------------------------------------------------------------------------------------------------------

ns.OnReady(function()
	-- DefaultCompactUnitFrameSetup decides the power bar on every full update (it reads the unit's role).
	if type(DefaultCompactUnitFrameSetup) == "function" then
		hooksecurefunc("DefaultCompactUnitFrameSetup", OnSetup)
	end
	if type(CompactUnitFrame_UpdateRoleIcon) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateRoleIcon", OnRoleIconUpdated)
	end
end)
