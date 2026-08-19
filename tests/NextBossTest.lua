-- luacheck: ignore 111 121
-- Drives /wishlist testnextboss against a stubbed journal, so the raid layouts
-- are checked through the same path the command uses in game.

LootWishlist = {}

local VENOMOUS_ABYSS = 1320
local BOSSES = {
  { id = 2888, name = "Nek'zali the Soulcoiler" },
  { id = 2874, name = "Entombed Sentinels" },
  { id = 2882, name = "Vashnik the Malignant" },
  { id = 2894, name = "The Lost Explorers" },
  { id = 2871, name = "Sszorak" },
  { id = 2887, name = "The Twin Fangs" },
  { id = 2883, name = "The Coiled Altar" },
  { id = 2895, name = "Ula'tek" },
}

function EJ_SelectInstance() end
function EJ_GetEncounterInfoByIndex(index, instanceID)
  if instanceID ~= VENOMOUS_ABYSS then return nil end
  local boss = BOSSES[index]
  if not boss then return nil end
  return boss.name, nil, boss.id
end
function GetInstanceInfo() return "The Venomous Abyss", "raid", 16 end
function IsInInstance() return true, "raid" end

-- Standing in the raid: the map resolves to the journal instance, and the
-- lockout is what the bare command reads instead of a named kill list.
C_Map = { GetBestMapForUnit = function() return 2601 end }
function EJ_GetInstanceForMap(mapID)
  return mapID == 2601 and VENOMOUS_ABYSS or nil
end

local lockoutKills = {}
function GetNumSavedInstances() return 1 end
function GetSavedInstanceInfo() return "The Venomous Abyss", nil, nil, 16 end
function GetSavedInstanceEncounterInfo(_, encounterIndex)
  local boss = BOSSES[encounterIndex]
  if not boss then return nil end
  return boss.name, nil, lockoutKills[boss.name] or false
end
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function() end }
LuckyUI = { C = {}, WC = {} }

local printed = {}
local realPrint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

dofile("src/LootWishlist_Constants.lua")
dofile("src/LootWishlist_ReminderPlanner.lua")
dofile("src/LootWishlist_Reminders.lua")

local Reminders = LootWishlist.Reminders

local function namesOf(available)
  local names = {}
  for name in pairs(available or {}) do names[#names + 1] = name end
  table.sort(names)
  return table.concat(names, ", ")
end

local function simulate(killed)
  return namesOf(Reminders:TestNextBoss(VENOMOUS_ABYSS, killed))
end

local checks = 0
local function check(killed, expected, why)
  local got = simulate(killed)
  assert(got == expected, string.format("%s\n  killed: %s\n  expected: %s\n  got: %s",
    why, killed, expected, got))
  checks = checks + 1
end

check("", "Nek'zali the Soulcoiler",
  "nothing dead leaves only the entrance boss")

check("nek'zali", "Entombed Sentinels, The Lost Explorers",
  "the entrance boss opens both crypts at once")

check("nek'zali,entombed", "The Lost Explorers, Vashnik the Malignant",
  "a crypt's second boss waits for its first")

check("nek'zali,entombed,vashnik", "The Lost Explorers",
  "one crypt cleared is not enough for The Twin Fangs")

check("nek'zali,entombed,vashnik,explorers,sszorak", "The Twin Fangs",
  "both crypts cleared opens The Twin Fangs")

check("nek'zali,entombed,vashnik,explorers,sszorak,twin fangs", "The Coiled Altar",
  "the tail runs one boss at a time")

local available = Reminders:TestNextBoss(VENOMOUS_ABYSS, "nothing matches this")
assert(namesOf(available) == "Nek'zali the Soulcoiler", "an unmatched name kills nothing")
local warned = false
for _, line in ipairs(printed) do
  if line:find("no boss matches", 1, true) then warned = true end
end
assert(warned, "an unmatched name is reported rather than silently ignored")
checks = checks + 1

assert(Reminders:TestNextBoss(9999, "") == nil, "a raid the journal does not know returns nothing")
checks = checks + 1

-- No instance ID and no names: the raid you are standing in, killed as your
-- own lockout has it.
lockoutKills = { ["Nek'zali the Soulcoiler"] = true, ["Entombed Sentinels"] = true }
assert(namesOf(Reminders:TestNextBoss(nil, "")) == "The Lost Explorers, Vashnik the Malignant",
  "the bare command reads the raid you are in and your own lockout")
checks = checks + 1

print = realPrint
print(string.format("NextBossTest: %d checks passed", checks))
