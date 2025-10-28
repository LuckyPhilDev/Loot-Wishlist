-- Loot Wishlist - Core and SavedVariables

local ADDON_NAME = ... or "LootWishlist"

-- (Legacy migration removed)

-- New per-character DB
LootWishlistCharDB = LootWishlistCharDB or {}
-- New account-wide DB
LootWishlistDB = LootWishlistDB or {}

local DEBUG = false

-- Public API table
LootWishlist = {
  DEBUG = function() return DEBUG end,
}

-- Local state
local trackedItems -- assigned after DB init; may use string keys for difficulty variants

-- No basic frame: AceGUI is the only UI path now

-- Spec detection ------------------------------------------------------------
local function tryGetItemSpecsImmediate(itemID, itemLink)
  local query = itemLink or (itemID and ("item:"..tostring(itemID))) or itemID
  if not query then return nil end
  -- Prefer modern API
  if C_Item and C_Item.GetItemSpecInfo then
    local ok, res = pcall(C_Item.GetItemSpecInfo, query)
    if ok and type(res) == "table" and #res > 0 then return res end
  end
  return nil
end

local function computeItemSpecs(itemID, itemLink, onDone)
  -- Try immediately first
  local specs = tryGetItemSpecsImmediate(itemID, itemLink)
  if specs then if onDone then onDone(specs) end; return end
  -- Try async load via Item API if available
  local ItemAPI = _G and _G["Item"]
  if type(ItemAPI) == "table" and ItemAPI.CreateFromItemID then
    local obj = ItemAPI:CreateFromItemID(itemID)
    if obj and obj.ContinueOnItemLoad then
      obj:ContinueOnItemLoad(function()
        local again = tryGetItemSpecsImmediate(itemID, (obj.GetItemLink and obj:GetItemLink()) or itemLink)
        if onDone then onDone(again or {}) end
      end)
      return
    end
  end
  -- Fallback: request and call back empty
  if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
  if onDone then onDone({}) end
end

function LootWishlist.GetSpecNames(specIDs)
  local names = {}
  if type(specIDs) ~= "table" then return names end
  local getInfo = _G and _G["GetSpecializationInfoByID"]
  for _, sid in ipairs(specIDs) do
    if type(getInfo) == "function" then
      local ok, _specID, specName = pcall(getInfo, sid)
      if ok and type(specName) == "string" and specName ~= "" then
        table.insert(names, specName)
      end
    end
  end
  return names
end

-- DB and migration -----------------------------------------------------------
local function InitializeDB()
  -- Initialize per-character DB
  LootWishlistCharDB.trackedItems = LootWishlistCharDB.trackedItems or {}
  LootWishlist.trackedItems = LootWishlistCharDB.trackedItems
  trackedItems = LootWishlist.trackedItems

  -- Initialize settings tables
  LootWishlistCharDB.settings = LootWishlistCharDB.settings or {}
  LootWishlistDB.settings = LootWishlistDB.settings or {}

  local C = LootWishlist.Const or {}
  local charS = LootWishlistCharDB.settings
  local acctS = LootWishlistDB.settings

  -- Migration: move whisper/party templates from per-character to account-wide if present
  if charS.whisperTemplate and not acctS.whisperTemplate then acctS.whisperTemplate = charS.whisperTemplate; charS.whisperTemplate = nil end
  if charS.partyTemplate and not acctS.partyTemplate then acctS.partyTemplate = charS.partyTemplate; charS.partyTemplate = nil end

  -- Migration: move raid roll alert toggle from per-character to account-wide
  if charS.enableRaidRollAlert ~= nil and acctS.enableRaidRollAlert == nil then
    acctS.enableRaidRollAlert = charS.enableRaidRollAlert
    charS.enableRaidRollAlert = nil
  end

  -- Defaults for account-wide templates
  acctS.whisperTemplate = acctS.whisperTemplate or C.DEFAULT_WHISPER_TEMPLATE 
  acctS.partyTemplate = acctS.partyTemplate or C.DEFAULT_PARTY_TEMPLATE
  if acctS.debug == nil then acctS.debug = false end
  DEBUG = acctS.debug and true or false

  -- Account-wide toggle default
  if acctS.enableRaidRollAlert == nil then acctS.enableRaidRollAlert = true end

  -- Restore window position is handled by Ace frame status table

  -- Gentle migration for legacy tracked shapes (pre-difficulty and non-table values)
  do
    local toAdd = {}
    local toRemove = {}
    local function parseKeyParts(k)
      if k == nil then return nil, nil end
      local ks = tostring(k)
  local id = tonumber(ks:match("^(%d+)$") or ks:match("^(%d+)%@%d+$"))
  local diff = tonumber(ks:match("^%d+%@(%d+)$"))
      return id, diff
    end
    for k, v in pairs(trackedItems) do
      if type(v) ~= "table" or (type(v)=="table" and type(v.id) ~= "number") then
        local id, diff = parseKeyParts(k)
        if id then
          local newKey = diff and (tostring(id).."@"..tostring(diff)) or tostring(id)
          toAdd[newKey] = toAdd[newKey] or {
            id = id,
            boss = nil,
            dungeon = nil,
            isRaid = nil,
            link = nil,
            encounterID = nil,
            instanceID = nil,
            difficultyID = diff,
            difficultyName = nil,
            specs = nil,
          }
          table.insert(toRemove, k)
        end
      end
    end
    for k in pairs(toAdd) do
      trackedItems[k] = trackedItems[k] or toAdd[k]
    end
    for _, k in ipairs(toRemove) do
      trackedItems[k] = nil
    end
  end

  -- Backfill specs for existing tracked entries if missing
  for _, v in pairs(trackedItems) do
    if type(v) == "table" and type(v.id) == "number" and (v.specs == nil or (type(v.specs)=="table" and next(v.specs)==nil)) then
      computeItemSpecs(v.id, v.link, function(specs)
        v.specs = specs or {}
        if LootWishlist.Ace and LootWishlist.Ace.refresh then LootWishlist.Ace.refresh() end
        if LootWishlist.Summary and LootWishlist.Summary.refresh then LootWishlist.Summary.refresh() end
      end)
    end
  end
