-- Per-Edit-Mode-layout settings storage.
--
-- Blizzard's layout data is never written to (that would taint C_EditMode.SaveLayouts). EditTime keeps its
-- own table keyed by layout identity and follows Blizzard's layout lifecycle (switch, rename, copy, delete)
-- through hooksecurefunc only.
--
-- Settings save immediately. Blizzard reverts every unsaved change when Edit Mode closes
-- (ExitEditMode -> RevertAllChanges), and the only way to flag "unsaved changes" is SetHasActiveChanges, which
-- would taint the save path. So EditTime settings behave like the Edit Mode account settings checkboxes:
-- they apply and persist at once.
local _, ns = ...

local Layouts = {}
ns.Layouts = Layouts

local hooksecurefunc, next, type = hooksecurefunc, next, type

local PRESET = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Preset or 0
local ACCOUNT = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account or 1
local CHARACTER = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character or 2

local charPrefix -- "char:Name-Realm:"; resolved lazily because realm info isn't ready at file load

local function GetCharPrefix()
	if not charPrefix then
		local name, realm = UnitFullName("player")
		realm = realm or GetNormalizedRealmName() or ""
		charPrefix = "char:" .. (name or "?") .. "-" .. realm .. ":"
	end
	return charPrefix
end

-- Builds the storage key for a Blizzard layoutInfo table. presetIndex is only needed for presets.
local function KeyForLayoutInfo(layoutInfo, presetIndex)
	if type(layoutInfo) ~= "table" then return nil end
	local layoutType = layoutInfo.layoutType
	if layoutType == PRESET then
		return presetIndex and ("preset:" .. presetIndex) or nil
	elseif layoutType == CHARACTER then
		return GetCharPrefix() .. tostring(layoutInfo.layoutName)
	elseif layoutType == ACCOUNT then
		return "account:" .. tostring(layoutInfo.layoutName)
	end
	return nil
end

function Layouts.GetActiveKey()
	local manager = EditModeManagerFrame
	if not (manager and manager.GetActiveLayoutInfo) then return nil end
	local info = manager:GetActiveLayoutInfo()
	if not info then return nil end

	local presetIndex
	if info.layoutType == PRESET then
		local layouts = C_EditMode.GetLayouts()
		presetIndex = layouts and layouts.activeLayout
	end
	return KeyForLayoutInfo(info, presetIndex)
end

local function GetLayoutTable(create)
	local key = Layouts.GetActiveKey()
	if not key then return nil end
	local all = ns.db.layouts
	local t = all[key]
	if not t and create then
		t = {}
		all[key] = t
	end
	return t
end

-- Returns the stored value of a field for a system in the active layout, or nil.
function Layouts.Get(systemKey, field)
	local t = GetLayoutTable(false)
	local entry = t and t[systemKey]
	return entry and entry[field]
end

-- Stores (or clears, with nil) a value for a system in the active layout.
function Layouts.Set(systemKey, field, value)
	local t = GetLayoutTable(value ~= nil)
	if not t then return end
	local entry = t[systemKey]
	if not entry then
		if value == nil then return end
		entry = {}
		t[systemKey] = entry
	end
	entry[field] = value

	if next(entry) == nil then
		t[systemKey] = nil
	end
	if next(t) == nil then
		local key = Layouts.GetActiveKey()
		if key then ns.db.layouts[key] = nil end
	end
end

-- Every system entry of the active layout: iterate with pairs(Layouts.GetAll()).
local EMPTY = {}
function Layouts.GetAll()
	return GetLayoutTable(false) or EMPTY
end

-- Lifecycle tracking -----------------------------------------------------------------------------------------------

local pendingRenameKey, pendingDeleteKey, pendingCopySourceKey

local function OnShowRename(_, _, layoutInfo)
	pendingRenameKey = KeyForLayoutInfo(layoutInfo)
end

local function OnRenamed(_, layoutIndex, layoutName)
	local oldKey = pendingRenameKey
	pendingRenameKey = nil
	if not oldKey then return end

	local layouts = EditModeManagerFrame:GetLayouts()
	local info = layouts and layouts[layoutIndex]
	if not (info and info.layoutName == layoutName) then return end -- rename was rejected

	local newKey = KeyForLayoutInfo(info)
	local all = ns.db.layouts
	if newKey and newKey ~= oldKey and all[oldKey] then
		all[newKey] = all[oldKey]
		all[oldKey] = nil
	end
end

local function OnShowDelete(_, _, layoutInfo)
	pendingDeleteKey = KeyForLayoutInfo(layoutInfo)
end

local function OnDeleted()
	local key = pendingDeleteKey
	pendingDeleteKey = nil
	if key then
		ns.db.layouts[key] = nil
	end
end

local function OnShowNewLayout(_, sourceLayoutInfo)
	if sourceLayoutInfo then
		-- Copying a specific layout from the dropdown. Presets have no stable name, so find their index.
		local presetIndex
		if sourceLayoutInfo.layoutType == PRESET then
			local layouts = EditModeManagerFrame:GetLayouts()
			for index, info in ipairs(layouts or EMPTY) do
				if info == sourceLayoutInfo then
					presetIndex = index
					break
				end
			end
		end
		pendingCopySourceKey = KeyForLayoutInfo(sourceLayoutInfo, presetIndex)
	else
		-- "New layout" / saving a preset: Blizzard copies the active layout.
		pendingCopySourceKey = Layouts.GetActiveKey()
	end
end

local function OnMadeNewLayout(_, newLayoutInfo, layoutType, layoutName, isLayoutImported)
	local sourceKey = pendingCopySourceKey
	pendingCopySourceKey = nil
	if isLayoutImported or not sourceKey then return end

	local newKey = KeyForLayoutInfo({ layoutType = layoutType, layoutName = layoutName })
	local source = ns.db.layouts[sourceKey]
	if newKey and source and newKey ~= sourceKey then
		ns.db.layouts[newKey] = CopyTable(source)
	end
end

ns.OnReady(function()
	local manager = EditModeManagerFrame
	if not manager then return end

	hooksecurefunc(manager, "ShowRenameLayoutDialog", OnShowRename)
	hooksecurefunc(manager, "RenameLayout", OnRenamed)
	hooksecurefunc(manager, "ShowDeleteLayoutDialog", OnShowDelete)
	hooksecurefunc(manager, "DeleteLayout", OnDeleted)
	hooksecurefunc(manager, "ShowNewLayoutDialog", OnShowNewLayout)
	hooksecurefunc(manager, "MakeNewLayout", OnMadeNewLayout)

	-- Fires after Blizzard has applied a layout to every system (login, layout switch, spec switch, revert).
	hooksecurefunc(manager, "UpdateLayoutInfo", function()
		ns.RequestRefresh()
	end)
end)
