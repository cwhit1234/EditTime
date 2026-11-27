-- Registry of Edit Mode systems and what EditTime adds to each.
--
-- Everything here only READS Blizzard state (fields, read-only getters) and changes frames through widget API
-- calls (SetWidth, SetScale, SetAlpha, EnableMouse). It never calls Blizzard Lua methods that write shared state:
-- writes from addon code would taint the Edit Mode and managed-frame layout paths.
local _, ns = ...

local Systems = {}
ns.Systems = Systems

local ipairs, tostring, type, sort, floor = ipairs, tostring, type, table.sort, math.floor

local SYS = Enum.EditModeSystem or {}

-- Keys ---------------------------------------------------------------------------------------------------------------

function Systems.KeyFor(frame)
	return tostring(frame.system) .. ":" .. tostring(frame.systemIndex or "-")
end

local EMPTY = {}
function Systems.GetRegistered()
	local manager = EditModeManagerFrame
	return manager and manager.registeredSystemFrames or EMPTY
end

function Systems.FrameFor(key)
	if type(key) ~= "string" then return nil end
	for _, frame in ipairs(Systems.GetRegistered()) do
		if Systems.KeyFor(frame) == key then
			return frame
		end
	end
	return nil
end

-- Same result as EditModeSystemMixin:GetSystemName, without calling it: one override (the XP bar) writes
-- fields on the frame when called.
function Systems.GetName(frame)
	local name = frame.systemNameString
	if type(name) ~= "string" then
		return tostring(frame:GetDebugName() or "?")
	end
	if frame.addSystemIndexToName and frame.systemIndex then
		return name:format(frame.systemIndex)
	end
	return name
end

