-- luacheck: ignore 111 121

LootWishlist = {}
LootWishlistCharDB = {}

C_Timer = { After = function() end }
function CreateFrame()
    return setmetatable({}, { __index = function() return function() end end })
end
function GetInstanceInfo() return "Somewhere", "none", 0 end
function UnitClass() return "Mage", "MAGE", 8 end

local SPEC_NAMES = { [62] = "Arcane", [63] = "Fire", [64] = "Frost" }
function GetSpecializationInfoByID(specID) return specID, SPEC_NAMES[specID] end

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_BonusRollOdds.lua")

local Odds = LootWishlist.BonusRollOdds
local passed = 0

local function check(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
    passed = passed + 1
end

local function contains(text, needle, label)
    if not text:find(needle, 1, true) then
        error(string.format("%s: %q does not contain %q", label, text, needle))
    end
    passed = passed + 1
end

local SPECS = { 62, 63, 64 }

-- itemID -> specs it drops for; 4 is open to every spec.
local ITEM_SPECS = {
    [1] = { 62 },
    [2] = { 63 },
    [3] = { 63, 64 },
    [4] = {},
}
local function specsOf(itemID) return ITEM_SPECS[itemID] end
local function wantedIs(set)
    return function(itemID) return set[itemID] == true end
end

local items = { { itemID = 1 }, { itemID = 2 }, { itemID = 3 }, { itemID = 4 } }

-- Tally ---------------------------------------------------------------------
local tally = Odds.Tally(items, SPECS, wantedIs({ [2] = true, [4] = true }), specsOf)

check(tally[62].total, 2, "arcane table size")   -- item 1 and the open item
check(tally[62].wanted, 1, "arcane wanted")      -- only the open item
check(tally[63].total, 3, "fire table size")     -- items 2, 3 and the open item
check(tally[63].wanted, 2, "fire wanted")
check(tally[64].total, 2, "frost table size")
check(tally[64].wanted, 1, "frost wanted")

-- Best spec -----------------------------------------------------------------
check(Odds.Best(tally, SPECS, 62), 63, "fire beats arcane")
check(Odds.Best(tally, SPECS, 63), nil, "fire is already the best")

local noneWanted = Odds.Tally(items, SPECS, wantedIs({}), specsOf)
check(Odds.Best(noneWanted, SPECS, 62), nil, "nothing wanted suggests nothing")

-- Describe ------------------------------------------------------------------
local text = Odds.Describe(tally, SPECS, 62, 3)
contains(text, "1|r of 2 items", "current spec share")
contains(text, "Charges spent here", "spend count")
contains(text, "Fire", "better spec named")
check(select(2, text:gsub("\n", "\n")), 2, "three lines")

local quiet = Odds.Describe(tally, SPECS, 63, 0)
check(quiet:find("\n"), nil, "no spend line and no better spec")

local empty = Odds.Describe({ [62] = { total = 0, wanted = 0 } }, { 62 }, 62, 0)
contains(empty, "No loot table", "empty table")

local nothing = Odds.Describe({ [62] = { total = 7, wanted = 0 } }, { 62 }, 62, 0)
contains(nothing, "None of the 7", "nothing wanted")

-- Spends --------------------------------------------------------------------
check(Odds.GetSpent(1234, 0), 0, "nothing spent yet")
Odds.RecordSpend(1234, 0)
Odds.RecordSpend(1234, 0)
check(Odds.GetSpent(1234, 0), 2, "two rolls on the boss")
check(Odds.GetSpent(nil, 55), 0, "the dungeon is counted apart")
Odds.RecordSpend(nil, 55)
check(Odds.GetSpent(0, 55), 1, "dungeon roll counted")
Odds.RecordSpend(nil, nil)
check(Odds.GetSpent(nil, nil), 0, "a roll with no boss or dungeon is not counted")

-- A smaller table with the same want in it is the better roll ---------------
local PROT, RET = 66, 70
SPEC_NAMES[PROT], SPEC_NAMES[RET] = "Protection", "Retribution"
local paladinItems = {
    { itemID = 10 },  -- the boots, wanted, on both tables
    { itemID = 11 },
    { itemID = 12 },
    { itemID = 13 },  -- shield, Protection only
}
local PALADIN_SPECS = { PROT, RET }
local paladinSpecs = {
    [10] = { PROT, RET }, [11] = { PROT, RET }, [12] = { PROT, RET }, [13] = { PROT },
}
local boots = Odds.Tally(paladinItems, PALADIN_SPECS, wantedIs({ [10] = true }),
    function(itemID) return paladinSpecs[itemID] end)

check(boots[PROT].total, 4, "protection sees four items")
check(boots[RET].total, 3, "retribution sees three")
check(Odds.Best(boots, PALADIN_SPECS, PROT), RET, "retribution is the better roll")
check(Odds.Best(boots, PALADIN_SPECS, RET), nil, "retribution has nothing better to move to")
contains(Odds.Describe(boots, PALADIN_SPECS, PROT, 0), "Retribution", "the better spec is named")

-- ForRoll -------------------------------------------------------------------
function GetNumSpecializations() return 3 end
function GetSpecializationInfo(index) return SPECS[index] end
function GetLootSpecialization() return 63 end
LootWishlist.GetCurrentEJInstanceID = function() return 1200 end
LootWishlist.GetTracked = function() return { [2] = { id = 2 } } end

local table1200 = nil
LootWishlist.Browser = { RequestLoot = function() return table1200 end }

check(select(1, Odds.ForRoll(9001, 0, false)), LootWishlist.Strings.bonusRollOdds.reading,
    "an unread table says so")
check(select(2, Odds.ForRoll(9001, 0, false)), false, "an unread table is not ready")
check(Odds.ForRoll(9001, 0, true), "", "giving up on an unread table says nothing")

table1200 = { items = {
    { itemID = 1, encounterID = 9001 },
    { itemID = 2, encounterID = 9001 },
    { itemID = 3, encounterID = 9002 },
} }
local rollText, rollReady = Odds.ForRoll(9001, 0, false)
check(rollReady, true, "a read table is ready")
contains(rollText, "1|r of 2 items", "only the rolled boss's items count")

print("BonusRollOddsTest: " .. passed .. " checks passed")
