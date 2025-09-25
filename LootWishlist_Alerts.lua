-- Loot Wishlist - Drop Alerts

LootWishlist = LootWishlist or {}
LootWishlist.Alerts = LootWishlist.Alerts or {}

local Alerts = LootWishlist.Alerts
local alertFrame, alertFS, alertHideAt
local raidDropFrame, raidDropFS, raidDropHideAt
local rollAlertFrame, rollAlertFS, rollHideAt
local rollAlertItems = {}
-- Show a simple popup when a tracked item drops in a raid (regardless of looter)
local function ShowRaidDropAlert(itemLink)
  if not itemLink then return end
  if not raidDropFrame then
    raidDropFrame = CreateFrame("Frame", "LootWishlistRaidDropFrame", UIParent, "BackdropTemplate")
    raidDropFrame:SetSize(420, 60)
    raidDropFrame:SetPoint("TOP", UIParent, "TOP", 0, -220)
    raidDropFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    raidDropFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    raidDropFrame:SetBackdropColor(0, 0, 0, 0.8)
    raidDropFrame:SetBackdropBorderColor(1, 0.8, 0.2, 0.95)
    raidDropFrame:EnableMouse(true)
    raidDropFrame:SetMovable(true)
    raidDropFrame:RegisterForDrag("LeftButton")
    raidDropFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    raidDropFrame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      if LootWishlistCharDB and self:GetPoint(1) then
        local p, rel, rp, x, y = self:GetPoint(1)
        LootWishlistCharDB.raidDropWindow = {point=p, relative=rel and rel:GetName(), relativePoint=rp, x=x, y=y}
      end
    end)
    raidDropFS = raidDropFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    raidDropFS:SetPoint("CENTER")
    raidDropFS:SetJustifyH("CENTER")
    raidDropFS:SetJustifyV("MIDDLE")
    raidDropFS:SetText("")
    local w = LootWishlistCharDB and LootWishlistCharDB.raidDropWindow
    if w and w.point then
      raidDropFrame:ClearAllPoints()
      raidDropFrame:SetPoint(w.point, w.relative and _G[w.relative] or UIParent, w.relativePoint or w.point, w.x or 0, w.y or 0)
    end
    raidDropFrame:Hide()
    raidDropFrame:SetScript("OnUpdate", function(_, elapsed)
      if raidDropHideAt and GetTime() >= raidDropHideAt then
        raidDropFrame:Hide()
        raidDropHideAt = nil
      end
    end)
  end
  raidDropFS:SetText("Tracked item dropped in raid!\n"..(itemLink or "[unknown]"))
  raidDropFrame:Show()
  raidDropHideAt = GetTime() + 8
end

