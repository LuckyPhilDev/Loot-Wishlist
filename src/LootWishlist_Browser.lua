-- Loot Wishlist - Loot Browser
-- Browse the current season's dungeon and raid drop tables without the
-- Encounter Journal, filtered to a class and spec (the player's own by
-- default, other classes read-only), and toggle wishlist entries directly.
-- Drives the native EJ data APIs headless, the same pattern
-- getEncounterOrder in LootWishlist_UI.lua already uses.

LootWishlist = LootWishlist or {}
LootWishlist.Browser = LootWishlist.Browser or {}

local UI = LuckyUI
local S = LootWishlist.Strings.browser
local C  = UI.C
local WC = UI.WC

local SIDEBAR_W    = 180
local ITEM_ROW_H   = 44
local HEAD_ROW_H   = 26
local BOSS_ROW_H   = 22
local NOTE_ROW_H   = 26
local SIDE_ROW_H   = 24
local TOOLBAR_H    = 62
local DEFAULT_W    = 720
local DEFAULT_H    = 540
-- Wide enough that the track buttons and the group dropdown share the top row.
local MIN_W        = 650
local MIN_H        = 400
local SCAN_TIMEOUT = 3

local DOT   = " \194\183 "   -- ·
local CROSS = "\195\151"     -- ×

-- %d is the track's lowest key level, filled in from the track entry.
local TRACK_TIPS = {
  Veteran  = S.trackVeteran,
  Champion = S.trackChampion,
  Hero     = S.trackHero,
  Myth     = S.trackMyth,
}

------------------------------------------------------------------------
-- Module state
------------------------------------------------------------------------
local frame, sidebarList, lootList, searchBox, statusLabel
local trackButtons = {}
local season                 -- { dungeons = {..}, raids = {..} }
local lootCache = {}         -- [cacheKey(...)] = { items = {..}, diffID = scanned }
local bossNames = {}         -- encounterID -> name (false = lookup failed)
-- classID/specID drive the EJ loot filter; specID 0 = all specs. A class other
-- than the player's is browse-only: rows lose their add controls.
local state = { track = "Hero", view = "dungeons", instanceID = nil, instanceName = nil, isRaid = nil, search = "", slot = nil, group = "source", classID = nil, specID = 0 }

local scheduleRefresh        -- forward: defined with the UI, used by the scanner

local DevLog = LuckyLog and LuckyLog:New("[Lwl-Browser][debug]", function()
  return LootWishlist.IsDebug and LootWishlist.IsDebug()
end) or function() end

local function charDB()
  LootWishlistCharDB.browser = LootWishlistCharDB.browser or {}
  return LootWishlistCharDB.browser
end

local function journalShown()
  return (EncounterJournal and EncounterJournal:IsShown()) and true or false
end

local function playerClassID()
  return (select(3, UnitClass("player")))
end

local function browsingOwnClass()
  return state.classID == playerClassID()
end

local function classNameAndColor(classID)
  local name, file = GetClassInfo(classID)
  local color = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
  return name or "?", color
end

local function coloredClassName(classID)
  local name, color = classNameAndColor(classID)
  if color and color.colorStr then
    return "|c" .. color.colorStr .. name .. "|r"
  end
  return name
end

