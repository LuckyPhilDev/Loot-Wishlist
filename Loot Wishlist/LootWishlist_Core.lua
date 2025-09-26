-- Loot Wishlist - Core and SavedVariables

local ADDON_NAME = ... or "LootWishlist"

-- (Legacy migration removed)

-- New per-character DB
LootWishlistCharDB = LootWishlistCharDB or {}

local DEBUG = false

-- Public API table
LootWishlist = {
  DEBUG = function() return DEBUG end,
}

-- Local state
local trackedItems -- assigned after DB init; may use string keys for difficulty variants

-- No basic frame: AceGUI is the only UI path now

-- DB and migration -----------------------------------------------------------
local function InitializeDB()
  -- Initialize per-character DB
  LootWishlistCharDB.trackedItems = LootWishlistCharDB.trackedItems or {}
  LootWishlist.trackedItems = LootWishlistCharDB.trackedItems
  trackedItems = LootWishlist.trackedItems

  -- Settings defaults
  LootWishlistCharDB.settings = LootWishlistCharDB.settings or {}
  local s = LootWishlistCharDB.settings
  local C = LootWishlist.Const or {}
  s.whisperTemplate = s.whisperTemplate or C.DEFAULT_WHISPER_TEMPLATE or "Hi %looter%, grats! If %item% is tradeable, could I please have it? It's on my wishlist."
  s.partyTemplate = s.partyTemplate or C.DEFAULT_PARTY_TEMPLATE or "If %item% is tradeable, I'd love it (wishlist). Thanks!"
  -- New: raid roll alert toggle (default on)
  if s.enableRaidRollAlert == nil then s.enableRaidRollAlert = true end

  -- Restore window position is handled by Ace frame status table
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
  }
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
  if type(keyOrID) == "string" then
    if trackedItems[keyOrID] then trackedItems[keyOrID] = nil; removed = true end
  elseif type(keyOrID) == "number" then
    for k, v in pairs(trackedItems) do
      local vid = (type(v)=="table" and v.id) or k
      local vdiff = (type(v)=="table" and v.difficultyID) or nil
      if vid == keyOrID and (difficultyID == nil or vdiff == difficultyID) then
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

function LootWishlist.GetSettings()
  return LootWishlistCharDB and LootWishlistCharDB.settings or nil
end

function LootWishlist.SetDebug(val)
  DEBUG = not not val
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
    print("/wishlist commands: show | hide | remove <ID> | list | clear | debug")
  end
end
