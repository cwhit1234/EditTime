-- EditTime's settings, shown as a panel docked to Blizzard's Edit Mode system settings dialog.
--
-- Nothing is added to EditModeSystemSettingsDialog itself. Its layout, pools and setting callbacks stay
-- untouched. The panel copies the dialog's look (DialogBorderTranslucentTemplate plus the rows from UI/Rows.lua)
-- and follows it around.
--
-- Rows come from ns.RegisterOption(option): the option fields of UI/Rows.lua, plus
--   order           sort position in the panel
--   appliesTo(sys)  true if the row is shown for this Edit Mode system frame
local _, ns = ...

local hooksecurefunc, ipairs = hooksecurefunc, ipairs

local Panel = {}
ns.SettingsPanel = Panel

local frame          -- the panel
local rows           -- Rows set
local attachedSystem -- the Edit Mode system frame currently shown in Blizzard's dialog

local function Place()
	local dialog = EditModeSystemSettingsDialog
	if not (frame:IsShown() and dialog:IsShown()) then return end

	-- Below the dialog, as if part of it. Above it instead when the dialog sits too low for the panel to fit.
	frame:ClearAllPoints()
	frame:SetPoint("TOP", dialog, "BOTTOM", 0, 0)
	frame.fixedWidth = dialog:GetWidth()
	frame:Layout()

	local bottom = dialog:GetBottom()
	local height = frame:GetHeight()
	if bottom and height and (bottom * dialog:GetEffectiveScale()) < (height * frame:GetEffectiveScale()) then
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOM", dialog, "TOP", 0, 0)
	end
end

local function ApplicableOptions(system)
	local list = {}
	for _, option in ipairs(ns.options) do
		if option.appliesTo(system) then
			list[#list + 1] = option
		end
	end
	return list
end

function Panel.Update()
	local system = attachedSystem
	local options = system and EditModeSystemSettingsDialog:IsShown() and ApplicableOptions(system)
	if not (options and #options > 0) then
		frame:Hide()
		return
	end

	rows:Show(options, system)
	frame:Show()
	frame.Settings:Layout()
	Place()
end

local function CreatePanel()
	local dialog = EditModeSystemSettingsDialog

	frame = CreateFrame("Frame", nil, UIParent, "ResizeLayoutFrame")
	frame:SetFrameStrata(dialog:GetFrameStrata())
	frame:SetFrameLevel(dialog:GetFrameLevel())
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true) -- clicks on the panel's background must not reach the world
	frame.widthPadding = 40
	frame.heightPadding = 40
	frame:Hide()

	frame.Border = CreateFrame("Frame", nil, frame, "DialogBorderTranslucentTemplate")
	frame.Border.ignoreInLayout = true

	frame.Settings = CreateFrame("Frame", nil, frame, "VerticalLayoutFrame")
	frame.Settings.spacing = 2
	frame.Settings:SetPoint("TOP", 0, -20)
	rows = ns.Rows.CreateSet(frame.Settings)

	frame:HookScript("OnShow", Place)
end

ns.OnReady(function()
	local dialog = EditModeSystemSettingsDialog
	if not dialog then return end

	CreatePanel()

	hooksecurefunc(dialog, "AttachToSystemFrame", function(_, system)
		attachedSystem = system
		Panel.Update()
	end)
	-- Fires on every setting change (e.g. Lock to Player Frame, Use Raid-Style Party Frames) and when the system
	-- is moved in or out of its default position.
	hooksecurefunc(dialog, "UpdateDialog", function(self, system)
		if system == attachedSystem and self:IsShown() then
			Panel.Update()
		end
	end)
	dialog:HookScript("OnHide", function()
		attachedSystem = nil
		frame:Hide()
	end)
	dialog:HookScript("OnSizeChanged", Place)
	dialog:HookScript("OnDragStop", Place)
end)

-- A setting or system position may change outside the dialog's own updates (drag, layout switch).
ns.RegisterRefresher(function()
	if frame and frame:IsShown() and not rows:IsMenuOpen() then
		Panel.Update()
	end
end)
