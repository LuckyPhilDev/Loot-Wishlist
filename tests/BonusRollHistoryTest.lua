-- luacheck: ignore 111 121
-- Backfilling bonus rolls made before the addon was installed. The rule under
-- test is which bucket a backfilled roll lands in: a raid roll is on the boss
-- and a dungeon roll on the whole instance, which is what a live Mythic+ roll
-- records. Get that wrong and history written in the browser never meets the
-- history written by the game.

LootWishlist = {}
LootWishlistCharDB = {}
LuckyUI = { C = { textLight = { 0.910, 0.863, 0.784 } }, WC = {},
           DOT = "\194\183" }

local function noop() end
function CreateFrame()
  return setmetatable({}, { __index = function() return noop end })
end

C_Timer = { After = function() end }
Enum = { ItemSlotFilterType = {} }
function GetInstanceInfo() return "Somewhere", "none", 0 end

local PLAYER_CLASS = 8
function UnitClass() return "Mage", "MAGE", PLAYER_CLASS end

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Browser.lua")
dofile("src/LootWishlist_BonusRollOdds.lua")

local Browser = LootWishlist.Browser
local Odds = LootWishlist.BonusRollOdds
local state = Browser.testScanner.state
local passed = 0

local function check(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
  passed = passed + 1
end

local RAID = { id = 1320, name = "The Venomous Abyss", isRaid = true }
local DUNGEON = { id = 1270, name = "Ara-Kara", isRaid = false }
local BOSS = 2888

-- Which bucket a row writes to --------------------------------------------
local encounterID, instanceID = Browser.rollScope(RAID, BOSS)
check(encounterID, BOSS, "a raid roll is filed against the boss")
check(instanceID, nil, "and not against the raid")

encounterID, instanceID = Browser.rollScope(DUNGEON, BOSS)
check(encounterID, nil, "a dungeon roll names no boss")
check(instanceID, DUNGEON.id, "and is filed against the whole dungeon")

-- Which heading carries the stepper ----------------------------------------
state.classID = PLAYER_CLASS
state.history = true

local raidBoss = { kind = "boss", instance = RAID, encounterID = BOSS }
local raidHead = { kind = "instance", instance = RAID }
local dungeonBoss = { kind = "boss", instance = DUNGEON, encounterID = BOSS }
local dungeonHead = { kind = "instance", instance = DUNGEON }

check(Browser.ownsSpends(raidBoss), true, "a raid boss carries its own charges")
check(Browser.ownsSpends(raidHead), false, "the raid heading above it does not")
check(Browser.ownsSpends(dungeonHead), true, "a dungeon carries charges as a whole")
check(Browser.ownsSpends(dungeonBoss), false, "so its bosses do not")
check(Browser.ownsSpends({ kind = "item", instance = RAID }), false, "an item row never does")
check(Browser.ownsSpends({ kind = "boss", instance = RAID }), false,
  "nor a boss the journal named no encounter for")

state.history = false
check(Browser.ownsSpends(raidBoss), false, "no stepper while browsing loot")

state.history = true
state.classID = PLAYER_CLASS + 1
check(Browser.ownsSpends(raidBoss), false, "nor on another class's loot")
state.classID = PLAYER_CLASS

-- Writing history ----------------------------------------------------------
Odds.SetSpent(BOSS, nil, 3)
check(Odds.GetSpent(BOSS, nil), 3, "a typed-in count is remembered")

Odds.RecordSpend(BOSS, nil)
check(Odds.GetSpent(BOSS, nil), 4, "a live roll counts on top of it")

Odds.SetSpent(BOSS, nil, -2)
check(Odds.GetSpent(BOSS, nil), 0, "a count cannot go below zero")
check(LootWishlistCharDB.bonusRollSpends[BOSS], nil, "and zero leaves no record behind")

Odds.SetWon(55, BOSS, nil, true)
check(Odds.HasWon(55, BOSS, nil), true, "an item ticked as won reads back won")

Odds.SetWon(55, BOSS, nil, false)
check(Odds.HasWon(55, BOSS, nil), false, "a mis-tick can be taken off again")
check(LootWishlistCharDB.bonusRollWins[BOSS], nil, "and the emptied boss leaves no record")

-- A dungeon win is filed against the instance, so the odds for a boss inside
-- it must find it there.
Odds.SetWon(77, nil, DUNGEON.id, true)
check(Odds.HasWon(77, BOSS, DUNGEON.id), true, "a dungeon win covers its bosses too")

print("BonusRollHistoryTest: " .. passed .. " checks passed")
