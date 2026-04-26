-- Loot Wishlist - Bonus Roll integration (Midnight Season 1)
-- Per-character flag set marking wishlist items as targets for bonus rolls
-- (Nebulous Voidcore charges). Reminds the player after eligible runs.

LootWishlist = LootWishlist or {}
LootWishlist.BonusRoll = LootWishlist.BonusRoll or {}
local BR = LootWishlist.BonusRoll

local CURRENCY_ID        = 3418   -- Nebulous Voidcore
local DUNGEON_COST       = 1
local RAID_COST          = 2
local MIN_KEYSTONE_LEVEL = 10
local RAID_DIFF_HEROIC   = 15
local RAID_DIFF_MYTHIC   = 16

local DevLog = LuckyLog and LuckyLog:New("[Lwl-BR][debug]", function()
  return LootWishlist.IsDebug and LootWishlist.IsDebug()
end) or function() end

local function ensureFlagSet()
  LootWishlistCharDB = LootWishlistCharDB or {}
  LootWishlistCharDB.bonusRollItems = LootWishlistCharDB.bonusRollItems or {}
  return LootWishlistCharDB.bonusRollItems
end

local function refreshUI()
  local ace = LootWishlist.Ace
  if ace and ace.deferredRefresh then ace.deferredRefresh()
  elseif ace and ace.refresh then ace.refresh() end
  if LootWishlist.Summary and LootWishlist.Summary.refresh then
    LootWishlist.Summary.refresh()
  end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function BR.IsFlagged(itemID)
  if not itemID then return false end
  return ensureFlagSet()[itemID] == true
end

function BR.SetFlagged(itemID, val)
  if not itemID then return end
  local set = ensureFlagSet()
  set[itemID] = val and true or nil
  DevLog("SetFlagged", itemID, "=", tostring(val))
  refreshUI()
end

function BR.Toggle(itemID)
  BR.SetFlagged(itemID, not BR.IsFlagged(itemID))
end

function BR.GetCharges()
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local info = C_CurrencyInfo.GetCurrencyInfo(CURRENCY_ID)
    if info and type(info.quantity) == "number" then return info.quantity end
  end
  return 0
end

function BR.IterateFlagged()
  return pairs(ensureFlagSet())
end

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local function getSettings()
  if LootWishlist.GetSettings then return LootWishlist.GetSettings() end
  return (LootWishlistDB and LootWishlistDB.settings) or {}
end

local function remindersEnabled()
  local s = getSettings()
  return s and s.enableBonusRollReminders ~= false
end

local function soundEnabled()
  local s = getSettings()
  return s and s.bonusRollSound ~= false
end

------------------------------------------------------------------------
-- Match flagged items against current dungeon / encounter
------------------------------------------------------------------------
local function findMatches(predicate)
  local matches = {}
  local seen = {}
  if not LootWishlist.GetTracked then return matches end
  for _, entry in pairs(LootWishlist.GetTracked()) do
    if type(entry) == "table" and type(entry.id) == "number"
       and BR.IsFlagged(entry.id) and not seen[entry.id] then
      if predicate(entry) then
        seen[entry.id] = true
        table.insert(matches, entry)
      end
    end
  end
  return matches
end

function BR.GetItemsForDungeon(instanceID, instanceName)
  return findMatches(function(e)
    if e.isRaid then return false end
    if instanceID and e.instanceID == instanceID then return true end
    if instanceName and e.dungeon == instanceName then return true end
    return false
  end)
end

function BR.GetItemsForEncounter(encounterID)
  return findMatches(function(e)
    return e.isRaid and e.encounterID == encounterID
  end)
end

