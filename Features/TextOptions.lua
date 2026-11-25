-- Text options:
--   * Keybind Text on the action bars: Blizzard's (Default), Short ("SM4", "CN1", "WU"), or Hidden.
--   * Experience Text and Reputation Text on the status bars: Current / Max (Blizzard's), Percentage, or both.
--
-- Both run right after Blizzard sets its own text (post-hooks) and only change the text of a font string. No
-- Blizzard Lua is called on the secure action buttons: restoring the default text is done here from the same
-- binding Blizzard used, since running ActionBarActionButtonMixin:UpdateHotkeys from addon code would write
-- the button's bindingAction field.
local _, ns = ...

local Systems, Layouts = ns.Systems, ns.Layouts
local L = ns.L

local hooksecurefunc, ipairs, pairs, type, tostring = hooksecurefunc, ipairs, pairs, type, tostring
local floor = math.floor
local GetBindingKey, GetBindingText = GetBindingKey, GetBindingText

local SYS = Enum.EditModeSystem or {}

-- =====================================================================================================================
-- Keybind text
-- =====================================================================================================================

local HOTKEY_FIELD = "hotkeyText"
local DEFAULT, SHORT, HIDDEN = "DEFAULT", "SHORT", "HIDDEN"

local hookedButtons = setmetatable({}, { __mode = "k" })
local changedButtons = setmetatable({}, { __mode = "k" })

local MODIFIERS = { ALT = "A", CTRL = "C", SHIFT = "S", META = "M" }

local SHORT_KEYS = {
	MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD",
	NUMPADPLUS = "N+", NUMPADMINUS = "N-", NUMPADMULTIPLY = "N*", NUMPADDIVIDE = "N/",
	NUMPADDECIMAL = "N.", NUMPADENTER = "NEn",
	SPACE = "Sp", ESCAPE = "Esc", BACKSPACE = "Bs", TAB = "Tab", ENTER = "Ent", CAPSLOCK = "Cap",
	INSERT = "Ins", DELETE = "Del", HOME = "Hm", END = "End", PAGEUP = "PU", PAGEDOWN = "PD",
	UP = "Up", DOWN = "Dn", LEFT = "Lt", RIGHT = "Rt",
	PRINTSCREEN = "PS", SCROLLLOCK = "SL", PAUSE = "Pa", NUMLOCK = "NL",
}

-- "SHIFT-BUTTON4" -> "SM4", "CTRL-NUMPAD1" -> "CN1", "ALT-MOUSEWHEELUP" -> "AWU", "SHIFT-Q" -> "SQ".
local function ShortBindingText(key)
	local prefix = ""
	local rest = key
	while true do
		local modifier, remainder = rest:match("^(%u+)%-(.+)$")
		if modifier and MODIFIERS[modifier] then
			prefix = prefix .. MODIFIERS[modifier]
			rest = remainder
		else
			break
		end
	end

	local base = SHORT_KEYS[rest]
	if not base then
		local button = rest:match("^BUTTON(%d+)$")
		local numpad = rest:match("^NUMPAD(%d)$")
		if button then
			base = "M" .. button
		elseif numpad then
			base = "N" .. numpad
		else
			base = GetBindingText(rest, true) -- letters, digits, F-keys: Blizzard's own localized name
		end
	end
	return prefix .. base
end

-- The binding key a button displays, exactly as Blizzard looks it up.
local function ButtonKey(button)
	if type(button.bindingAction) == "string" then
		-- ActionBarActionButtonMixin:UpdateHotkeys
		return GetBindingKey(button.bindingAction) or GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton")
	elseif type(button.SetHotkeys) == "function" and button.GetID then
		-- PetActionButtonMixin:SetHotkeys
		return GetBindingKey("BONUSACTIONBUTTON" .. button:GetID())
	end
	return nil
end

local function HotkeyMode(bar)
	return Layouts.Get(Systems.KeyFor(bar), HOTKEY_FIELD) or DEFAULT
end

local function ApplyHotkey(button, mode)
	local hotkey = button.HotKey
	if not hotkey then return end

	local key = ButtonKey(button)
	-- Unbound buttons show Blizzard's range dot; gamepad bindings have their own art. Neither is touched.
	if not key or (IsBindingForGamePad and IsBindingForGamePad(key)) then return end

	if mode == SHORT then
		hotkey:SetText(ShortBindingText(key))
		hotkey:Show()
		changedButtons[button] = true
	elseif mode == HIDDEN then
		hotkey:Hide()
		changedButtons[button] = true
	elseif changedButtons[button] then
		-- Back to Blizzard's text (GetBindingText with abbreviation, as UpdateHotkeys and SetHotkeys do).
		hotkey:SetText(GetBindingText(key, true))
		hotkey:Show()
		changedButtons[button] = nil
	end
end

local function BarButtons(bar)
	return type(bar.actionButtons) == "table" and bar.actionButtons or {}
end

local function HasHotkeyButtons(bar)
	for _, button in pairs(BarButtons(bar)) do
		if button.HotKey and (type(button.UpdateHotkeys) == "function" or type(button.SetHotkeys) == "function") then
			return true
		end
	end
	return false
end

local function HookBar(bar)
	for _, button in pairs(BarButtons(bar)) do
		if not hookedButtons[button] then
			for _, method in ipairs({ "UpdateHotkeys", "SetHotkeys" }) do
				if type(button[method]) == "function" then
					hooksecurefunc(button, method, function(self)
						-- Blizzard just set its own text: that's the starting point now.
						changedButtons[self] = nil
						ApplyHotkey(self, HotkeyMode(bar))
					end)
					hookedButtons[button] = true
				end
			end
		end
	end
end

local function RefreshHotkeys()
	for _, bar in ipairs(Systems.GetRegistered()) do
		if bar.system == SYS.ActionBar and HasHotkeyButtons(bar) then
			HookBar(bar)
			local mode = HotkeyMode(bar)
			for _, button in pairs(BarButtons(bar)) do
				ApplyHotkey(button, mode)
			end
		end
	end
end

ns.RegisterRefresher(RefreshHotkeys)

ns.RegisterOption({
	kind = "dropdown",
	order = 80,
	appliesTo = function(system)
		return system.system == SYS.ActionBar and HasHotkeyButtons(system)
	end,
	label = function() return L.KEYBIND_TEXT end,
	get = HotkeyMode,
	set = function(system, value)
		Layouts.Set(Systems.KeyFor(system), HOTKEY_FIELD, value ~= DEFAULT and value or nil)
		ns.RequestRefresh()
	end,
	choices = function()
		return {
			{ value = DEFAULT, text = _G.DEFAULT or "Default" },
			{ value = SHORT, text = L.KEYBIND_SHORT },
			{ value = HIDDEN, text = _G.HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_HIDDEN or "Hidden" },
		}
	end,
})

-- =====================================================================================================================
-- Experience / reputation text
-- =====================================================================================================================
-- Every text change goes through StatusTrackingBarMixin:SetBarText. EditTime keeps the text Blizzard set and
-- rewrites it in the chosen format.

local STATUS_KEY = "statusbars" -- one setting for every status bar container: it follows the bar, not the slot
local VALUES, PERCENT, BOTH = "VALUES", "PERCENT", "BOTH"

local BARS = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum or {}
local FIELDS = {}
if BARS.Experience then FIELDS[BARS.Experience] = "xpText" end
if BARS.Reputation then FIELDS[BARS.Reputation] = "repText" end

local blizzardText = setmetatable({}, { __mode = "k" }) -- [bar] = the text Blizzard last set
local hookedBars = setmetatable({}, { __mode = "k" })

local function Percent(value, max)
	local pct = floor(value / max * 1000 + 0.5) / 10
	return (("%.1f"):format(pct):gsub("%.0$", ""))
end

-- The text in the chosen format, or nil to keep Blizzard's.
local function FormatBarText(bar, text, mode)
	if mode == VALUES or type(text) ~= "string" then return nil end

	if bar.barIndex == BARS.Experience then
		local current, max = bar.currXP, bar.maxBar
		if type(current) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
		local pct = Percent(current, max)
		if mode == PERCENT then
			return L.XP_PERCENT:format(pct)
		end
		return L.XP_BOTH:format(tostring(current), tostring(max), pct)
	elseif bar.barIndex == BARS.Reputation then
		-- ReputationStatusBarMixin builds `name .. " %d / %d"`; a capped standing shows the name alone.
		local name, value, max = text:match("^(.-) (%d+) / (%d+)$")
		value, max = tonumber(value), tonumber(max)
		if not (name and value and max and max > 0) then return nil end
		local pct = Percent(value, max)
		if mode == PERCENT then
			return L.REP_PERCENT:format(name, pct)
		end
		return L.REP_BOTH:format(name, value, max, pct)
	end
	return nil
end

local function ApplyBarText(bar)
	local field = FIELDS[bar.barIndex]
	local text = blizzardText[bar]
	local label = bar.OverlayFrame and bar.OverlayFrame.Text
	if not (field and text and label) then return end

	local formatted = FormatBarText(bar, text, Layouts.Get(STATUS_KEY, field) or VALUES)
	label:SetText(formatted or text)
end

local function ForEachStatusBar(func)
	for _, container in ipairs({ MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer }) do
		if container and type(container.bars) == "table" then
			for _, bar in pairs(container.bars) do
				if FIELDS[bar.barIndex] then func(bar) end
			end
		end
	end
end

local function HookStatusBars()
	ForEachStatusBar(function(bar)
		if hookedBars[bar] or type(bar.SetBarText) ~= "function" then return end
		hookedBars[bar] = true
		hooksecurefunc(bar, "SetBarText", function(self, text)
			blizzardText[self] = text
			ApplyBarText(self)
		end)
	end)
end

ns.RegisterRefresher(function()
	HookStatusBars()
	ForEachStatusBar(ApplyBarText)
end)

local function StatusOption(order, field, label)
	ns.RegisterOption({
		kind = "dropdown",
		order = order,
		appliesTo = function(system)
			return system.system == SYS.StatusTrackingBar
		end,
		label = function() return label end,
		get = function()
			return Layouts.Get(STATUS_KEY, field) or VALUES
		end,
		set = function(_, value)
			Layouts.Set(STATUS_KEY, field, value ~= VALUES and value or nil)
			ns.RequestRefresh()
		end,
		choices = function()
			return {
				{ value = VALUES, text = L.TEXT_VALUES },
				{ value = PERCENT, text = L.TEXT_PERCENT },
				{ value = BOTH, text = L.TEXT_BOTH },
			}
		end,
	})
end

StatusOption(81, "xpText", L.EXPERIENCE_TEXT)
StatusOption(82, "repText", L.REPUTATION_TEXT)
