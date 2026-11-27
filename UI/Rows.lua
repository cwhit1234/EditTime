-- Setting rows in the look of Edit Mode's own (EditModeSettingDropdownTemplate / EditModeSettingCheckboxTemplate),
-- shared by the system settings panel and the mover dialog. Blizzard's row templates aren't reused: their
-- callbacks route into EditModeSystemSettingsDialog:OnSettingValueChanged.
--
-- Option fields (the same everywhere options are registered):
--   kind                 "dropdown", "checkbox" or "slider"
--   label(context)       row label text
--   disabledReason(context)  optional; nil if usable, else the tooltip explaining why not
--   get(context)         current value
--   set(context, value)  store a new value
--   choices(context)     dropdown only: list of { value = v, text = "..." }
--   range(context)       slider only: min, max, step
--   minText, maxText     slider only, optional: captions under the ends (like Blizzard's Narrow / Wide)
--   formatValue(value)   slider only, optional: text shown right of the slider (like Blizzard's "100%")
--   editable             slider only, optional: a box right of the slider where a value can be typed instead
-- `context` is whatever the rows are shown for: an Edit Mode system frame, or a mover definition.
local _, ns = ...

local Rows = {}
ns.Rows = Rows

local ipairs, pairs, tonumber, tostring = ipairs, pairs, tonumber, tostring
local floor, min, max = math.floor, math.min, math.max

local LABEL_WIDTH, DROPDOWN_WIDTH, ROW_HEIGHT, CHECKBOX_LABEL_WIDTH = 100, 225, 32, 300

Rows.WIDTH = LABEL_WIDTH + 5 + DROPDOWN_WIDTH

local function ShowReasonTooltip(row, owner)
	if row.disabledReason then
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip_AddErrorLine(GameTooltip, row.disabledReason, true)
		GameTooltip:Show()
	end
end

local function HideReasonTooltip(owner)
	if GameTooltip:GetOwner() == owner then
		GameTooltip_Hide()
	end
end

local function SetLabelEnabled(label, enabled)
	local color = enabled and HIGHLIGHT_FONT_COLOR or DISABLED_FONT_COLOR
	label:SetTextColor(color:GetRGB())
end

local function CreateDropdownRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(Rows.WIDTH, ROW_HEIGHT)

	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	row.Label:SetJustifyH("LEFT")
	row.Label:SetWidth(LABEL_WIDTH)
	row.Label:SetPoint("LEFT")

	row.Dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	row.Dropdown:SetWidth(DROPDOWN_WIDTH)
	row.Dropdown:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)

	-- Disabled buttons still get OnEnter/OnLeave, so the reason tooltip hangs off the dropdown.
	row.Dropdown:HookScript("OnEnter", function(self) ShowReasonTooltip(row, self) end)
	row.Dropdown:HookScript("OnLeave", HideReasonTooltip)
	return row
end

local function SetupDropdownRow(row, option, context)
	row.Label:SetText(option.label(context))
	row.disabledReason = option.disabledReason and option.disabledReason(context) or nil
	row.Dropdown:SetEnabled(row.disabledReason == nil)
	SetLabelEnabled(row.Label, row.disabledReason == nil)

	local function IsSelected(value)
		return option.get(context) == value
	end
	local function SetSelected(value)
		option.set(context, value)
	end

	row.Dropdown:SetupMenu(function(_, root)
		for _, choice in ipairs(option.choices(context)) do
			root:CreateRadio(choice.text, IsSelected, SetSelected, choice.value)
		end
	end)
end

local function CreateCheckboxRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(Rows.WIDTH, ROW_HEIGHT)

	local button = CreateFrame("CheckButton", nil, row)
	button:SetSize(32, 32)
	button:SetPoint("LEFT", -5, 0)
	button:SetMotionScriptsWhileDisabled(true)
	button:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	button:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	button:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
	button:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	button:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
	button:SetScript("OnEnter", function(self) ShowReasonTooltip(row, self) end)
	button:SetScript("OnLeave", HideReasonTooltip)
	row.Button = button

	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	row.Label:SetJustifyH("LEFT")
	row.Label:SetSize(CHECKBOX_LABEL_WIDTH, ROW_HEIGHT)
	row.Label:SetPoint("LEFT", button, "RIGHT", 5, 0)
	return row
end

local function SetupCheckboxRow(row, option, context)
	row.Label:SetText(option.label(context))
	row.disabledReason = option.disabledReason and option.disabledReason(context) or nil
	row.Button:SetEnabled(row.disabledReason == nil)
	SetLabelEnabled(row.Label, row.disabledReason == nil)
	row.Button:SetChecked(option.get(context) and true or false)
	row.Button:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		option.set(context, self:GetChecked() and true or false)
	end)