------------------------------------------------------------------------
-- Reminder popup
------------------------------------------------------------------------
local popup
local function ensurePopup()
  if popup then return popup end
  local UI = LuckyUI
  local Cl = UI.C

  popup = CreateFrame("Frame", "LootWishlistBonusRollPopup", UIParent, "BackdropTemplate")
  popup:SetSize(440, 180)
  popup:SetPoint("CENTER", 0, 120)
  popup:SetFrameStrata("DIALOG")
  popup:SetBackdrop(UI.Backdrop)
  popup:SetBackdropColor(Cl.bgDark[1], Cl.bgDark[2], Cl.bgDark[3], 0.95)
  popup:SetBackdropBorderColor(Cl.goldAccent[1], Cl.goldAccent[2], Cl.goldAccent[3])
  popup:EnableMouse(true)
  popup:SetMovable(true)
  popup:RegisterForDrag("LeftButton")
  popup:SetScript("OnDragStart", function(s) s:StartMoving() end)
  popup:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
  popup:SetClampedToScreen(true)

  popup.title = popup:CreateFontString(nil, "OVERLAY")
  popup.title:SetFont(UI.TITLE_FONT, 15)
  popup.title:SetTextColor(Cl.goldPrimary[1], Cl.goldPrimary[2], Cl.goldPrimary[3])
  popup.title:SetPoint("TOP", 0, -12)

  popup.subtitle = popup:CreateFontString(nil, "OVERLAY")
  popup.subtitle:SetFont(UI.BODY_FONT, 12)
  popup.subtitle:SetTextColor(Cl.textLight[1], Cl.textLight[2], Cl.textLight[3])
  popup.subtitle:SetPoint("TOP", popup.title, "BOTTOM", 0, -6)
  popup.subtitle:SetPoint("LEFT", 14, 0)
  popup.subtitle:SetPoint("RIGHT", -14, 0)
  popup.subtitle:SetJustifyH("CENTER")

  popup.charges = popup:CreateFontString(nil, "OVERLAY")
  popup.charges:SetFont(UI.BODY_FONT, 11)
  popup.charges:SetTextColor(Cl.goldAccent[1], Cl.goldAccent[2], Cl.goldAccent[3])
  popup.charges:SetPoint("TOP", popup.subtitle, "BOTTOM", 0, -6)

  popup.body = popup:CreateFontString(nil, "OVERLAY")
  popup.body:SetFont(UI.BODY_FONT, 12)
  popup.body:SetTextColor(Cl.textLight[1], Cl.textLight[2], Cl.textLight[3])
  popup.body:SetPoint("TOPLEFT", 18, -78)
  popup.body:SetPoint("RIGHT", -18, 0)
  popup.body:SetJustifyH("LEFT")
  popup.body:SetJustifyV("TOP")

  popup.close = UI.CreateButton(popup, "Dismiss", 100, 22, "secondary")
  popup.close:SetPoint("BOTTOM", 0, 12)
  popup.close:SetScript("OnClick", function() popup:Hide() end)

  popup:Hide()
  return popup
end

local function formatItemLine(entry)
  local link = entry.link or ("item:" .. tostring(entry.id))
  return "  \194\183 " .. link
end

