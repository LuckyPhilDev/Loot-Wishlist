-- luacheck: ignore 121

LootWishlist = {}
LuckyUI = { C = {}, WC = {} }
LuckyLog = { New = function() return function() end end }

local now = 0
function GetTime() return now end

local timers = {}
C_Timer = { After = function(delay, fn) table.insert(timers, { at = now + delay, fn = fn }) end }

local function advance(seconds)
    now = now + seconds
    local due, pending = {}, {}
    for _, t in ipairs(timers) do
        if t.at <= now then table.insert(due, t) else table.insert(pending, t) end
    end
    timers = pending
    for _, t in ipairs(due) do t.fn() end
end

-- Empty bags and no gear: every scan counts zero, so nothing looks like a gain
C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemInfo = function() return nil end,
}
function GetInventoryItemID() return nil end

dofile("src/LootWishlist_Constants.lua")
dofile("src/LootWishlist_UI.lua")
dofile("src/LootWishlist_Alerts.lua")

function LootWishlist.GetTracked() return { ["100@16"] = { id = 100, link = "item:100:318" } } end

local fire = LootWishlist.Alerts.HandleEvent
local settling = LootWishlist.Alerts.BagsSettling
local passed = 0

local function check(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
    passed = passed + 1
end

fire(nil, "PLAYER_ENTERING_WORLD")
check(settling(), true, "the loading screen arms the guard")

-- A wave landing late still counts as loading, and pushes the window out with it
advance(2)
fire(nil, "BAG_UPDATE_DELAYED")
advance(2)
check(settling(), true, "a late bag wave extends the window")

advance(2)
check(settling(), false, "the guard lifts once the bags fall quiet")

print(string.format("BagSettleTest: %d checks passed", passed))