end

-- Public API: Add/Remove/Iterate --------------------------------------------
function LootWishlist.AddTrackedItem(itemID, bossName, instanceName, isRaid, itemLink, encounterID, instanceID, difficultyID, difficultyName)
  -- Compose a unique key so that the same item can be tracked for multiple difficulties
  local key
  if difficultyID then
    key = tostring(itemID).."@"..tostring(difficultyID)
  else
    -- Back-compat when difficulty isn\'t provided
    key = tostring(itemID)
  end
  trackedItems[key] = {
    id = itemID,
    boss = bossName,
    dungeon = instanceName,
    isRaid = isRaid and true or false,
    link = itemLink,
    encounterID = encounterID,
    instanceID = instanceID,
    difficultyID = difficultyID,
    difficultyName = difficultyName,
    specs = nil,
  }
  -- Compute and attach spec list asynchronously
  computeItemSpecs(itemID, itemLink, function(specs)
    local entry = trackedItems[key]
    if entry then entry.specs = specs or {} end
    if LootWishlist.Ace and LootWishlist.Ace.refresh then LootWishlist.Ace.refresh() end
    if LootWishlist.Summary and LootWishlist.Summary.refresh then LootWishlist.Summary.refresh() end
  end)
  -- Prefer Ace view opening; the UI module will handle opening and refreshing
  if LootWishlist.Ace and LootWishlist.Ace.open then
    LootWishlist.Ace.open()
    LootWishlist.Ace.refresh()
    if LootWishlist.Summary and LootWishlist.Summary.refresh then LootWishlist.Summary.refresh() end
  else
    print("Loot Wishlist: AceGUI-3.0 not found. Please install Ace3 to use the UI. Item tracked.")
  end
end

-- Remove one or more tracked entries.
-- If keyOrID is a string key, remove that exact entry.
-- If it\'s a number itemID and difficultyID is provided, remove matching entries for that difficulty only.
-- If it\'s a number itemID and difficultyID is nil, remove all entries for that itemID.
function LootWishlist.RemoveTrackedItem(keyOrID, difficultyID)
  local removed = false
  local function parseKeyParts(k)
    if k == nil then return nil, nil end
    local ks = tostring(k)
  local id = tonumber(ks:match("^(%d+)$") or ks:match("^(%d+)%@%d+$"))
  local diff = tonumber(ks:match("^%d+%@(%d+)$"))
    return id, diff
  end
  if type(keyOrID) == "string" then
    if trackedItems[keyOrID] then trackedItems[keyOrID] = nil; removed = true end
  elseif type(keyOrID) == "number" then
    for k, v in pairs(trackedItems) do
      local vid, vdiff
      if type(v) == "table" then
        vid = v.id
        vdiff = v.difficultyID
      else
        vid, vdiff = parseKeyParts(k)
      end
      if vid == keyOrID and (difficultyID == nil or vdiff == difficultyID or vdiff == nil) then
        trackedItems[k] = nil
        removed = true
      end
    end
  end
  if removed then
    if LootWishlist.Ace and LootWishlist.Ace.refresh then LootWishlist.Ace.refresh() end
    if LootWishlist.Summary and LootWishlist.Summary.refresh then LootWishlist.Summary.refresh() end
  end
