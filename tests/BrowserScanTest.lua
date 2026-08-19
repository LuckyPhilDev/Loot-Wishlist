-- luacheck: ignore 111 121
-- The Loot Browser reads the journal headless, over selection state the
-- Adventure Guide shares. This drives one scan against a mock journal that
-- behaves the way the real one does: a slot filter hides loot from
-- EJ_GetNumLoot, and touching the selection restarts the server's loot query.

LootWishlist = {}
LuckyUI = { C = {}, WC = {} }

------------------------------------------------------------------------
-- Timers: collected, then run on demand
------------------------------------------------------------------------
local pending = {}
C_Timer = {
  After = function(_, fn) pending[#pending + 1] = fn end,
  NewTimer = function(_, fn)
    local t = { fire = fn }
    function t:Cancel() self.cancelled = true end
    return t
  end,
}

local function runTimers()
  while #pending > 0 do table.remove(pending, 1)() end
end

------------------------------------------------------------------------
-- Mock Encounter Journal
------------------------------------------------------------------------
local NO_FILTER, HEAD = 15, 0
Enum = { ItemSlotFilterType = { NoFilter = NO_FILTER, Head = HEAD } }

local INSTANCE = 1300
local NAMES = { [INSTANCE] = "Altar of Fangs" }
local LOOT = {
  { itemID = 111, name = "Hood",  slot = "Head",     link = "|Hitem:111|h[Hood]|h" },
  { itemID = 222, name = "Blade", slot = "One-Hand", link = "|Hitem:222|h[Blade]|h" },
}

local ej = { difficulty = 1, classF = 0, specF = 0, slotFilter = NO_FILTER, selects = 0 }
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
  GetLootInfoByIndex = function(i) return LOOT[i] end,
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

print("4 browser scan tests passed")
