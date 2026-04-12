-- Loot Wishlist - Great Vault Awareness
-- Overlays wishlist badges on Great Vault reward choices.

LootWishlist = LootWishlist or {}
LootWishlist.Vault = LootWishlist.Vault or {}

local Vault = LootWishlist.Vault
local UI = LuckyUI
local C  = UI.C

local DevLog = LuckyLog:New("[Lwl-Vault][debug]", function()
  return LootWishlist.DEBUG and LootWishlist.DEBUG()
end)

local hooked = false

-- Difficulty tag helpers (mirrors Summary.lua logic) --------------------------

local function diffTag(name, id)
  if name and name ~= "" then
    local n = name:lower()
    if n:find("raid finder") or n:find("lfr") then return "LFR" end
    if n:find("normal") then return "N" end
    if n:find("heroic") then return "H" end
    if n:find("mythic%+") or n:find("keystone") then return "+" end
    if n:find("mythic") then return "M" end
  end
  if id then
    local map = { [1]="N", [2]="H", [8]="+", [23]="M", [24]="TW", [14]="N", [15]="H", [16]="M", [17]="LFR" }
    return map[id]
  end
  return nil
end

local function joinTags(set)
  local arr = {}
  for k in pairs(set) do table.insert(arr, k) end
  table.sort(arr, function(a, b)
    local order = { LFR=1, N=2, H=3, ["+"]=4, M=5 }
    return (order[a] or 99) < (order[b] or 99)
  end)
  return table.concat(arr, ", ")
end

-- Matching --------------------------------------------------------------------

local function findWishlistMatches(itemID)
  local tracked = LootWishlist.GetTracked()
  if not tracked then return nil end
  local matches = {}
  for _, v in pairs(tracked) do
    if type(v) == "table" and v.id == itemID then
      table.insert(matches, v)
    end
  end
  return #matches > 0 and matches or nil
end

-- Badge overlay ---------------------------------------------------------------

local function ensureBadge(parent)
  if parent.LootWishlistVaultBadge then return parent.LootWishlistVaultBadge end

  local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  badge:SetSize(22, 22)
  badge:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)
  badge:SetFrameStrata("FULLSCREEN_DIALOG")
  badge:SetFrameLevel((parent:GetFrameLevel() or 5) + 10)
  badge:SetBackdrop(UI.Backdrop)
  badge:SetBackdropColor(C.bgDark[1], C.bgDark[2], C.bgDark[3], 0.92)
  badge:SetBackdropBorderColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 1)

  local text = badge:CreateFontString(nil, "OVERLAY")
  text:SetFont(UI.BODY_FONT, 10, "OUTLINE")
  text:SetTextColor(C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3])
  text:SetPoint("CENTER", 0, 0)
  text:SetText("WL")

  badge:Hide()
  parent.LootWishlistVaultBadge = badge
  return badge
end

-- Tooltip enhancement ---------------------------------------------------------

local function onRewardEnter(frame)
  local badge = frame.LootWishlistVaultBadge
  if not badge or not badge:IsShown() then return end
  local matches = badge.wishlistMatches
  if not matches or #matches == 0 then return end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("On your Wishlist:", C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3])
  -- Group matches by dungeon/boss
  local seen = {}
  for _, m in ipairs(matches) do
    local boss = m.boss or "Unknown"
    local dungeon = m.dungeon or "Unknown"
    local tag = diffTag(m.difficultyName, m.difficultyID)
    local lineKey = boss .. "|" .. dungeon
    if not seen[lineKey] then
      seen[lineKey] = { boss = boss, dungeon = dungeon, diffs = {} }
    end
    if tag then seen[lineKey].diffs[tag] = true end
  end
  for _, info in pairs(seen) do
    local tagStr = next(info.diffs) and (" [" .. joinTags(info.diffs) .. "]") or ""
    GameTooltip:AddLine("  " .. info.boss .. " - " .. info.dungeon .. tagStr,
      C.textLight[1], C.textLight[2], C.textLight[3])
  end
  GameTooltip:Show()
end

-- Scan and annotate vault items -----------------------------------------------

local function extractItemID(link)
  if not link or type(link) ~= "string" then return nil end
  local idStr = link:match("item:(%d+)")
  return idStr and tonumber(idStr) or nil