-- Show a popup when a group loot roll starts in a raid for a tracked item
local function ShowRaidRollAlert(itemLink)
  if not itemLink then return end
  if not rollAlertFrame then
    rollAlertFrame = CreateFrame("Frame", "LootWishlistRaidRollFrame", UIParent, "BackdropTemplate")
    rollAlertFrame:SetSize(420, 60)
    rollAlertFrame:SetPoint("TOP", UIParent, "TOP", 0, -280)
    rollAlertFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    rollAlertFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    rollAlertFrame:SetBackdropColor(0, 0, 0, 0.8)
    rollAlertFrame:SetBackdropBorderColor(0.3, 0.8, 1.0, 0.95)
    rollAlertFrame:EnableMouse(true)
    rollAlertFrame:SetMovable(true)
    rollAlertFrame:RegisterForDrag("LeftButton")
    rollAlertFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    rollAlertFrame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      if LootWishlistCharDB and self:GetPoint(1) then
        local p, rel, rp, x, y = self:GetPoint(1)
        LootWishlistCharDB.raidRollWindow = {point=p, relative=rel and rel:GetName(), relativePoint=rp, x=x, y=y}
      end
    end)
    rollAlertFS = rollAlertFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  rollAlertFS:SetPoint("CENTER")
    rollAlertFS:SetJustifyH("CENTER")
    rollAlertFS:SetJustifyV("MIDDLE")
    rollAlertFS:SetText("")
    local w = LootWishlistCharDB and LootWishlistCharDB.raidRollWindow
    if w and w.point then
      rollAlertFrame:ClearAllPoints()
      rollAlertFrame:SetPoint(w.point, w.relative and _G[w.relative] or UIParent, w.relativePoint or w.point, w.x or 0, w.y or 0)
    end
    rollAlertFrame:Hide()
    rollAlertFrame:SetScript("OnUpdate", function(_, elapsed)
      if rollHideAt and GetTime() >= rollHideAt then
        rollAlertFrame:Hide()
        rollHideAt = nil
        -- Clear accumulated items when the alert hides
        wipe(rollAlertItems)
      end
    end)
  end
  -- Accumulate unique items into the roll list
  local exists = false
  for _, l in ipairs(rollAlertItems) do if l == itemLink then exists = true; break end end
  if not exists then table.insert(rollAlertItems, itemLink or "[unknown]") end
  local lines = { "Roll now if needed!" }
  for _, l in ipairs(rollAlertItems) do table.insert(lines, "- " .. (l or "[unknown]")) end
  local text = table.concat(lines, "\n")
  rollAlertFS:SetText(text)
  -- Ensure wrapping width for height calculation
  if rollAlertFS.SetWidth and rollAlertFrame.GetWidth then
    rollAlertFS:SetWidth(rollAlertFrame:GetWidth() - 20)
  end
  -- Adjust height to fit multiple items
  local desiredH = (rollAlertFS.GetStringHeight and (rollAlertFS:GetStringHeight() + 20)) or 60
  rollAlertFrame:SetHeight(math.max(60, math.min(200, desiredH)))
  rollAlertFrame:Show()
  -- Extend visibility timer with each new item
  rollHideAt = GetTime() + 8
end
local btnRemove, btnKeep, btnWhisper, btnParty, btnDismiss
local currentItemID, currentItemLink, currentLooter, currentIsSelf

local function ensureAlertFrame()
  if alertFrame then return alertFrame end
  local C = LootWishlist.Const or {}
  alertFrame = CreateFrame("Frame", "LootWishlistAlertFrame", UIParent, "BackdropTemplate")
  alertFrame:SetSize(C.ALERT_FRAME_INITIAL_WIDTH or 480, C.ALERT_FRAME_INITIAL_HEIGHT or 110)
  alertFrame:SetPoint("TOP", UIParent, "TOP", 0, C.ALERT_TOP_OFFSET or -160)
  alertFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  alertFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  alertFrame:SetBackdropColor(0, 0, 0, (C.ALERT_BG_ALPHA or 0.7))
  do
    local b = C.ALERT_BORDER_COLOR_DEFAULT or {1,1,1,0.8}
    alertFrame:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
  end
  alertFrame:EnableMouse(true)
  alertFrame:SetMovable(true)
  alertFrame:RegisterForDrag("LeftButton")
  alertFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  alertFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if LootWishlistCharDB and self:GetPoint(1) then
      local p, rel, rp, x, y = self:GetPoint(1)
      LootWishlistCharDB.alertWindow = {point=p, relative=rel and rel:GetName(), relativePoint=rp, x=x, y=y}
    end
  end)
  alertFrame:SetScript("OnMouseUp", function()
    if (btnRemove and btnRemove:IsShown() and btnRemove:IsMouseOver())
      or (btnKeep and btnKeep:IsShown() and btnKeep:IsMouseOver())
      or (btnWhisper and btnWhisper:IsShown() and btnWhisper:IsMouseOver())
      or (btnParty and btnParty:IsShown() and btnParty:IsMouseOver())
      or (btnDismiss and btnDismiss:IsShown() and btnDismiss:IsMouseOver()) then
      return
    end
    if LootWishlist.Ace and LootWishlist.Ace.open then LootWishlist.Ace.open() end
  end)

  alertFS = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  alertFS:SetPoint("TOP", 0, -12)
  alertFS:SetJustifyH("CENTER")
  alertFS:SetJustifyV("MIDDLE")
  alertFS:SetText("")

  local function createButton(text)
    local b = CreateFrame("Button", nil, alertFrame, "UIPanelButtonTemplate")
    b:SetSize(110, 22)
    b:Hide()
    return b
  end

  btnRemove = createButton("Remove")
  btnKeep = createButton("Keep")
  btnWhisper = createButton("Whisper")
  btnParty = createButton("Party")
  btnDismiss = createButton("Dismiss")

  -- Position buttons (centered row near bottom)
  btnRemove:SetPoint("BOTTOM", alertFrame, "BOTTOM", -115, 12)
  btnKeep:SetPoint("BOTTOM", alertFrame, "BOTTOM", 115, 12)

  btnWhisper:SetPoint("BOTTOM", alertFrame, "BOTTOM", -150, 12)
  btnParty:SetPoint("BOTTOM", alertFrame, "BOTTOM", 0, 12)
  btnDismiss:SetPoint("BOTTOM", alertFrame, "BOTTOM", 150, 12)

  local w = LootWishlistCharDB and LootWishlistCharDB.alertWindow
  if w and w.point then
    alertFrame:ClearAllPoints()
    alertFrame:SetPoint(w.point, w.relative and _G[w.relative] or UIParent, w.relativePoint or w.point, w.x or 0, w.y or 0)
  end

  alertFrame:Hide()
  alertFrame:SetScript("OnUpdate", function(_, elapsed)
    if alertHideAt and GetTime() >= alertHideAt then
      alertFrame:Hide()
      alertHideAt = nil
    end
  end)
  return alertFrame
