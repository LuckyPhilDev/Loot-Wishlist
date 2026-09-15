-- Loot Wishlist - Sticky Summary Window
-- Uses LuckyUI for consistent dark/gold styling.

LootWishlist = LootWishlist or {}
LootWishlist.Summary = LootWishlist.Summary or {}

local Summary = LootWishlist.Summary
local frame, textFS, button
local isDragging = false
local unfurled = false
local refresh

local UI = LuckyUI
local C  = UI.C
local S  = LootWishlist.Strings.summary

local BUTTON_SIZE = 36
local BUTTON_GAP = 4

local function settings()
  return LootWishlistDB and LootWishlistDB.settings
end

local function mode()
  local s = settings()
  return s and s.summaryMode or "button"
end

local function unhoveredAlpha(key)
  local s = settings()
  return s and s[key] or 1.0
end

local function fadeUnlessHovered(f, key)
  f:SetAlpha(f:IsMouseOver() and 1.0 or unhoveredAlpha(key))
end

local function savePosition(f, key)
  local p, rel, rp, x, y = f:GetPoint(1)
  if LootWishlistCharDB and p then
    LootWishlistCharDB[key] = {point=p, relative=rel and rel:GetName(), relativePoint=rp, x=x, y=y}
  end
end

local function restorePosition(f, saved)
  f:ClearAllPoints()
  if saved and saved.point then
    f:SetPoint(saved.point, saved.relative and _G[saved.relative] or UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
  else
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -300, -220)
  end
end

local function charDB()
  return LootWishlistCharDB or {}
end

-- The summary hangs off the button while it is one, so dragging the summary
-- has to move the button instead of pulling the two apart.
local function mover()
  if mode() == "button" then return button, "summaryButton" end
  return frame, "summaryWindow"
end

local function ensureFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", "LootWishlistSummary", UIParent, "BackdropTemplate")
  frame:SetSize(320, 120)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() mover():StartMoving() end)
  frame:SetScript("OnDragStop", function()
    local f, key = mover()
    f:StopMovingOrSizing()
    savePosition(f, key)
    refresh()
  end)

  frame:SetBackdrop(UI.Backdrop)
  frame:SetBackdropColor(C.bgDark[1], C.bgDark[2], C.bgDark[3], 0.80)
  frame:SetBackdropBorderColor(C.goldMuted[1], C.goldMuted[2], C.goldMuted[3], 0.6)

  textFS = frame:CreateFontString(nil, "OVERLAY")
  textFS:SetFont(UI.BODY_FONT, 11)
  textFS:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  textFS:SetJustifyH("LEFT")
  textFS:SetJustifyV("TOP")
  textFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
  textFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  textFS:SetText("")

  frame:SetScript("OnMouseUp", function(_, mouseButton)
    if mouseButton == "LeftButton" and not isDragging then
      if LootWishlist.UI and LootWishlist.UI.open then LootWishlist.UI.open() end
    end
  end)
  frame:HookScript("OnDragStart", function() isDragging = true end)
  frame:HookScript("OnDragStop", function() isDragging = false end)

  frame:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 0.8)
    self:SetAlpha(1.0)
  end)
  frame:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(C.goldMuted[1], C.goldMuted[2], C.goldMuted[3], 0.6)
    self:SetAlpha(unhoveredAlpha("summaryUnhoveredAlpha"))
  end)

  restorePosition(frame, charDB().summaryWindow)
  frame:Hide()
  return frame
end

local function ensureButton()
  if button then return button end
  button = UI.CreateIconButton(UIParent, {
    icon    = LuckyMedia("promo-loot-wishlist.tga"),
    size    = BUTTON_SIZE,
    color   = { 1, 1, 1 },
    tooltip = function(tt)
      tt:AddLine(LootWishlist.Strings.addon.title, C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3])
      tt:AddLine(S.buttonClick, C.textLight[1], C.textLight[2], C.textLight[3])
      tt:AddLine(S.buttonDrag, C.textMuted[1], C.textMuted[2], C.textMuted[3])
    end,
  })
  button:SetFrameStrata("MEDIUM")
  button:SetClampedToScreen(true)
  button:SetMovable(true)
  -- A button's drag only starts once the cursor leaves it, so the press itself picks it up.
  button:SetScript("OnMouseDown", function(self, mouseButton)
    if mouseButton == "RightButton" then self:StartMoving() end
  end)
  button:SetScript("OnMouseUp", function(self, mouseButton)
    if mouseButton ~= "RightButton" then return end
    self:StopMovingOrSizing()
    savePosition(self, "summaryButton")
    refresh()
  end)
  button:SetScript("OnClick", function()
    unfurled = not unfurled
    refresh()
  end)
  button:HookScript("OnEnter", function(self) self:SetAlpha(1.0) end)
  button:HookScript("OnLeave", function(self) self:SetAlpha(unhoveredAlpha("summaryButtonUnhoveredAlpha")) end)

  -- A first button takes the spot the summary window was left in.
  restorePosition(button, charDB().summaryButton or charDB().summaryWindow)
  button:Hide()
  return button
end

-- Opens toward the middle of the screen, so a button parked by an edge never
-- pushes the summary off it.
local function anchorToButton()
  local x, y = button:GetCenter()
  local below = y > UIParent:GetHeight() / 2
  local side = x > UIParent:GetWidth() / 2 and "RIGHT" or "LEFT"
  frame:ClearAllPoints()
  if below then
    frame:SetPoint("TOP" .. side, button, "BOTTOM" .. side, 0, -BUTTON_GAP)
  else
    frame:SetPoint("BOTTOM" .. side, button, "TOP" .. side, 0, BUTTON_GAP)
  end
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
  local s = settings()
  if not s or s.hideSummaryInCombatAndMythicPlus == false then return false end
  if InCombatLockdown() then return true end
  if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
    return true
  end
  return false
end

local function hideAll()
  frame:Hide()
  button:Hide()
end

function refresh()
  local f, b = ensureFrame(), ensureButton()
  if mode() == "hidden" or shouldAutoHide() then hideAll(); return end
  local lines = buildSummaryLines()
  if not next(lines) then hideAll(); return end

  local asButton = mode() == "button"
  b:SetShown(asButton)
  fadeUnlessHovered(b, "summaryButtonUnhoveredAlpha")
  if asButton and not unfurled then f:Hide(); return end

  textFS:SetText(table.concat(lines, "\n"))
  local width = 300
  if textFS.GetStringWidth then width = math.max(200, math.min(300, textFS:GetStringWidth() + 24)) end
  frame:SetWidth(width)
  local height = 30 + (textFS.GetStringHeight and textFS:GetStringHeight() or 60)
  frame:SetHeight(height)

  if asButton then
    anchorToButton()
  elseif select(2, f:GetPoint(1)) == b then
    restorePosition(f, charDB().summaryWindow)
  end

  fadeUnlessHovered(f, "summaryUnhoveredAlpha")
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

local autoHideWatcher = CreateFrame("Frame")
autoHideWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
autoHideWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
autoHideWatcher:RegisterEvent("CHALLENGE_MODE_START")
autoHideWatcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
autoHideWatcher:RegisterEvent("CHALLENGE_MODE_RESET")
autoHideWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
autoHideWatcher:SetScript("OnEvent", function() refresh() end)