end

local function scanAndAnnotate()
  local settings = LootWishlistDB and LootWishlistDB.settings
  if settings and settings.enableVaultOverlay == false then return end

  local vaultFrame = _G["WeeklyRewardsFrame"]
  if not vaultFrame then return end

  DevLog("scanAndAnnotate: scanning vault choices")

  -- The Blizzard vault frame uses Activities which contain ItemFrame children.
  -- Each activity has .ItemFrame with .displayedItemDBID or we can get links
  -- via C_WeeklyRewards.GetExampleRewardItemHyperlinks.
  local activities = C_WeeklyRewards and C_WeeklyRewards.GetActivities()
  if not activities then return end

  -- Build a map of activityID → item frames from the vault UI
  -- Iterate child frames to find reward elements
  local rewardElements = {}
  for _, child in pairs({vaultFrame:GetChildren()}) do
    -- Blizzard WeeklyRewardActivity frames have .info with .id
    if child.info and child.info.id then
      rewardElements[child.info.id] = child
    end
  end

  for _, activity in ipairs(activities) do
    local element = rewardElements[activity.id]
    if element then
      local badge = ensureBadge(element)
      badge.wishlistMatches = nil
      badge:Hide()

      -- Try to get the item from the element's displayed item
      local itemID
      local itemFrame = element.ItemFrame
      if itemFrame then
        -- Try common fields
        itemID = itemFrame.displayedItemDBID or itemFrame.itemID
        if not itemID and itemFrame.hyperlink then
          itemID = extractItemID(itemFrame.hyperlink)
        end
        if not itemID and itemFrame.itemLink then
          itemID = extractItemID(itemFrame.itemLink)
        end
      end

      -- Fallback: try the API
      if not itemID and C_WeeklyRewards.GetExampleRewardItemHyperlinks then
        local ok, link = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, activity.id)
        if ok and link then
          itemID = extractItemID(link)
        end
      end

      if itemID then
        local matches = findWishlistMatches(itemID)
        if matches then
          DevLog("Vault match: itemID=", itemID, "matches=", #matches)
          badge.wishlistMatches = matches
          badge:Show()
        end
      end
    end
  end
end

-- Hook Blizzard vault UI ------------------------------------------------------

local function hookVaultUI()
  if hooked then return end
  local vaultFrame = _G["WeeklyRewardsFrame"]
  if not vaultFrame then return end
  hooked = true

  DevLog("hookVaultUI: hooking WeeklyRewardsFrame")

  -- Scan when vault is shown
  vaultFrame:HookScript("OnShow", function()
    C_Timer.After(0.1, scanAndAnnotate)
  end)

  -- Hook tooltip enhancement on activity frames
  for _, child in pairs({vaultFrame:GetChildren()}) do
    if child.info and child.ItemFrame then
      local itemFrame = child.ItemFrame
      if itemFrame:GetScript("OnEnter") then
        itemFrame:HookScript("OnEnter", function() onRewardEnter(child) end)
      else
        itemFrame:SetScript("OnEnter", function(self)
          -- Preserve default tooltip behavior by calling parent's tooltip if needed
          if self.UpdateTooltip then self:UpdateTooltip() end
          onRewardEnter(child)
        end)
      end
    end
  end

  -- Initial scan if already visible
  if vaultFrame:IsShown() then
    C_Timer.After(0.1, scanAndAnnotate)
  end
end

-- Events ----------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("WEEKLY_REWARDS_SHOW")
eventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
eventFrame:RegisterEvent("WEEKLY_REWARDS_ITEM_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local addonName = ...
    if addonName == "Blizzard_WeeklyRewards" then
      hookVaultUI()
    end
  elseif event == "WEEKLY_REWARDS_SHOW" then
    hookVaultUI()
    C_Timer.After(0.2, scanAndAnnotate)
  elseif event == "WEEKLY_REWARDS_UPDATE" or event == "WEEKLY_REWARDS_ITEM_CHANGED" then
    if hooked then
      C_Timer.After(0.1, scanAndAnnotate)
    end
  end
end)

-- Also check if Blizzard_WeeklyRewards is already loaded at PLAYER_LOGIN time
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
  local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards")
  if isLoaded then
    hookVaultUI()
  end
end)
