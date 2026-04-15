-- Loot Wishlist - Great Vault Awareness
-- Overlays wishlist badges on Great Vault reward choices.

LootWishlist = LootWishlist or {}
LootWishlist.Vault = LootWishlist.Vault or {}

local Vault = LootWishlist.Vault
local hooked = false

-- Register Diagnose EARLY so it survives any later load-time errors.
function Vault.Diagnose()
  local function p(...) print("|cffffd100[LWL-Vault]|r", ...) end
  local vaultFrame = _G["WeeklyRewardsFrame"]
  if not vaultFrame then
    p("WeeklyRewardsFrame not loaded. Open the vault first.")
    return
  end
  p("vaultFrame shown:", tostring(vaultFrame:IsShown()), "hooked:", tostring(hooked))

  local activities = C_WeeklyRewards and C_WeeklyRewards.GetActivities()
  p("GetActivities count:", activities and #activities or "nil")
  if activities then
    for i, a in ipairs(activities) do
      p(string.format("  act[%d] id=%s type=%s index=%s threshold=%s progress=%s rewards=%d",
        i, tostring(a.id), tostring(a.type), tostring(a.index),
        tostring(a.threshold), tostring(a.progress), a.rewards and #a.rewards or 0))
    end
  end

  p("vaultFrame.Activities type:", type(vaultFrame.Activities),
    "count:", type(vaultFrame.Activities) == "table" and #vaultFrame.Activities or "n/a")

  local children = {vaultFrame:GetChildren()}
  p("direct children:", #children)
  for i, c in ipairs(children) do
    local name = c.GetName and c:GetName() or "unnamed"
    local hasInfo = c.info ~= nil
    local hasItemFrame = c.ItemFrame ~= nil
    if hasInfo or hasItemFrame then
      p(string.format("  child[%d] %s info=%s itemFrame=%s",
        i, tostring(name), tostring(hasInfo), tostring(hasItemFrame)))
    end
  end

  local sample
  if type(vaultFrame.Activities) == "table" and vaultFrame.Activities[1] then
    sample = vaultFrame.Activities[1]
  else
    for _, c in ipairs(children) do if c.ItemFrame then sample = c; break end end
  end
  if sample then
    local f = sample.ItemFrame
    p("sample activity: info=", tostring(sample.info ~= nil))
    if f then
      p(string.format("  ItemFrame fields: displayedItemDBID=%s displayedItemLink=%s displayedItemID=%s",
        tostring(f.displayedItemDBID), tostring(f.displayedItemLink), tostring(f.displayedItemID)))
    end
  end

  -- Sample each activity frame's ItemFrame to see which fields are populated
  if type(vaultFrame.Activities) == "table" then
    for i, af in ipairs(vaultFrame.Activities) do
      local f = af.ItemFrame
      if f then
        p(string.format("  Activities[%d].ItemFrame: dbid=%s link=%s id=%s",
          i, tostring(f.displayedItemDBID), tostring(f.displayedItemLink), tostring(f.displayedItemID)))
      end
    end
  end

  -- Force a scan
  if Vault.Hook then Vault.Hook() end
  if Vault.Scan then
    p("running scan...")
    Vault.Scan()
  end

  -- Show tracked wishlist item IDs for comparison
  if LootWishlist.GetTracked then
    local tracked = LootWishlist.GetTracked() or {}
    local ids = {}
    for _, v in pairs(tracked) do
      if type(v) == "table" and v.id then table.insert(ids, tostring(v.id)) end
    end
    p("tracked item IDs (" .. #ids .. "):", table.concat(ids, ", "))
  end
end

local UI = LuckyUI
local C  = UI and UI.C

local DevLog
if LuckyLog and LuckyLog.New then
  DevLog = LuckyLog:New("[Lwl-Vault][debug]", function()
    return LootWishlist.DEBUG and LootWishlist.DEBUG()
  end)
else
  DevLog = function() end
end

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
  badge:SetSize(32, 32)
  badge:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)
  badge:SetFrameStrata("FULLSCREEN_DIALOG")
  badge:SetFrameLevel((parent:GetFrameLevel() or 5) + 10)
  badge:SetBackdrop(UI.Backdrop)
  badge:SetBackdropColor(C.bgDark[1], C.bgDark[2], C.bgDark[3], 0.92)
  badge:SetBackdropBorderColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 1)

  local star = badge:CreateTexture(nil, "OVERLAY")
  star:SetTexture("Interface\\COMMON\\FavoritesIcon")
  star:SetSize(32, 32)
  star:SetPoint("CENTER", 0, 0)

  badge:Hide()
  parent.LootWishlistVaultBadge = badge
  return badge
end

-- Tooltip enhancement ---------------------------------------------------------

-- Walk up an owner chain looking for an activity frame that carries our badge.
local function findBadgeOwner(frame)
  local f = frame
  local hops = 0
  while f and hops < 6 do
    if f.LootWishlistVaultBadge then return f end
    f = f.GetParent and f:GetParent() or nil
    hops = hops + 1
  end
  return nil
end

local function appendWishlistLines(tooltip, matches)
  tooltip:AddLine(" ")
  tooltip:AddLine("On your Wishlist:", C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3])
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
    tooltip:AddLine("  " .. info.boss .. " - " .. info.dungeon .. tagStr,
      C.textLight[1], C.textLight[2], C.textLight[3])
  end
  tooltip:Show()
end

-- Modern tooltip hook: post-call runs after Blizzard has populated the tooltip.
if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip
       and tooltip ~= EmbeddedItemTooltip and tooltip ~= GameTooltip.ItemTooltip then
      return
    end
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if not owner then return end
    local activity = findBadgeOwner(owner)
    if not activity then return end
    local badge = activity.LootWishlistVaultBadge
    if not badge or not badge:IsShown() then return end
    local matches = badge.wishlistMatches
    if not matches or #matches == 0 then return end
    appendWishlistLines(tooltip, matches)
  end)
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

  local activities = C_WeeklyRewards and C_WeeklyRewards.GetActivities()
  if not activities then return end

  -- Collect activity frames. Blizzard stores them in WeeklyRewardsFrame.Activities
  -- (a plain Lua table) and also as direct children of the vault frame. Prefer the
  -- table since children include many non-activity frames (headers, close button,
  -- overlay, etc.) and mixin field names have shifted across patches.
  local activityFrames = {}
  if type(vaultFrame.Activities) == "table" then
    for _, f in ipairs(vaultFrame.Activities) do
      table.insert(activityFrames, f)
    end
  end
  if #activityFrames == 0 then
    for _, child in pairs({vaultFrame:GetChildren()}) do
      if child.info or child.ItemFrame then
        table.insert(activityFrames, child)
      end
    end
  end

  DevLog("scanAndAnnotate: found", #activityFrames, "activity frames,", #activities, "activities")

  -- Build activityID → frame map. Match on info.id, falling back to (type,index) pair.
  local rewardElements = {}
  for _, frame in ipairs(activityFrames) do
    local info = frame.info or frame.activityInfo
    if info then
      if info.id then
        rewardElements[info.id] = frame
      end
      if info.type and info.index then
        rewardElements[info.type .. ":" .. info.index] = frame
      end
    end
  end

  for _, activity in ipairs(activities) do
    local element = rewardElements[activity.id]
      or (activity.type and activity.index and rewardElements[activity.type .. ":" .. activity.index])
    if element then
      local badge = ensureBadge(element)
      badge.wishlistMatches = nil
      badge:Hide()

      -- Try to get the item from the element's displayed item.
      -- Note: displayedItemDBID is a weekly-reward DB row id, NOT an itemID.
      -- Convert via C_WeeklyRewards.GetItemHyperlink, or use displayedItemLink directly.
      local itemID
      local itemFrame = element.ItemFrame
      if itemFrame then
        if itemFrame.displayedItemLink then
          itemID = extractItemID(itemFrame.displayedItemLink)
        end
        if not itemID and itemFrame.displayedItemDBID and C_WeeklyRewards.GetItemHyperlink then
          local ok, link = pcall(C_WeeklyRewards.GetItemHyperlink, itemFrame.displayedItemDBID)
          if ok and link then
            itemID = extractItemID(link)
          end
        end
      end

      -- Fallback: convert rewards from the activity info itself
      if not itemID and activity.rewards and C_WeeklyRewards.GetItemHyperlink then
        for _, reward in ipairs(activity.rewards) do
          if reward.id or reward.itemDBID then
            local ok, link = pcall(C_WeeklyRewards.GetItemHyperlink, reward.id or reward.itemDBID)
            if ok and link then
              local id = extractItemID(link)
              if id then itemID = id; break end
            end
          end
        end
      end

      -- Last resort: example hyperlinks API
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

  -- Tooltip enhancement is handled globally by TooltipDataProcessor above.

  -- Initial scan if already visible
  if vaultFrame:IsShown() then
    C_Timer.After(0.1, scanAndAnnotate)
  end
end

-- Expose early so even if event registration errors, slash command can trigger.
Vault.Scan = scanAndAnnotate
Vault.Hook = hookVaultUI

-- Events ----------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local function safeRegister(name)
  local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, name)
  if not ok then
    print("|cffff6b6b[LWL-Vault]|r RegisterEvent failed for " .. tostring(name) .. ": " .. tostring(err))
  end
end
safeRegister("ADDON_LOADED")
safeRegister("WEEKLY_REWARDS_SHOW")
safeRegister("WEEKLY_REWARDS_UPDATE")
safeRegister("WEEKLY_REWARDS_ITEM_CHANGED")
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
    if _G["WeeklyRewardsFrame"] and _G["WeeklyRewardsFrame"]:IsShown() then
      C_Timer.After(0.1, scanAndAnnotate)
    end
  end
end)

-- If the vault was already open across a /reload, ADDON_LOADED / WEEKLY_REWARDS_SHOW
-- already fired. Hook and scan immediately at file-load time to recover.
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards")
   and _G["WeeklyRewardsFrame"] then
  hookVaultUI()
  if _G["WeeklyRewardsFrame"]:IsShown() then
    C_Timer.After(0.1, scanAndAnnotate)
  end
end

