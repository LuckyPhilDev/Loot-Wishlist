-- Loot Wishlist - Bonus Roll odds.
-- What a Voidcore charge is worth on the boss in front of you: how much of its
-- loot table you actually want, what you have already spent there, and whether
-- another loot spec would do better.

LootWishlist = LootWishlist or {}
LootWishlist.BonusRollOdds = LootWishlist.BonusRollOdds or {}
local Odds = LootWishlist.BonusRollOdds
local S = LootWishlist.Strings.bonusRollOdds
local Scope = LootWishlist.Strings.bonusRoll

local DUNGEON_SCAN_DIFF = 23  -- the journal carries no Mythic+ dungeon table
local MAX_WAITS         = 5   -- one-second retries while a table is still being read
local WARM_DELAY        = 5   -- seconds after a zone change before reading its table

local DevLog = LuckyLog and LuckyLog:New("[Lwl-Odds][debug]", function()
  return LootWishlist.IsDebug and LootWishlist.IsDebug()
end) or function() end

------------------------------------------------------------------------
-- Charges spent, per boss
------------------------------------------------------------------------
-- A Mythic+ roll names only the dungeon, so those count against the instance.
local function spendKey(encounterID, instanceID)
  if (encounterID or 0) ~= 0 then return encounterID end
  if (instanceID or 0) ~= 0 then return "i" .. instanceID end
  return nil
end

local function spends()
  LootWishlistCharDB = LootWishlistCharDB or {}
  LootWishlistCharDB.bonusRollSpends = LootWishlistCharDB.bonusRollSpends or {}
  return LootWishlistCharDB.bonusRollSpends
end

function Odds.GetSpent(encounterID, instanceID)
  local key = spendKey(encounterID, instanceID)
  return (key and spends()[key]) or 0
end

-- ponytail: counts the click, not the currency, so a roll the server refuses
-- still counts. Watch the currency instead if that turns out to happen.
function Odds.RecordSpend(encounterID, instanceID)
  local key = spendKey(encounterID, instanceID)
  if not key then return end
  local t = spends()
  t[key] = (t[key] or 0) + 1
  DevLog("spend recorded", tostring(key), t[key])
end

------------------------------------------------------------------------
-- What rolls have already handed over
------------------------------------------------------------------------
local function wins()
  LootWishlistCharDB = LootWishlistCharDB or {}
  LootWishlistCharDB.bonusRollWins = LootWishlistCharDB.bonusRollWins or {}
  return LootWishlistCharDB.bonusRollWins
end

local function wonAt(key, itemID)
  local bucket = key and wins()[key]
  return (bucket and bucket[itemID]) and true or false
end

-- A Mythic+ win sits against the dungeon and a raid win against the boss, so
-- both buckets are asked: a boss inside a dungeon shares the dungeon's wins.
function Odds.HasWon(itemID, encounterID, instanceID)
  return wonAt(spendKey(encounterID, nil), itemID)
      or wonAt(spendKey(nil, instanceID), itemID)
end

-- ponytail: a win is remembered for good and never told apart by track, so a
-- Normal copy keeps its Heroic twin out of the count too. Store the difficulty
-- alongside if that starts to matter. Deliberately does not mark the wishlist
-- entry obtained: that clears every difficulty variant, which is the player's
-- call to make in the window, not a roll's.
function Odds.RecordWin(itemID, encounterID, instanceID)
  local key = spendKey(encounterID, instanceID)
  if not (key and type(itemID) == "number") then return end
  local bucket = wins()[key] or {}
  bucket[itemID] = true
  wins()[key] = bucket
  DevLog("win recorded", tostring(key), itemID)
end

-- A roll never hands over what an earlier roll gave you, so a win leaves the
-- table. An item marked obtained stays in it: a roll can still hand it over.
function Odds.Won(encounterID, instanceID)
  return function(itemID)
    return Odds.HasWon(itemID, encounterID, instanceID)
  end
end

