-- Loot Wishlist - Great Vault Awareness
-- Overlays wishlist badges on Great Vault reward choices.

LootWishlist = LootWishlist or {}
LootWishlist.Vault = LootWishlist.Vault or {}

local Vault = LootWishlist.Vault
local S = LootWishlist.Strings.vault
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

local C = LuckyUI.C

local DevLog
if LuckyLog and LuckyLog.New then
  DevLog = LuckyLog:New("[Lwl-Vault][debug]", function()
    return LootWishlist.DEBUG and LootWishlist.DEBUG()
  end)
else
  DevLog = function() end
end

-- Badge overlay ---------------------------------------------------------------

local function ensureBadge(parent)
  if parent.LootWishlistVaultBadge then return parent.LootWishlistVaultBadge end

  local badge = CreateFrame("Frame", nil, parent)
  badge:SetSize(30, 30)
  badge:SetPoint("CENTER", parent, "TOPRIGHT", -10, -10)
  badge:SetFrameStrata("FULLSCREEN_DIALOG")
  badge:SetFrameLevel((parent:GetFrameLevel() or 5) + 10)

  local glow = badge:CreateTexture(nil, "ARTWORK")
  glow:SetTexture("Interface\\Cooldown\\star4")
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3], 0.8)
  glow:SetSize(44, 44)
  glow:SetPoint("CENTER")

  local star = badge:CreateTexture(nil, "OVERLAY")
  star:SetAtlas("auctionhouse-icon-favorite")
  star:SetSize(24, 22)
  star:SetPoint("CENTER")

  local pulse = glow:CreateAnimationGroup()
  pulse:SetLooping("BOUNCE")
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.4)
  fade:SetDuration(0.9)
  fade:SetSmoothing("IN_OUT")
  badge:SetScript("OnShow", function() pulse:Play() end)
  badge:SetScript("OnHide", function() pulse:Stop() end)

  -- Hover explains the badge; clicks pass through so reward selection still works.
  badge:SetMouseMotionEnabled(true)
  badge:SetMouseClickEnabled(false)
  badge:SetScript("OnEnter", function(self)
    local lines = self.wishlistLines
    if not lines or #lines == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(S.title, C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3])
    LootWishlist.UI.AddWishlistLines(GameTooltip, lines, S.matchesLine)
    GameTooltip:Show()
  end)
  badge:SetScript("OnLeave", function() GameTooltip:Hide() end)

  badge:Hide()
  parent.LootWishlistVaultBadge = badge
  return badge
end

-- Scan and annotate vault items -----------------------------------------------
-- The reward's own tooltip says it is on the wishlist the way every item
-- tooltip does, from LootWishlist_Tooltips.lua; the badge only adds the star.

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
      badge.wishlistLines = nil
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
        local lines = LootWishlist.UI.WishlistLines(itemID)
        if #lines > 0 then
          DevLog("Vault match: itemID=", itemID, "sources=", #lines)
          badge.wishlistLines = lines
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

