-- Combat-safe execution: anything that changes frame geometry or visibility goes through Combat.Run.
-- Work that cannot run now is queued (one entry per key, latest wins) and flushed when combat ends.
local _, ns = ...

local InCombatLockdown = InCombatLockdown
local pcall, next, geterrorhandler = pcall, next, geterrorhandler

local Combat = {}
ns.Combat = Combat

local pending = {}      -- [key] = fn
local eventFrame = CreateFrame("Frame")

local function SafeCall(fn)
	local ok, err = pcall(fn)
	if not ok then
		geterrorhandler()(err)
	end
end

-- key:   any value used to dedupe (normally the frame being changed)
-- fn:    the work
-- frame: optional; if given and not protected, the work may run even in combat
function Combat.Run(key, fn, frame)
	local canRunNow = not InCombatLockdown()
	if not canRunNow and frame and frame.IsProtected then
		local isProtected = frame:IsProtected()
		canRunNow = not isProtected
	end

	if canRunNow then
		pending[key] = nil
		SafeCall(fn)
	else
		pending[key] = fn
		eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
end

function Combat.Cancel(key)
	pending[key] = nil
end

eventFrame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local queue = pending
	pending = {}
	for _, fn in next, queue do
		SafeCall(fn)
	end
end)
