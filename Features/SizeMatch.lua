-- Match Width / Match Height: an Edit Mode system keeps its on-screen width or height equal to another system's.
--
-- "stretch" systems resize each dimension directly. "scale" systems (icon-based: bags, micro menu) scale
-- uniformly to reach the target size, so they can follow either width or height, never both at once.
local _, ns = ...

local Systems, Layouts, Combat = ns.Systems, ns.Layouts, ns.Combat

local SizeMatch = {}
ns.SizeMatch = SizeMatch

local DIMENSIONS = { "width", "height" }
local FIELD = { width = "widthMatch", height = "heightMatch" }
local SIZE_EPSILON, SCALE_EPSILON = 0.05, 0.0005

local hooksecurefunc, ipairs, pairs, type, abs = hooksecurefunc, ipairs, pairs, type, math.abs

local modified = setmetatable({}, { __mode = "k" })     -- [frame] = { width = true, height = true, scale = true }
local sourceHooked = setmetatable({}, { __mode = "k" })
local targetHooked = setmetatable({}, { __mode = "k" })

local function GetSize(frame, dimension)
	if dimension == "width" then
		return frame:GetWidth()
	end
	return frame:GetHeight()
end

-- Rules ---------------------------------------------------------------------------------------------------------------

function SizeMatch.GetTarget(sourceKey, dimension)
	return Layouts.Get(sourceKey, FIELD[dimension])
end

-- True if sourceKey would end up depending on its own size through targetKey. Width and height count as one
-- graph, because a scaled system's width and height change together.
function SizeMatch.WouldCycle(sourceKey, targetKey)
	local visited = {}
	local function Reaches(key)
		if key == sourceKey then return true end
		if visited[key] then return false end
		visited[key] = true
		for _, dimension in ipairs(DIMENSIONS) do
			local nextKey = Layouts.Get(key, FIELD[dimension])
			if nextKey and Reaches(nextKey) then return true end
		end
		return false
	end
	return Reaches(targetKey)
end

function SizeMatch.SetTarget(sourceKey, dimension, targetKey, adapter)
	if targetKey and SizeMatch.WouldCycle(sourceKey, targetKey) then
		return
	end
	Layouts.Set(sourceKey, FIELD[dimension], targetKey)

	-- One scale can't satisfy two targets: picking one dimension clears the other.
	if targetKey and adapter and adapter.mode == "scale" then
		local other = dimension == "width" and "height" or "width"
		Layouts.Set(sourceKey, FIELD[other], nil)
	end
	ns.RequestRefresh()
end

-- Hooks ---------------------------------------------------------------------------------------------------------------

local function HookScale(frame)
	-- Edit Mode systems replace SetScale with their own field. Hooking it catches every scale setting change.
	if type(frame.SetScale) == "function" then
		hooksecurefunc(frame, "SetScale", ns.RequestRefresh)
	end
end

local function HookTarget(frame)
	if targetHooked[frame] then return end
	targetHooked[frame] = true
	frame:HookScript("OnSizeChanged", ns.RequestRefresh)
	HookScale(frame)
end

local function HookSource(frame, adapter)
	if sourceHooked[frame] then return end
	sourceHooked[frame] = true
	for _, method in ipairs(adapter.hooks) do
		if type(frame[method]) == "function" then
			hooksecurefunc(frame, method, ns.RequestRefresh)
		end
	end
	HookScale(frame)
	if adapter.mode == "scale" then
		-- A scaled system's own size (button count, orientation) decides the scale it needs.
		frame:HookScript("OnSizeChanged", ns.RequestRefresh)
	end
end

-- Scale ---------------------------------------------------------------------------------------------------------------

-- Sets a system frame's scale without running EditModeSystemMixin:SetScaleOverride. That override is Lua that
-- writes Edit Mode state, which would be tainted if run from here. SetScaleBase and SetPointBase are the
-- original widget methods. The frame's position is kept the same way the override keeps it.
local function SetScaleKeepingPosition(frame, newScale)
	local setScale = frame.SetScaleBase or frame.SetScale
	local setPoint = frame.SetPointBase or frame.SetPoint
	local oldScale = frame:GetScale()
	if abs(oldScale - newScale) < SCALE_EPSILON then return end

	local points = {}
	for i = 1, frame:GetNumPoints() do
		points[i] = { frame:GetPoint(i) }
	end

	setScale(frame, newScale)

	for _, p in ipairs(points) do
		setPoint(frame, p[1], p[2], p[3], (p[4] or 0) * oldScale / newScale, (p[5] or 0) * oldScale / newScale)
	end
end

-- Apply ---------------------------------------------------------------------------------------------------------------

local function Mark(frame, what, value)
	local m = modified[frame]
	if not m then
		if not value then return end
		m = {}
		modified[frame] = m
	end
	m[what] = value or nil
end

local function IsModified(frame, what)
	local m = modified[frame]
	return m ~= nil and m[what] == true