end

-- Like EditModeSettingSliderTemplate: sized like the dropdowns, a little narrower when it shows its value.
local SLIDER_WIDTH, SLIDER_WITH_VALUE_WIDTH, SLIDER_WITH_INPUT_WIDTH, INPUT_WIDTH = DROPDOWN_WIDTH, 195, 172, 44

-- Rounds a typed value to the slider's steps and keeps it in range. Returns nil for anything that isn't a number.
local function SnapToRange(value, minValue, maxValue, step)
	value = tonumber(value)
	if not value or value ~= value then return nil end
	value = minValue + floor((value - minValue) / step + 0.5) * step
	return min(max(value, minValue), maxValue)
end

local function FormatInput(value)
	if value == floor(value) then return tostring(floor(value)) end
	return tostring(value)
end

local function ResetInput(row)
	if row.option then
		row.Input:SetText(FormatInput(row.option.get(row.context)))
	end
	row.Input:SetCursorPosition(0)
end

local function CommitInput(row)
	if not (row.option and row.disabledReason == nil) then return ResetInput(row) end
	local value = SnapToRange(row.Input:GetText(), row.option.range(row.context))
	if value ~= nil then
		row.initInProgress = true
		row.Slider:SetValue(value)
		row.initInProgress = false
		row.option.set(row.context, value)
	end
	ResetInput(row)
end

local function CreateSliderRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(Rows.WIDTH, ROW_HEIGHT)

	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	row.Label:SetJustifyH("LEFT")
	row.Label:SetSize(LABEL_WIDTH, ROW_HEIGHT)

	row.Slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	row.Slider:SetSize(SLIDER_WIDTH, ROW_HEIGHT)
	row.Slider:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)

	row.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if not row.initInProgress and row.option then
			row.option.set(row.context, value)
		end
		if row.Input:IsShown() and not row.Input:HasFocus() then
			row.Input:SetText(FormatInput(value))
		end
	end, row)

	-- The box for typing a value (option.editable). Enter applies it, Escape puts the current value back.
	local input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	input:SetSize(INPUT_WIDTH, 20)
	input:SetPoint("LEFT", row.Slider, "RIGHT", 8, 0)
	input:SetAutoFocus(false)
	input:SetMaxLetters(6)
	input:SetJustifyH("CENTER")
	input:SetScript("OnEnterPressed", function(self)
		CommitInput(row)
		self:ClearFocus()
	end)
	input:SetScript("OnEscapePressed", function(self)
		ResetInput(row)
		self:ClearFocus()
	end)
	input:SetScript("OnEditFocusLost", function() ResetInput(row) end)
	input:SetScript("OnEnter", function(self) ShowReasonTooltip(row, self) end)
	input:SetScript("OnLeave", HideReasonTooltip)
	input:Hide()
	row.Input = input

	-- The disabled reason shows when hovering the slider, as on the other rows.
	row.Slider.Slider:HookScript("OnEnter", function() ShowReasonTooltip(row, row.Slider) end)
	row.Slider.Slider:HookScript("OnLeave", function() HideReasonTooltip(row.Slider) end)
	return row
end

