-- Loot Wishlist - Sticky Summary Window
-- Uses LuckyUI for consistent dark/gold styling.

LootWishlist = LootWishlist or {}
LootWishlist.Summary = LootWishlist.Summary or {}

local Summary = LootWishlist.Summary
local frame, textFS
local isDragging = false

local UI = LuckyUI
local C  = UI.C

local function ensureFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", "LootWishlistSummary", UIParent, "BackdropTemplate")
  frame:SetSize(320, 120)
  frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -300, -220)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if LootWishlistCharDB and self:GetPoint(1) then
      local p, rel, rp, x, y = self:GetPoint(1)
      LootWishlistCharDB.summaryWindow = {point=p, relative=rel and rel:GetName(), relativePoint=rp, x=x, y=y}
    end
  end)

  -- LuckyUI backdrop: dark bg with gold-muted border (subtle for sticky note)
  frame:SetBackdrop(UI.Backdrop)
  frame:SetBackdropColor(C.bgDark[1], C.bgDark[2], C.bgDark[3], 0.80)
  frame:SetBackdropBorderColor(C.goldMuted[1], C.goldMuted[2], C.goldMuted[3], 0.6)

  -- Text content
  textFS = frame:CreateFontString(nil, "OVERLAY")
  textFS:SetFont(UI.BODY_FONT, 11)
  textFS:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  textFS:SetJustifyH("LEFT")
  textFS:SetJustifyV("TOP")
  textFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
  textFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  textFS:SetText("")

  -- Click anywhere to open full list
  frame:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and not isDragging then
      if LootWishlist.UI and LootWishlist.UI.open then LootWishlist.UI.open() end
    end
  end)
  frame:HookScript("OnDragStart", function() isDragging = true end)
  frame:HookScript("OnDragStop", function() isDragging = false end)

  -- Hover: brighten border, restore full alpha
  frame:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 0.8)
    self:SetAlpha(1.0)
  end)
  frame:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(C.goldMuted[1], C.goldMuted[2], C.goldMuted[3], 0.6)
    local settings = LootWishlistDB and LootWishlistDB.settings
    local a = settings and settings.summaryUnhoveredAlpha
    if a == nil then a = 1.0 end
    self:SetAlpha(a)
  end)

  -- Restore position if saved
  local w = LootWishlistCharDB and LootWishlistCharDB.summaryWindow
  if w and w.point then
    frame:ClearAllPoints()
    frame:SetPoint(w.point, w.relative and _G[w.relative] or UIParent, w.relativePoint or w.point, w.x or 0, w.y or 0)
  end

  frame:Hide()
  return frame
end

local function joinTags(set)
  local arr = {}
  for k in pairs(set) do table.insert(arr, k) end
  local order = LootWishlist.Const.DIFF_TAG_ORDER
  table.sort(arr, function(a, b)
    local oa, ob = order[a] or 99, order[b] or 99
    if oa ~= ob then return oa < ob end
    return a < b
  end)
  return table.concat(arr, ", ")
end

local function tagText(items)
  local tags = {}
  for _, it in ipairs(items) do
    local tag = LootWishlist.Const.DiffTag(it.info.difficultyName, it.info.difficultyID)
    if tag then tags[tag] = true end
  end
  if not next(tags) then return "" end
  return " " .. UI.WC.textMuted .. "[" .. joinTags(tags) .. "]" .. UI.WC.reset
end

local function buildSummaryLines()
  local WC = UI.WC
  local lines = {}
  for _, inst in ipairs(LootWishlist.Layout.Build()) do
    if inst.bosses then
      lines[#lines + 1] = WC.goldPrimary .. inst.name .. WC.reset
      for _, boss in ipairs(inst.bosses) do
        lines[#lines + 1] = string.format("  - %s (%d)%s", boss.name, boss.count, tagText(boss.items))
      end
    else
      lines[#lines + 1] = string.format("%s%s%s (%d)%s", WC.goldPrimary, inst.name, WC.reset, inst.count, tagText(inst.items))
    end
  end
  return lines
end

local function shouldAutoHide()
  local settings = LootWishlistDB and LootWishlistDB.settings
  if not settings or settings.hideSummaryInCombatAndMythicPlus == false then return false end
  if InCombatLockdown() then return true end
  if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
    return true
  end
  return false
end

local function refresh()
  local f = ensureFrame()
  local settings = LootWishlistDB and LootWishlistDB.settings
  if settings and settings.hideSummaryWindow then f:Hide(); return end
  if shouldAutoHide() then f:Hide(); return end
  local lines = buildSummaryLines()
  if not next(lines) then f:Hide(); return end
  local content = table.concat(lines, "\n")
  textFS:SetText(content)
  local width = 300
  if textFS.GetStringWidth then width = math.max(200, math.min(300, textFS:GetStringWidth() + 24)) end
  frame:SetWidth(width)
  local height = 30 + (textFS.GetStringHeight and textFS:GetStringHeight() or 60)
  frame:SetHeight(height)
  -- Apply unhovered alpha (unless mouse is currently over the frame)
  local a = settings and settings.summaryUnhoveredAlpha
  if a == nil then a = 1.0 end
  if frame:IsMouseOver() then
    frame:SetAlpha(1.0)
  else
    frame:SetAlpha(a)
  end
  f:Show()
end

-- Coalesce refresh bursts (a bulk import calls this once per item) into a
-- single rebuild on the next frame.
local refreshPending = false
local function scheduleRefresh()
  if refreshPending then return end
  refreshPending = true
  C_Timer.After(0, function()
    refreshPending = false
    refresh()
  end)
end

Summary.refresh = scheduleRefresh

function Summary.showIfNeeded()
  scheduleRefresh()
end

-- Auto-hide on combat / Mythic+ transitions
local autoHideWatcher = CreateFrame("Frame")
autoHideWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
autoHideWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
autoHideWatcher:RegisterEvent("CHALLENGE_MODE_START")
autoHideWatcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
autoHideWatcher:RegisterEvent("CHALLENGE_MODE_RESET")
autoHideWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
autoHideWatcher:SetScript("OnEvent", function() refresh() end)