end

-- The target's size in the source frame's coordinate space, or nil if the target has no size yet.
local function TargetSizeFor(source, target, dimension)
	local size = GetSize(target, dimension)
	local targetScale, sourceScale = target:GetEffectiveScale(), source:GetEffectiveScale()
	if not (size and size > 0 and sourceScale and sourceScale > 0) then
		return nil
	end
	return size * targetScale / sourceScale
end

local function ApplyStretch(frame, adapter, dimension, target)
	local handler = adapter[dimension]
	if not handler then return end

	if target then
		local size = TargetSizeFor(frame, target, dimension)
		if not size then return end -- keep the last good size
		if IsModified(frame, dimension) and abs(GetSize(frame, dimension) - size) < SIZE_EPSILON then
			return
		end
		Combat.Run(frame, function()
			Mark(frame, dimension, true)
			handler.apply(frame, size)
		end, frame)
	elseif IsModified(frame, dimension) then
		Combat.Run(frame, function()
			Mark(frame, dimension, false)
			handler.restore(frame)
		end, frame)
	end
end

local function ApplyScale(frame, adapter, dimension, target)
	if target then
		local ownSize = GetSize(frame, dimension)
		local targetSize = GetSize(target, dimension)
		local parent = frame:GetParent()
		local parentScale = parent and parent:GetEffectiveScale() or 1
		if not (ownSize and ownSize > 0 and targetSize and targetSize > 0 and parentScale > 0) then
			return -- keep the last good scale
		end
		local scale = targetSize * target:GetEffectiveScale() / (ownSize * parentScale)
		Combat.Run(frame, function()
			Mark(frame, "scale", true)
			SetScaleKeepingPosition(frame, scale)
		end, frame)
	elseif IsModified(frame, "scale") then
		Combat.Run(frame, function()
			Mark(frame, "scale", false)
			SetScaleKeepingPosition(frame, adapter.naturalScale(frame))
		end, frame)
	end
end

local function Refresh()
	for _, frame in ipairs(Systems.GetRegistered()) do
		local adapter = Systems.GetSizeAdapter(frame)
		if adapter and frame.systemInfo ~= nil then
			HookSource(frame, adapter)

			local sourceKey = Systems.KeyFor(frame)
			local blocked = adapter.blockedReason(frame) ~= nil
			local targets = {}
			for _, dimension in ipairs(DIMENSIONS) do
				local targetKey = not blocked and SizeMatch.GetTarget(sourceKey, dimension)
				local target = targetKey and Systems.FrameFor(targetKey)
				if target and target ~= frame then
					HookTarget(target)
					targets[dimension] = target
				end
			end

			if adapter.mode == "scale" then
				if targets.width then
					ApplyScale(frame, adapter, "width", targets.width)
				else
					ApplyScale(frame, adapter, "height", targets.height)
				end
			else
				for _, dimension in ipairs(DIMENSIONS) do
					ApplyStretch(frame, adapter, dimension, targets[dimension])
				end
			end
		end
	end
end

ns.RegisterRefresher(Refresh)

-- Panel rows ----------------------------------------------------------------------------------------------------------

local LABELS = { width = "MATCH_WIDTH", height = "MATCH_HEIGHT" }

for order, dimension in ipairs(DIMENSIONS) do
	ns.RegisterOption({
		kind = "dropdown",
		order = 10 + order,
		appliesTo = function(system)
			return Systems.SupportsDimension(Systems.GetSizeAdapter(system), dimension)
		end,
		label = function()
			return ns.L[LABELS[dimension]]
		end,
		disabledReason = function(system)
			return Systems.GetSizeAdapter(system).blockedReason(system)
		end,
		get = function(system)
			return SizeMatch.GetTarget(Systems.KeyFor(system), dimension) or false
		end,
		set = function(system, value)
			SizeMatch.SetTarget(Systems.KeyFor(system), dimension, value or nil, Systems.GetSizeAdapter(system))
		end,
		choices = function(system)
			local sourceKey = Systems.KeyFor(system)
			local current = SizeMatch.GetTarget(sourceKey, dimension)
			local list = { { value = false, text = NONE } }
			for _, entry in ipairs(Systems.List()) do
				local eligible = entry.key ~= sourceKey
					and (entry.frame:IsShown() or entry.key == current)
					and not SizeMatch.WouldCycle(sourceKey, entry.key)
				if eligible then
					list[#list + 1] = { value = entry.key, text = entry.name }
				end
			end
			return list
		end,
	})
end

-- Hook every target that any stored rule references, even for systems not loaded yet when a rule was saved.
ns.OnReady(function()
	for _, entries in pairs(ns.db.layouts) do
		for _, entry in pairs(entries) do
			for _, field in pairs(FIELD) do
				local target = entry[field] and Systems.FrameFor(entry[field])
				if target then HookTarget(target) end
			end
		end
	end
end)