------------------------------------------------------------------------
-- Odds
------------------------------------------------------------------------
local function inList(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

-- An item with no spec list counts for every spec.
function Odds.Tally(items, specs, isWanted, specsOf, isWon)
  local tally = {}
  for _, specID in ipairs(specs) do tally[specID] = { total = 0, wanted = 0 } end
  for _, item in ipairs(items) do
    local itemID = item.itemID or item
    if not (isWon and isWon(itemID)) then
      local list = specsOf(itemID)
      local wanted = isWanted(itemID)
      for _, specID in ipairs(specs) do
        if not list or #list == 0 or inList(list, specID) then
          local row = tally[specID]
          row.total = row.total + 1
          if wanted then row.wanted = row.wanted + 1 end
        end
      end
    end
  end
  return tally
end

function Odds.Ratio(row)
  if not row or row.total == 0 then return 0 end
  return row.wanted / row.total
end

local function percent(row)
  return math.floor(Odds.Ratio(row) * 100 + 0.5)
end

-- The spec worth switching your loot spec to, or nil when the one you are on
-- already holds the best share of the table.
function Odds.Best(tally, specs, currentSpecID)
  local bestID, bestRatio = nil, Odds.Ratio(tally[currentSpecID])
  for _, specID in ipairs(specs) do
    local row = tally[specID]
    if specID ~= currentSpecID and row and row.wanted > 0 and Odds.Ratio(row) > bestRatio then
      bestID, bestRatio = specID, Odds.Ratio(row)
    end
  end
  return bestID
end

local function specName(specID)
  local ok, _, name = pcall(GetSpecializationInfoByID, specID)
  return (ok and name) or tostring(specID)
end

-- A dungeon roll is on the whole instance rather than one boss, so the scope
-- has to be named or its larger table reads as a mistake.
function Odds.Describe(tally, specs, currentSpecID, spent, scope)
  local lines = {}
  local row = tally[currentSpecID]
  scope = scope or Scope.thisBoss

  if not row or row.total == 0 then
    lines[#lines + 1] = S.emptyTable
  elseif row.wanted == 0 then
    lines[#lines + 1] = S.nothingWanted:format(row.total, scope)
  else
    lines[#lines + 1] = S.wanted:format(percent(row), scope, row.wanted, row.total)
  end

  if (spent or 0) > 0 then lines[#lines + 1] = S.spent:format(spent) end

  local best = Odds.Best(tally, specs, currentSpecID)
  if best then
    local b = tally[best]
    lines[#lines + 1] = S.betterSpec:format(specName(best), percent(b), b.wanted, b.total)
  end

  return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- Reading the boss's table
------------------------------------------------------------------------
local function playerClassID()
  return (select(3, UnitClass("player")))
end

local function playerSpecs()
  local specs = {}
  for i = 1, (GetNumSpecializations and GetNumSpecializations() or 0) do
    local id = GetSpecializationInfo(i)
    if id then specs[#specs + 1] = id end
  end
  return specs
end

-- A loot spec of 0 means "whatever I am playing".
local function currentLootSpec()
  local id = GetLootSpecialization and GetLootSpecialization() or 0
  if id and id > 0 then return id end
  local index = GetSpecialization and GetSpecialization()
  return index and GetSpecializationInfo(index) or nil
end

local function wantedSet()
  local set = {}
  local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked()
  for _, entry in pairs(tracked or {}) do
    if type(entry) == "table" and type(entry.id) == "number"
       and not (LootWishlist.IsObtained and LootWishlist.IsObtained(entry.id)) then
      set[entry.id] = true
    end
  end
  return set
end

local function scanDiff(isRaid, difficultyID)
  if isRaid then return difficultyID end
  if difficultyID == 1 or difficultyID == 2 then return difficultyID end
  return DUNGEON_SCAN_DIFF
end

-- The browser's scanner owns the journal reads, so this only asks it for a
-- table and gets nil back while one is still on the way.
local function lootTable(instanceID, encounterID, specID)
  local Browser = LootWishlist.Browser
  if not (Browser and Browser.RequestLoot and instanceID) then return nil end

  local _, instanceType, difficultyID = GetInstanceInfo()
  local isRaid = instanceType == "raid"
  local cache = Browser.RequestLoot(instanceID, isRaid,
    scanDiff(isRaid, difficultyID), playerClassID(), specID)
  if not cache then return nil end

  if (encounterID or 0) == 0 then return cache.items end
  local items = {}
  for _, item in ipairs(cache.items) do
    if item.encounterID == encounterID then items[#items + 1] = item end
  end
  return items
end

-- What each spec can be given comes from the journal's own spec filter, the
-- table you see in the Adventure Guide. Item spec info cannot stand in for it:
-- it returns nothing for an item not yet cached, which counted most of the
-- class table for every spec. Every spec is asked before giving up, so the
-- scans queue together. Returns the items across all specs and a lookup of
-- the specs each one drops for, or nil while any table is still being read.
local function specTables(instanceID, encounterID)
  local items, specsByItem, seen, missing = {}, {}, {}, false
  for _, specID in ipairs(playerSpecs()) do
    local list = lootTable(instanceID, encounterID, specID)
    if not list then
      missing = true
    else
      for _, item in ipairs(list) do
        local key = item.itemID .. ":" .. tostring(item.encounterID)
        if not seen[key] then
          seen[key] = true
          items[#items + 1] = item
        end
        local specs = specsByItem[item.itemID] or {}
        if not inList(specs, specID) then specs[#specs + 1] = specID end
        specsByItem[item.itemID] = specs
      end
    end
  end
  if missing then return nil end
  return items, function(itemID) return specsByItem[itemID] end
end

------------------------------------------------------------------------
-- Public: the text for one roll
------------------------------------------------------------------------
-- Returns the lines and whether the table behind them has actually been read,
-- so a caller can come back for a better answer. giveUp drops the note saying
-- the read is still coming, for the last time a caller means to ask.
function Odds.ForRoll(encounterID, instanceID, giveUp)
  local spent = Odds.GetSpent(encounterID, instanceID)
  local ejInstance = (instanceID or 0) ~= 0 and instanceID
    or (LootWishlist.GetCurrentEJInstanceID and LootWishlist.GetCurrentEJInstanceID())
  local items, specsOf
  if ejInstance then items, specsOf = specTables(ejInstance, encounterID) end

  if not items then
    local spentLine = spent > 0 and S.spent:format(spent) or ""
    if giveUp then return spentLine, false end
    return spentLine ~= "" and (S.reading .. "\n" .. spentLine) or S.reading, false
  end

  local set = wantedSet()
  local specs = playerSpecs()
  local tally = Odds.Tally(items, specs, function(id) return set[id] == true end, specsOf,
    Odds.Won(encounterID, instanceID))
  local scope = (encounterID or 0) ~= 0 and Scope.thisBoss or Scope.thisDungeon
  return Odds.Describe(tally, specs, currentLootSpec(), spent, scope), true
end

-- Shows the working behind a percentage: what the table held, what was dropped
-- before counting, and what each of your specs could be given of the rest.
local function explain(label, items, specsOf, set, isWon, tally, specs, currentSpecID)
  if not (LootWishlist.IsDebug and LootWishlist.IsDebug()) then return end

  DevLog(label, "loot table holds", #items, "across your specs")
  for _, item in ipairs(items) do
    local itemID = item.itemID or item
    local list = specsOf(itemID)
    local reach = (not list or #list == 0) and "any spec" or table.concat(list, "/")
    if isWon and isWon(itemID) then
      DevLog("  ", itemID, "skipped, a roll already gave you this")
    elseif set[itemID] then
      DevLog("  ", itemID, "wanted, drops for", reach)
    end
  end

  for _, specID in ipairs(specs) do
    local row = tally[specID]
    DevLog("  ", specName(specID), row.wanted .. " of " .. row.total,
      "=", percent(row) .. "%", specID == currentSpecID and "(your loot spec)" or "")
  end
end

local function summarise(tally, specs, currentSpecID)
  local row = tally[currentSpecID] or { total = 0, wanted = 0 }
  local best = Odds.Best(tally, specs, currentSpecID)
  return {
    percent = percent(row),
    wanted = row.wanted,
    total = row.total,
    best = best and {
      name = specName(best),
      percent = percent(tally[best]),
      wanted = tally[best].wanted,
      total = tally[best].total,
    } or nil,
  }
end

-- A keystone roll is on the whole dungeon rather than one boss, so its odds are
-- a single figure for the instance.
function Odds.ForInstance(instanceID)
  if not instanceID then return nil, false end
  local items, specsOf = specTables(instanceID, nil)
  if not items then return nil, false end

  local set, specs, current = wantedSet(), playerSpecs(), currentLootSpec()
  local isWon = Odds.Won(nil, instanceID)
  local tally = Odds.Tally(items, specs, function(id) return set[id] == true end, specsOf, isWon)
  explain("instance " .. tostring(instanceID), items, specsOf, set, isWon, tally, specs, current)
  return summarise(tally, specs, current), true
end

-- What a charge is worth on each boss still to come, keyed by encounter. Returns
-- whether the table behind the numbers has been read, so a caller can come back
-- for a better answer.
function Odds.ForUpcoming(instanceID, bosses)
  if not instanceID then return nil, false end
  local items, specsOf = specTables(instanceID, nil)
  if not items then return nil, false end

  local byBoss = {}
  for _, item in ipairs(items) do
    local id = item.encounterID or 0
    byBoss[id] = byBoss[id] or {}
    table.insert(byBoss[id], item)
  end

  local set, specs, current = wantedSet(), playerSpecs(), currentLootSpec()
  local isWanted = function(id) return set[id] == true end
  local odds = {}
  for _, boss in ipairs(bosses) do
    local bossItems = byBoss[boss.encounterID] or {}
    local isWon = Odds.Won(boss.encounterID, instanceID)
    local tally = Odds.Tally(bossItems, specs, isWanted, specsOf, isWon)
    explain(boss.name, bossItems, specsOf, set, isWon, tally, specs, current)
    odds[boss.encounterID] = summarise(tally, specs, current)
  end
  return odds, true
end

function Odds.Enabled()
  local s = (LootWishlist.GetSettings and LootWishlist.GetSettings())
    or (LootWishlistDB and LootWishlistDB.settings) or {}
  return s.bonusRollOdds ~= false
end

------------------------------------------------------------------------
-- The line under the roll popup
------------------------------------------------------------------------
local label
local function ensureLabel()
  if label then return label end
  if not BonusRollFrame then return nil end
  label = BonusRollFrame:CreateFontString(nil, "OVERLAY")
  label:SetFont(LuckyUI.BODY_FONT, 12)
  label:SetTextColor(LuckyUI.C.textLight[1], LuckyUI.C.textLight[2], LuckyUI.C.textLight[3])
  label:SetPoint("TOP", BonusRollFrame, "BOTTOM", 0, -2)
  label:SetWidth(320)
  label:SetJustifyH("CENTER")
  return label
end

local function showOdds(waits)
  if not (BonusRollFrame and BonusRollFrame:IsShown()) then return end
  if not Odds.Enabled() then return end
  local text = ensureLabel()
  if not text then return end

  local lastAsk = waits >= MAX_WAITS
  local lines, ready = Odds.ForRoll(BonusRollFrame.encounterID, BonusRollFrame.instanceID, lastAsk)
  text:SetText(lines)
  if lines == "" then text:Hide() else text:Show() end

  if not ready and not lastAsk then
    C_Timer.After(1, function() showOdds(waits + 1) end)
  end
end

------------------------------------------------------------------------
-- Warming, so the numbers are there when the boss dies
------------------------------------------------------------------------
local function warm()
  if not Odds.Enabled() then return end
  local _, instanceType = GetInstanceInfo()
  if instanceType ~= "party" and instanceType ~= "raid" then return end
  local instanceID = LootWishlist.GetCurrentEJInstanceID and LootWishlist.GetCurrentEJInstanceID()
  if instanceID then specTables(instanceID, nil) end
end

------------------------------------------------------------------------
-- Diagnostics (/wishlist odds)
------------------------------------------------------------------------
function Odds.Report()
  local prefix = LootWishlist.Strings.addon.prefix
  local instanceName, instanceType = GetInstanceInfo()
  if instanceType ~= "party" and instanceType ~= "raid" then
    print(prefix .. S.notInInstance)
    return
  end
  local instanceID = LootWishlist.GetCurrentEJInstanceID and LootWishlist.GetCurrentEJInstanceID()
  local items, specsOf
  if instanceID then items, specsOf = specTables(instanceID, nil) end
  if not items then
    print(prefix .. S.reading)
    return
  end

  local set, specs = wantedSet(), playerSpecs()
  local current = currentLootSpec()
  print(prefix .. S.reportHeader:format(instanceName or "?"))
  -- A Mythic+ roll is on the dungeon rather than a boss, so its spends sit
  -- against the instance and would show against no boss below.
  local onInstance = Odds.GetSpent(nil, instanceID)
  if onInstance > 0 then print("  " .. S.spent:format(onInstance)) end

  local byBoss, order = {}, {}
  for _, item in ipairs(items) do
    local id = item.encounterID or 0
    if not byBoss[id] then byBoss[id] = {}; order[#order + 1] = id end
    table.insert(byBoss[id], item)
  end
  for _, encounterID in ipairs(order) do
    local tally = Odds.Tally(byBoss[encounterID], specs,
      function(id) return set[id] == true end, specsOf, Odds.Won(encounterID, instanceID))
    local name = (EJ_GetEncounterInfo and EJ_GetEncounterInfo(encounterID)) or tostring(encounterID)
    local lines = Odds.Describe(tally, specs, current, Odds.GetSpent(encounterID, nil))
    print("  " .. name .. ": " .. lines:gsub("\n", " "))
  end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
-- The prompt's buttons are built with the roll, not with the frame, so the
-- click hook waits for the first popup rather than for login.
local rollHooked = false
-- The result arrives after the popup has moved on, so the click records where
-- the roll was spent and the reward is filed against that.
local rolledAt
local function hookRollButton()
  if rollHooked then return end
  local prompt = BonusRollFrame and BonusRollFrame.PromptFrame
  local rollButton = prompt and prompt.RollButton
  if not rollButton then return end
  rollButton:HookScript("OnClick", function()
    Odds.NoteRoll(BonusRollFrame.encounterID, BonusRollFrame.instanceID)
  end)
  rollHooked = true
end

function Odds.NoteRoll(encounterID, instanceID)
  rolledAt = { encounterID = encounterID, instanceID = instanceID }
  Odds.RecordSpend(encounterID, instanceID)
end

-- A roll can pay out in currency instead, which carries no item link.
function Odds.OnRollResult(itemLink)
  if not (rolledAt and itemLink) then return end
  local itemID = tonumber(tostring(itemLink):match("item:(%d+)"))
  if itemID then Odds.RecordWin(itemID, rolledAt.encounterID, rolledAt.instanceID) end
end

local hooked = false
local function tryHook()
  if hooked then return true end
  if not BonusRollFrame then return false end
  BonusRollFrame:HookScript("OnShow", function()
    hookRollButton()
    showOdds(0)
  end)
  BonusRollFrame:HookScript("OnHide", function()
    if label then label:Hide() end
  end)
  hooked = true
  return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BONUS_ROLL_RESULT")
-- The popup stays up while you change spec, and the odds it quotes are the
-- reason to, so they are worked out again rather than left reading for the spec
-- you killed the boss in. A loot spec of "current specialization" moves with the
-- spec itself, which raises no loot spec event of its own.
f:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:SetScript("OnEvent", function(_, event, unit, itemLink)
  if event == "BONUS_ROLL_RESULT" then return Odds.OnRollResult(itemLink) end
  if event == "PLAYER_LOOT_SPEC_UPDATED"
     or (event == "PLAYER_SPECIALIZATION_CHANGED" and unit == "player") then
    return showOdds(0)
  end
  if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(WARM_DELAY, warm) end
  if tryHook() then f:UnregisterEvent("ADDON_LOADED") end
end)
