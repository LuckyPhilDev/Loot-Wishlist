-- Loot Wishlist - Share (export/import the wishlist as a LuckyProfiles string)

LootWishlist = LootWishlist or {}
LootWishlist.Share = {}

local Share = LootWishlist.Share

local S = LootWishlist.Strings.share
local P = LootWishlist.Strings.addon.prefix

-- Envelope stamped onto every export so a share string from another Lucky
-- addon, or a newer wishlist format, is refused with a clear message.
local ADDON_TAG = "LootWishlist"
local FORMAT = 1

-- A wishlist bigger than this is not a wishlist someone built by hand; refuse
-- rather than let a crafted string stuff the SavedVariables.
local MAX_ITEMS = 500

-- An honest export never nears these; a crafted one could pack megabytes into
-- a single field.
local MAX_NAME_LEN = 120
local MAX_LINK_LEN = 400

-- Every id ends up in C_Item and journal APIs that take 32-bit ids, and NaN
-- or infinity would poison table keys downstream (a NaN instanceID errors the
-- wishlist render), so only positive int32 values count as ids at all.
local function isID(v)
  return type(v) == "number" and v > 0 and v % 1 == 0 and v < 2147483648
end

local function cleanString(v, maxLen)
  if type(v) == "string" and v ~= "" and #v <= maxLen then return v end
  return nil
end

-- The portable subset of a tracked entry. Specs, icons and qualities are
-- recomputed on the importing character, so only the journal facts travel.
local function cleanItem(raw)
  if type(raw) ~= "table" or not isID(raw.id) then return nil end
  local item = { id = raw.id, isRaid = raw.isRaid and true or false }
  item.boss = cleanString(raw.boss, MAX_NAME_LEN)
  item.dungeon = cleanString(raw.dungeon, MAX_NAME_LEN)
  item.link = cleanString(raw.link, MAX_LINK_LEN)
  item.difficultyName = cleanString(raw.difficultyName, MAX_NAME_LEN)
  if isID(raw.encounterID) then item.encounterID = raw.encounterID end
  if isID(raw.instanceID) then item.instanceID = raw.instanceID end
  if isID(raw.difficultyID) then item.difficultyID = raw.difficultyID end
  return item
end

-- Must mirror the key AddTrackedItemQuiet composes, so imported entries land
-- on (and merge over) the same slots the addon would create itself.
local function keyForItem(item)
  if item.difficultyID then
    return tostring(item.id) .. "@" .. tostring(item.difficultyID)
  end
  return tostring(item.id)
end

function Share.BuildPayload(tracked)
  local items = {}
  for _, info in pairs(tracked or {}) do
    items[#items + 1] = cleanItem(info)
  end
  table.sort(items, function(a, b)
    if a.id ~= b.id then return a.id < b.id end
    return (a.difficultyID or 0) < (b.difficultyID or 0)
  end)
  return { addon = ADDON_TAG, format = FORMAT, items = items }
end

-- Validate a decoded share string down to a clean item list, deduplicated by
-- the same key the wishlist stores under. Returns nil plus a user-facing
-- reason when the table is not a usable wishlist export.
function Share.SanitizePayload(decoded)
  if type(decoded) ~= "table" or decoded.addon ~= ADDON_TAG
  or type(decoded.format) ~= "number" or type(decoded.items) ~= "table" then
    return nil, S.notAnExport
  end
  if decoded.format > FORMAT then
    return nil, S.newerVersion
  end
  local items, seen = {}, {}
  for _, raw in pairs(decoded.items) do
    local item = cleanItem(raw)
    if item then
      local key = keyForItem(item)
      if not seen[key] then
        seen[key] = true
        items[#items + 1] = item
      end
    end
  end
  if #items == 0 then
    return nil, S.noItems
  end
  if #items > MAX_ITEMS then
    return nil, S.tooManyItems:format(MAX_ITEMS)
  end
  return items
end

-- Write a sanitized item list into the wishlist, clearing it first when
-- replacing. Returns how many entries were new and how many already existed
-- (existing ones are overwritten by the imported copy).
function Share.ApplyImport(items, replace)
  if replace and LootWishlist.ClearAllTracked then LootWishlist.ClearAllTracked() end
  local tracked = (LootWishlist.GetTracked and LootWishlist.GetTracked()) or {}
  local added, existing = 0, 0
  for _, item in ipairs(items) do
    if tracked[keyForItem(item)] then existing = existing + 1 else added = added + 1 end
    LootWishlist.AddTrackedItemQuiet(item.id, item.boss, item.dungeon, item.isRaid,
      item.link, item.encounterID, item.instanceID, item.difficultyID, item.difficultyName)
  end
  return added, existing
end

local function countText(n)
  return n == 1 and S.oneItem or S.manyItems:format(n)
end

local function finishImport(items, replace)
  local added, existing = Share.ApplyImport(items, replace)
  if replace then
    print(P .. S.imported:format(countText(added)))
  elseif added == 0 then
    print(P .. S.allAlreadyTracked)
  elseif existing == 1 then
    print(P .. S.addedOneExisting:format(countText(added)))
  elseif existing > 1 then
    print(P .. S.addedManyExisting:format(countText(added), existing))
  else
    print(P .. S.added:format(countText(added)))
  end
  if LootWishlist.UI and LootWishlist.UI.open then LootWishlist.UI.open() end
end

function Share.Export()
  local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked()
  if not tracked or not next(tracked) then
    print(P .. S.nothingToExport)
    return
  end
  LuckyProfiles:ShowExport(S.exportTitle, Share.BuildPayload(tracked))
end

function Share.Import()
  LuckyProfiles:ShowImport(S.importTitle, function(decoded)
    local items, err = Share.SanitizePayload(decoded)
    if not items then
      print(P .. err)
      return
    end
    local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked()
    if not tracked or not next(tracked) then
      finishImport(items, false)
      return
    end
    StaticPopupDialogs["LOOTWISHLIST_IMPORT_MODE"] = {
      text = S.importPrompt,
      button1 = S.importAdd,
      button3 = S.importReplace,
      button2 = S.importCancel,
      OnAccept = function(_, data) finishImport(data, false) end,
      OnAlt = function(_, data) finishImport(data, true) end,
      timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local dialog = StaticPopup_Show("LOOTWISHLIST_IMPORT_MODE", countText(#items))
    if dialog then
      dialog.data = items
    else
      print(P .. S.tooManyPopups)
    end
  end)
end