end

local function ShowDropAlert(itemLink)
  local C = LootWishlist.Const or {}
  local f = ensureAlertFrame()
  local prefix = C.ALERT_TEXT_PREFIX_WISHLIST or "Wishlist item dropped:"
  alertFS:SetText(string.format("%s\n%s", prefix, itemLink or "[unknown]"))

  f:SetBackdropBorderColor(0.2, 1.0, 0.2, 0.9)
  -- Adjust width to content
  local width = (LootWishlist.Const and LootWishlist.Const.ALERT_FRAME_INITIAL_WIDTH) or 480
  if alertFS.GetStringWidth then
    local minW = (LootWishlist.Const and LootWishlist.Const.ALERT_WIDTH_MIN_DEFAULT) or 360
    local maxW = (LootWishlist.Const and LootWishlist.Const.ALERT_WIDTH_MAX_DEFAULT) or 700
    local pad = (LootWishlist.Const and LootWishlist.Const.ALERT_WIDTH_PAD) or 80
    width = math.max(minW, math.min(maxW, alertFS:GetStringWidth() + pad))
  end
  f:SetWidth(width)
  f:Show()
  alertHideAt = GetTime() + ((LootWishlist.Const and LootWishlist.Const.ALERT_AUTOHIDE_SECONDS) or 6)
end

-- Resolve a proper clickable item link from an itemID, asynchronously if needed
local function getItemLinkAsync(itemID, cb)
  if not itemID then cb(nil); return end
  local item
  if Item and Item.CreateFromItemID then
    -- Use proper colon call so "Item" is passed as self
    item = Item:CreateFromItemID(itemID)
  end
  if not item then
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    cb(string.format("item:%d", itemID))
    return
  end
  local link = item.GetItemLink and item:GetItemLink()
  if link then cb(link); return end
  if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
  if item.ContinueOnItemLoad then
    item:ContinueOnItemLoad(function()
      local l = item.GetItemLink and item:GetItemLink()
      cb(l or string.format("item:%d", itemID))
    end)
  else
    cb(string.format("item:%d", itemID))
  end
end

-- Helpers to parse chat loot messages into looter context (localized-safe best effort)
local function escapeLuaPattern(s)
  return s and s:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1") or s
