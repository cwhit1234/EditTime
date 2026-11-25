-- Visibility: Always / In Combat / Out of Combat / Hidden, for systems Blizzard gives no such option.
--
-- Frames are faded (alpha 0 + mouse off), never hidden. These systems are managed frames: calling :Hide()
-- from addon code runs Blizzard's managed-container layout tainted. That container also lays out protected
-- action bars, so in combat it would cause ADDON_ACTION_BLOCKED.
local _, ns = ...

local Systems, Layouts = ns.Systems, ns.Layouts

local Visibility = {}
ns.Visibility = Visibility

local FIELD = "visibility"

Visibility.ALWAYS = 0
Visibility.IN_COMBAT = 1
Visibility.OUT_OF_COMBAT = 2
Visibility.HIDDEN = 3

local hooksecurefunc, ipairs, pairs, next, type = hooksecurefunc, ipairs, pairs, next, type
local InCombatLockdown, wipe = InCombatLockdown, wipe

local inCombat = false
local editModeActive = false

-- [systemFrame] = { alpha = { [object] = previousAlpha }, mouse = { [frame] = { mouse, wheel } } }
local faded = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })

function Visibility.Get(systemKey)
	return Layouts.Get(systemKey, FIELD) or Visibility.ALWAYS
end

function Visibility.Set(systemKey, mode)
	if mode == Visibility.ALWAYS then
		mode = nil -- the default, so nothing is stored
	end
	Layouts.Set(systemKey, FIELD, mode)
	ns.RequestRefresh()
end

local function ShouldShow(mode)
	if editModeActive or mode == Visibility.ALWAYS then
		return true
	elseif mode == Visibility.IN_COMBAT then
		return inCombat
	elseif mode == Visibility.OUT_OF_COMBAT then
		return not inCombat
	end
	return false -- HIDDEN
end

local function CanChangeMouse(frame)
	return not (InCombatLockdown() and frame:IsProtected())
end

local function DisableMouse(frame, store)
	if not store[frame] and CanChangeMouse(frame) then
		local mouse, wheel = frame:IsMouseEnabled(), frame:IsMouseWheelEnabled()
		if mouse or wheel then
			store[frame] = { mouse, wheel }
			if mouse then frame:EnableMouse(false) end
			if wheel then frame:EnableMouseWheel(false) end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		DisableMouse(child, store)
	end
end

local Unfade

-- Rebuilt from scratch every time: restore, then fade again in the same frame, so nothing is drawn in between.
-- This picks up children created since the last fade, and lets go of frames moved elsewhere (the micro menu
-- on a vehicle bar).
local function Fade(frame, adapter)
	Unfade(frame)

	local state = faded[frame]
	if not state then
		state = { alpha = {}, mouse = {} }
		faded[frame] = state
	end

	for _, object in ipairs(adapter.fadeObjects(frame)) do
		if state.alpha[object] == nil then
			state.alpha[object] = object:GetAlpha()
		end
		object:SetAlpha(0)
		if object:IsObjectType("Frame") then
			DisableMouse(object, state.mouse)
		end
	end
end

function Unfade(frame)
	local state = faded[frame]
	if not state then return end

	for object, alpha in pairs(state.alpha) do
		object:SetAlpha(alpha)
	end
	for object, saved in pairs(state.mouse) do
		if CanChangeMouse(object) then
			if saved[1] then object:EnableMouse(true) end
			if saved[2] then object:EnableMouseWheel(true) end
			state.mouse[object] = nil
		end
	end

	if next(state.mouse) == nil then
		faded[frame] = nil
	else
		-- A protected child could not be restored in combat; keep only that part for after combat.
		wipe(state.alpha)
	end
end

local function HookFrame(frame, adapter)
	if hooked[frame] then return end
	hooked[frame] = true
	for _, method in ipairs(adapter.reapplyHooks) do
		if type(frame[method]) == "function" then
			hooksecurefunc(frame, method, ns.RequestRefresh)
		end
	end
	if adapter.extraHooks then
		for _, hook in ipairs(adapter.extraHooks()) do
			local object, method = hook[1], hook[2]
			if object and type(object[method]) == "function" then
				hooksecurefunc(object, method, ns.RequestRefresh)
			end
		end
	end
end

local function Refresh()
	for _, frame in ipairs(Systems.GetRegistered()) do
		local adapter = Systems.GetVisibilityAdapter(frame)
		if adapter and frame.systemInfo ~= nil then
			local mode = Visibility.Get(Systems.KeyFor(frame))
			if mode ~= Visibility.ALWAYS then
				HookFrame(frame, adapter)
			end
			if ShouldShow(mode) then
				Unfade(frame)
			else
				Fade(frame, adapter)
			end
		end
	end
end

ns.RegisterRefresher(Refresh)

-- Panel row: Blizzard's own action bar wording, so it reads and translates like the built-in options.
local CHOICES = {
	{ value = Visibility.ALWAYS, global = "HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_ALWAYS", fallback = "Always Visible" },
	{ value = Visibility.IN_COMBAT, global = "HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_IN_COMBAT", fallback = "In Combat" },
	{ value = Visibility.OUT_OF_COMBAT, global = "HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_OUT_OF_COMBAT", fallback = "Out of Combat" },
	{ value = Visibility.HIDDEN, global = "HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_HIDDEN", fallback = "Hidden" },
}

ns.RegisterOption({
	kind = "dropdown",
	order = 90,
	appliesTo = function(system)
		return Systems.GetVisibilityAdapter(system) ~= nil
	end,
	label = function()
		-- The Cooldown Viewer's label is generic ("Visibility"); the action bar's says "Bar".
		return _G.HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_VISIBLE_SETTING or ns.L.VISIBILITY
	end,
	get = function(system)
		return Visibility.Get(Systems.KeyFor(system))
	end,
	set = function(system, value)
		Visibility.Set(Systems.KeyFor(system), value)
	end,
	choices = function()
		local list = {}
		for _, choice in ipairs(CHOICES) do
			list[#list + 1] = { value = choice.value, text = _G[choice.global] or choice.fallback }
		end
		return list
	end,
})

-- Combat changes apply at once, not a frame later. PLAYER_REGEN_DISABLED fires before lockdown begins, so
-- the mouse can still be switched off on any protected child.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
	inCombat = (event == "PLAYER_REGEN_DISABLED")
	if ns.db then
		Refresh()
	end
end)

ns.OnReady(function()
	inCombat = InCombatLockdown() or UnitAffectingCombat("player") or false
	local manager = EditModeManagerFrame
	editModeActive = manager and manager.IsEditModeActive and manager:IsEditModeActive() or false

	EventRegistry:RegisterCallback("EditMode.Enter", function()
		editModeActive = true
		Refresh()
	end, Visibility)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		editModeActive = false
		Refresh()
	end, Visibility)
end)