local function SetupSliderRow(row, option, context)
	row.option, row.context = option, context
	row.Label:SetText(option.label(context))
	row.disabledReason = option.disabledReason and option.disabledReason(context) or nil
	SetLabelEnabled(row.Label, row.disabledReason == nil)

	-- With captions the row is taller and the label sits a little higher, like Blizzard's.
	local hasCaptions = option.minText ~= nil or option.maxText ~= nil
	row:SetHeight(hasCaptions and 38 or ROW_HEIGHT)
	row.Label:ClearAllPoints()
	row.Label:SetPoint("LEFT", row, "LEFT", 0, hasCaptions and 3 or 0)
	row.Slider.MinText:SetText(option.minText or "")
	row.Slider.MinText:SetShown(option.minText ~= nil)
	row.Slider.MaxText:SetText(option.maxText or "")
	row.Slider.MaxText:SetShown(option.maxText ~= nil)

	local formatters = {}
	row.Input:SetShown(option.editable == true)
	if option.editable then
		row.Slider.RightText:Hide()
		row.Slider:SetWidth(SLIDER_WITH_INPUT_WIDTH)
	elseif option.formatValue then
		local right = MinimalSliderWithSteppersMixin.Label.Right
		formatters[right] = CreateMinimalSliderFormatter(right, option.formatValue)
		row.Slider:SetWidth(SLIDER_WITH_VALUE_WIDTH)
	else
		row.Slider.RightText:Hide()
		row.Slider:SetWidth(SLIDER_WIDTH)
	end

	local minValue, maxValue, step = option.range(context)
	row.initInProgress = true
	row.Slider:Init(option.get(context), minValue, maxValue, (maxValue - minValue) / step, formatters)
	row.initInProgress = false
	row.Slider:SetEnabled(row.disabledReason == nil)
	if option.editable then
		row.Input:SetEnabled(row.disabledReason == nil)
		row.Input:SetTextColor((row.disabledReason == nil and HIGHLIGHT_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())
		row.Input:ClearFocus()
		ResetInput(row)
	end
end

local function IsSliderInUse(row)
	if row.Input:IsShown() and row.Input:HasFocus() then return true end
	local slider = row.Slider.Slider
	return slider.IsDraggingThumb ~= nil and slider:IsDraggingThumb()
end

local CREATE = { dropdown = CreateDropdownRow, checkbox = CreateCheckboxRow, slider = CreateSliderRow }
local SETUP = { dropdown = SetupDropdownRow, checkbox = SetupCheckboxRow, slider = SetupSliderRow }

-- A set of rows inside `parent` (a VerticalLayoutFrame), reused across updates.
function Rows.CreateSet(parent)
	local set = { parent = parent, pools = { dropdown = {}, checkbox = {}, slider = {} } }

	-- Shows one row per option, in order, and hides the rest. Returns the number of rows shown.
	function set:Show(options, context)
		local used = { dropdown = 0, checkbox = 0, slider = 0 }
		for index, option in ipairs(options) do
			local kind = option.kind
			used[kind] = used[kind] + 1
			local row = self.pools[kind][used[kind]]
			if not row then
				row = CREATE[kind](self.parent)
				self.pools[kind][used[kind]] = row
			end
			SETUP[kind](row, option, context)
			row.layoutIndex = index
			row:Show()
		end
		for kind, list in pairs(self.pools) do
			for i = used[kind] + 1, #list do
				list[i]:Hide()
			end
		end
		return #options
	end

	-- True while a dropdown menu is open or a slider is being dragged or typed in, so a refresh doesn't rebuild it under the
	-- player.
	function set:IsMenuOpen()
		for _, row in ipairs(self.pools.dropdown) do
			if row:IsShown() and row.Dropdown.IsMenuOpen and row.Dropdown:IsMenuOpen() then
				return true
			end
		end
		for _, row in ipairs(self.pools.slider) do
			if row:IsShown() and IsSliderInUse(row) then
				return true
			end
		end
		return false
	end

	return set
end
