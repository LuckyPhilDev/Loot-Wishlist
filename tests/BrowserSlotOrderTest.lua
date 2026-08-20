-- luacheck: ignore 111 121

LootWishlist = {}
LuckyUI = { C = {}, WC = {} }

local function noop() end
function CreateFrame()
  return setmetatable({}, { __index = function() return noop end })
end

-- The client sets these before addons load; the slot order is keyed off them.
INVTYPE_HEAD = "Head"
INVTYPE_NECK = "Neck"
INVTYPE_SHOULDER = "Shoulder"
INVTYPE_CLOAK = "Back"
INVTYPE_CHEST = "Chest"
INVTYPE_ROBE = "Chest"
INVTYPE_BODY = "Shirt"
INVTYPE_TABARD = "Tabard"
INVTYPE_WRIST = "Wrist"
INVTYPE_HAND = "Hands"
INVTYPE_WAIST = "Waist"
INVTYPE_LEGS = "Legs"
INVTYPE_FEET = "Feet"
INVTYPE_FINGER = "Finger"
INVTYPE_TRINKET = "Trinket"
INVTYPE_WEAPONMAINHAND = "Main Hand"
INVTYPE_WEAPON = "One-Hand"
INVTYPE_2HWEAPON = "Two-Hand"
INVTYPE_WEAPONOFFHAND = "Off Hand"
INVTYPE_SHIELD = "Off Hand"
INVTYPE_HOLDABLE = "Held In Off-hand"
INVTYPE_RANGED = "Ranged"
INVTYPE_RANGEDRIGHT = "Ranged"
INVTYPE_THROWN = "Thrown"
INVTYPE_RELIC = "Relic"

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Browser.lua")

local sorted = LootWishlist.Browser.sortSlots({
  "Trinket", "Two-Hand", "Back", "Head", "Other", "Held In Off-hand",
  "Finger", "One-Hand", "Chest", "Waist", "Neck",
})

local expected = {
  "Head", "Neck", "Back", "Chest", "Waist", "Finger", "Trinket",
  "Other", "One-Hand", "Two-Hand", "Held In Off-hand",
}

for i, slot in ipairs(expected) do
  assert(sorted[i] == slot,
    string.format("position %d: expected %s, got %s", i, slot, tostring(sorted[i])))
end
assert(#sorted == #expected, "slot count changed during sort")

print("1 browser slot order test passed")
