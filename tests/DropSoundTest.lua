-- luacheck: ignore 121

LootWishlist = {}

SOUNDKIT = { UI_LEGENDARY_LOOT_TOAST = 1, UI_EPICLOOT_TOAST = 2 }
local now = 0
function GetTime() return now end

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Alerts.lua")

local settings = {}
function LootWishlist.GetSettings() return settings end

local soundKit = LootWishlist.Alerts.DropSoundKit
local passed = 0

local function check(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
    passed = passed + 1
end

check(soundKit(true, 100), SOUNDKIT.UI_LEGENDARY_LOOT_TOAST, "self drop plays the big toast")
check(soundKit(false, 200), SOUNDKIT.UI_EPICLOOT_TOAST, "someone else's drop plays the lesser toast")

-- Chat and encounter loot both fire for one drop; the second event stays quiet
check(soundKit(true, 100), nil, "same item inside the silence window")
now = 11
check(soundKit(true, 100), SOUNDKIT.UI_LEGENDARY_LOOT_TOAST, "same item after the silence window")

settings.enableDropSound = false
check(soundKit(true, 300), nil, "toggle off silences a fresh item")

print(string.format("DropSoundTest: %d checks passed", passed))