-- Sorted list of { key, name, frame } for every system that is part of the active layout.
function Systems.List()
	local list = {}
	for _, frame in ipairs(Systems.GetRegistered()) do
		if frame.systemInfo ~= nil then -- IsInitialized(), i.e. present in the active layout
			list[#list + 1] = { key = Systems.KeyFor(frame), name = Systems.GetName(frame), frame = frame }
		end
	end
	sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- Size sources -------------------------------------------------------------------------------------------------------
-- Every adapter has:
--   blockedReason(frame) -> nil when matching may be used now, else a reason shown as a tooltip
--   hooks                -> Blizzard methods after which the size must be re-applied
--   mode                 -> "stretch" or "scale"
--
-- "stretch" adapters resize each dimension on its own:
--   width/height = { apply(frame, size), restore(frame) }; a missing dimension isn't offered.
--   A dimension may also have custom = { min, max, step, natural(frame) }: a slider that sets the size directly
--   when nothing is matched. natural(frame) is the size Blizzard gives the frame, shown when the slider is unset.
--
-- "scale" adapters (icon-based frames) scale uniformly to reach the target size in one dimension:
--   naturalScale(frame) -> the scale Blizzard would use; restored when matching is off

local function BlockedInDefaultPosition(frame)
	if frame.IsInDefaultPosition and frame:IsInDefaultPosition() then
		return ns.L.MATCH_DEFAULT_POSITION_TOOLTIP
	end
	return nil
end

local function BlockedIfManagedInDefaultPosition(frame)
	if frame.isManagedFrame then
		return BlockedInDefaultPosition(frame)
	end
	return nil
end

local function ReadSetting(frame, enumTable, name, useRawValue)
	local setting = enumTable and enumTable[name]
	if setting ~= nil and frame:HasSetting(setting) then
		return frame:GetSettingValue(setting, useRawValue)
	end
	return nil
end

local function SetWidth(frame, width) frame:SetWidth(width) end
local function SetHeight(frame, height) frame:SetHeight(height) end

-- A dimension whose natural size is an Edit Mode setting that Blizzard applies with SetWidth/SetSize.
local function SettingDimension(setter, getSettingSize)
	return {
		apply = setter,
		restore = function(frame)
			local size = getSettingSize(frame)
			if size and size > 0 then
				setter(frame, size)
			end
		end,
	}
end

-- Cast Bar

-- The widths CastingBarMixin:SetLook gives each look.
local function CastBarNaturalWidth(frame)
	local look = frame.look
	if look == "UNITFRAME" then
		return 150
	elseif look == "CLASSIC" then
		return frame.classicStyleCastBar and 195 or 208
	end
	return 208
end

local castBar = {
	mode = "stretch",
	blockedReason = function(frame)
		if frame.attachedToPlayerFrame then
			return ns.L.MATCH_LOCKED_TOOLTIP
		end
		return BlockedInDefaultPosition(frame)
	end,
	width = {
		apply = SetWidth,
		restore = function(frame)
			frame:SetWidth(CastBarNaturalWidth(frame))
		end,
		-- Blizzard only offers Bar Size (a scale) for the cast bar. 148 puts the usual 208 width on a 10 pixel step.
		custom = { min = 148, max = 828, step = 10, natural = CastBarNaturalWidth },
	},
	hooks = { "SetLook", "UpdateSystem", "ApplySystemAnchor", "UpdateSystemSettingBarSize" },
}

-- Personal Resource Display
local PRD_PARTS = { "HealthBarsContainer", "PowerBar", "AlternatePowerBar", "ClassFrameContainer" }

local function SetPRDWidth(frame, width)
	frame:SetWidth(width)
	for _, key in ipairs(PRD_PARTS) do
		local part = frame[key]
		if part and part.SetWidth then
			part:SetWidth(width)
		end
	end
end

local personalResourceDisplay = {
	mode = "stretch",
	blockedReason = BlockedIfManagedInDefaultPosition,
	width = {
		apply = SetPRDWidth,
		restore = function(frame)
			-- PersonalResourceDisplayMixin:UpdateBarWidth
			local base = frame.defaultBarWidth
			if base then
				SetPRDWidth(frame, base * (frame.barWidthPercent or 100) / 100)
			end
		end,
	},
	hooks = { "UpdateBarWidth", "UpdateSystem" },
}

-- Experience / Status bars
local function SetStatusBarWidth(frame, width)
	frame:SetWidth(width)

	-- StatusTrackingBarContainerMixin:ResizeContainerBars, reproduced so no Blizzard table gets written.
	local adjust = STATUS_BAR_SIZE_ADJUSTMENT or 3
	if type(frame.bars) == "table" then
		for _, bar in ipairs(frame.bars) do
			bar:SetWidth(width - adjust)
			if bar.StatusBar then
				bar.StatusBar:SetWidth(width - adjust)
			end
		end
	end

	-- StatusTrackingBarContainerMixin:UpdateDividers: move the existing dividers, keeping their order.
	local pool = frame.HorizontalDividersPool
	if pool and pool.EnumerateActive then
		local dividers = {}
		for divider in pool:EnumerateActive() do
			local _, _, _, x = divider:GetPoint(1)
			dividers[#dividers + 1] = { frame = divider, x = x or 0 }
		end
		sort(dividers, function(a, b) return a.x < b.x end)
		local segment = width / (#dividers + 1)
		for i, entry in ipairs(dividers) do
			entry.frame:ClearAllPoints()
			PixelUtil.SetPoint(entry.frame, "LEFT", frame, "LEFT", segment * i, 0)
		end
	end
end

local statusTrackingBar = {
	mode = "stretch",
	blockedReason = BlockedInDefaultPosition,
	width = {
		apply = SetStatusBarWidth,
		restore = function(frame)
			local size = ReadSetting(frame, Enum.EditModeStatusTrackingBarSetting, "Size") or 100
			SetStatusBarWidth(frame, frame:GetExpectedWidth() * size / 100)
		end,
	},
	hooks = { "UpdateSystem", "UpdateSystemSetting", "ApplySystemAnchor", "ResizeContainerBars" },
}

-- Swing Timer bars (EditModeSwingTimerSystemMixin:UpdateSystemSettingWidth/Height)
local swingTimer = {
	mode = "stretch",
	blockedReason = BlockedIfManagedInDefaultPosition,
	width = SettingDimension(SetWidth, function(frame)
		return ReadSetting(frame, Enum.EditModeSwingTimerSetting, "Width")
	end),
	height = SettingDimension(SetHeight, function(frame)
		return ReadSetting(frame, Enum.EditModeSwingTimerSetting, "Height")
	end),
	hooks = { "UpdateSystemSettingWidth", "UpdateSystemSettingHeight", "UpdateSystem", "ApplySystemAnchor" },
}

-- Damage Meter (EditModeDamageMeterSystemMixin:UpdateSystemSettingFrameWidth/Height)
local damageMeter = {
	mode = "stretch",
	blockedReason = BlockedIfManagedInDefaultPosition,
	width = SettingDimension(SetWidth, function(frame)
		return ReadSetting(frame, Enum.EditModeDamageMeterSetting, "FrameWidth")
	end),
	height = SettingDimension(SetHeight, function(frame)
		return ReadSetting(frame, Enum.EditModeDamageMeterSetting, "FrameHeight")
	end),
	hooks = { "UpdateSystemSettingFrameWidth", "UpdateSystemSettingFrameHeight", "UpdateSystem" },
}

-- Chat Frame (EditModeChatFrameSystemMixin:UpdateSystemSettingWidth/Height; stored as hundreds + tens-and-ones)
local function ChatSetting(frame, hundredsName, tensName)
	local hundreds = ReadSetting(frame, Enum.EditModeChatFrameSetting, hundredsName, true)
	local tensAndOnes = ReadSetting(frame, Enum.EditModeChatFrameSetting, tensName, true)
	if hundreds and tensAndOnes then
		return floor(hundreds * 100 + tensAndOnes)
	end
	return nil
end

local chatFrame = {
	mode = "stretch",
	blockedReason = BlockedIfManagedInDefaultPosition,
	width = SettingDimension(SetWidth, function(frame)
		return ChatSetting(frame, "WidthHundreds", "WidthTensAndOnes")
	end),
	height = SettingDimension(SetHeight, function(frame)
		return ChatSetting(frame, "HeightHundreds", "HeightTensAndOnes")
	end),
	hooks = { "UpdateSystemSettingWidth", "UpdateSystemSettingHeight", "UpdateSystem" },
}

-- Bags Bar: Blizzard scales the system frame itself (EditModeBagsSystemMixin:UpdateSystemSettingSize).
local bagsBar = {
	mode = "scale",
	blockedReason = BlockedInDefaultPosition,
	naturalScale = function(frame)
		return (ReadSetting(frame, Enum.EditModeBagsSetting, "Size") or 100) / 100
	end,
	hooks = { "UpdateSystem", "UpdateSystemSettingSize", "ApplySystemAnchor", "Layout" },
}

-- Micro Menu: Blizzard scales the inner MicroMenu; the system frame (MicroMenuContainer) stays at 1.
local microMenu = {
	mode = "scale",
	blockedReason = BlockedInDefaultPosition,
	naturalScale = function()
		return 1
	end,
	hooks = { "UpdateSystem", "ApplySystemAnchor", "Layout" },
}

local SIZE_ADAPTERS = {}
if SYS.CastBar then SIZE_ADAPTERS[SYS.CastBar] = castBar end
if SYS.PersonalResourceDisplay then SIZE_ADAPTERS[SYS.PersonalResourceDisplay] = personalResourceDisplay end
if SYS.StatusTrackingBar then SIZE_ADAPTERS[SYS.StatusTrackingBar] = statusTrackingBar end
if SYS.SwingTimer then SIZE_ADAPTERS[SYS.SwingTimer] = swingTimer end
if SYS.DamageMeter then SIZE_ADAPTERS[SYS.DamageMeter] = damageMeter end
if SYS.ChatFrame then SIZE_ADAPTERS[SYS.ChatFrame] = chatFrame end
if SYS.Bags then SIZE_ADAPTERS[SYS.Bags] = bagsBar end
if SYS.MicroMenu then SIZE_ADAPTERS[SYS.MicroMenu] = microMenu end

function Systems.GetSizeAdapter(frame)
	-- Only the real player cast bar: other frames share the CastBar system id in some flavors.
	if frame.system == SYS.CastBar and frame ~= PlayerCastingBarFrame then
		return nil
	end
	return SIZE_ADAPTERS[frame.system]
end

-- dimension: "width" or "height"
function Systems.SupportsDimension(adapter, dimension)
	if not adapter then return false end
	return adapter.mode == "scale" or adapter[dimension] ~= nil
end

-- Visibility ---------------------------------------------------------------------------------------------------------
-- fadeObjects(frame) -> the frames/regions whose alpha EditTime controls. The status bar containers run their own
--                       alpha fade animations, so their children are faded instead of the container.
-- reapplyHooks       -> Blizzard methods after which the fade must be recomputed (new children, reparenting).
-- extraHooks()       -> optional { object, method } pairs on other frames, for the same purpose.

local function Self(frame)
	return { frame }
end

local function StatusBarChildren(frame)
	local objects = { frame:GetChildren() }
	for _, region in ipairs({ frame:GetRegions() }) do
		objects[#objects + 1] = region
	end
	return objects
end

local VISIBILITY_ADAPTERS = {}
if SYS.Minimap then
	VISIBILITY_ADAPTERS[SYS.Minimap] = { fadeObjects = Self, reapplyHooks = { "Layout" } }
end
if SYS.ObjectiveTracker then
	VISIBILITY_ADAPTERS[SYS.ObjectiveTracker] = { fadeObjects = Self, reapplyHooks = {} }
end
if SYS.StatusTrackingBar then
	VISIBILITY_ADAPTERS[SYS.StatusTrackingBar] = { fadeObjects = StatusBarChildren, reapplyHooks = { "UpdateDividers", "UpdateShownState" } }
end
if SYS.Bags then
	VISIBILITY_ADAPTERS[SYS.Bags] = { fadeObjects = Self, reapplyHooks = { "Layout" } }
end
if SYS.MicroMenu then
	VISIBILITY_ADAPTERS[SYS.MicroMenu] = {
		fadeObjects = Self,
		reapplyHooks = { "Layout" },
		-- Vehicles and pet battles move MicroMenu onto their own bar (and back). It must not stay faded or
		-- unclickable there.
		extraHooks = function()
			return MicroMenu and { { MicroMenu, "SetParent" } } or EMPTY
		end,
	}
end

function Systems.GetVisibilityAdapter(frame)
	return VISIBILITY_ADAPTERS[frame.system]
end

-- Group frames -------------------------------------------------------------------------------------------------------

local UNIT_INDICES = Enum.EditModeUnitFrameSystemIndices or {}

function Systems.IsPartyFrames(frame)
	return frame.system == SYS.UnitFrame and UNIT_INDICES.Party ~= nil and frame.systemIndex == UNIT_INDICES.Party
end

function Systems.IsRaidFrames(frame)
	return frame.system == SYS.UnitFrame and UNIT_INDICES.Raid ~= nil and frame.systemIndex == UNIT_INDICES.Raid
end

-- The Party Frames system frame shows the player only in raid style (CompactPartyFrame).
function Systems.UsesRaidStylePartyFrames(frame)
	local setting = Enum.EditModeUnitFrameSetting and Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames
	return setting ~= nil and frame:HasSetting(setting) and frame:GetSettingValueBool(setting)
end

function Systems.BlockedIfManagedInDefaultPosition(frame)
	return BlockedIfManagedInDefaultPosition(frame)
end
