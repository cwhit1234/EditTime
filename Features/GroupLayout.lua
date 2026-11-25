-- Post-layout changes to the raid-style Party Frames and the Raid Frames:
--   * Hide Own Frame: removes the player's own frame and closes the gap it leaves.
--   * Hide Party Title: removes the "Party" label above the party frames and moves the frames up into its space.
--
-- Blizzard decides which units are shown (filter, sort and group mode are set by its raid manager). Changing any of
-- that from addon code taints the raid layout and breaks it in combat. So EditTime works only AFTER Blizzard's
-- layout, with widget calls (Hide/SetPoint) on the buttons, and only out of combat.
--
-- Fail-safe in combat: if Blizzard re-shows the player's button without a new layout, it appears off screen, never
-- on top of another player's frame. If Blizzard lays the frames out again (roster change), its own layout is used
-- as-is until combat ends: your frame and the title may come back, but no teammate's frame is hidden or covered.
local _, ns = ...

local Systems, Layouts, Combat = ns.Systems, ns.Layouts, ns.Combat
local L = ns.L

local GroupLayout = {}
ns.GroupLayout = GroupLayout

local FIELD_HIDE_SELF, FIELD_HIDE_TITLE = "hideSelf", "hideTitle"
local COMBAT_KEY = GroupLayout

local hooksecurefunc, ipairs, pairs, type, wipe = hooksecurefunc, ipairs, pairs, type, wipe
local UnitIsUnit, UnitExists, UnitGUID, IsInRaid, InCombatLockdown = UnitIsUnit, UnitExists, UnitGUID, IsInRaid, InCombatLockdown
local issecretvalue = issecretvalue or function() return false end

local editModeActive = false

-- What EditTime changed since Blizzard's last layout of each group, so it can be undone exactly.
local moved = {}      -- [button] = original points { {point, relativeTo, relativePoint, x, y}, ... }
local parked = {}     -- [button] = true: the player's button, hidden and off screen
local hiddenTitles = {} -- [title] = true

local function FindSystem(test)
	for _, frame in ipairs(Systems.GetRegistered()) do
		if test(frame) then return frame end
	end
	return nil
end

local function IsEnabled(test, field)
	local system = FindSystem(test)
	return system ~= nil and Layouts.Get(Systems.KeyFor(system), field) == true
end

-- True only when it's certain the button shows the player. On addon-restricted maps unit comparisons can be
-- secret; then the answer is "no", and nothing is hidden.
local function IsPlayerButton(button)
	local unit = button.unit
	if type(unit) ~= "string" then return false end
	if unit == "player" then return true end
	if not UnitExists(unit) then return false end

	local same = UnitIsUnit(unit, "player")
	if not issecretvalue(same) then
		return same == true
	end
	local guid, playerGUID = UnitGUID(unit), UnitGUID("player")
	if issecretvalue(guid) or issecretvalue(playerGUID) or not guid then
		return false
	end
	return guid == playerGUID
end

local function GetPoints(region)
	local points = {}
	for i = 1, region:GetNumPoints() do
		points[i] = { region:GetPoint(i) }
	end
	return points
end

local function SavePoints(button)
	if not moved[button] then
		moved[button] = GetPoints(button)
	end
end

local function SetPoints(button, points)
	button:ClearAllPoints()
	for _, p in ipairs(points) do
		button:SetPoint(p[1], p[2], p[3], p[4], p[5])
	end
end

local function Park(button)
	SavePoints(button)
	parked[button] = true
	button:Hide()
	button:ClearAllPoints()
	button:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -500, 500)
end

-- Restore / forget ----------------------------------------------------------------------------------------------------

local function Restore()
	for button, points in pairs(moved) do
		SetPoints(button, points)
	end
	for button in pairs(parked) do
		if type(button.unit) == "string" and UnitExists(button.unit) then
			button:Show()
		end
	end
	for title in pairs(hiddenTitles) do
		title:Show()
	end
	wipe(moved)
	wipe(parked)
	wipe(hiddenTitles)