end

local function gs2pat(gs)
  if not gs then return nil end
  local p = escapeLuaPattern(gs)
  p = p:gsub("%%s", "(.+)")
  return "^" .. p .. "$"
end

local SELF_PATS = {
  function(msg)
    local pat = gs2pat(LOOT_ITEM_SELF)
    return pat and msg:match(pat)
  end,
  function(msg)
    local pat = gs2pat(LOOT_ITEM_SELF_MULTIPLE)
    return pat and msg:match(pat)
  end,
  function(msg)
    local pat = gs2pat(LOOT_ITEM_PUSHED_SELF)
    return pat and msg:match(pat)
  end,
  function(msg)
    local pat = gs2pat(LOOT_ITEM_BONUS_ROLL)
    return pat and msg:match(pat)
  end,
}

local OTHER_PATS = {
  function(msg)
    local pat = gs2pat(LOOT_ITEM) -- %s receives loot: %s.
    if not pat then return end
    return msg:match(pat)
  end,
  function(msg)
    local pat = gs2pat(LOOT_ITEM_MULTIPLE)
    if not pat then return end
    return msg:match(pat)
  end,
  function(msg)
    local pat = gs2pat(LOOT_ITEM_PUSHED)
    if not pat then return end
    return msg:match(pat)
  end,
}

local function extractLooterFromChat(msg)
  -- Returns isSelf, looterNameOrNil
  for _, fn in ipairs(SELF_PATS) do
    local ok, a = pcall(fn, msg)
    if ok and a then return true, UnitName("player") end
  end
  for _, fn in ipairs(OTHER_PATS) do
    local ok, name = pcall(fn, msg)
    if ok and name then return false, name end
  end
  return nil, nil
end

local function chooseGroupChatPrefix()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "/i" end
  if IsInRaid() then return "/raid" end
  if IsInGroup() then return "/p" end
  return "/s"
end

local function hideAllButtons()
  if btnRemove then btnRemove:Hide() end
  if btnKeep then btnKeep:Hide() end
  if btnWhisper then btnWhisper:Hide() end
  if btnParty then btnParty:Hide() end
  if btnDismiss then btnDismiss:Hide() end
end

local function configureSelfActions(itemID, itemLink)
  hideAllButtons()
  alertHideAt = nil -- keep visible until action
  -- Expand alert for two buttons
  if alertFrame then
    local minW = (LootWishlist.Const and LootWishlist.Const.ALERT_MIN_WIDTH_SELF) or 460
    if alertFrame.GetWidth then alertFrame:SetWidth(math.max(alertFrame:GetWidth(), minW)) end
    alertFrame:SetHeight((LootWishlist.Const and LootWishlist.Const.ALERT_HEIGHT_WITH_BUTTONS) or 130)
  end
  if btnRemove and btnKeep then
    btnRemove:SetText("Remove")
    btnKeep:SetText("Keep")
    btnRemove:SetScript("OnClick", function()
      if LootWishlist.RemoveTrackedItem then LootWishlist.RemoveTrackedItem(itemID) end
      alertFrame:Hide()
    end)
    btnKeep:SetScript("OnClick", function() alertFrame:Hide() end)
    btnRemove:Show()
    btnKeep:Show()
  end
end

