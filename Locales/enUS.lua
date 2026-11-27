-- Only strings Blizzard does not already provide. Everything else uses Blizzard's localized global strings.
local _, ns = ...

local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

L.MATCH_WIDTH = "Match Width"
L.MATCH_HEIGHT = "Match Height"
L.MATCH_LOCKED_TOOLTIP = "Unavailable while locked to the Player Frame."
L.MATCH_DEFAULT_POSITION_TOOLTIP = "Move this frame out of its default position first."
L.BAR_WIDTH = "Bar Width"
L.BAR_WIDTH_MATCHED_TOOLTIP = "Unavailable while Match Width is set."
L.VISIBILITY = "Visibility"

L.HORIZONTAL_GROWTH = "Horizontal Growth"
L.VERTICAL_GROWTH = "Vertical Growth"
L.GROWTH_CENTER = "Center"
L.GROWTH_LEFT = "Left"
L.GROWTH_RIGHT = "Right"
L.GROWTH_UP = "Up"
L.GROWTH_DOWN = "Down"

L.HIDE_OWN_FRAME = "Hide Own Frame"
L.HIDE_PARTY_TITLE = "Hide Party Title"
L.HIDE_DPS_ROLE_ICONS = "Hide DPS Role Icons"
L.TANK_HEALER_POWER_BARS = "Only Tank & Healer Power Bars"
L.HIDE_PORTRAIT_COMBAT_TEXT = "Hide Portrait Combat Text"
L.HIDE_PLAYER_NAME = "Hide Player Name"
L.LEVEL_SCALE = "Level Scale"
-- Fallbacks only; Blizzard's REPLACE_MY_PLAYER_PORTRAIT and REPLACE_OTHER_PLAYER_PORTRAITS are used when present.
L.CLASS_ICON_MY_PORTRAIT = "Show My Class Icon as Portrait"
L.CLASS_ICON_OTHER_PORTRAITS = "Show Other Players' Class Icons as Portraits"
-- Fallbacks only; Blizzard's STATUSTEXT_LABEL and STATUS_TEXT_* globals are used when present.
L.STATUS_TEXT = "Status Text"
L.STATUS_TEXT_VALUE = "Numeric Value"
L.STATUS_TEXT_PERCENT = "Percentage"
L.STATUS_TEXT_BOTH = "Both"
L.RAID_STYLE_ONLY_TOOLTIP = "Only available with Use Raid-Style Party Frames."

L.TARGET_OF_TARGET = "Target of Target"
L.FOCUS_TARGET = "Focus Target"
L.TOASTS = "Toasts"
L.LOOT_ROLLS = "Loot Rolls"
L.GROWTH_DIRECTION = "Growth Direction"

L.KEYBIND_TEXT = "Keybind Text"
L.KEYBIND_SHORT = "Short"
L.EXPERIENCE_TEXT = "Experience Text"
L.REPUTATION_TEXT = "Reputation Text"
L.TEXT_VALUES = "Current / Max"
L.TEXT_PERCENT = "Percentage"
L.TEXT_BOTH = "Current / Max (Percentage)"
L.XP_PERCENT = "XP: %s%%"
L.XP_BOTH = "XP: %s/%s (%s%%)"
L.REP_PERCENT = "%s %s%%"
L.REP_BOTH = "%s %d / %d (%s%%)"