function BR.ShowReminder(opts)
  local p = ensurePopup()
  p.title:SetText(opts.title or "Bonus Roll Reminder")
  p.subtitle:SetText(opts.subtitle or "")
  p.charges:SetText(string.format("Charges: %d  (cost %d per roll)",
    opts.charges or 0, opts.cost or 1))

  local lines = {}
  for _, e in ipairs(opts.items or {}) do
    table.insert(lines, formatItemLine(e))
  end
  p.body:SetText(table.concat(lines, "\n"))

  local rows = math.max(1, #(opts.items or {}))
  p:SetHeight(110 + rows * 18)
  p:Show()
  p:Raise()

  if opts.sound ~= false then
    local kit = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
    PlaySound(kit)
  end
end

------------------------------------------------------------------------
-- Eligibility / event handlers
------------------------------------------------------------------------
local function getCompletedKeyLevel()
  if C_ChallengeMode and C_ChallengeMode.GetCompletionInfo then
    local _, level = C_ChallengeMode.GetCompletionInfo()
    if type(level) == "number" then return level end
  end
  if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
    local level = C_ChallengeMode.GetActiveKeystoneInfo()
    if type(level) == "number" then return level end
  end
  return nil
end

local function checkDungeonReminder()
  if not remindersEnabled() then return end

  local instanceName, instType, _, _, _, _, _, instID = GetInstanceInfo()
  if instType ~= "party" then
    DevLog("dungeon end - not in party instance:", tostring(instType))
    return
  end

  local keyLevel = getCompletedKeyLevel()
  if not (keyLevel and keyLevel >= MIN_KEYSTONE_LEVEL) then
    DevLog("dungeon end - key level not eligible:", tostring(keyLevel))
    return
  end

  local charges = BR.GetCharges()
  if charges < DUNGEON_COST then
    DevLog("dungeon end - insufficient charges:", charges)
    return
  end

  local items = BR.GetItemsForDungeon(instID, instanceName)
  if #items == 0 then
    DevLog("dungeon end - no flagged items for", tostring(instanceName))
    return
  end

  BR.ShowReminder({
    title = "Bonus Roll Available",
    subtitle = string.format("Spend a charge in |cffffd100%s|r:", instanceName or "this dungeon"),
    charges = charges,
    cost = DUNGEON_COST,
    items = items,
    sound = soundEnabled(),
  })
end

local function checkRaidReminder(encounterID, difficultyID)
  if not remindersEnabled() then return end
  if not encounterID then return end
  if difficultyID ~= RAID_DIFF_HEROIC and difficultyID ~= RAID_DIFF_MYTHIC then
    DevLog("raid end - difficulty not eligible:", tostring(difficultyID))
    return
  end

  local charges = BR.GetCharges()
  if charges < RAID_COST then
    DevLog("raid end - insufficient charges:", charges)
    return
  end

  local items = BR.GetItemsForEncounter(encounterID)
  if #items == 0 then
    DevLog("raid end - no flagged items for encounter", tostring(encounterID))
    return
  end

  local bossName
  if EJ_GetEncounterInfo then bossName = EJ_GetEncounterInfo(encounterID) end

  BR.ShowReminder({
    title = "Bonus Roll Available",
    subtitle = string.format("Spend %d charges on |cffffd100%s|r:", RAID_COST, bossName or "this boss"),
    charges = charges,
    cost = RAID_COST,
    items = items,
    sound = soundEnabled(),
  })
end

------------------------------------------------------------------------
-- Test entry points (used by /wishlist bonusroll-test)
------------------------------------------------------------------------
function BR.TestPopup()
  local items = {}
  for itemID in pairs(ensureFlagSet()) do
    table.insert(items, { id = itemID, link = nil })
    if #items >= 5 then break end
  end
  if #items == 0 then
    items = { { id = 0, link = "(no items flagged for bonus roll)" } }
  end
  BR.ShowReminder({
    title = "Bonus Roll Reminder (Test)",
    subtitle = "Test popup",
    charges = BR.GetCharges(),
    cost = DUNGEON_COST,
    items = items,
    sound = soundEnabled(),
  })
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
f:RegisterEvent("ENCOUNTER_END")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    ensureFlagSet()
    local s = getSettings()
    if s then
      if s.enableBonusRollReminders == nil then s.enableBonusRollReminders = true end
      if s.bonusRollSound == nil then s.bonusRollSound = true end
    end
  elseif event == "CHALLENGE_MODE_COMPLETED" then
    -- Small delay so completion info / instance state settles
    C_Timer.After(1.5, checkDungeonReminder)
  elseif event == "ENCOUNTER_END" then
    local encounterID, _, difficultyID, _, success = ...
    if success ~= 1 then return end
    C_Timer.After(0.5, function() checkRaidReminder(encounterID, difficultyID) end)
  end
end)