local function configureOtherActions(looterName, itemID, itemLink)
  hideAllButtons()
  alertHideAt = nil -- keep visible until action
  -- Expand alert for three buttons
  if alertFrame then
    local minW = (LootWishlist.Const and LootWishlist.Const.ALERT_MIN_WIDTH_OTHER) or 540
    if alertFrame.GetWidth then alertFrame:SetWidth(math.max(alertFrame:GetWidth(), minW)) end
    alertFrame:SetHeight((LootWishlist.Const and LootWishlist.Const.ALERT_HEIGHT_WITH_BUTTONS) or 130)
  end
  looterName = looterName or "player"
  local st = LootWishlist.GetSettings and LootWishlist.GetSettings() or (LootWishlistCharDB and LootWishlistCharDB.settings) or {}
  local function applyTemplate(tpl)
    if not tpl or tpl == "" then return "" end
    local out = tpl:gsub("%%item%%", itemLink or "[item]")
    out = out:gsub("%%looter%%", looterName)
    return out
  end
  local whisperText = applyTemplate(st.whisperTemplate) ~= "" and applyTemplate(st.whisperTemplate) or string.format("Hi %s, grats! If %s is tradeable, could I please have it? It's on my wishlist.", looterName, itemLink)
  local partyText = applyTemplate(st.partyTemplate) ~= "" and applyTemplate(st.partyTemplate) or string.format("If %s is tradeable, I'd love it (wishlist). Thanks!", itemLink)
  if btnWhisper and btnParty and btnDismiss then
    btnWhisper:SetText("Whisper")
    btnParty:SetText("Party")
    btnDismiss:SetText("Dismiss")
    btnWhisper:SetScript("OnClick", function()
      if not looterName then alertFrame:Hide(); return end
      if ChatEdit_ChooseBoxForSend and ChatEdit_SendText and ChatEdit_ActivateChat then
        local eb = ChatEdit_ChooseBoxForSend()
        if eb then
          local prevShown = eb:IsShown()
          ChatEdit_ActivateChat(eb)
          eb:SetText(string.format("/w %s %s", looterName, whisperText))
          ChatEdit_SendText(eb, 0)
          eb:SetText("")
          if not prevShown then eb:Hide() end
        end
      end
      alertFrame:Hide()
    end)
    btnParty:SetScript("OnClick", function()
      -- Only send if the player is actually in a group (instance, raid, or party)
      local grouped = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or IsInRaid() or IsInGroup()
      if not grouped then
        -- Silently do nothing when solo
        alertFrame:Hide()
        return
      end
      local prefix = chooseGroupChatPrefix()
      if ChatEdit_ChooseBoxForSend and ChatEdit_SendText and ChatEdit_ActivateChat then
        local eb = ChatEdit_ChooseBoxForSend()
        if eb then
          local prevShown = eb:IsShown()
          ChatEdit_ActivateChat(eb)
          eb:SetText(prefix .. " " .. partyText)
          ChatEdit_SendText(eb, 0)
          eb:SetText("")
          if not prevShown then eb:Hide() end
        end
      end
      alertFrame:Hide()
    end)
    btnDismiss:SetScript("OnClick", function() alertFrame:Hide() end)
    btnWhisper:Show(); btnParty:Show(); btnDismiss:Show()
  end
end

local function ShowDropAlertWithContext(itemLink, isSelf, looterName, itemID)
  ShowDropAlert(itemLink)
  if isSelf then
    configureSelfActions(itemID, itemLink)
  else
    configureOtherActions(looterName, itemID, itemLink)
  end
  currentItemID, currentItemLink, currentLooter, currentIsSelf = itemID, itemLink, looterName, isSelf
end

local function extractLinks(msg)
  local links = {}
  if not msg or type(msg) ~= "string" then return links end
  for link in msg:gmatch("|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r") do
    table.insert(links, link)
  end
  return links
end

local function parseItemIDFromLink(link)
  if not link then return nil end
  local idStr = link:match("item:(%d+)")
  return idStr and tonumber(idStr) or nil
end

local function isTracked(itemID)
  local t = LootWishlist.GetTracked and LootWishlist.GetTracked()
  return t and t[itemID] and true or false
end

