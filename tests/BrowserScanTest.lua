-- luacheck: ignore 111 121
-- The Loot Browser reads the journal headless, over selection state the
-- Adventure Guide shares. This drives one scan against a mock journal that
-- behaves the way the real one does: a slot filter hides loot from
-- EJ_GetNumLoot, and touching the selection restarts the server's loot query.

LootWishlist = {}
-- The browser reads a colour at load to build its own escape, so the stub
-- carries the palette entries it takes rather than an empty table.
LuckyUI = { C = { textLight = { 0.910, 0.863, 0.784 } }, WC = {},
           DOT = "\194\183" }

------------------------------------------------------------------------
-- Timers: collected, then run on demand
------------------------------------------------------------------------
local now = 0
function GetTime() return now end

local pending, timers = {}, {}
C_Timer = {
  After = function(_, fn) pending[#pending + 1] = fn end,
  NewTimer = function(_, fn)
    local t = { fire = fn }
    function t:Cancel() self.cancelled = true end
    timers[#timers + 1] = t
    return t
  end,
}

local function runTimers()
  while #pending > 0 do table.remove(pending, 1)() end
end

local function fireTimeout()
  local t = table.remove(timers, 1)
  while t and t.cancelled do t = table.remove(timers, 1) end
  assert(t, "a timeout should be pending")
  t.fire()
end

------------------------------------------------------------------------
-- Mock Encounter Journal
------------------------------------------------------------------------
local NO_FILTER, HEAD = 15, 0
Enum = { ItemSlotFilterType = { NoFilter = NO_FILTER, Head = HEAD } }

local INSTANCE, INSTANCE2, INSTANCE3 = 1300, 1301, 1302
local NAMES = {
  [INSTANCE] = "Altar of Fangs",
  [INSTANCE2] = "Web of Chains",
  [INSTANCE3] = "Halls of Rust",
}
local LOOT = {
  { itemID = 111, name = "Hood",  slot = "Head",     link = "|Hitem:111|h[Hood]|h" },
  { itemID = 222, name = "Blade", slot = "One-Hand", link = "|Hitem:222|h[Blade]|h" },
}

local ej = { difficulty = 1, classF = 0, specF = 0, slotFilter = NO_FILTER, selects = 0,
              linksReady = true }
local dataReady = false

-- Anything that moves the selection makes the client ask the server again.
local function requery() dataReady = false end

function EJ_SelectInstance(id)
  ej.instance = id
  ej.selects = ej.selects + 1
  requery()
end
function EJ_GetInstanceInfo(id) return NAMES[id or ej.instance] end
function EJ_SetDifficulty(d) ej.difficulty = d; requery() end
function EJ_GetDifficulty() return ej.difficulty end
function EJ_SetLootFilter(c, s) ej.classF, ej.specF = c, s; requery() end
function EJ_GetLootFilter() return ej.classF, ej.specF end
function EJ_GetNumLoot()
  if not dataReady then return 0 end
  if ej.slotFilter ~= NO_FILTER then return 0 end
  return #LOOT
end

C_EncounterJournal = {
  GetLootInfoByIndex = function(i)
    local it = LOOT[i]
    if not it or ej.linksReady then return it end
    -- The list arrives before the item links do on a cold client.
    return { itemID = it.itemID, name = it.name, slot = it.slot }
  end,
  GetSlotFilter      = function() return ej.slotFilter end,
  SetSlotFilter      = function(f) ej.slotFilter = f end,
  ResetSlotFilter    = function() ej.slotFilter = NO_FILTER end,
}

local onEvent
function CreateFrame()
  local f = setmetatable({}, { __index = function() return function() end end })
  function f:SetScript(kind, fn) if kind == "OnEvent" then onEvent = fn end end
  return f
end

------------------------------------------------------------------------
dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Constants.lua")
dofile("src/LootWishlist_Browser.lua")

local scanner = LootWishlist.Browser.testScanner
scanner.state.classID, scanner.state.specID = 7, 0

-- A slot picked in the Adventure Guide and never cleared.
ej.slotFilter = HEAD

assert(scanner.requestLoot(INSTANCE, false, 23) == nil, "first call queues a scan")
runTimers()
assert(ej.selects == 1, "the scan selects the instance once")
assert(ej.difficulty == 23, "the scan reads at the difficulty it asked for")

-- The server answers, and the journal says so.
dataReady = true
onEvent(nil, "EJ_LOOT_DATA_RECIEVED")
runTimers()

local cache = scanner.requestLoot(INSTANCE, false, 23)
assert(cache, "the scan finished")
assert(#cache.items == #LOOT, "a leftover slot filter must not hide the loot")
assert(ej.selects == 1, "reading again must not re-select and restart the query")
assert(ej.slotFilter == HEAD, "the journal's own slot filter is put back")

------------------------------------------------------------------------
-- A cold journal: the server only answers after the scan has given up.
------------------------------------------------------------------------
assert(scanner.requestLoot(INSTANCE2, false, 23) == nil, "second instance queues a scan")
runTimers()
fireTimeout()
cache = scanner.requestLoot(INSTANCE2, false, 23)
assert(cache and #cache.items == 0 and cache.incomplete,
  "a timed-out empty scan is cached but flagged incomplete")

-- Loot data landing later requeues the flagged entry. The requeue re-selects,
-- which restarts the server query, and the query's own answer completes it.
now = now + 60
dataReady = true
onEvent(nil, "EJ_LOOT_DATA_RECIEVED")
runTimers()
dataReady = true
onEvent(nil, "EJ_LOOT_DATA_RECIEVED")
runTimers()
cache = scanner.requestLoot(INSTANCE2, false, 23)
assert(cache and #cache.items == #LOOT and not cache.incomplete,
  "loot data arriving after the timeout rescans the empty table")

------------------------------------------------------------------------
-- The list arrives but the links are slow: a timeout keeps what resolved
-- and still flags the entry, so a reopen or a late reply finishes the job.
------------------------------------------------------------------------
ej.linksReady = false
assert(scanner.requestLoot(INSTANCE3, false, 23) == nil, "third instance queues a scan")
dataReady = true
runTimers()
fireTimeout()
cache = scanner.requestLoot(INSTANCE3, false, 23)
assert(cache and #cache.items == #LOOT and cache.incomplete,
  "a timed-out partial read keeps its items but is flagged incomplete")

------------------------------------------------------------------------
-- A rescan that comes back with nothing must not throw away the partial
-- items it replaced.
------------------------------------------------------------------------
now = now + 60
onEvent(nil, "EJ_LOOT_DATA_RECIEVED")
runTimers()
fireTimeout()
cache = scanner.requestLoot(INSTANCE3, false, 23)
assert(cache and #cache.items == #LOOT and cache.incomplete,
  "a rescan that reads worse keeps the items it replaced")

-- Straight after a failed rescan the cooldown holds, so a loot event echoed
-- by the scanner's own restore cannot burn another retry.
dataReady = true
local selectsBefore = ej.selects
onEvent(nil, "EJ_LOOT_DATA_RECIEVED")
runTimers()
assert(ej.selects == selectsBefore, "the cooldown blocks an immediate rescan")

-- Once the cooldown passes and the links have arrived, the retry finishes.
now = now + 60
ej.linksReady = true
onEvent(nil, "EJ_LOOT_DATA_RECIEVED")
runTimers()
dataReady = true
onEvent(nil, "EJ_LOOT_DATA_RECIEVED")
runTimers()
cache = scanner.requestLoot(INSTANCE3, false, 23)
assert(cache and #cache.items == #LOOT and not cache.incomplete,
  "the table completes once its data arrives")

print("13 browser scan tests passed")