end

function LootWishlist.IterateTracked()
  return pairs(trackedItems)
end

function LootWishlist.GetTracked()
  return trackedItems
end

function LootWishlist.ClearAllTracked()
  if not trackedItems or not next(trackedItems) then return end
  for k in pairs(trackedItems) do trackedItems[k] = nil end
  if LootWishlist.Ace and LootWishlist.Ace.refresh then LootWishlist.Ace.refresh() end
  if LootWishlist.Summary and LootWishlist.Summary.refresh then LootWishlist.Summary.refresh() end
end

do
  -- Proxy that reads/writes account-wide templates and per-character toggles
  local settingsProxy
  function LootWishlist.GetSettings()
    if settingsProxy then return settingsProxy end
    local function buildProxy()
      local proxy = {}
      return setmetatable(proxy, {
        __index = function(_, k)
          local acct = (LootWishlistDB and LootWishlistDB.settings) or {}
          local ch = (LootWishlistCharDB and LootWishlistCharDB.settings) or {}
          if k == "whisperTemplate" or k == "partyTemplate" then
            return acct[k]
          elseif k == "enableRaidRollAlert" then
            return acct[k]
          end
          return acct[k] or ch[k]
        end,
        __newindex = function(_, k, v)
          local acct = (LootWishlistDB and LootWishlistDB.settings) or {}
          local ch = (LootWishlistCharDB and LootWishlistCharDB.settings) or {}
          if k == "whisperTemplate" or k == "partyTemplate" then
            acct[k] = v
          elseif k == "enableRaidRollAlert" then
            acct[k] = v
          else
            acct[k] = v
          end
        end,
      })
    end
    settingsProxy = buildProxy()
    return settingsProxy
  end
end

function LootWishlist.SetDebug(val)
  DEBUG = not not val
  if LootWishlistDB and LootWishlistDB.settings then
    LootWishlistDB.settings.debug = DEBUG
  end
  print("Loot Wishlist debug:", DEBUG and "ON" or "OFF")
end

function LootWishlist.IsDebug()
  return DEBUG
end

-- Events ---------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local addonName = ...
    if addonName == ADDON_NAME then
      InitializeDB()
      -- Defer UI refresh to modules after they initialize
    elseif addonName == "Blizzard_EncounterJournal" then
      if LootWishlist.EJ and LootWishlist.EJ.hook then LootWishlist.EJ.hook() end
    end
  elseif event == "PLAYER_LOGIN" then
    print("Loot Wishlist loaded. Track loot from the Adventure Guide! Use /wishlist for help.")
    local isLoaded = false
    if C_AddOns and C_AddOns.IsAddOnLoaded then
      isLoaded = C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
    end
    if isLoaded then
      if LootWishlist.EJ and LootWishlist.EJ.hook then LootWishlist.EJ.hook() end
    else
      local loader = CreateFrame("Frame")
      loader:RegisterEvent("ADDON_LOADED")
      loader:SetScript("OnEvent", function(_, _, addonName)
        if addonName == "Blizzard_EncounterJournal" then
          if LootWishlist.EJ and LootWishlist.EJ.hook then LootWishlist.EJ.hook() end
        end
      end)
    end
    -- Initial UI refresh without forcing windows open
    if LootWishlist.Ace and LootWishlist.Ace.refresh then LootWishlist.Ace.refresh() end
    if LootWishlist.Summary and LootWishlist.Summary.showIfNeeded then LootWishlist.Summary.showIfNeeded() end
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    -- When item info is received, try to resolve missing spec info for that item
    local itemID = ...
    if type(itemID) == "number" then
      for _, v in pairs(trackedItems) do
        if type(v) == "table" and v.id == itemID and (v.specs == nil or (type(v.specs)=="table" and next(v.specs)==nil)) then
          computeItemSpecs(itemID, v.link, function(specs)
            v.specs = specs or {}
            if LootWishlist.Ace and LootWishlist.Ace.refresh then LootWishlist.Ace.refresh() end
            if LootWishlist.Summary and LootWishlist.Summary.refresh then LootWishlist.Summary.refresh() end
          end)
        end
      end
    end
    if LootWishlist.Ace and LootWishlist.Ace.refresh then LootWishlist.Ace.refresh() end
    if LootWishlist.Summary and LootWishlist.Summary.refresh then LootWishlist.Summary.refresh() end
  end