end

-- Blizzard just laid out the buttons inside `layoutFrame` again: what EditTime remembered for those buttons no
-- longer applies. Buttons in other groups keep their records.
local function Forget(layoutFrame)
	for button in pairs(moved) do
		if button:GetParent() == layoutFrame then moved[button] = nil end
	end
	for button in pairs(parked) do
		if button:GetParent() == layoutFrame then parked[button] = nil end
	end
end

-- Group frames (CompactPartyFrame, CompactRaidGroupN) -----------------------------------------------------------------
-- Member1 hangs below the title; every other member is chained to the one before it.

-- The title's hidden state is EditTime's own (Blizzard's layout never shows it again). Member1's anchor is redone
-- after every Blizzard layout, which Forget() signals by dropping Member1's record.
local function CollapseTitle(group)
	local title, first = group.title, group.memberUnitFrames and group.memberUnitFrames[1]
	if not (title and first) then return end

	title:Hide()
	hiddenTitles[title] = true
	if moved[first] then return end -- already moved up since Blizzard's last layout

	local titleHeight = title:GetHeight() or 0
	local points = GetPoints(first)
	for _, p in ipairs(points) do
		if p[2] == group then
			p[5] = (p[5] or 0) + titleHeight -- Blizzard placed it titleHeight below the top
		end
	end
	SavePoints(first)
	SetPoints(first, points)
end

local function CollapsePlayer(group)
	local members = group.memberUnitFrames
	if type(members) ~= "table" then return end

	-- Found by unit, not by IsShown: after a re-layout Blizzard may leave an already-hidden button hidden.
	local playerButton
	for _, button in ipairs(members) do
		if IsPlayerButton(button) then
			playerButton = button
			break
		end
	end
	if not playerButton or parked[playerButton] then return end

	local playerPoints = GetPoints(playerButton)
	local playerParent = playerPoints[1] and playerPoints[1][2]

	-- Member frames all have the same size, so the next one takes the player's anchor as-is.
	local successor
	for _, button in ipairs(members) do
		if button ~= playerButton then
			for i = 1, button:GetNumPoints() do
				local _, relativeTo = button:GetPoint(i)
				if relativeTo == playerButton then
					SavePoints(button)
					SetPoints(button, playerPoints)
					successor = button
					break
				end
			end
		end
	end

	-- Pets are smaller: they keep their own points and only switch what they're attached to.
	if type(group.petUnitFrames) == "table" then
		local replacement = (playerParent and playerParent ~= group and playerParent) or successor
		for _, pet in ipairs(group.petUnitFrames) do
			local points, attached = GetPoints(pet), false
			for _, p in ipairs(points) do
				if p[2] == playerButton then
					attached = true
					p[2] = replacement
				end
			end
			if attached and replacement then
				SavePoints(pet)
				SetPoints(pet, points)
			end
		end
	end

	Park(playerButton)
end

-- Raid container in combined ("flush") mode ---------------------------------------------------------------------------
-- Every button is placed with its own TOPLEFT offset, in order.

local function CollapsePlayerInFlow(container)
	local frames, types = container.flowFrames, container.flowFrameTypes
	if type(frames) ~= "table" or type(types) ~= "table" then return end

	-- Every "raid" object in the flow list is in use (Blizzard rebuilds the list on each layout), shown or not.
	local buttons = {}
	for i, object in ipairs(frames) do
		if types[i] == "object" and type(object) == "table" and object.frameType == "raid" then
			buttons[#buttons + 1] = object
		end
	end

	local playerIndex
	for i, button in ipairs(buttons) do
		if IsPlayerButton(button) then
			playerIndex = i
			break
		end
	end
	if not playerIndex or parked[buttons[playerIndex]] then return end

	-- Each following button moves into the slot of the one before it.
	local slots = {}
	for i = playerIndex, #buttons do
		slots[i] = GetPoints(buttons[i])
	end
	for i = playerIndex + 1, #buttons do
		SavePoints(buttons[i])
		SetPoints(buttons[i], slots[i - 1])
	end

	Park(buttons[playerIndex])
end

-- Apply ---------------------------------------------------------------------------------------------------------------

local function Apply()
	if editModeActive then return end -- Edit Mode previews fill the frames with copies of the player

	local party = CompactPartyFrame
	if party and party:IsShown() and not IsInRaid() then
		-- The title first: the player collapse then copies the corrected anchor.
		if IsEnabled(Systems.IsPartyFrames, FIELD_HIDE_TITLE) then
			CollapseTitle(party)
		end
		if IsEnabled(Systems.IsPartyFrames, FIELD_HIDE_SELF) then
			CollapsePlayer(party)
		end
	end

	local container = CompactRaidFrameContainer
	if container and container:IsShown() and IsEnabled(Systems.IsRaidFrames, FIELD_HIDE_SELF) then
		if container.GetGroupMode and container:GetGroupMode() == "discrete" then
			for i = 1, MAX_RAID_GROUPS or 8 do
				local group = _G["CompactRaidGroup" .. i]
				if group and group:IsShown() and group:GetParent() == container then
					CollapsePlayer(group)
				end
			end
		else
			CollapsePlayerInFlow(container)
		end
	end
end

-- Everything here moves secure unit buttons, so it only ever runs out of combat (no frame passed to Combat.Run).

-- Settings or state changed: undo what EditTime did, then do it again from Blizzard's layout.
local function Refresh()
	Combat.Run(COMBAT_KEY, function()
		Restore()
		Apply()
	end)
end

-- Blizzard laid out the buttons inside layoutFrame: its layout is the truth for them now.
local function OnBlizzardLayout(layoutFrame)
	Forget(layoutFrame)
	Combat.Run(COMBAT_KEY, Apply)
end

ns.RegisterRefresher(Refresh)

-- Options -------------------------------------------------------------------------------------------------------------

local function PartyNeedsRaidStyle(system)
	if Systems.IsPartyFrames(system) and not Systems.UsesRaidStylePartyFrames(system) then
		return L.RAID_STYLE_ONLY_TOOLTIP
	end
	return nil
end

local function Option(order, field, label, appliesTo)
	ns.RegisterOption({
		kind = "checkbox",
		order = order,
		appliesTo = appliesTo,
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

Option(60, FIELD_HIDE_SELF, L.HIDE_OWN_FRAME, function(system)
	return Systems.IsPartyFrames(system) or Systems.IsRaidFrames(system)
end)
Option(61, FIELD_HIDE_TITLE, L.HIDE_PARTY_TITLE, Systems.IsPartyFrames)

-- Hooks ---------------------------------------------------------------------------------------------------------------

ns.OnReady(function()
	local manager = EditModeManagerFrame
	editModeActive = manager and manager.IsEditModeActive and manager:IsEditModeActive() or false

	-- Every Blizzard layout of the party frame and raid groups runs through CompactRaidGroup_UpdateLayout.
	if type(CompactRaidGroup_UpdateLayout) == "function" then
		hooksecurefunc("CompactRaidGroup_UpdateLayout", OnBlizzardLayout)
	end
	local container = CompactRaidFrameContainer
	if container and type(container.LayoutFrames) == "function" then
		hooksecurefunc(container, "LayoutFrames", OnBlizzardLayout)
	end

	-- Blizzard shows a button again when its unit is refreshed. A parked button goes straight back out of sight.
	-- In combat it stays parked off screen.
	if type(CompactUnitFrame_UpdateVisible) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateVisible", function(button)
			if parked[button] and button:IsShown() and not InCombatLockdown() then
				button:Hide()
			end
		end)
	end

	EventRegistry:RegisterCallback("EditMode.Enter", function()
		editModeActive = true
		Refresh()
	end, GroupLayout)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		editModeActive = false
		Refresh()
	end, GroupLayout)
end)
