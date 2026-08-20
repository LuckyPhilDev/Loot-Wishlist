-- luacheck: ignore 111 121
-- A prerequisite pointing at an ID that is not a boss of that raid gates
-- nothing and says nothing: the reminder just goes back to offering every
-- boss. Typos have to fail here, since in game they look like working code.

LootWishlist = {}
dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Constants.lua")

local layouts = LootWishlist.Const.RAID_LAYOUTS
local checks = 0

for instanceID, bosses in pairs(layouts) do
  local reachable = {}

  local function reaches(encounterID, seen)
    if reachable[encounterID] then return true end
    assert(not seen[encounterID],
      string.format("raid %d: boss %d is its own prerequisite", instanceID, encounterID))
    seen[encounterID] = true
    for _, requiredID in ipairs(bosses[encounterID]) do
      assert(bosses[requiredID],
        string.format("raid %d: boss %d requires %d, which is not a boss of that raid",
          instanceID, encounterID, requiredID))
      reaches(requiredID, seen)
    end
    seen[encounterID] = nil
    reachable[encounterID] = true
    return true
  end

  local entrances = 0
  for encounterID, prerequisites in pairs(bosses) do
    if #prerequisites == 0 then entrances = entrances + 1 end
    reaches(encounterID, {})
    checks = checks + 1
  end
  assert(entrances > 0, string.format("raid %d: no boss is available at the start", instanceID))
end

assert(checks > 0, "no raid layouts to check")
print(string.format("RaidLayoutTest: %d bosses checked", checks))
