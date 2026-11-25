std = "lua51"
max_line_length = false
codes = true
exclude_files = { ".luacheckrc" }

ignore = {
	"212/self", -- unused self in methods
}

globals = {
	"EditTimeDB",
}

read_globals = {
	-- WoW Lua extensions / utilities
	"CopyTable", "Mixin", "CreateFrame", "CreateFromMixins", "GenerateClosure", "hooksecurefunc",
	"InCombatLockdown", "geterrorhandler", "wipe", "C_Timer", "C_EditMode", "Enum", "EventRegistry",
	"PixelUtil", "UnitFullName", "UnitAffectingCombat", "GetNormalizedRealmName",
	"GameTooltip", "GameTooltip_AddErrorLine", "GameTooltip_Hide",

	-- Frames
	"UIParent", "EditModeManagerFrame", "EditModeSystemSettingsDialog", "PlayerCastingBarFrame", "MicroMenu",
	"CompactRaidFrameContainer", "CompactPartyFrame", "MAX_RAID_GROUPS",
	"CompactRaidGroup_UpdateLayout", "CompactUnitFrame_UpdateVisible",
	"UnitIsUnit", "UnitExists", "IsInRaid", "PlaySound", "SOUNDKIT",
	"UnitGUID", "UnitGroupRolesAssigned", "issecretvalue", "CompactRaidGroupTypeEnum",
	"DefaultCompactUnitFrameSetup", "CompactUnitFrame_UpdateRoleIcon",
	"NineSliceUtil", "ShrinkUntilTruncateFontStringMixin",
	"HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT", "HUD_EDIT_MODE_RESET_POSITION", "RESET_TO_DEFAULT",
	"TargetFrame", "FocusFrame", "AlertFrame", "GroupLootContainer", "GroupLootContainer_Update",
	"GroupLootFrame1", "InputUtil", "AlertFrameAutoAnchoredMixin", "EditModeMagnetismManager", "EditModeUtil",
	"GetBindingKey", "GetBindingText", "IsBindingForGamePad", "StatusTrackingBarInfo",
	"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",

	-- Blizzard constants and global strings
	"STATUS_BAR_SIZE_ADJUSTMENT", "NONE", "ALWAYS", "HIDE", "DISABLED_FONT_COLOR", "HIGHLIGHT_FONT_COLOR",
	"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_VISIBLE_SETTING",
	"HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_ALWAYS",
	"HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_IN_COMBAT",
	"HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_OUT_OF_COMBAT",
	"HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_HIDDEN",
}
