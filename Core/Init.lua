local addonName, ns = ...

local DB_VERSION = 1

local DEFAULTS = {
	version = DB_VERSION,
	layouts = {},      -- committed settings: [layoutKey][systemKey] = { widthMatch = systemKey|nil, visibility = 0..3 }
}

-- Run once the saved variables are loaded. Modules register with ns.OnReady(fn).
local readyCallbacks = {}
function ns.OnReady(fn)
	if readyCallbacks then
		readyCallbacks[#readyCallbacks + 1] = fn
	else
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

-- Coalesced refresh: any number of requests within a frame produce one pass over all refreshers.
local refreshers = {}
local refreshQueued = false

function ns.RegisterRefresher(fn)
	refreshers[#refreshers + 1] = fn
end

local function RunRefreshers()
	refreshQueued = false
	if not ns.db then return end
	for _, fn in ipairs(refreshers) do
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

function ns.RequestRefresh()
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, RunRefreshers)
end

-- Settings shown in the Edit Mode panel. Each feature registers its own; see UI/SettingsPanel.lua for the fields.
ns.options = {}

function ns.RegisterOption(option)
	ns.options[#ns.options + 1] = option
	table.sort(ns.options, function(a, b) return a.order < b.order end)
end

local function Migrate(db)
	if type(db.layouts) ~= "table" then
		db.layouts = {}
	end
	-- Future migrations go here, keyed on db.version.
	db.version = DB_VERSION
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, _, loadedName)
	if loadedName ~= addonName then return end
	self:UnregisterEvent("ADDON_LOADED")

	if type(EditTimeDB) ~= "table" then
		EditTimeDB = CopyTable(DEFAULTS)
	end
	Migrate(EditTimeDB)
	ns.db = EditTimeDB

	for _, fn in ipairs(readyCallbacks) do
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
	readyCallbacks = nil

	-- Load-on-demand Blizzard addons (e.g. the Cooldown Viewer) register Edit Mode systems after us.
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:SetScript("OnEvent", function()
		ns.RequestRefresh()
	end)
	ns.RequestRefresh()
end)
