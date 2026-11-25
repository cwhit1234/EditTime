-- Setting rows in the look of Edit Mode's own (EditModeSettingDropdownTemplate / EditModeSettingCheckboxTemplate),
-- shared by the system settings panel and the mover dialog. Blizzard's row templates aren't reused: their
-- callbacks route into EditModeSystemSettingsDialog:OnSettingValueChanged.
--
-- Option fields (the same everywhere options are registered):
--   kind                 "dropdown" or "checkbox"
--   label(context)       row label text
--   disabledReason(context)  optional; nil if usable, else the tooltip explaining why not
--   get(context)         current value
--   set(context, value)  store a new value
--   choices(context)     dropdown only: list of { value = v, text = "..." }
-- `context` is whatever the rows are shown for: an Edit Mode system frame, or a mover definition.
local _, ns = ...

local Rows = {}
ns.Rows = Rows

local ipairs, pairs = ipairs, pairs

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

local CREATE = { dropdown = CreateDropdownRow, checkbox = CreateCheckboxRow }
local SETUP = { dropdown = SetupDropdownRow, checkbox = SetupCheckboxRow }

-- A set of rows inside `parent` (a VerticalLayoutFrame), reused across updates.
function Rows.CreateSet(parent)
	local set = { parent = parent, pools = { dropdown = {}, checkbox = {} } }

	-- Shows one row per option, in order, and hides the rest. Returns the number of rows shown.
	function set:Show(options, context)
		local used = { dropdown = 0, checkbox = 0 }
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

	-- True while one of the dropdown menus is open, so a refresh doesn't rebuild it under the player.
	function set:IsMenuOpen()
		for _, row in ipairs(self.pools.dropdown) do
			if row:IsShown() and row.Dropdown.IsMenuOpen and row.Dropdown:IsMenuOpen() then
				return true
			end
		end
		return false
	end

	return set
end
