-- The wishlist grouped by instance and boss, in the one order the wishlist
-- window and the summary window both show.

LootWishlist = LootWishlist or {}
LootWishlist.Layout = LootWishlist.Layout or {}

local Layout = LootWishlist.Layout
local S = LootWishlist.Strings.wishlist

local encounterOrderCache = {}
local function getEncounterOrder(instanceID)
  if not instanceID then return nil end
  if encounterOrderCache[instanceID] then return encounterOrderCache[instanceID] end
  local EJ_GetEncounterInfoByIndex = _G["EJ_GetEncounterInfoByIndex"]
  if type(EJ_GetEncounterInfoByIndex) ~= "function" then return nil end
  local order
  local EJ_SelectInstance = _G["EJ_SelectInstance"]
  local prevInstance = (EncounterJournal and EncounterJournal.instanceID) or nil
  if type(EJ_SelectInstance) == "function" then
    pcall(EJ_SelectInstance, instanceID)
    order = { id = {}, name = {} }
    for idx = 1, 200 do
      local ename, _, encounterID = EJ_GetEncounterInfoByIndex(idx)
      if not ename then break end
      if encounterID then order.id[encounterID] = idx end
      order.name[ename:lower()] = idx
    end
    if prevInstance and prevInstance ~= instanceID then pcall(EJ_SelectInstance, prevInstance) end
  end
  if not order or not next(order.id) then
    order = { id = {}, name = {} }
    for idx = 1, 200 do
      local ename, _, encounterID = EJ_GetEncounterInfoByIndex(idx, instanceID)
      if not ename then break end
      if encounterID then order.id[encounterID] = idx end
      order.name[ename:lower()] = idx
    end
  end
  -- A journal that has not answered yet lists no encounters at all; caching
  -- that would fix the fallback boss order in place for the session, so an
  -- empty map is returned but not kept and the next refresh reads again.
  if next(order.id) or next(order.name) then
    encounterOrderCache[instanceID] = order
  end
  return order
end

function Layout.Order()
  local settings = LootWishlistDB and LootWishlistDB.settings
  return settings and settings.wishlistOrder or "journal"
end

function Layout.SetOrder(key)
  local settings = LootWishlistDB and LootWishlistDB.settings
  if settings then settings.wishlistOrder = key end
  if LootWishlist.UI and LootWishlist.UI.refresh then LootWishlist.UI.refresh() end
  if LootWishlist.Summary and LootWishlist.Summary.refresh then LootWishlist.Summary.refresh() end
end

-- Headings count what is still being chased, one per item however many
-- difficulties it is tracked at, so they agree with the status bar.
local function uniqueCount(items)
  local seen, n = {}, 0
  for _, it in ipairs(items) do
    if not it.obtained and not seen[it.id] then
      seen[it.id] = true
      n = n + 1
    end
  end
  return n
end

local function journalRank(orderMap, boss)
  return orderMap and (orderMap.id[boss.encounterID] or orderMap.name[boss.name:lower()]) or nil
end

local function bossBefore(a, b, orderMap, byCount)
  if byCount and a.count ~= b.count then return a.count > b.count end
  local ao, bo = journalRank(orderMap, a), journalRank(orderMap, b)
  if ao and bo and ao ~= bo then return ao < bo end
  if ao and not bo then return true end
  if bo and not ao then return false end
  if a.encounterID ~= -1 and b.encounterID ~= -1 and a.encounterID ~= b.encounterID then
    return a.encounterID < b.encounterID
  end
  return a.name < b.name
end

local function instanceBefore(a, b, byCount)
  if a.isRaid ~= b.isRaid then return a.isRaid end
  if byCount and a.count ~= b.count then return a.count > b.count end
  return a.name < b.name
end

local function bossesOf(items, instanceID, byCount)
  local byName, bosses = {}, {}
  for _, it in ipairs(items) do
    local name = (it.info.boss and it.info.boss ~= "") and it.info.boss or S.unknownBoss
    local boss = byName[name]
    if not boss then
      boss = { name = name, encounterID = -1, items = {} }
      byName[name] = boss
      bosses[#bosses + 1] = boss
    end
    if it.info.encounterID then boss.encounterID = it.info.encounterID end
    boss.items[#boss.items + 1] = it
  end
  for _, boss in ipairs(bosses) do boss.count = uniqueCount(boss.items) end
  local orderMap = getEncounterOrder(instanceID)
  table.sort(bosses, function(a, b) return bossBefore(a, b, orderMap, byCount) end)
  return bosses
end

local function entryBefore(a, b)
  local ab, bb = a.info.boss or "", b.info.boss or ""
  if ab ~= bb then return ab < bb end
  if a.id ~= b.id then return a.id < b.id end
  return (a.info.difficultyID or 0) < (b.info.difficultyID or 0)
end

-- Every wishlist entry grouped by instance, raids first, with raid entries
-- grouped again by boss. opts.includeObtained folds the obtained items in;
-- opts.keep(entry) drops any entry it answers false for.
function Layout.Build(opts)
  opts = opts or {}
  local groups, ordered = {}, {}
  local function collect(source, obtained)
    for key, info in pairs(source or {}) do
      local entry = { key = key, id = info.id or tonumber(key) or 0, info = info, obtained = obtained }
      if not opts.keep or opts.keep(entry) then
        local name = info.dungeon or "Unknown"
        local g = groups[name]
        if not g then
          g = { name = name, isRaid = false, instanceID = info.instanceID, items = {} }
          groups[name] = g
          ordered[#ordered + 1] = g
        end
        if info.isRaid then g.isRaid = true end
        g.instanceID = g.instanceID or info.instanceID
        g.items[#g.items + 1] = entry
      end
    end
  end
  collect(LootWishlist.GetTracked())
  if opts.includeObtained then collect(LootWishlist.GetObtained and LootWishlist.GetObtained(), true) end

  local byCount = Layout.Order() == "count"
  for _, g in ipairs(ordered) do
    table.sort(g.items, entryBefore)
    g.count = uniqueCount(g.items)
    if g.isRaid then g.bosses = bossesOf(g.items, g.instanceID, byCount) end
  end
  table.sort(ordered, function(a, b) return instanceBefore(a, b, byCount) end)
  return ordered
end
