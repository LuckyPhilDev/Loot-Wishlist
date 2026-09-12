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
contains(text, "(1 of the 2 that can drop for you)", "current spec share")
contains(text, "50%|r chance", "the chance leads")
contains(text, "Charges spent here", "spend count")
contains(text, "Fire", "better spec named")
check(select(2, text:gsub("\n", "\n")), 3, "the count sits under the chance, over spend and better spec")

local quiet = Odds.Describe(tally, SPECS, 63, 0)
check(select(2, quiet:gsub("\n", "\n")), 1, "no spend line and no better spec")

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
-- itemID -> specs the journal files it under; nil files everything under every spec.
local journalSpecs = nil
local lastRequest = {}
LootWishlist.Browser = { RequestLoot = function(instanceID, isRaid, diffID, classID, specID)
    lastRequest = { instanceID = instanceID, isRaid = isRaid, diffID = diffID,
        classID = classID, specID = specID }
    if not (table1200 and journalSpecs) or specID == 0 then return table1200 end
    local items = {}
    for _, item in ipairs(table1200.items) do
        local specs = journalSpecs[item.itemID]
        local open = not specs or #specs == 0
        for _, s in ipairs(specs or {}) do open = open or s == specID end
        if open then items[#items + 1] = item end
    end
    return { items = items }
end }

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
contains(rollText, "(1 of the 2 that can drop for you)", "only the rolled boss's items count")
contains(rollText, "this boss", "a raid roll names the boss")
contains(select(1, Odds.ForRoll(0, 1200, false)), "this dungeon", "a dungeon roll names the dungeon")

-- Wins leave the table -------------------------------------------------------
LootWishlist.IsObtained = function() return false end

local fiveItems = { { itemID = 1 }, { itemID = 2 }, { itemID = 3 }, { itemID = 4 }, { itemID = 5 } }
local threeWanted = wantedIs({ [1] = true, [2] = true, [3] = true })
local openSpecs = function() return nil end

local before = Odds.Tally(fiveItems, { 62 }, threeWanted, openSpecs, Odds.Won(9500, 0))
check(before[62].total, 5, "nothing won yet leaves five in the table")
check(before[62].wanted, 3, "three of them wanted")

Odds.RecordWin(4, 9500, 0)
check(Odds.HasWon(4, 9500, 0), true, "the won item is remembered")
local after = Odds.Tally(fiveItems, { 62 }, threeWanted, openSpecs, Odds.Won(9500, 0))
check(after[62].total, 4, "the won item leaves the table")
check(after[62].wanted, 3, "the three you still want are untouched")
check(math.floor(Odds.Ratio(after[62]) * 100 + 0.5), 75, "three of four is 75%")

LootWishlist.IsObtained = function(id) return id == 5 end
check(Odds.Won(9500, 0)(5), false, "an item marked obtained can still come out of a roll")
LootWishlist.IsObtained = function() return false end

-- A dungeon win counts against every boss inside it --------------------------
Odds.RecordWin(5, nil, 4200)
check(Odds.HasWon(5, 9501, 4200), true, "a dungeon win covers its bosses")
check(Odds.HasWon(5, 9501, 0), false, "and not some other dungeon's")

-- The reward's item link is what gets filed ---------------------------------
local link = "|cffa335ee|Hitem:12345::::::::80:::::|h[Thing]|h|r"
Odds.OnRollResult(link)
check(Odds.HasWon(12345, 9600, 0), false, "a result with no roll behind it is ignored")

Odds.NoteRoll(9600, 0)
Odds.OnRollResult(link)
check(Odds.HasWon(12345, 9600, 0), true, "the reward is filed against the boss rolled on")
check(Odds.GetSpent(9600, 0), 1, "and the charge is counted once")

Odds.OnRollResult(nil)
check(Odds.HasWon(0, 9600, 0), false, "a currency reward files nothing")

-- Mythic+ --------------------------------------------------------------------
-- A keystone run rolls on the whole dungeon, so the popup carries no encounter
-- and the journal is read at Mythic, the table Mythic+ actually pays out from.
function GetInstanceInfo() return "Some Dungeon", "party", 8 end
LootWishlist.GetTracked = function() return { [1] = { id = 1 }, [3] = { id = 3 } } end
table1200 = { items = {
    { itemID = 1, encounterID = 9001 },
    { itemID = 2, encounterID = 9001 },
    { itemID = 3, encounterID = 9002 },
    { itemID = 4, encounterID = 9002 },
} }

local keyText, keyReady = Odds.ForRoll(0, 1200, false)
check(keyReady, true, "the keystone table reads")
check(lastRequest.diffID, 23, "a keystone run is read at Mythic")
check(lastRequest.isRaid, false, "and not as a raid")
contains(keyText, "this dungeon", "a keystone roll names the dungeon")
contains(keyText, "(2 of the 4 that can drop for you)", "every boss in the dungeon counts")
contains(keyText, "50%|r chance", "two of four is 50%")

Odds.NoteRoll(0, 1200)
Odds.OnRollResult("|cffa335ee|Hitem:2::::::::80:::::|h[Spare]|h|r")
check(Odds.GetSpent(0, 1200), 1, "the charge is counted against the dungeon")
contains(select(1, Odds.ForRoll(0, 1200, false)), "(2 of the 3 that can drop for you)",
    "what the keystone roll gave leaves the dungeon table")
Odds.RecordWin(4, nil, 1200)
contains(select(1, Odds.ForRoll(9002, 1200, false)), "(1 of the 1 that can drop for you)",
    "a dungeon win leaves the table of a boss inside it too")


-- Upcoming bosses ------------------------------------------------------------
-- Spec reach comes from the journal's per-spec tables alone. Item spec info
-- returns nothing for uncached items, so it must not be what decides it.
C_Item = { GetItemSpecInfo = function() return nil end }
journalSpecs = ITEM_SPECS
function GetInstanceInfo() return "The Venomous Abyss", "raid", 16 end
LootWishlist.GetTracked = function() return { [1] = { id = 1 }, [3] = { id = 3 } } end

local upcoming = {
    { encounterID = 2888, name = "Nek'zali" },
    { encounterID = 2874, name = "Sszorak" },
}

table1200 = nil
check(select(2, Odds.ForUpcoming(1320, upcoming)), false, "an unread table is not ready")

table1200 = { items = {
    { itemID = 1, encounterID = 2888 },
    { itemID = 2, encounterID = 2888 },
    { itemID = 3, encounterID = 2874 },
    { itemID = 4, encounterID = 2874 },
} }

local upcomingOdds, upcomingReady = Odds.ForUpcoming(1320, upcoming)
check(upcomingReady, true, "a read table is ready")
check(upcomingOdds[2888].percent, 0, "Fire wants nothing from the first boss")
check(upcomingOdds[2888].total, 1, "and only one of its items can drop for Fire at all")
check(upcomingOdds[2888].best.name, "Arcane", "Arcane holds what Fire cannot be given")
check(upcomingOdds[2888].best.percent, 100, "and holds all of its own table")
check(upcomingOdds[2874].percent, 50, "Fire wants one of the two on the second boss")
check(upcomingOdds[2874].best, nil, "no spec beats Fire there")

local barren = Odds.ForUpcoming(1320, { { encounterID = 9999, name = "Nobody" } })
check(barren[9999].total, 0, "a boss with nothing on it counts nothing")
check(barren[9999].best, nil, "and points at no other spec")

print("BonusRollOddsTest: " .. passed .. " checks passed")
