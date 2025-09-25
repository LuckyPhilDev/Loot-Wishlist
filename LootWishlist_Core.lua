-- Loot Wishlist - Core and SavedVariables

local ADDON_NAME = ... or "LootWishlist"

-- Legacy DBs for migration
RemindMeDB = RemindMeDB
RemindMeCharDB = RemindMeCharDB

-- New per-character DB
LootWishlistCharDB = LootWishlistCharDB or {}

local DEBUG = false

-- Public API table
LootWishlist = {
  DEBUG = function() return DEBUG end,
}

-- Local state
local trackedItems -- assigned after DB init

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

  -- Migrate from RemindMe (account-wide to per-character) if applicable
  if (not next(LootWishlistCharDB.trackedItems)) and RemindMeCharDB and RemindMeCharDB.trackedItems and next(RemindMeCharDB.trackedItems) then
    LootWishlistCharDB.trackedItems = CopyTable and CopyTable(RemindMeCharDB.trackedItems) or RemindMeCharDB.trackedItems
    LootWishlistCharDB.window = RemindMeCharDB.window or LootWishlistCharDB.window
    LootWishlistCharDB.aceStatus = RemindMeCharDB.aceStatus or LootWishlistCharDB.aceStatus
    LootWishlistCharDB._migratedFromRemindMeChar = true
    print("Loot Wishlist: Imported tracked items from RemindMe per-character data.")
  elseif (not next(LootWishlistCharDB.trackedItems)) and RemindMeDB and RemindMeDB.trackedItems and next(RemindMeDB.trackedItems) then
    LootWishlistCharDB.trackedItems = CopyTable and CopyTable(RemindMeDB.trackedItems) or RemindMeDB.trackedItems
    LootWishlistCharDB.window = RemindMeDB.window or LootWishlistCharDB.window
    LootWishlistCharDB.aceStatus = RemindMeDB.aceStatus or LootWishlistCharDB.aceStatus
    LootWishlistCharDB._migratedFromRemindMe = true
    print("Loot Wishlist: Imported tracked items from RemindMe account-wide data.")
  end

  -- Restore window position is handled by Ace frame status table
end

-- Public API: Add/Remove/Iterate --------------------------------------------
function LootWishlist.AddTrackedItem(itemID, bossName, instanceName, isRaid, itemLink, encounterID, instanceID)
  trackedItems[itemID] = {
    boss = bossName,
    dungeon = instanceName,
    isRaid = isRaid and true or false,
    link = itemLink,
    encounterID = encounterID,
    instanceID = instanceID,
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

function LootWishlist.RemoveTrackedItem(itemID)
  if trackedItems[itemID] then
    trackedItems[itemID] = nil
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
SLASH_WISHLIST2 = "/remindme" -- keep legacy alias
SLASH_WISHLIST3 = "/lwl" -- short alias for Loot Wishlist
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
    wipe(trackedItems)
    if LootWishlist.Ace and LootWishlist.Ace.refresh then LootWishlist.Ace.refresh() end
    if LootWishlist.BasicUI and LootWishlist.BasicUI.refresh then LootWishlist.BasicUI.refresh() end
    print("Loot Wishlist: cleared all tracked items")
  else
    print("/wishlist commands: show | hide | remove <ID> | list | clear | debug")
  end
end
