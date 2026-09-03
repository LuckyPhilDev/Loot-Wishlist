-- luacheck: ignore 111 121
-- The wishlist window and the summary share one layout: instances raids
-- first, bosses in journal order, or both by how many items they hold when
-- the order setting says so.

LootWishlist = {}
LootWishlistDB = { settings = {} }

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Layout.lua")

local RAID = 1200
local JOURNAL = { { "Vexie", 3001 }, { "Cauldron", 3002 }, { "Rik", 3003 } }
function EJ_GetEncounterInfoByIndex(idx, instanceID)
  if instanceID ~= RAID then return nil end
  local boss = JOURNAL[idx]
  if not boss then return nil end
  return boss[1], nil, boss[2]
end

local tracked, obtained = {}, {}
LootWishlist.GetTracked = function() return tracked end
LootWishlist.GetObtained = function() return obtained end

local function track(store, id, diff, boss, encounterID, instance, isRaid)
  store[id .. "@" .. diff] = {
    id = id, boss = boss, encounterID = encounterID, dungeon = instance, isRaid = isRaid,
    instanceID = isRaid and RAID or nil, difficultyID = diff,
  }
end

-- Rik holds three items, Cauldron two, Vexie one tracked on two difficulties.
track(tracked, 101, 14, "Vexie", 3001, "Undermine", true)
track(tracked, 101, 15, "Vexie", 3001, "Undermine", true)
track(tracked, 201, 14, "Cauldron", 3002, "Undermine", true)
track(tracked, 202, 14, "Cauldron", 3002, "Undermine", true)
track(tracked, 301, 14, "Rik", 3003, "Undermine", true)
track(tracked, 302, 14, "Rik", 3003, "Undermine", true)
track(tracked, 303, 14, "Rik", 3003, "Undermine", true)
-- Two dungeons, the later one alphabetically holding more.
track(tracked, 401, 2, "Boss", 5001, "Darkflame Cleft", false)
track(tracked, 501, 2, "Boss", 5002, "Rookery", false)
track(tracked, 502, 2, "Boss", 5003, "Rookery", false)
-- An obtained item still under Rik.
track(obtained, 304, 14, "Rik", 3003, "Undermine", true)

local checks = 0
local function check(cond, why)
  assert(cond, why)
  checks = checks + 1
end

local function names(list)
  local out = {}
  for _, entry in ipairs(list) do out[#out + 1] = entry.name end
  return table.concat(out, ",")
end

local layout = LootWishlist.Layout.Build()
check(names(layout) == "Undermine,Darkflame Cleft,Rookery", "journal order: raids first, then dungeons by name")
check(names(layout[1].bosses) == "Vexie,Cauldron,Rik", "journal order follows the Adventure Guide")
check(layout[1].bosses[1].count == 1, "an item on two difficulties counts once")
check(layout[1].count == 6, "the raid counts every unique item")
check(layout[2].bosses == nil, "dungeons have no boss groups")

LootWishlistDB.settings.wishlistOrder = "count"
layout = LootWishlist.Layout.Build()
check(names(layout) == "Undermine,Rookery,Darkflame Cleft", "most items first keeps raids ahead of dungeons")
check(names(layout[1].bosses) == "Rik,Cauldron,Vexie", "most items first puts the fullest boss on top")

-- Obtained items ride along when asked for but never count.
layout = LootWishlist.Layout.Build({ includeObtained = true })
check(#layout[1].bosses[1].items == 4, "the obtained item sits under its boss")
check(layout[1].bosses[1].count == 3, "the obtained item is not counted")
check(layout[1].bosses[1].items[4].obtained, "the obtained item is marked")

-- A filter that empties an instance drops it entirely.
layout = LootWishlist.Layout.Build({ keep = function(entry) return entry.id >= 500 end })
check(names(layout) == "Rookery", "filtered-out instances vanish")
check(layout[1].count == 2, "the filtered instance counts what survived")

-- Two Rookery entries tie on count, so the order falls back to journal order
-- and, without one, to the encounter ID.
LootWishlistDB.settings.wishlistOrder = "journal"
track(tracked, 601, 14, "Zed", 3009, "Undermine", true)
layout = LootWishlist.Layout.Build()
check(names(layout[1].bosses) == "Vexie,Cauldron,Rik,Zed", "a boss the journal does not list goes last")

print(string.format("LayoutOrderTest: %d checks passed", checks))