end)

-- Slash commands -------------------------------------------------------------
SLASH_WISHLIST1 = "/wishlist"
SLASH_WISHLIST2 = "/lwl" -- short alias for Loot Wishlist
SlashCmdList.WISHLIST = function(msg)
  msg = msg and msg:lower() or ""
  if msg == "show" then
    if LootWishlist.Ace and LootWishlist.Ace.open then LootWishlist.Ace.open() else print("Loot Wishlist: Ace3 is required for the UI.") end
  elseif msg == "hide" then
    if LootWishlist.Ace and LootWishlist.Ace.hide then LootWishlist.Ace.hide() end
  elseif msg == "debug" then
    LootWishlist.SetDebug(not LootWishlist.IsDebug())
    if EncounterJournal and EncounterJournal:IsShown() then
      local upd = _G["EncounterJournal_LootUpdate"]
      if type(upd) == "function" then upd() end
    end
  elseif msg:match("^remove ") then
    local idStr = msg:match("^remove%s+(%d+)") or msg:match("item:(%d+)")
    local itemID = idStr and tonumber(idStr)
    if itemID and trackedItems[itemID] then
      LootWishlist.RemoveTrackedItem(itemID)
      print("Loot Wishlist: removed", itemID)
    else
      print("Loot Wishlist: item not tracked; usage /wishlist remove <itemID>")
    end
  elseif msg == "list" then
    local n = 0
    for _ in pairs(trackedItems) do n = n + 1 end
    print("Loot Wishlist: tracking", n, "item(s)")
  elseif msg == "options" or msg == "settings" then
    if LootWishlist.Options and LootWishlist.Options.Open then
      LootWishlist.Options.Open()
    else
      print("Open Interface Options and look for 'Loot Wishlist'.")
    end
  elseif msg == "reset-spec" or msg == "resetspec" then
    if LootWishlist.Alerts and LootWishlist.Alerts.ResetSpecReminderDebounce then
      LootWishlist.Alerts.ResetSpecReminderDebounce()
      print("Loot Wishlist: spec reminder reset. Target a boss or re-enter to trigger again.")
    else
      print("Loot Wishlist: alerts module not ready.")
    end
  elseif msg:match("^testdrop ") then
    local arg = msg:match("^testdrop%s+(.+)$")
    if arg then
      if LootWishlist.Alerts and LootWishlist.Alerts.TestDrop then
        LootWishlist.Alerts.TestDrop(arg, false)
      end
    else
      print("/wishlist testdrop <itemID|itemLink>")
    end
  elseif msg:match("^testdropnot ") or msg:match("^testdrop%-not ") then
    local arg = msg:match("^testdrop%-?not%s+(.+)$")
    if arg then
      if LootWishlist.Alerts and LootWishlist.Alerts.TestDrop then
        LootWishlist.Alerts.TestDrop(arg, true)
      end
    else
      print("/wishlist testdrop-not <itemID|itemLink>")
    end
  elseif msg:match("^testdrop%-other ") then
    local arg = msg:match("^testdrop%-other%s+(.+)$")
    if arg then
      if LootWishlist.Alerts and LootWishlist.Alerts.TestDropOther then
        LootWishlist.Alerts.TestDropOther(arg)
      end
    else
      print("/wishlist testdrop-other <itemID|itemLink> [looterName]")
    end
  elseif msg == "clear" then
    if LootWishlist.ClearAllTracked then LootWishlist.ClearAllTracked() end
    print("Loot Wishlist: cleared all tracked items")
  else
    print("/wishlist commands: show | hide | remove <ID> | list | clear | debug | reset-spec")
  end
end
