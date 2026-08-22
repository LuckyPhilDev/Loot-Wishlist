-- luacheck: ignore 111 121
-- Marking an item obtained moves its entries out of the tracked table, which is
-- what silences every consumer that iterates the wishlist.

LootWishlist = {}
LootWishlistDB = {}
LootWishlistCharDB = {}

LuckyLog = { New = function() return function() end end }

local onEvent
function CreateFrame()
  return {
    RegisterEvent = function() end,
    SetScript = function(_, script, fn) if script == "OnEvent" then onEvent = fn end end,
  }
end
function debugprofilestop() return 0 end
SlashCmdList = {}

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Constants.lua")
dofile("src/LootWishlist_LootParser.lua")
dofile("src/LootWishlist_Core.lua")

assert(onEvent, "Core should register an event handler")
onEvent(nil, "ADDON_LOADED", "LootWishlist")

local Parser  = LootWishlist.LootParser
local tracked = LootWishlist.GetTracked()
local got     = LootWishlist.GetObtained()

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local checks = 0
local function check(cond, why)
  assert(cond, why)
  checks = checks + 1
end

-- Two difficulties of the same item, plus one unrelated item.
LootWishlist.AddTrackedItemQuiet(207168, "Boss", "Amirdrassil", true, nil, 1, 2, 14, "Normal")
LootWishlist.AddTrackedItemQuiet(207168, "Boss", "Amirdrassil", true, nil, 1, 2, 15, "Heroic")
LootWishlist.AddTrackedItemQuiet(190000, "Other", "Amirdrassil", true, nil, 1, 2, 14, "Normal")
check(count(tracked) == 3, "three entries tracked to begin with")
check(count(got) == 0, "nothing obtained to begin with")

-- Obtaining is per item, so both difficulties move together.
LootWishlist.SetObtained(207168, true)
check(count(tracked) == 1, "only the unrelated item is still tracked")
check(count(got) == 2, "both difficulties moved across")
check(got["207168@14"] and got["207168@15"], "entries keep their keys")
check(LootWishlist.IsObtained(207168), "the item reads as obtained")
check(not LootWishlist.IsObtained(190000), "the untouched item does not")

-- Consumers that iterate the wishlist stop seeing it, which is what stops the
-- alert on a second drop.
check(not Parser:IsTracked(tracked, 207168), "an obtained item is not tracked")
check(Parser:IsTracked(tracked, 190000), "the untouched item still is")

-- Un-ticking puts it back with its difficulties intact.
LootWishlist.SetObtained(207168, false)
check(count(tracked) == 3, "both difficulties came back")
check(count(got) == 0, "nothing left behind")
check(tracked["207168@15"].difficultyName == "Heroic", "the entry survived the round trip")

-- Tracking an item again is the other way to take back an obtained mark.
LootWishlist.SetObtained(207168, true)
LootWishlist.AddTrackedItemQuiet(207168, "Boss", "Amirdrassil", true, nil, 1, 2, 16, "Mythic")
check(count(got) == 0, "re-adding clears the obtained copies")
check(count(tracked) == 2, "the re-added entry is the only one for that item")

-- Removing reaches an obtained item, so the × on a greyed row still works.
LootWishlist.SetObtained(207168, true)
LootWishlist.RemoveTrackedItem(207168)
check(count(got) == 0, "removing clears the obtained entry")
check(count(tracked) == 1, "the unrelated item is untouched")

-- Clear All takes both tables.
LootWishlist.AddTrackedItemQuiet(207168, "Boss", "Amirdrassil", true, nil, 1, 2, 14, "Normal")
LootWishlist.SetObtained(207168, true)
LootWishlist.ClearAllTracked()
check(count(tracked) == 0 and count(got) == 0, "clear all empties both tables")

print(checks .. " obtained tests passed")