-- Event handling
local ef = CreateFrame("Frame")
ef:RegisterEvent("CHAT_MSG_LOOT")
ef:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
ef:RegisterEvent("START_LOOT_ROLL")
ef:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_LOOT" then
    local msg = ...
    local inRaid = IsInRaid() or (IsInGroup() and IsInInstance() and select(2, IsInInstance()) == "raid")
    local isSelf, looter = extractLooterFromChat(msg)
    if isSelf == nil then return end -- couldn't determine: avoid false prompts
    for _, link in ipairs(extractLinks(msg)) do
      local itemID = parseItemIDFromLink(link)
      if itemID and isTracked(itemID) then
        if inRaid then
          -- In raids, suppress the action/party-whisper alert and the simple raid drop banner.
          -- We'll rely on the START_LOOT_ROLL reminder popup instead.
        else
          if isSelf then
            ShowDropAlertWithContext(link, true, UnitName("player"), itemID)
          else
            ShowDropAlertWithContext(link, false, looter, itemID)
          end
        end
      end
    end
  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    -- encounterID, itemID, itemLink, quantity, playerName, ...
    local _encounterID, itemID, itemLink, _quantity, playerName = ...
    if itemID and isTracked(itemID) then
      local function withLink(l)
        local inRaid = IsInRaid() or (IsInGroup() and IsInInstance() and select(2, IsInInstance()) == "raid")
        if inRaid then
          -- In raids, skip the action/party-whisper alert and the simple raid drop banner.
          -- The roll reminder (START_LOOT_ROLL) will handle notifying the player.
          return
        end
        local you = UnitName("player")
        local isSelf = (playerName == nil) or (playerName == you) or (playerName == you.."-"..GetRealmName())
        ShowDropAlertWithContext(l, isSelf, playerName, itemID)
      end
      if itemLink then withLink(itemLink) else getItemLinkAsync(itemID, withLink) end
    end
  elseif event == "START_LOOT_ROLL" then
    -- rollID, rollTime
    local rollID = ...
    local st = LootWishlist.GetSettings and LootWishlist.GetSettings() or (LootWishlistCharDB and LootWishlistCharDB.settings) or {}
    if st and st.enableRaidRollAlert == false then return end
    -- Only alert in raid instances or raid groups
    local inRaid = IsInRaid() or (IsInGroup() and IsInInstance() and select(2, IsInInstance()) == "raid")
    if not inRaid then return end
    -- Try to fetch itemLink from roll info APIs
    local itemLink
    if C_LootHistory and C_LootHistory.GetItem then
      local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, link = C_LootHistory.GetItem(rollID)
      itemLink = link
    end
    if not itemLink and GetLootRollItemLink then
      itemLink = GetLootRollItemLink(rollID)
    end
    if not itemLink then return end
    -- Only alert for wishlist-tracked items
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return end
    if not isTracked(itemID) then return end
    ShowRaidRollAlert(itemLink)
  end
end)

-- Public API
function Alerts.TestDrop(input, forceNot)
  local itemID, link
  if type(input) == "number" then itemID = input end
  if not itemID and type(input) == "string" then
    local num = tonumber(input)
    if num then itemID = num end
    if not itemID then
      link = input
      itemID = parseItemIDFromLink(link)
    end
  end
  if not itemID then
    print("Loot Wishlist: testdrop requires an itemID or item link")
    return
  end
  local tracked = isTracked(itemID)
  if forceNot then tracked = false end
  -- Only show alerts for items that are in the wishlist
  if not tracked then return end
  local function show(l)
    ShowDropAlertWithContext(l, true, UnitName("player"), itemID)
  end
  if link then show(link) else getItemLinkAsync(itemID, show) end
end

function Alerts.TestDropOther(input)
  -- input can be: "<itemID|link> [looterName]"
  local itemArg, looterName = input:match("^%s*(.-)%s+([^%s].*)$")
  if not itemArg then itemArg = input end
  local itemID, link
  local num = tonumber(itemArg)
  if num then itemID = num else link = itemArg; itemID = parseItemIDFromLink(link) end
  if not itemID then
    print("Loot Wishlist: testdrop-other requires an itemID or item link")
    return
  end
  if not isTracked(itemID) then return end
  local function show(l)
    ShowDropAlertWithContext(l, false, looterName or "Teammate", itemID)
  end
  if link then show(link) else getItemLinkAsync(itemID, show) end
end