------------------------------------------------------------------------
-- Season instance list (Current Season = last EJ tier)
------------------------------------------------------------------------
local function getSeason()
  if season then return season end
  if type(EJ_GetNumTiers) ~= "function" then return nil end
  local numTiers = EJ_GetNumTiers() or 0
  if numTiers == 0 then return nil end
  local prevTier
  if EJ_GetCurrentTier then
    local ok, t = pcall(EJ_GetCurrentTier)
    if ok then prevTier = t end
  end
  local function listTier(tier)
    pcall(EJ_SelectTier, tier)
    local excluded = LootWishlist.Const.EXCLUDED_JOURNAL_INSTANCES
    local function list(isRaid)
      local out, i = {}, 1
      while true do
        local id, name = EJ_GetInstanceByIndex(i, isRaid)
        if not id then break end
        if not excluded[id] then
          out[#out + 1] = { id = id, name = name, isRaid = isRaid }
        end
        i = i + 1
      end
      return out
    end
    return list(false), list(true)
  end
  local dungeons, raids = listTier(numTiers)
  if #dungeons == 0 and #raids == 0 and numTiers > 1 then
    dungeons, raids = listTier(numTiers - 1)
  end
  if prevTier then pcall(EJ_SelectTier, prevTier) end
  if #dungeons == 0 and #raids == 0 then return nil end
  season = { dungeons = dungeons, raids = raids }
  return season
end

local function bossName(encounterID)
  if not encounterID then return nil end
  if bossNames[encounterID] == nil and type(EJ_GetEncounterInfo) == "function" then
    local ok, name = pcall(EJ_GetEncounterInfo, encounterID)
    bossNames[encounterID] = (ok and name) or false
  end
  local v = bossNames[encounterID]
  if v ~= false then return v end
  return nil
end

------------------------------------------------------------------------
-- Loot scanner: serialized queue over global EJ selection state
------------------------------------------------------------------------
local scanEvents = CreateFrame("Frame")
local queue, pendingKeys = {}, {}
local current, snapshot
local pump -- forward: mutual recursion with finishScan

local function snapshotEJ()
  if snapshot then return end
  snapshot = {}
  if EJ_GetLootFilter then
    local ok, cls, spec = pcall(EJ_GetLootFilter)
    if ok then snapshot.classF, snapshot.specF = cls, spec end
  end
  if C_EncounterJournal and C_EncounterJournal.GetSlotFilter then
    local ok, slot = pcall(C_EncounterJournal.GetSlotFilter)
    if ok then snapshot.slotF = slot end
  end
  if EJ_GetDifficulty then
    local ok, d = pcall(EJ_GetDifficulty)
    if ok then snapshot.diff = d end
  end
  if EncounterJournal then
    snapshot.instanceID  = EncounterJournal.instanceID
    snapshot.encounterID = EncounterJournal.encounterID
  end
end

local function restoreEJ()
  if not snapshot then return end
  if snapshot.slotF and C_EncounterJournal and C_EncounterJournal.SetSlotFilter then
    pcall(C_EncounterJournal.SetSlotFilter, snapshot.slotF)
  end
  if snapshot.instanceID and EJ_SelectInstance then pcall(EJ_SelectInstance, snapshot.instanceID) end
  if snapshot.diff and EJ_SetDifficulty then pcall(EJ_SetDifficulty, snapshot.diff) end
  if snapshot.encounterID and EJ_SelectEncounter then pcall(EJ_SelectEncounter, snapshot.encounterID) end
  if snapshot.classF and EJ_SetLootFilter then pcall(EJ_SetLootFilter, snapshot.classF, snapshot.specF or 0) end
  snapshot = nil
end

-- Put the journal on a difficulty and confirm it took, since asking for one an
-- instance does not have leaves the previous difficulty in place, and reading
-- then would file one track's loot under another's. Returns the difficulty
-- actually in effect, trying the requested one first and then the source's
-- chain outward. nil = nothing could be applied.
local function applyDifficulty(scan)
  local Const = LootWishlist.Const
  local chain = scan.isRaid and Const.DIFFICULTY_CHAINS.raid or Const.DIFFICULTY_CHAINS.dungeon

  local function sticks(d)
    if not d then return false end
    if type(EJ_GetDifficulty) ~= "function" then
      pcall(EJ_SetDifficulty, d)
      return true
    end
    local ok, actual = pcall(EJ_GetDifficulty)
    if ok and actual == d then return true end
    pcall(EJ_SetDifficulty, d)
    local settled, now = pcall(EJ_GetDifficulty)
    return settled and now == d
  end

  if sticks(scan.diffID) then return scan.diffID end

  local pos
  for i, d in ipairs(chain) do
    if d == scan.diffID then pos = i break end
  end
  if pos then
    for i = pos - 1, 1, -1 do if sticks(chain[i]) then return chain[i] end end
    for i = pos + 1, #chain do if sticks(chain[i]) then return chain[i] end end
  end

  local ok, actual = pcall(EJ_GetDifficulty)
  return (ok and actual) or nil
end

-- Loot that is not gear: profession patterns, cosmetic drops such as housing
-- decor, and collectibles like mounts and battle pets. Tier and catalyst
-- tokens have no equip slot either, so the cut is by item class and subclass,
-- never by equippability. Tokens sit in Miscellaneous under other subclasses
-- and survive.
local function isNonGearLoot(itemID)
  if not (C_Item and C_Item.GetItemInfoInstant) then return false end
  local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
  if not classID or not Enum.ItemClass then return false end
  if classID == Enum.ItemClass.Recipe then return true end
  if Enum.ItemClass.Housing and classID == Enum.ItemClass.Housing then return true end
  if classID == Enum.ItemClass.Armor and Enum.ItemArmorSubclass
      and subClassID == Enum.ItemArmorSubclass.Cosmetic then
    return true
  end
  local misc = Enum.ItemMiscellaneousSubclass
  if classID == Enum.ItemClass.Miscellaneous and misc then
    if subClassID == misc.Mount then return true end
    if misc.MountEquipment and subClassID == misc.MountEquipment then return true end
    if subClassID == misc.CompanionPet then return true end
  end
  return false
end

local function selectedInstanceIs(instanceID)
  local okWant, want = pcall(EJ_GetInstanceInfo, instanceID)
  local okHave, have = pcall(EJ_GetInstanceInfo)
  return okWant and okHave and want ~= nil and want == have
end

-- The journal's slot filter is global and gates EJ_GetNumLoot, so a slot left
-- chosen in the Adventure Guide hides most of a scan's loot, or all of it.
-- Blizzard's own whole-table reads clear it the same way and put it back.
local function clearSlotFilter()
  local CEJ = C_EncounterJournal
  if not (CEJ and CEJ.GetSlotFilter and CEJ.ResetSlotFilter) then return end
  local none = Enum.ItemSlotFilterType and Enum.ItemSlotFilterType.NoFilter
  local ok, filter = pcall(CEJ.GetSlotFilter)
  if ok and none and filter == none then return end
  pcall(CEJ.ResetSlotFilter)
end

-- Point the journal at what this scan wants to read, before every read, since
-- EJ selection is global and this addon's own UI and Summary refreshes can
-- move it mid-wait. Only what has actually drifted is written: selecting an
-- instance or a difficulty again restarts the server's loot query, so writing
-- unconditionally would reset the table each time an item arrived and leave a
-- slow instance stuck at zero until the scan timed out.
local function assertSelection(scan)
  -- The first select goes by ID, so the right instance is always what gets
  -- read; the name check afterwards only asks whether it is still selected.
  if not (scan.selected and selectedInstanceIs(scan.instanceID)) then
    pcall(EJ_SelectInstance, scan.instanceID)
    scan.selected = true
  end
  local diff = applyDifficulty(scan)
  if not diff then return nil end
  scan.scannedDiff = diff
  local ok, cls, spec = pcall(EJ_GetLootFilter)
  if not ok or cls ~= scan.classID or spec ~= scan.specID then
    pcall(EJ_SetLootFilter, scan.classID, scan.specID)
  end
  clearSlotFilter()
  return diff
end

-- One read attempt. Returns items (or nil when nothing arrived yet) and done.
local function readLoot(scan)
  if not (C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex) then return {}, true end
  local diff = assertSelection(scan)
  if not diff then return {}, true end
  local n = (type(EJ_GetNumLoot) == "function") and (EJ_GetNumLoot() or 0) or 0
  scan.lastN = n
  if n == 0 then return nil, false end
  local items, complete = {}, true
  for i = 1, n do
    local ok, info = pcall(C_EncounterJournal.GetLootInfoByIndex, i)
    if ok and type(info) == "table" and info.itemID and not isNonGearLoot(info.itemID) then
      items[#items + 1] = {
        itemID      = info.itemID,
        encounterID = info.encounterID,
        name        = info.name,
        icon        = info.icon,
        slot        = info.slot,
        filterType  = info.filterType,
        armorType   = info.armorType,
        link        = info.link,
        veryRare    = (info.displayAsVeryRare or info.displayAsExtremelyRare) and true or false,
      }
      if not info.link then complete = false end
    end
  end
  return items, complete and #items > 0
end

local function finishScan(scan, items)
  if scan.timer then scan.timer:Cancel(); scan.timer = nil end
  local count = items and #items or 0
  DevLog("scan", scan.key, "read", count, "of", scan.lastN or 0, "journal entries",
    scan.timedOut and "(timed out)" or "")
  -- An empty read is kept for this browsing session so the queue does not spin
  -- on it, but flagged: reopening the browser rescans it, since nothing came
  -- back is as often a lost race with the journal as a genuinely empty table.
  lootCache[scan.key] = {
    items = items or {}, diffID = scan.scannedDiff or scan.diffID, empty = count == 0,
  }
  pendingKeys[scan.key] = nil
  current = nil
  if LuckyItem and items then
    local ids = {}
    for _, it in ipairs(items) do
      if not LuckyItem:IsCached(it.itemID) then ids[#ids + 1] = it.itemID end
    end
    if #ids > 0 then LuckyItem:GetMany(ids, function() scheduleRefresh() end) end
  end
  scheduleRefresh()
  pump()
end

local function requeueCurrent()
  if not current then return end
  local scan = current
  if scan.timer then scan.timer:Cancel(); scan.timer = nil end
  current = nil
  table.insert(queue, 1, scan)
end

local function attemptRead()
  local scan = current
  if not scan then return end
  if journalShown() then
    -- The journal owns the shared selection now; abort and requeue rather
    -- than reading (or clobbering) its state.
    requeueCurrent()
    pump()
    return
  end
  local items, done = readLoot(scan)
  if items then scan.partial = items end
  if done then finishScan(scan, items) end
end

local function startScan(scan)
  current = scan
  snapshotEJ()
  scan.timer = C_Timer.NewTimer(SCAN_TIMEOUT, function()
    scan.timer = nil
    if current ~= scan then return end
    if journalShown() then requeueCurrent(); pump(); return end
    -- Accept what resolved; stragglers fall back to LuckyItem base links.
    scan.timedOut = true
    finishScan(scan, scan.partial or {})
  end)
  -- Point the journal first, then read a frame later. Reading straight after
  -- setting a difficulty can hand back the list the previous difficulty left
  -- behind, which would cache one track's items under another's key.
  assertSelection(scan)
  C_Timer.After(0, function()
    if current == scan then attemptRead() end
  end)
end

pump = function()
  if current then return end
  if journalShown() then
    -- Paused while the journal is open; drain when it hides.
    if EncounterJournal and not EncounterJournal.LootWishlistBrowserHideHook then
      EncounterJournal.LootWishlistBrowserHideHook = true
      EncounterJournal:HookScript("OnHide", function() C_Timer.After(0, function() pump() end) end)
    end
    return
  end
  local scan = table.remove(queue, 1)
  if not scan then
    scanEvents:UnregisterEvent("EJ_LOOT_DATA_RECIEVED")
    restoreEJ()
    return
  end
  if lootCache[scan.key] then
    pendingKeys[scan.key] = nil
    return pump()
  end
  scanEvents:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
  startScan(scan)
end

scanEvents:SetScript("OnEvent", function(_, event)
  if event == "EJ_LOOT_DATA_RECIEVED" then
    attemptRead()
  end
end)

-- The loot filter shapes what a scan reads, so class and spec are part of the
-- cache identity alongside instance and difficulty.
local function cacheKey(instanceID, diffID)
  return table.concat({ instanceID, diffID, state.classID, state.specID }, "@")
end

-- Returns the cache entry when ready, else queues a scan and returns nil.
local function requestLoot(instanceID, isRaid, diffID)
  local key = cacheKey(instanceID, diffID)
  if lootCache[key] then return lootCache[key] end
  if not pendingKeys[key] then
    pendingKeys[key] = true
    queue[#queue + 1] = {
      key = key, instanceID = instanceID, isRaid = isRaid, diffID = diffID,
      classID = state.classID, specID = state.specID,
    }
    pump()
  end
  return nil
end

-- The scan pipeline runs headless, so the test drives it without building the
-- window that normally does.
LootWishlist.Browser.testScanner = { state = state, requestLoot = requestLoot }

------------------------------------------------------------------------
-- Row building
------------------------------------------------------------------------
local function isTracked(itemID)
  local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked()
  if not tracked then return false end
  for _, v in pairs(tracked) do
    if type(v) == "table" and v.id == itemID then return true end
  end
  return false
end

-- Item level delta bonus IDs, one per point of difference from an item's base
-- level. Engine data stable since Warlords; the IDs run in contiguous blocks,
-- stored here as offsets rather than a nine-hundred-entry table.
local function ilvlDeltaBonus(delta)
  if delta == 0 then return nil end
  if delta >= -100 and delta <= 200 then return 1472 + delta end
  if delta >= 201 and delta <= 400 then return 2929 + delta end
  if delta >= 401 and delta <= 407 then return 9054 + delta end
  if delta >= 408 and delta <= 410 then return 9056 + delta end
  if delta >= 411 and delta <= 430 then return 9423 + delta end
  if delta >= 431 and delta <= 450 then return 9443 + delta end
  if delta >= 451 and delta <= 600 then return 9467 + delta end
  if delta >= 601 and delta <= 900 then return 10740 + delta end
end

-- A dungeon item rebuilt as the track's own version, the way Keystone Loot
-- builds its previews: a delta bonus lifts the item's base level to the
-- track's level, the track bonus adds the "Upgrade Level: Hero 1/6" line, and
-- the item level and stats follow from those. Returns a full link, or nil for
-- loot that cannot carry a track (tier tokens), or while the item's base data
-- has not been cached yet; callers fall back to the scanned link either way.
local function trackItemLink(itemID, tr)
  if not (tr.trackIlvl and tr.trackBonus) then return nil end
  local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
  if classID ~= Enum.ItemClass.Armor and classID ~= Enum.ItemClass.Weapon then return nil end
  local _, _, base = C_Item.GetDetailedItemLevelInfo(itemID)
  if not base or base <= 0 then return nil end
  local delta = tr.trackIlvl - base
  local deltaBonus = ilvlDeltaBonus(delta)
  if delta ~= 0 and not deltaBonus then return nil end
  local bonuses = {}
  bonuses[#bonuses + 1] = deltaBonus
  bonuses[#bonuses + 1] = tr.trackBonus
  bonuses[#bonuses + 1] = 1674  -- epic quality
  if equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_NECK" then
    bonuses[#bonuses + 1] = 13534  -- Midnight ring and amulet stat layout
  end
  -- The link's spec field decides which stat spread variable items show, so a
  -- browsed spec renders as that spec's drop rather than the player's.
  local specID = state.specID
  if specID == 0 and GetSpecialization and GetSpecializationInfo then
    specID = GetSpecializationInfo(GetSpecialization() or 0) or 0
  end
  local payload = string.format("item:%d::::::::%d:%d:::%d:%s",
    itemID, UnitLevel("player"), specID, #bonuses, table.concat(bonuses, ":"))
  return (select(2, C_Item.GetItemInfo(payload)))
end

local function trackEntry()
  for _, t in ipairs(LootWishlist.Const.TRACKS) do
    if t.key == state.track then return t end
  end
  return LootWishlist.Const.TRACKS[3]
end

local function instancesForView()
  if state.view == "instance" then
    return { { id = state.instanceID, name = state.instanceName, isRaid = state.isRaid } }
  end
  local s = getSeason()
  if not s then return nil end
  if state.view == "season" then
    local all = {}
    for _, d in ipairs(s.dungeons) do all[#all + 1] = d end
    for _, r in ipairs(s.raids) do all[#all + 1] = r end
    return all
  elseif state.view == "raids" then
    return s.raids
  end
  return s.dungeons
end

-- Slot bucket for filtering; loot with no slot of its own files under Other.
local OTHER_SLOT = "Other"

-- Character sheet order for the filter menu. The journal names a slot with the
-- localised inventory type string, so the ranks come off the same globals the
-- paperdoll is labelled from.
local PAPERDOLL_SLOTS = {
  "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST",
  "INVTYPE_ROBE", "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND",
  "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET",
}
local WEAPON_SLOTS = {
  "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONOFFHAND",
  "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT",
  "INVTYPE_THROWN", "INVTYPE_RELIC",
}

local WEAPON_RANK = 100
local slotRank = {}
do
  local function rank(keys, base)
    for i, key in ipairs(keys) do
      local label = _G[key]
      if label and not slotRank[label] then slotRank[label] = base + i end
    end
  end
  rank(PAPERDOLL_SLOTS, 0)
  rank(WEAPON_SLOTS, WEAPON_RANK)
end

-- Tokens and anything else the paperdoll has no place for follow the armour but
-- stay above the weapons, so the weapons are the last group in the menu.
local function slotRankOf(slot)
  return slotRank[slot] or WEAPON_RANK - 1
end

local function isWeaponSlot(slot)
  return slotRankOf(slot) >= WEAPON_RANK
end

local function sortSlots(slots)
  table.sort(slots, function(a, b)
    local ra, rb = slotRankOf(a), slotRankOf(b)
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  return slots
end
LootWishlist.Browser.sortSlots = sortSlots

------------------------------------------------------------------------
-- Tier tokens
------------------------------------------------------------------------
-- A token carries no equip slot, and the journal's class filter never reaches
-- one, so both facts come off the token's own tooltip: the Use line naming the
-- slot it turns into, and the restriction line naming the classes it turns
-- into it for.

-- The journal sorts its loot into the slot filter's buckets even when the item
-- carries no slot of its own, so that classification is asked first.
local FILTER_SLOTS = {}
do
  local slotKeys = {
    Head = "INVTYPE_HEAD", Neck = "INVTYPE_NECK", Shoulder = "INVTYPE_SHOULDER",
    Cloak = "INVTYPE_CLOAK", Chest = "INVTYPE_CHEST", Wrist = "INVTYPE_WRIST",
    Hand = "INVTYPE_HAND", Waist = "INVTYPE_WAIST", Legs = "INVTYPE_LEGS",
    Feet = "INVTYPE_FEET", Finger = "INVTYPE_FINGER", Trinket = "INVTYPE_TRINKET",
    MainHand = "INVTYPE_WEAPONMAINHAND", OffHand = "INVTYPE_WEAPONOFFHAND",
  }
  local filters = Enum.ItemSlotFilterType or {}
  for name, key in pairs(slotKeys) do
    if filters[name] and _G[key] then FILTER_SLOTS[filters[name]] = _G[key] end
  end
end

-- The Use line names the slot in the singular while the paperdoll labels some
-- of them in the plural, so a label matches by its stem. Longest stem first,
-- so "Main Hand" is never read as "Hand".
local slotStems = {}
do
  for label in pairs(slotRank) do
    slotStems[#slotStems + 1] = { label = label, stem = (label:lower():gsub("s$", "")) }
  end
  table.sort(slotStems, function(a, b)
    if #a.stem ~= #b.stem then return #a.stem > #b.stem end
    return a.stem < b.stem
  end)
end

local function slotFromUseLine(lines)
  for _, line in ipairs(lines) do
    local text = line.leftText
    if text and text:find(ITEM_SPELL_TRIGGER_ONUSE, 1, true) then
      local lower = text:lower()
      for _, candidate in ipairs(slotStems) do
        if lower:find(candidate.stem, 1, true) then return candidate.label end
      end
    end
  end
  return nil
end

-- Class names nest, "Hunter" sitting inside "Demon Hunter", so the longest
-- names are struck out of the list before the shorter ones are looked for.
local function classesNamedIn(text)
  local names = {}
  for i = 1, GetNumClasses() do
    local name, _, id = GetClassInfo(i)
    if name and id then names[#names + 1] = { id = id, name = name } end
  end
  table.sort(names, function(a, b) return #a.name > #b.name end)
  local found, rest = {}, text
  for _, c in ipairs(names) do
    local from, to = rest:find(c.name, 1, true)
    if from then
      found[c.id] = true
      rest = rest:sub(1, from - 1) .. rest:sub(to + 1)
    end
  end
  return next(found) and found or nil
end

-- The restriction line covers races as well as classes, so a line naming no
-- class at all is read as no class restriction rather than as none allowed.
local function classesFromRestrictionLine(lines)
  for _, line in ipairs(lines) do
    if line.type == Enum.TooltipDataLineType.RestrictedRaceClass and line.leftText then
      local classes = classesNamedIn(line.leftText)
      if classes then return classes end
    end
  end
  return nil
end

-- Absent facts record as false rather than nil, so a token whose tooltip says
-- nothing is still read only once.
local function readToken(lines)
  return { slot = slotFromUseLine(lines) or false, classes = classesFromRestrictionLine(lines) or false }
end
LootWishlist.Browser.readToken = readToken

local tokenFacts = {}

-- Nil until the item's data has arrived; the scan's own cache warming brings a
-- redraw with it, so the token sits under Other for that one frame.
local function factsFor(itemID)
  local cached = tokenFacts[itemID]
  if cached then return cached end
  if not (C_TooltipInfo and C_Item and C_Item.IsItemDataCachedByID(itemID)) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
  if not (ok and data and data.lines) then return nil end
  local facts = readToken(data.lines)
  tokenFacts[itemID] = facts
  return facts
end

local function isToken(it)
  return not (it.slot and it.slot ~= "")
end

local function slotOf(it)
  if not isToken(it) then return it.slot end
  if it.filterType and FILTER_SLOTS[it.filterType] then return FILTER_SLOTS[it.filterType] end
  local facts = factsFor(it.itemID)
  return (facts and facts.slot) or OTHER_SLOT
end

local function usableByBrowsedClass(it)
  if not isToken(it) then return true end
  local facts = factsFor(it.itemID)
  if not (facts and facts.classes) then return true end
  return facts.classes[state.classID] == true
end

-- Every slot present in the current view's cached loot, for the filter menu.
local function slotsInView()
  local seen, list = {}, {}
  local insts = instancesForView()
  if not insts then return list end
  local tr = trackEntry()
  for _, inst in ipairs(insts) do
    local key = cacheKey(inst.id, inst.isRaid and tr.raidDiff or tr.dungeonScanDiff)
    local cache = lootCache[key]
    if cache then
      for _, it in ipairs(cache.items) do
        local s = usableByBrowsedClass(it) and slotOf(it)
        if s and not seen[s] then
          seen[s] = true
          list[#list + 1] = s
        end
      end
    end
  end
  return sortSlots(list)
end

local function matchesFilters(it, inst)
  if not usableByBrowsedClass(it) then return false end
  if state.slot and slotOf(it) ~= state.slot then return false end
  if state.search == "" then return true end
  local hay = table.concat({
    it.name or "", slotOf(it), it.armorType or "",
    bossName(it.encounterID) or "", inst.name or "",
  }, " "):lower()
  return hay:find(state.search:lower(), 1, true) ~= nil
end

local function buildRows()
  local insts = instancesForView()
  if not insts then
    return { { kind = "note", text = S.journalNotReady } }, 0, 0
  end
  local rows, shown, onList = {}, 0, 0
  local readAt  -- difficulty actually applied, when it is not the one asked for
  local tr = trackEntry()
  local single = state.view == "instance"
  local viewOnly = not browsingOwnClass()
  local filtering = state.search ~= "" or state.slot ~= nil
  -- A slot filter leaves one or two items per instance, so headers would take
  -- as many rows as the loot; the item sub line already names boss and
  -- instance, so the headers go.
  local hideHeaders = state.slot ~= nil
  -- Slot grouping replaces the instance/boss sections with one section per
  -- gear slot in paperdoll order. A slot filter already flattens the list to
  -- one slot, so the filtered view keeps the source layout.
  local slotGrouping = state.group == "slot" and not hideHeaders
  local bySlot, slotNotes = {}, {}
  for _, inst in ipairs(insts) do
    local diffID = inst.isRaid and tr.raidDiff or tr.dungeonScanDiff
    local cache = requestLoot(inst.id, inst.isRaid, diffID)
    if cache and cache.diffID and cache.diffID ~= diffID then readAt = cache.diffID end
    local section, any = {}, false
    if not cache then
      local waiting = journalShown() and S.waitingForJournal or S.loading
      section[#section + 1] = {
        kind = "note",
        text = (hideHeaders or slotGrouping) and (inst.name .. ": " .. waiting) or waiting,
      }
    else
      -- Boss grouping: raids are shopped boss by boss, so they always group.
      -- Dungeon loot on an M+ difficulty (Hero and Myth tracks) comes from
      -- whole keystone runs, so there the boss is left to the sub line.
      local withBoss = not hideHeaders and not slotGrouping and (inst.isRaid or not tr.keystone)
      local matched = {}
      for _, it in ipairs(cache.items) do
        if matchesFilters(it, inst) then matched[#matched + 1] = it end
      end
      any = #matched > 0
      -- What a wishlist entry from this row is recorded at. Dungeons are read
      -- at the only table the journal has, so the track's own difficulty is
      -- used instead, unless the scan had to fall back to another difficulty
      -- entirely, in which case the honest answer is the one it read.
      local trackDiff = cache.diffID
      if not inst.isRaid and cache.diffID == tr.dungeonScanDiff then
        trackDiff = tr.dungeonTrackDiff
      end
      -- Dungeon loot on a keystone track is the Mythic table's items rebuilt
      -- at the track's own rank, since the journal has no table of its own.
      local trackIlvl = (not inst.isRaid) and tr.trackIlvl or nil
      local function addItem(it)
        shown = shown + 1
        local on = isTracked(it.itemID)
        if on then onList = onList + 1 end
        local row = {
          kind = "item", item = it, instance = inst,
          scannedDiff = trackDiff, tracked = on, single = single, viewOnly = viewOnly,
          trackIlvl = trackIlvl, trackName = trackIlvl and state.track or nil,
          trackLink = trackIlvl and trackItemLink(it.itemID, tr) or nil,
        }
        if slotGrouping then
          local s = slotOf(it)
          if not bySlot[s] then bySlot[s] = {} end
          bySlot[s][#bySlot[s] + 1] = row
        else
          section[#section + 1] = row
        end
      end
      if withBoss then
        -- The journal interleaves bosses in instance-level loot, so grouping
        -- collects per boss rather than watching the encounter change.
        local buckets, order = {}, {}
        for _, it in ipairs(matched) do
          local encID = it.encounterID or -1
          if not buckets[encID] then
            buckets[encID] = {}
            order[#order + 1] = encID
          end
          local b = buckets[encID]
          b[#b + 1] = it
        end
        for _, encID in ipairs(order) do
          section[#section + 1] = { kind = "boss", name = (encID ~= -1 and bossName(encID)) or S.unknownBoss }
          for _, it in ipairs(buckets[encID]) do addItem(it) end
        end
      else
        for _, it in ipairs(matched) do addItem(it) end
      end
      if not any and not filtering and not slotGrouping then
        section[#section + 1] = { kind = "note", text = S.noItems }
      end
    end
    if slotGrouping then
      -- Only loading notes land in the section here; items went to bySlot.
      for _, r in ipairs(section) do slotNotes[#slotNotes + 1] = r end
    -- While filtering, drop instances with no matches entirely.
    elseif #section > 0 and (any or not filtering or not cache) then
      if not hideHeaders then
        rows[#rows + 1] = { kind = "instance", name = inst.name, isRaid = inst.isRaid }
      end
      for _, r in ipairs(section) do rows[#rows + 1] = r end
    end
  end
  if slotGrouping then
    for _, r in ipairs(slotNotes) do rows[#rows + 1] = r end
    local slots = {}
    for s in pairs(bySlot) do slots[#slots + 1] = s end
    sortSlots(slots)
    for _, s in ipairs(slots) do
      rows[#rows + 1] = { kind = "instance", name = s }
      for _, r in ipairs(bySlot[s]) do rows[#rows + 1] = r end
    end
  end
  if #rows == 0 then
    rows[#rows + 1] = { kind = "note", text = S.noMatches }
  end
  return rows, shown, onList, readAt
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------
local function toggleRow(r)
  -- Another class's loot is browse-only: this character could never loot it,
  -- so a wishlist entry would only produce reminders that cannot pay off.
  if r.viewOnly then return end
  local it = r.item
  if isTracked(it.itemID) then
    LootWishlist.RemoveTrackedItem(it.itemID)
  else
    -- Store the track's own link when one resolved, so the wishlist carries
    -- the Hero or Myth item rather than the Mythic table's Champion one.
    local link = r.trackLink or it.link
    if not link and LuckyItem then
      local cached = LuckyItem:GetCached(it.itemID)
      link = cached and cached.link or nil
    end
    LootWishlist.AddTrackedItemWithChain(
      it.itemID, bossName(it.encounterID), r.instance.name, r.instance.isRaid,
      link, it.encounterID, r.instance.id, r.scannedDiff,
      LootWishlist.Const.DIFFICULTY_NAMES[r.scannedDiff], true)
    -- Adding from the browser brings the wishlist up beside it, so the list
    -- fills in as you shop. Removals stay quiet.
    if LootWishlist.UI and LootWishlist.UI.open then LootWishlist.UI.open() end
  end
  scheduleRefresh()
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local function updateStatus(shown, onList, readAt)
  if not statusLabel then return end
  local text = S.status:format(
    shown, shown == 1 and "" or "s", DOT, onList)
  if not browsingOwnClass() then
    text = text .. DOT .. coloredClassName(state.classID) .. S.classLoot
      .. DOT .. WC.textMuted .. S.viewOnly .. WC.reset
  end
  -- The journal does not carry a table for every track. Say which one the
  -- items on screen actually came from rather than let the track button imply
  -- something the data cannot back up.
  if readAt then
    local name = LootWishlist.Const.DIFFICULTY_NAMES[readAt] or tostring(readAt)
    text = text .. DOT .. WC.textMuted .. S.noTrackTable:format(state.track, name) .. WC.reset
  end
  statusLabel:SetText(text)
end

local function paintTrackButtons()
  for _, b in ipairs(trackButtons) do
    if b.trackKey == state.track then
      b:SetBackdropColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 1)
      b:SetBackdropBorderColor(C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3])
      b.label:SetTextColor(C.bgDark[1], C.bgDark[2], C.bgDark[3])
    else
      b:SetBackdropColor(C.bgInput[1], C.bgInput[2], C.bgInput[3], C.bgInput[4])
      b:SetBackdropBorderColor(C.borderDark[1], C.borderDark[2], C.borderDark[3])
      b.label:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
    end
  end
end

local function refreshNow()
  if not lootList then return end
  local rows, shown, onList, readAt = buildRows()
  lootList:SetData(rows)
  updateStatus(shown, onList, readAt)
end

do
  local refreshPending = false
  scheduleRefresh = function()
    if not frame or not frame:IsShown() then return end
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.1, function()
      refreshPending = false
      if not frame or not frame:IsShown() then return end
      -- Mutate the backing array in place so Refresh() keeps scroll position
      -- while async scans stream in; SetData is for deliberate view changes.
      local rows, shown, onList, readAt = buildRows()
      local data = lootList:GetData()
      wipe(data)
      for i, r in ipairs(rows) do data[i] = r end
      lootList:Refresh()
      updateStatus(shown, onList, readAt)
    end)
  end
end

local function buildSidebarRows()
  local rows = {
    { kind = "view", view = "season",   label = S.entireSeason },
    { kind = "view", view = "dungeons", label = S.allDungeons },
    { kind = "view", view = "raids",    label = S.allRaids },
  }
  local s = getSeason()
  if s then
    if #s.dungeons > 0 then
      rows[#rows + 1] = { kind = "header", label = "DUNGEONS" }
      for _, d in ipairs(s.dungeons) do rows[#rows + 1] = { kind = "inst", inst = d } end
    end
    if #s.raids > 0 then
      rows[#rows + 1] = { kind = "header", label = "RAIDS" }
      for _, r in ipairs(s.raids) do rows[#rows + 1] = { kind = "inst", inst = r } end
    end
  end
  return rows
end

local function createSidebarRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  row.sel:SetColorTexture(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 0.18)
  row.sel:Hide()
  row.text = row:CreateFontString(nil, "OVERLAY")
  row.text:SetFont(UI.BODY_FONT, 12)
  row.text:SetPoint("LEFT", 10, 0)
  row.text:SetPoint("RIGHT", -4, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)
  return row
end

local function updateSidebarRow(row, item)
  row.sel:Hide()
  if item.kind == "header" then
    row.text:SetFont(UI.BODY_FONT, 10)
    row.text:SetText(item.label)
    row.text:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
    return
  end
  row.text:SetFont(UI.BODY_FONT, 12)
  local selected
  if item.kind == "view" then
    row.text:SetText(item.label)
    selected = state.view == item.view
  else
    row.text:SetText(item.inst.name)
    selected = state.view == "instance" and state.instanceID == item.inst.id
  end
  if selected then
    row.sel:Show()
    row.text:SetTextColor(C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3])
  else
    row.text:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  end
end

local function onSidebarClick(item)
  if item.kind == "header" then return end
  if item.kind == "view" then
    state.view = item.view
    state.instanceID, state.instanceName, state.isRaid = nil, nil, nil
  else
    state.view = "instance"
    state.instanceID, state.instanceName, state.isRaid = item.inst.id, item.inst.name, item.inst.isRaid
  end
  local db = charDB()
  db.view, db.instanceID, db.instanceName, db.isRaid = state.view, state.instanceID, state.instanceName, state.isRaid
  sidebarList:Refresh()
  refreshNow()
end

------------------------------------------------------------------------
-- Loot pane: virtual scroll with a height per row kind, so a boss heading
-- does not cost the same as an item. LuckyUI.CreateScrollList is uniform
-- height by design, hence the local implementation.
------------------------------------------------------------------------
local function rowHeight(r)
  if r.kind == "instance" then return HEAD_ROW_H end
  if r.kind == "boss"     then return BOSS_ROW_H end
  if r.kind == "note"     then return NOTE_ROW_H end
  return ITEM_ROW_H
end

local function createLootRow(parent)
  local row = CreateFrame("Frame", nil, parent)

  row.bg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(0, 0, 0, 0)

  row.sep = row:CreateTexture(nil, "BACKGROUND")
  row.sep:SetHeight(1)
  row.sep:SetPoint("BOTTOMLEFT", 0, 0)
  row.sep:SetPoint("BOTTOMRIGHT", 0, 0)
  row.sep:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.4)

  row.heading = row:CreateFontString(nil, "OVERLAY")
  row.heading:SetPoint("LEFT", 10, 0)
  row.heading:SetPoint("RIGHT", -10, 0)
  row.heading:SetJustifyH("LEFT")

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(32, 32)
  row.icon:SetPoint("LEFT", 8, 0)
  row:EnableMouse(true)

  row.hl = row:CreateTexture(nil, "HIGHLIGHT")
  row.hl:SetAllPoints()
  row.hl:SetColorTexture(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 0.12)

  row.qbar = row:CreateTexture(nil, "OVERLAY")
  row.qbar:SetSize(2, 32)
  row.qbar:SetPoint("LEFT", row.icon, "LEFT", -3, 0)

  row.right = row:CreateFontString(nil, "OVERLAY")
  row.right:SetFont(UI.BODY_FONT, 10)
  row.right:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  row.right:SetPoint("TOPRIGHT", -36, -7)
  row.right:SetJustifyH("RIGHT")
  row.right:SetWordWrap(false)

  row.name = row:CreateFontString(nil, "OVERLAY")
  row.name:SetFont(UI.BODY_FONT, 12)
  row.name:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -2)
  row.name:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row.sub = row:CreateFontString(nil, "OVERLAY")
  row.sub:SetFont(UI.BODY_FONT, 10)
  row.sub:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 3)
  row.sub:SetPoint("RIGHT", -36, 0)
  row.sub:SetJustifyH("LEFT")
  row.sub:SetWordWrap(false)

  row.btn = UI.CreateButton(row, "+", 24, 22, "secondary")
  row.btn:SetPoint("RIGHT", -4, 0)
  row.btn:SetScript("OnClick", function()
    if row._r and row._r.kind == "item" then toggleRow(row._r) end
  end)
  row.btn:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(C.goldMuted[1], C.goldMuted[2], C.goldMuted[3])
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText((row._r and row._r.tracked) and S.removeFromWishlist or S.addToWishlist, 1, 1, 1)
    GameTooltip:Show()
  end)
  row.btn:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(C.borderDark[1], C.borderDark[2], C.borderDark[3])
    GameTooltip:Hide()
  end)

  row:SetScript("OnEnter", function(self)
    if self._link then
      LootWishlist.ApplyWardrobePreviewFlag(self)
      LootWishlist.UI.AnchorItemTooltip(self)
      GameTooltip:SetHyperlink(self._link)
      -- With no donor resolved yet the link is still the Mythic one, so say
      -- what the track this row is being browsed on is actually worth rather
      -- than contradict the row. A track link speaks for itself.
      local r = self._r
      if r and r.trackIlvl and not r.trackLink then
        GameTooltip:AddLine(string.format("%s track: item level %d", r.trackName, r.trackIlvl),
          0.788, 0.659, 0.298)
      end
      GameTooltip:Show()
      LootWishlist.UI.PlaceComparisonTooltips()
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnMouseUp", function(self)
    if self._r and self._r.kind == "item" then toggleRow(self._r) end
  end)

  return row
end

local function updateLootRow(row, r)
  row.heading:Hide()
  row.icon:Hide()
  row.qbar:Hide()
  row.name:Hide()
  row.sub:Hide()
  row.right:Hide()
  row.btn:Hide()
  row.sep:Show()
  row.bg:SetColorTexture(0, 0, 0, 0)
  row._r = r
  row._link = nil

  row.hl:SetAlpha(r.kind == "item" and 1 or 0)

  if r.kind == "instance" then
    row.heading:SetFont(UI.TITLE_FONT, 13, "OUTLINE")
    local raidTag = r.isRaid and "  |cffff8000[Raid]|r" or ""
    row.heading:SetText(string.format("|cffffd100%s|r%s", r.name or "", raidTag))
    row.heading:Show()
    row.bg:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.6)
    row.sep:SetColorTexture(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 0.4)
    return
  end
  row.sep:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.4)

  if r.kind == "boss" then
    row.heading:SetFont(UI.TITLE_FONT, 11, "")
    row.heading:SetText(string.format("  |cffc9a84c%s|r", r.name or ""))
    row.heading:Show()
    row.bg:SetColorTexture(C.bgPanel[1], C.bgPanel[2], C.bgPanel[3], 0.5)
    return
  end

  if r.kind == "note" then
    row.heading:SetFont(UI.BODY_FONT, 11)
    row.heading:SetText("   " .. WC.textMuted .. (r.text or "") .. WC.reset)
    row.heading:Show()
    return
  end

  -- item row
  local it = r.item
  local cached = LuckyItem and LuckyItem:GetCached(it.itemID)
  local link = r.trackLink or it.link or (cached and cached.link)
  row._link = link or ("item:" .. tostring(it.itemID))

  local iconTex = it.icon or (cached and cached.icon)
  if not iconTex and C_Item and C_Item.GetItemIconByID then
    iconTex = C_Item.GetItemIconByID(it.itemID)
  end
  row.icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
  row.icon:Show()

  local quality = cached and cached.quality
  if not quality and C_Item and C_Item.GetItemQualityByID then
    quality = C_Item.GetItemQualityByID(it.itemID)
  end
  if quality then
    local qr, qg, qb = GetItemQualityColor(quality)
    if qr then
      row.qbar:SetColorTexture(qr, qg, qb, 1)
      row.qbar:Show()
    end
  end

  row.name:SetText(link or it.name or ("Item " .. tostring(it.itemID)))
  row.name:Show()

  local rightParts = {}
  -- For raids the journal's link carries the difficulty's own bonus IDs, so it
  -- is already the track's item level. Dungeons above Champion have no table
  -- of their own, so the track's level is used instead of the Mythic link's.
  local ilvl = r.trackIlvl
  if not ilvl then
    ilvl = link and C_Item and C_Item.GetDetailedItemLevelInfo
      and C_Item.GetDetailedItemLevelInfo(link)
  end
  if ilvl and ilvl > 1 then
    rightParts[#rightParts + 1] = WC.goldAccent .. ilvl .. WC.reset
  end
  local slot = slotOf(it)
  if slot ~= OTHER_SLOT then rightParts[#rightParts + 1] = slot end
  if it.armorType and it.armorType ~= "" then rightParts[#rightParts + 1] = it.armorType end
  if #rightParts > 0 then
    row.right:SetText(table.concat(rightParts, DOT))
    row.right:Show()
  end

  local subParts = {}
  local boss = bossName(it.encounterID)
  if boss then subParts[#subParts + 1] = boss end
  if not r.single and r.instance and r.instance.name then subParts[#subParts + 1] = r.instance.name end
  if it.veryRare then subParts[#subParts + 1] = WC.purple .. S.veryRare .. WC.reset end
  if #subParts > 0 then
    row.sub:SetText(table.concat(subParts, DOT))
    row.sub:Show()
  end

  if not r.viewOnly then
    if r.tracked then
      row.btn:SetBackdropColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 0.9)
      row.btn.label:SetText(CROSS)
      row.btn.label:SetTextColor(C.bgDark[1], C.bgDark[2], C.bgDark[3])
    else
      row.btn:SetBackdropColor(C.bgInput[1], C.bgInput[2], C.bgInput[3], C.bgInput[4])
      row.btn.label:SetText("+")
      row.btn.label:SetTextColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3])
    end
    row.btn:Show()
  end
end

-- A pooled, mixed-height scrolling list over rows built by createLootRow.
-- Mirrors LuckyUI.CreateScrollList's contract (SetData/Refresh/GetData) so the
-- rest of the module does not care which one it is talking to.
local function createLootList(parent)
  local GUTTER = 14
  local list = CreateFrame("Frame", nil, parent)
  list.data = {}
  list.rows = {}

  local area = CreateFrame("Frame", nil, list)
  area:SetClipsChildren(true)
  area:SetPoint("TOPLEFT", 0, 0)
  area:SetPoint("BOTTOMRIGHT", -GUTTER, 0)

  local bar = CreateFrame("Slider", nil, list)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(GUTTER - 4)
  bar:SetPoint("TOPRIGHT", 0, -2)
  bar:SetPoint("BOTTOMRIGHT", 0, 2)
  bar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
  bar:SetMinMaxValues(0, 0)
  bar:SetValue(0)

  local trough = bar:CreateTexture(nil, "BACKGROUND")
  trough:SetAllPoints()
  trough:SetColorTexture(C.bgInput[1], C.bgInput[2], C.bgInput[3], 0.6)

  local thumb = bar:GetThumbTexture()
  thumb:SetColorTexture(C.goldMuted[1], C.goldMuted[2], C.goldMuted[3], 0.9)
  thumb:SetWidth(GUTTER - 4)

  local function totalHeight()
    local h = 0
    for _, r in ipairs(list.data) do h = h + rowHeight(r) end
    return h
  end

  function list:UpdateView()
    local areaH = area:GetHeight()
    local total = totalHeight()
    local maxScroll = math.max(0, total - areaH)

    bar:SetMinMaxValues(0, maxScroll)
    if maxScroll <= 0 then
      bar:Hide()
      bar:SetValue(0)
    else
      bar:Show()
      thumb:SetHeight(math.max(20, areaH * (areaH / total)))
    end

    local offset = math.min(bar:GetValue(), maxScroll)
    local areaW = area:GetWidth()
    local used, y = 0, 0
    for _, r in ipairs(self.data) do
      local h = rowHeight(r)
      if y + h > offset and y < offset + areaH then
        used = used + 1
        local row = self.rows[used]
        if not row then
          row = createLootRow(area)
          self.rows[used] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(y - offset))
        row:SetWidth(areaW)
        row:SetHeight(h)
        updateLootRow(row, r)
        row:Show()
      end
      y = y + h
      if y >= offset + areaH then break end
    end
    for i = used + 1, #self.rows do
      self.rows[i]._r = nil
      self.rows[i]:Hide()
    end
  end

  function list:Refresh() self:UpdateView() end
  function list:GetData() return self.data end
  function list:SetData(arr)
    self.data = arr or {}
    bar:SetValue(0)
    self:UpdateView()
  end

  bar:SetScript("OnValueChanged", function() list:UpdateView() end)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    bar:SetValue(bar:GetValue() - delta * ITEM_ROW_H * 3)
  end)
  list:SetScript("OnSizeChanged", function(self) self:UpdateView() end)

  return list
end

local function savePosition(f)
  local pos = charDB().windowPos or {}
  pos.point, _, pos.relPoint, pos.x, pos.y = f:GetPoint(1)
  pos.w, pos.h = f:GetSize()
  charDB().windowPos = pos
end

local function ensureFrame()
  if frame then return end

  -- Restore persisted browse state. The class always opens as the player's
  -- own: another class's loot is view-only, and coming back a session later
  -- to a browser that cannot add anything would read as broken. The spec
  -- sticks, it is a preference about your own loot.
  local db = charDB()
  state.track = db.track or state.track
  state.view = db.view or state.view
  state.group = db.group or state.group
  state.instanceID, state.instanceName, state.isRaid = db.instanceID, db.instanceName, db.isRaid
  if state.view == "instance" and not state.instanceID then state.view = "dungeons" end
  state.classID = playerClassID()
  state.specID = db.specID or 0

  frame = CreateFrame("Frame", "LootWishlistBrowserFrame", UIParent, "BackdropTemplate")
  frame:SetSize(DEFAULT_W, DEFAULT_H)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H) end
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("MEDIUM")
  frame:SetFrameLevel(20)
  frame:EnableMouse(true)
  frame.lootWishlistWindow = true
  frame:SetBackdrop(UI.Backdrop)
  frame:SetBackdropColor(C.bgDark[1], C.bgDark[2], C.bgDark[3], C.bgDark[4])
  frame:SetBackdropBorderColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3])

  local header = UI.CreateHeader(frame, S.title)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() frame:StartMoving() end)
  header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    savePosition(frame)
  end)

  local resizer = CreateFrame("Button", nil, frame)
  resizer:SetSize(16, 16)
  resizer:SetPoint("BOTTOMRIGHT", -4, 4)
  resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  resizer:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  resizer:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    savePosition(frame)
  end)

  -- Sidebar
  sidebarList = UI.CreateScrollList(frame, {
    rowHeight = SIDE_ROW_H,
    createRow = createSidebarRow,
    updateRow = updateSidebarRow,
    onClick   = onSidebarClick,
  })
  sidebarList:SetPoint("TOPLEFT", 2, -36)
  sidebarList:SetPoint("BOTTOMLEFT", 2, 36)
  sidebarList:SetWidth(SIDEBAR_W)

  local vline = frame:CreateTexture(nil, "ARTWORK")
  vline:SetWidth(1)
  vline:SetPoint("TOPLEFT", SIDEBAR_W + 4, -34)
  vline:SetPoint("BOTTOMLEFT", SIDEBAR_W + 4, 34)
  vline:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3])

  -- Toolbar: track picker + search
  local toolbar = CreateFrame("Frame", nil, frame)
  toolbar:SetPoint("TOPLEFT", SIDEBAR_W + 6, -36)
  toolbar:SetPoint("TOPRIGHT", -2, -36)
  toolbar:SetHeight(TOOLBAR_H)

  local trackLabel = toolbar:CreateFontString(nil, "OVERLAY")
  trackLabel:SetFont(UI.BODY_FONT, 12)
  trackLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  trackLabel:SetPoint("TOPLEFT", 4, -6)
  trackLabel:SetText("Track:")

  local prev
  for _, t in ipairs(LootWishlist.Const.TRACKS) do
    local b = UI.CreateButton(toolbar, t.key, 68, 22, "secondary")
    b.trackKey = t.key
    if prev then
      b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    else
      b:SetPoint("LEFT", trackLabel, "RIGHT", 8, 0)
    end
    b:SetScript("OnEnter", function(self)
      if self.trackKey ~= state.track then
        self:SetBackdropBorderColor(C.goldMuted[1], C.goldMuted[2], C.goldMuted[3])
      end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(t.key .. " track", 1, 1, 1)
      local tip = TRACK_TIPS[t.key] or ""
      if t.keystoneLevel then tip = tip:format(t.keystoneLevel) end
      GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
      paintTrackButtons()
      GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
      if state.track == self.trackKey then return end
      state.track = self.trackKey
      charDB().track = state.track
      paintTrackButtons()
      refreshNow()
    end)
    trackButtons[#trackButtons + 1] = b
    prev = b
  end
  paintTrackButtons()

  -- Group mode: lay the list out by where loot drops or by gear slot
  local groupDropdown = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1DropdownTemplate")
  groupDropdown:SetPoint("TOPRIGHT", -4, -4)
  groupDropdown:SetWidth(110)
  groupDropdown:SetDefaultText(state.group == "slot" and S.bySlot or S.bySource)
  groupDropdown:SetupMenu(function(_, root)
    local function groupRadio(label, value)
      root:CreateRadio(label,
        function() return state.group == value end,
        function()
          state.group = value
          charDB().group = value
          refreshNow()
        end)
    end
    groupRadio(S.bySource, "source")
    groupRadio(S.bySlot, "slot")
  end)

  -- Slot filter: every slot present in the current view's loot. The menu is
  -- regenerated on each open, so it tracks the view and streaming scans.
  local slotDropdown = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1DropdownTemplate")
  slotDropdown:SetPoint("BOTTOMRIGHT", -4, 3)
  slotDropdown:SetWidth(130)
  slotDropdown:SetDefaultText(S.allSlots)
  slotDropdown:SetupMenu(function(_, root)
    root:CreateRadio(S.allSlots,
      function() return state.slot == nil end,
      function()
        state.slot = nil
        refreshNow()
      end)
    local slots = slotsInView()
    -- Keep the active slot listed even in a view that has none of it, so the
    -- button text and selection stay truthful.
    if state.slot then
      local listed = false
      for _, s in ipairs(slots) do
        if s == state.slot then listed = true break end
      end
      if not listed then
        slots[#slots + 1] = state.slot
        sortSlots(slots)
      end
    end
    local weaponsStarted = false
    for _, slot in ipairs(slots) do
      if not weaponsStarted and isWeaponSlot(slot) then
        weaponsStarted = true
        root:CreateDivider()
      end
      root:CreateRadio(slot,
        function() return state.slot == slot end,
        function()
          state.slot = slot
          refreshNow()
        end)
    end
  end)

  -- Class and spec filter: the browser opens on the player's class, and any
  -- other class can be browsed read-only. Spec radios narrow the loot the way
  -- the Adventure Guide's own filter does.
  local function specRadio(parent, classID, specID, text)
    parent:CreateRadio(text,
      function() return state.classID == classID and state.specID == specID end,
      function()
        state.classID, state.specID = classID, specID
        -- Only a spec of your own class is worth remembering; a foreign
        -- class peek should not survive into the next session's open.
        if classID == playerClassID() then charDB().specID = specID end
        refreshNow()
      end)
  end

  local function addSpecEntries(parent, classID)
    specRadio(parent, classID, 0, "All " .. coloredClassName(classID))
    for i = 1, GetNumSpecializationsForClassID(classID) or 0 do
      local specID, specName = GetSpecializationInfoForClassID(classID, i)
      if specID then
        specRadio(parent, classID, specID, specName .. " " .. coloredClassName(classID))
      end
    end
  end

  local classDropdown = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1DropdownTemplate")
  classDropdown:SetPoint("BOTTOMRIGHT", slotDropdown, "BOTTOMLEFT", -6, 0)
  classDropdown:SetWidth(140)
  classDropdown:SetDefaultText(coloredClassName(playerClassID()))
  classDropdown:SetupMenu(function(_, root)
    addSpecEntries(root, playerClassID())
    root:CreateDivider()
    for i = 1, GetNumClasses() do
      local _, _, id = GetClassInfo(i)
      if id and id ~= playerClassID() then
        addSpecEntries(root:CreateButton(coloredClassName(id)), id)
      end
    end
  end)

  searchBox = UI.CreateSearchBox(toolbar, {
    height = 24,
    placeholder = S.searchPlaceholder,
    onChange = function(query)
      if query == state.search then return end
      state.search = query
      refreshNow()
    end,
  })
  searchBox:ClearAllPoints()
  searchBox:SetPoint("BOTTOMLEFT", 4, 4)
  searchBox:SetPoint("BOTTOMRIGHT", classDropdown, "BOTTOMLEFT", -8, 1)

  -- Loot list
  lootList = createLootList(frame)
  lootList:SetPoint("TOPLEFT", SIDEBAR_W + 6, -(36 + TOOLBAR_H + 2))
  lootList:SetPoint("BOTTOMRIGHT", -2, 36)

  -- Status bar
  local statusBar = CreateFrame("Frame", nil, frame)
  statusBar:SetHeight(28)
  statusBar:SetPoint("BOTTOMLEFT", 2, 4)
  statusBar:SetPoint("BOTTOMRIGHT", -2, 4)

  local statusLine = statusBar:CreateTexture(nil, "ARTWORK")
  statusLine:SetHeight(1)
  statusLine:SetPoint("TOPLEFT")
  statusLine:SetPoint("TOPRIGHT")
  statusLine:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3])

  statusLabel = statusBar:CreateFontString(nil, "OVERLAY")
  statusLabel:SetFont(UI.BODY_FONT, 11)
  statusLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  statusLabel:SetPoint("LEFT", 8, -2)

  local closeBtn = UI.CreateButton(statusBar, "Close", 80, 22, "secondary")
  closeBtn:SetPoint("RIGHT", -4, -2)
  closeBtn:SetScript("OnClick", function() frame:Hide() end)

  statusLabel:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
  statusLabel:SetJustifyH("LEFT")
  statusLabel:SetWordWrap(false)

  -- Restore saved position and size
  local pos = charDB().windowPos
  if pos and pos.point then
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    -- A size saved before the minimum grew would let controls overlap.
    if pos.w and pos.h then frame:SetSize(math.max(pos.w, MIN_W), math.max(pos.h, MIN_H)) end
  end

  table.insert(UISpecialFrames, "LootWishlistBrowserFrame")
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function LootWishlist.Browser.open()
  ensureFrame()
  for key, entry in pairs(lootCache) do
    if entry.empty then lootCache[key] = nil end
  end
  frame:Show()
  frame:Raise()
  sidebarList:SetData(buildSidebarRows())
  refreshNow()
end

function LootWishlist.Browser.hide()
  if frame then frame:Hide() end
end

function LootWishlist.Browser.isShown()
  return (frame and frame:IsShown()) and true or false
end

-- Report the season's track data and a sample rebuilt link per keystone
-- track, clickable in chat, so a wrong bonus ID or item level shows itself.
function LootWishlist.Browser.DiagnoseTracks()
  local P = "|cffC9A84CLoot Wishlist|r: "
  local sampleID
  for _, cache in pairs(lootCache) do
    for _, it in ipairs(cache.items) do
      local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(it.itemID)
      if classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon then
        sampleID = it.itemID
        break
      end
    end
    if sampleID then break end
  end
  for _, tr in ipairs(LootWishlist.Const.TRACKS) do
    if tr.keystone then
      print(P .. tr.key .. ": rank 1 is item level " .. tostring(tr.trackIlvl)
        .. " (bonus " .. tostring(tr.trackBonus) .. ")")
      if sampleID then
        local base = select(3, C_Item.GetDetailedItemLevelInfo(sampleID))
        print(P .. "  sample (base " .. tostring(base) .. "): "
          .. (trackItemLink(sampleID, tr) or "no link built"))
      end
    end
  end
  if not sampleID then print(P .. "open the browser first so there is loot to sample") end
end

function LootWishlist.Browser.toggle()
  if frame and frame:IsShown() then
    LootWishlist.Browser.hide()
  else
    LootWishlist.Browser.open()
  end
end

-- Keep row toggle states truthful when the wishlist changes elsewhere
LootWishlist.Browser.refresh = function() scheduleRefresh() end
