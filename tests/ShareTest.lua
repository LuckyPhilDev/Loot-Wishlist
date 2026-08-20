-- luacheck: ignore 111 121
-- Export/import payloads: what travels in a share string, how untrusted
-- strings are sanitized, and how an import lands in the tracked table.

LootWishlist = {}
dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Share.lua")

local Share = LootWishlist.Share
local checks = 0

local function check(cond, why)
  assert(cond, why)
  checks = checks + 1
end

-- BuildPayload: only the portable fields travel ------------------------------

local tracked = {
  ["229351@15"] = {
    id = 229351, boss = "Vexie", dungeon = "Liberation of Undermine", isRaid = true,
    link = "|cffa335ee|Hitem:229351::::::::80:105::5:5:6652:10355:10265:1540:10255:::::|h[Bloody Wake]|h|r",
    encounterID = 2639, instanceID = 1296, difficultyID = 15, difficultyName = "Heroic",
    specs = { 71, 72 }, icon = 12345, quality = 4,
    _specNamesStr = "Arms/Fury", _specNamesForSpecs = {},
  },
  ["229351@16"] = {
    id = 229351, boss = "Vexie", dungeon = "Liberation of Undermine", isRaid = true,
    difficultyID = 16, difficultyName = "Mythic",
  },
  ["19019"] = { id = 19019, dungeon = "Manually Added", isRaid = false },
  ["bad-entry"] = "not a table",
  ["worse-entry"] = { boss = "No ID" },
}

