-- luacheck: ignore 111 121
-- The Roll History notice asks once, and only a character with no roll on
-- record. Asking a player who already has history, or asking twice, is the
-- nag this guards against.

LootWishlist = {}
LootWishlistCharDB = {}

C_Timer = { After = function() end }
function CreateFrame()
  return setmetatable({}, { __index = function() return function() end end })
end
function GetInstanceInfo() return "Somewhere", "none", 0 end
function UnitClass() return "Mage", "MAGE", 8 end

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_BonusRollOdds.lua")
dofile("src/RollHistoryNotice.lua")

local Notice = LootWishlist.RollHistoryNotice
local Odds = LootWishlist.BonusRollOdds
local passed = 0

local function check(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
  passed = passed + 1
end

check(Notice.ShouldShow({}, false), true, "a character with no rolls on record is asked")
check(Notice.ShouldShow({}, true), false, "one with history already is not")
check(Notice.ShouldShow({ rollHistoryNoticeDone = true }, false), false, "nor one who answered")

check(Odds.HasHistory(), false, "a fresh character has no history")
Odds.RecordSpend(2888, nil)
check(Odds.HasHistory(), true, "a counted spend is history")
Odds.SetSpent(2888, nil, 0)
check(Odds.HasHistory(), false, "taking it back to zero leaves none")
Odds.SetWon(55, nil, 1270, true)
check(Odds.HasHistory(), true, "a ticked win is history on its own")
Odds.SetWon(55, nil, 1270, false)

Notice.Acknowledge()
check(LootWishlistCharDB.rollHistoryNoticeDone, true, "answering is remembered for the character")
check(Notice.ShouldShow(LootWishlistCharDB, Odds.HasHistory()), false, "and the notice stays gone")

print("RollHistoryNoticeTest: " .. passed .. " checks passed")