local payload = Share.BuildPayload(tracked)
check(payload.addon == "LootWishlist" and payload.format == 1, "payload carries the envelope")
check(#payload.items == 3, "malformed entries are left out of the export")
check(payload.items[1].id == 19019, "items are sorted by id")
check(payload.items[2].difficultyID == 15 and payload.items[3].difficultyID == 16,
  "same item sorts by difficulty")

local heroic = payload.items[2]
check(heroic.boss == "Vexie" and heroic.dungeon == "Liberation of Undermine", "names travel")
check(heroic.link ~= nil and heroic.encounterID == 2639 and heroic.instanceID == 1296, "journal facts travel")
check(heroic.isRaid == true and payload.items[1].isRaid == false, "isRaid is a plain boolean")
check(heroic.specs == nil and heroic.icon == nil and heroic.quality == nil
  and heroic._specNamesStr == nil and heroic._specNamesForSpecs == nil,
  "recomputable and cached fields stay home")

-- SanitizePayload: envelope checks -------------------------------------------

local function sanitizeFails(decoded, fragment, why)
  local items, err = Share.SanitizePayload(decoded)
  assert(items == nil and type(err) == "string" and err:find(fragment, 1, true), why)
  checks = checks + 1
end

sanitizeFails(nil, "not a Loot Wishlist export", "nil is refused")
sanitizeFails({ some = "table" }, "not a Loot Wishlist export", "a foreign table is refused")
sanitizeFails({ addon = "WarbandStorage", format = 1, items = {} }, "not a Loot Wishlist export",
  "another addon's export is refused")
sanitizeFails({ addon = "LootWishlist", items = {} }, "not a Loot Wishlist export",
  "a missing format stamp is refused")
sanitizeFails({ addon = "LootWishlist", format = 2, items = {} }, "newer version",
  "a future format asks for an update")
sanitizeFails({ addon = "LootWishlist", format = 1, items = {} }, "no wishlist items",
  "an empty export is refused")
sanitizeFails({ addon = "LootWishlist", format = 1, items = { { id = -5 }, { id = 1.5 }, "junk" } },
  "no wishlist items", "an export of only junk is refused")
sanitizeFails({ addon = "LootWishlist", format = 1, items = { { id = 2^31 }, { id = 0/0 }, { id = math.huge } } },
  "no wishlist items", "ids beyond int32, NaN and infinity are refused")

-- SanitizePayload: item cleaning ---------------------------------------------

local dirty = {
  addon = "LootWishlist", format = 1,
  items = {
    { id = 229351, boss = "Vexie", isRaid = 1, difficultyID = 15,
      rogue = "field", specs = { 71 }, encounterID = "2639" },
    { id = 229351, difficultyID = 15, boss = "Duplicate" },
    { id = 229351, difficultyID = -4 },
    { id = 19019 },
  },
}
local items = Share.SanitizePayload(dirty)
check(#items == 3, "duplicates collapse onto one key")
local byKey = {}
for _, it in ipairs(items) do
  byKey[it.difficultyID and (it.id .. "@" .. it.difficultyID) or tostring(it.id)] = it
end
local vexie = byKey["229351@15"]
check(vexie ~= nil and vexie.boss == "Vexie", "the first copy of a duplicate key wins")
check(vexie.rogue == nil and vexie.specs == nil, "unknown fields are stripped")
check(vexie.isRaid == true, "truthy isRaid becomes a boolean")
check(vexie.encounterID == nil, "wrongly typed fields are dropped")
check(byKey["229351"] ~= nil and byKey["229351"].difficultyID == nil,
  "an invalid difficulty falls back to the no-difficulty key")
check(byKey["19019"] ~= nil, "a bare id imports")

local hostile = Share.SanitizePayload({
  addon = "LootWishlist", format = 1,
  items = { { id = 5, encounterID = 0/0, instanceID = math.huge, difficultyID = 15,
    boss = string.rep("x", 121), link = string.rep("y", 401), dungeon = "" } },
})
local entry = hostile[1]
check(entry.encounterID == nil and entry.instanceID == nil,
  "NaN and infinity never survive as journal ids")
check(entry.boss == nil and entry.link == nil and entry.dungeon == nil,
  "overlong and empty strings are dropped")
check(entry.id == 5 and entry.difficultyID == 15, "valid fields on the same item still import")

local flood = { addon = "LootWishlist", format = 1, items = {} }
for i = 1, 501 do flood.items[i] = { id = i } end
sanitizeFails(flood, "more than 500", "an oversized import is refused outright")

-- Round trip: an export sanitizes back unchanged ------------------------------

local function itemKey(it)
  return it.difficultyID and (it.id .. "@" .. it.difficultyID) or tostring(it.id)
end

local roundTrip = Share.SanitizePayload(Share.BuildPayload(tracked))
check(#roundTrip == 3, "a real export survives sanitizing")
local roundTripByKey = {}
for _, it in ipairs(roundTrip) do roundTripByKey[itemKey(it)] = it end
for _, exported in ipairs(payload.items) do
  local it = roundTripByKey[itemKey(exported)]
  check(it ~= nil, "round trip keeps " .. itemKey(exported))
  for field, value in pairs(exported) do
    check(it[field] == value, "round trip preserves " .. field)
  end
end

-- ApplyImport: add vs replace -------------------------------------------------

local db, cleared, addCalls
local function resetStubs(existing)
  db, cleared, addCalls = existing, 0, {}
  LootWishlist.GetTracked = function() return db end
  LootWishlist.ClearAllTracked = function()
    cleared = cleared + 1
    for k in pairs(db) do db[k] = nil end
  end
  LootWishlist.AddTrackedItemQuiet = function(id, boss, dungeon, isRaid, link, encounterID, instanceID, difficultyID, difficultyName)
    addCalls[#addCalls + 1] = { id = id, boss = boss, difficultyID = difficultyID }
    local key = difficultyID and (tostring(id) .. "@" .. tostring(difficultyID)) or tostring(id)
    db[key] = { id = id, boss = boss, dungeon = dungeon, isRaid = isRaid, link = link,
      encounterID = encounterID, instanceID = instanceID,
      difficultyID = difficultyID, difficultyName = difficultyName }
  end
end

local imported = {
  { id = 229351, boss = "Vexie", isRaid = true, difficultyID = 15 },
  { id = 19019, isRaid = false },
}

resetStubs({ ["229351@15"] = { id = 229351 }, ["50000"] = { id = 50000 } })
local added, existing = Share.ApplyImport(imported, false)
check(cleared == 0, "adding does not clear the list")
check(added == 1 and existing == 1, "adding reports new against already-tracked")
check(db["50000"] ~= nil, "adding keeps entries the import did not mention")
check(db["229351@15"].boss == "Vexie", "an already-tracked entry takes the imported copy")
check(#addCalls == 2 and addCalls[1].difficultyID == 15, "every import row lands via AddTrackedItemQuiet")

resetStubs({ ["50000"] = { id = 50000 } })
added, existing = Share.ApplyImport(imported, true)
check(cleared == 1, "replacing clears the list first")
check(added == 2 and existing == 0, "after a clear everything imports as new")
check(db["50000"] == nil and db["229351@15"] ~= nil and db["19019"] ~= nil,
  "the replaced list holds exactly the import")

print(string.format("ShareTest: %d checks passed", checks))
