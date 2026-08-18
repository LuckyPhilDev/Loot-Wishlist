-- Loot Wishlist - Drop Alerts

LootWishlist = LootWishlist or {}
LootWishlist.Alerts = LootWishlist.Alerts or {}

local Alerts = LootWishlist.Alerts
local LootParser = LootWishlist.LootParser
local db
local eventFrame
local alertFrame, alertFS, alertHideAt
local rollAlertFrame, rollAlertFS, rollHideAt

-- Debug helper
local function dprint(...)
  local ok = LootWishlist and LootWishlist.IsDebug and LootWishlist.IsDebug()
  if not ok then return end
  local msg = "[LootWishlist] "
  local parts = {}
  for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
  print(msg .. table.concat(parts, " "))
end
-- Track bag counts to detect when a tracked item later appears in your inventory
local bagCounts = {}
local bagGraceUntil = 0
local recentSelfAlertAt = {}
-- Current instance difficulty helper (module scope)
local function getCurrentInstanceDifficulty()
  if GetInstanceInfo then
    local _, _, difficultyID, difficultyName = GetInstanceInfo()
    -- Outside instances WoW can return 0/""; treat that as no difficulty context
    if type(difficultyID) == "number" and difficultyID > 0 then
      return difficultyID, difficultyName
    else
      return nil, nil
    end
  end
  return nil, nil
end

-- Get the number of a given itemID on the player (bags + equipped, excluding bank),
-- plus the link of the first copy found so alerts can inspect the actual item
local function getInventoryCount(itemID)
  if not itemID then return 0 end
  local total = 0
  local firstLink
  if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
    local maxBag = (NUM_BAG_SLOTS or 4)
    for bag = 0, maxBag do
      local slots = C_Container.GetContainerNumSlots(bag) or 0
      for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID == itemID then
          total = total + (info.stackCount or 1)
          firstLink = firstLink or info.hyperlink
        end
      end
    end
    local reagentBag = rawget(_G, "REAGENTBAG_CONTAINER") or 5
    if type(reagentBag) == "number" then
      local slots = C_Container.GetContainerNumSlots(reagentBag) or 0
      for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(reagentBag, slot)
        if info and info.itemID == itemID then
          total = total + (info.stackCount or 1)
          firstLink = firstLink or info.hyperlink
        end
      end
    end
    -- Count equipped items so gear set swaps don't trigger false alerts
    for equipSlot = 1, 19 do
      if GetInventoryItemID("player", equipSlot) == itemID then
        total = total + 1
        firstLink = firstLink or GetInventoryItemLink("player", equipSlot)
      end
    end
    return total, firstLink
  end
  -- Debug: legacy bag API path not available in this build; return 0
  dprint("getInventoryCount fallback 0 for", tostring(itemID))
  return 0
end
local rollAlertItems = {}
-- Show a popup when a group loot roll starts in a raid for a tracked item
local function ShowRaidRollAlert(itemLink)
  if not itemLink then return end
  if not rollAlertFrame then
    rollAlertFrame = CreateFrame("Frame", "LootWishlistRaidRollFrame", UIParent, "BackdropTemplate")
    rollAlertFrame:SetSize(420, 60)
    rollAlertFrame:SetPoint("TOP", UIParent, "TOP", 0, -280)
    rollAlertFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    rollAlertFrame:SetBackdrop(LuckyUI.Backdrop)
    rollAlertFrame:SetBackdropColor(LuckyUI.C.bgDark[1], LuckyUI.C.bgDark[2], LuckyUI.C.bgDark[3], 0.95)
    rollAlertFrame:SetBackdropBorderColor(LuckyUI.C.info[1], LuckyUI.C.info[2], LuckyUI.C.info[3], 0.9)
    rollAlertFrame:EnableMouse(true)
    rollAlertFrame:SetMovable(true)
    rollAlertFrame:RegisterForDrag("LeftButton")
    rollAlertFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    rollAlertFrame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      if db and self:GetPoint(1) then
        local p, rel, rp, x, y = self:GetPoint(1)
        db.raidRollWindow = {point=p, relative=rel and rel:GetName(), relativePoint=rp, x=x, y=y}
      end
    end)
    rollAlertFS = rollAlertFrame:CreateFontString(nil, "OVERLAY")
    rollAlertFS:SetFont(LuckyUI.BODY_FONT, 13)
    rollAlertFS:SetTextColor(LuckyUI.C.textLight[1], LuckyUI.C.textLight[2], LuckyUI.C.textLight[3])
    rollAlertFS:SetPoint("TOP", 0, -8)
    rollAlertFS:SetJustifyH("CENTER")
    rollAlertFS:SetJustifyV("MIDDLE")
    rollAlertFS:SetText("")
    local rollBtnDismiss = LuckyUI.CreateButton(rollAlertFrame, "Dismiss", 100, 22, "secondary")
    rollBtnDismiss:SetPoint("BOTTOM", rollAlertFrame, "BOTTOM", 0, 10)
    rollBtnDismiss:SetScript("OnClick", function()
      rollHideAt = nil
      rollAlertFrame:Hide()
      if wipe then wipe(rollAlertItems) end
    end)
    local w = db and db.raidRollWindow
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
  local desiredH = (rollAlertFS.GetStringHeight and (rollAlertFS:GetStringHeight() + 40)) or 80
  rollAlertFrame:SetHeight(math.max(60, math.min(200, desiredH)))
  rollAlertFrame:Show()
  -- Extend visibility timer with each new item
  rollHideAt = GetTime() + 8
end
local btnRemove, btnKeep, btnWhisper, btnParty, btnDismiss
local currentDifficultyID

local function ensureAlertFrame()
  if alertFrame then return alertFrame end
  local C = LootWishlist.Const or {}
  alertFrame = CreateFrame("Frame", "LootWishlistAlertFrame", UIParent, "BackdropTemplate")
  alertFrame:SetSize(C.ALERT_FRAME_INITIAL_WIDTH or 480, C.ALERT_FRAME_INITIAL_HEIGHT or 110)
  alertFrame:SetPoint("TOP", UIParent, "TOP", 0, C.ALERT_TOP_OFFSET or -160)
  alertFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  alertFrame:SetBackdrop(LuckyUI.Backdrop)
  alertFrame:SetBackdropColor(LuckyUI.C.bgDark[1], LuckyUI.C.bgDark[2], LuckyUI.C.bgDark[3], C.ALERT_BG_ALPHA or 0.92)
  do
    local b = C.ALERT_BORDER_COLOR_DEFAULT or {0.788, 0.659, 0.298, 0.8}
    alertFrame:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
  end
  alertFrame:EnableMouse(true)
  alertFrame:SetMovable(true)
  alertFrame:RegisterForDrag("LeftButton")
  alertFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  alertFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if db and self:GetPoint(1) then
      local p, rel, rp, x, y = self:GetPoint(1)
      db.alertWindow = {point=p, relative=rel and rel:GetName(), relativePoint=rp, x=x, y=y}
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
    if LootWishlist.UI and LootWishlist.UI.open then LootWishlist.UI.open() end
  end)

  alertFS = alertFrame:CreateFontString(nil, "OVERLAY")
  alertFS:SetFont(LuckyUI.BODY_FONT, 13)
  alertFS:SetTextColor(LuckyUI.C.textLight[1], LuckyUI.C.textLight[2], LuckyUI.C.textLight[3])
  alertFS:SetPoint("TOP", 0, -12)
  alertFS:SetJustifyH("CENTER")
  alertFS:SetJustifyV("MIDDLE")
  alertFS:SetText("")

  local function createAlertButton(text, variant)
    local b = LuckyUI.CreateButton(alertFrame, text, 110, 22, variant or "secondary")
    b:Hide()
    return b
  end

  btnRemove = createAlertButton("Remove", "danger")
  btnKeep = createAlertButton("Keep", "secondary")
  btnWhisper = createAlertButton("Whisper", "primary")
  btnParty = createAlertButton("Party", "secondary")
  btnDismiss = createAlertButton("Dismiss", "secondary")

  -- Position buttons (centered row near bottom)
  btnRemove:SetPoint("BOTTOM", alertFrame, "BOTTOM", -115, 12)
  btnKeep:SetPoint("BOTTOM", alertFrame, "BOTTOM", 115, 12)

  btnWhisper:SetPoint("BOTTOM", alertFrame, "BOTTOM", -150, 12)
  btnParty:SetPoint("BOTTOM", alertFrame, "BOTTOM", 0, 12)
  btnDismiss:SetPoint("BOTTOM", alertFrame, "BOTTOM", 150, 12)

  local w = db and db.alertWindow
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

local function ShowDropAlert(itemLink, note)
  local C = LootWishlist.Const or {}
  local f = ensureAlertFrame()
  local prefix = C.ALERT_TEXT_PREFIX_WISHLIST or "Wishlist item dropped:"
  local text = string.format("%s\n%s", prefix, itemLink or "[unknown]")
  if note then text = text .. "\n" .. note end
  alertFS:SetText(text)

  f:SetBackdropBorderColor(LuckyUI.C.success[1], LuckyUI.C.success[2], LuckyUI.C.success[3], 0.9)
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

-- Warbound detection --------------------------------------------------------
local function isWarboundItemLink(itemLink)
  if not itemLink then return false end
  local warboundKey = rawget(_G, "ITEM_WARBOUND_UNTIL_EQUIPPED")
  local function hasWarboundText(s)
    if type(s) ~= "string" then return false end
    if warboundKey and s:find(warboundKey, 1, true) then return true end
    return s:lower():find("warbound", 1, true) ~= nil
  end
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local ok, tip = pcall(C_TooltipInfo.GetHyperlink, itemLink)
    if ok and type(tip) == "table" and tip.lines then
      if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, tip) end
      for _, line in ipairs(tip.lines) do
        if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
        if hasWarboundText(line and line.leftText) or hasWarboundText(line and line.rightText) then
          return true
        end
      end
    end
  end
  return false
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
      -- Debug: count before
      local before = 0
      do
        local t = LootWishlist.GetTracked and LootWishlist.GetTracked() or nil
        if t then for _ in pairs(t) do before = before + 1 end end
      end
      dprint("Remove clicked for", tostring(itemID), "diffID=", tostring(currentDifficultyID or "nil"), "beforeCount=", tostring(before))
      if LootWishlist.RemoveTrackedItem then LootWishlist.RemoveTrackedItem(itemID, currentDifficultyID) else dprint("RemoveTrackedItem missing") end
      -- Debug: count after
      local after = 0
      do
        local t = LootWishlist.GetTracked and LootWishlist.GetTracked() or nil
        if t then for _ in pairs(t) do after = after + 1 end end
      end
      dprint("After removal count=", tostring(after))
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
  local st = LootWishlist.GetSettings and LootWishlist.GetSettings() or (LootWishlistDB and LootWishlistDB.settings) or {}
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

local function getLinkIlvl(link)
  if not link then return nil end
  local ilvl = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
  if type(ilvl) == "number" and ilvl > 0 then return ilvl end
  return nil
end

-- What a drop has to reach to clear an entry: the item level rank 1 of the
-- entry's track carries, not the level of whichever copy was recorded. The
-- vault and bonus rolls hand out ranks well up a track, so an entry recorded
-- from a Myth 9/6 copy at item level 344 must still accept the Myth 1/6 the
-- boss actually drops at 318. TRACKS carries rank 1 only for the tracks the
-- Loot Browser rebuilds, so the rest fall back to the recorded copy.
local function entryThresholdIlvl(entry)
  local trackKey = LootWishlist.UI and LootWishlist.UI.TrackKeyForEntry
    and LootWishlist.UI.TrackKeyForEntry(entry)
  if trackKey then
    for _, tr in ipairs((LootWishlist.Const and LootWishlist.Const.TRACKS) or {}) do
      if tr.key == trackKey and tr.trackIlvl then return tr.trackIlvl end
    end
  end
  return getLinkIlvl(entry.link)
end

-- Offer actions only when the dropped copy provably reaches an entry's own
-- track. Entry links carry their difficulty/track bonus IDs, so comparing
-- effective ilvls compares upgrade tracks without locale-dependent tooltip
-- parsing. Anything unknowable stays a highlight-only alert.
local function dropMeetsWishlistTrack(itemID, droppedLink, simulatedIlvl)
  local droppedIlvl = simulatedIlvl or getLinkIlvl(droppedLink)
  if not droppedIlvl then return false end
  local t = LootWishlist.GetTracked and LootWishlist.GetTracked()
  if not t then return false end
  for _, v in pairs(t) do
    if type(v) == "table" and v.id == itemID then
      local entryIlvl = entryThresholdIlvl(v)
      if entryIlvl and droppedIlvl >= entryIlvl then return true end
    end
  end
  return false
end

Alerts.DropMeetsWishlistTrack = dropMeetsWishlistTrack

-- An alert that highlights the item you want and then offers nothing reads as
-- broken, so say what happened when the reason is knowable: the drop is the
-- wishlisted item at a track below the one you track. The easiest entry to
-- satisfy names the track, since clearing that one clears the alert.
local function trackShortfallText(itemID, droppedLink, simulatedIlvl)
  local droppedIlvl = simulatedIlvl or getLinkIlvl(droppedLink)
  if not droppedIlvl then return nil end
  local t = LootWishlist.GetTracked and LootWishlist.GetTracked()
  if not t then return nil end
  local lowestThreshold, trackKey
  for _, v in pairs(t) do
    if type(v) == "table" and v.id == itemID then
      local threshold = entryThresholdIlvl(v)
      if threshold and (not lowestThreshold or threshold < lowestThreshold) then
        lowestThreshold = threshold
        trackKey = LootWishlist.UI and LootWishlist.UI.TrackKeyForEntry
          and LootWishlist.UI.TrackKeyForEntry(v)
      end
    end
  end
  if not lowestThreshold or droppedIlvl >= lowestThreshold then return nil end
  local C = LootWishlist.Const or {}
  if trackKey then
    return (C.ALERT_TEXT_LOWER_TRACK or "Same item, on a lower track than the %s copy on your wishlist."):format(trackKey)
  end
  return C.ALERT_TEXT_LOWER_TRACK_UNNAMED or "Same item, on a lower track than the copy on your wishlist."
end

Alerts.TrackShortfallText = trackShortfallText

-- A tracked entry's own link carries its difficulty's bonus IDs, so a test drop
-- built from it clears the track gate the way a real drop of that difficulty
-- does. A link built from a bare item ID resolves to base ilvl and never will.
-- The highest tracked copy wins, so one test satisfies every entry for the item.
local function trackedEntryLink(itemID)
  local t = LootWishlist.GetTracked and LootWishlist.GetTracked()
  if not t then return nil end
  local bestLink, bestIlvl
  for _, v in pairs(t) do
    if type(v) == "table" and v.id == itemID and v.link then
      local ilvl = getLinkIlvl(v.link) or 0
      if not bestIlvl or ilvl > bestIlvl then bestLink, bestIlvl = v.link, ilvl end
    end
  end
  return bestLink
end

Alerts.TrackedEntryLink = trackedEntryLink

-- A track name from the Loot Browser's picker, or a bare item level. TRACKS
-- carries a season item level only for the tracks the browser has to rebuild,
-- so Veteran and Champion are reached by passing a number.
local function resolveSimulatedIlvl(word)
  if not word then return nil end
  local n = tonumber(word)
  if n then return n end
  for _, tr in ipairs((LootWishlist.Const and LootWishlist.Const.TRACKS) or {}) do
    if tr.key:lower() == word:lower() then return tr.trackIlvl end
  end
  return nil
end

Alerts.ResolveSimulatedIlvl = resolveSimulatedIlvl

-- Take a trailing track argument off a test command, leaving the rest intact.
-- An item link ends in "|h|r" and a looter name resolves to nothing, so only a
-- real track word or item level is ever consumed.
local function stripTrackArg(input)
  local rest, last = tostring(input):match("^(.-)%s+(%S+)%s*$")
  if not rest then return input, nil end
  local ilvl = resolveSimulatedIlvl(last)
  if not ilvl then return input, nil end
  return rest, ilvl
end

Alerts.StripTrackArg = stripTrackArg

-- What the gate saw, so a test that offers no actions says why. An entry whose
-- link never resolved carries no item level of its own, and nothing can clear
-- a gate that has nothing to compare against.
local function printTrackGate(itemID, droppedLink, simulatedIlvl)
  local dropped = simulatedIlvl or getLinkIlvl(droppedLink)
  print(string.format("Loot Wishlist: simulated drop at item level %s%s",
    tostring(dropped or "unknown"), simulatedIlvl and " (simulated)" or ""))
  local t = LootWishlist.GetTracked and LootWishlist.GetTracked()
  for key, v in pairs(t or {}) do
    if type(v) == "table" and v.id == itemID then
      local threshold = entryThresholdIlvl(v)
      local recorded = getLinkIlvl(v.link)
      print(string.format("  entry %s (%s): %s", tostring(key),
        tostring(v.difficultyName or "no difficulty"),
        threshold and ("needs item level " .. threshold
          .. (recorded and recorded ~= threshold and (", recorded at " .. recorded) or ""))
          or "no item level, this entry has no link"))
    end
  end
  if not dropMeetsWishlistTrack(itemID, droppedLink, simulatedIlvl) then
    print("  no actions: the drop reaches no entry's track. Try /wishlist testdrop " .. tostring(itemID) .. " myth")
  end
end

-- The game's own loot toasts, the bigger one for your own drop. Chat and
-- encounter loot both fire for the same drop, so each item stays quiet for a
-- while after it sounds.
local SOUND_SILENCE_SECONDS = 10
local lastSoundAt = {}

local function dropSoundKit(isSelf, itemID)
  local st = LootWishlist.GetSettings and LootWishlist.GetSettings() or (LootWishlistDB and LootWishlistDB.settings) or {}
  if st.enableDropSound == false then return nil end
  if itemID then
    local last = lastSoundAt[itemID]
    if last and (GetTime() - last) < SOUND_SILENCE_SECONDS then return nil end
    lastSoundAt[itemID] = GetTime()
  end
  return isSelf and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or SOUNDKIT.UI_EPICLOOT_TOAST
end

Alerts.DropSoundKit = dropSoundKit

local function playDropSound(isSelf, itemID)
  local kit = dropSoundKit(isSelf, itemID)
  if kit then LuckySound:PlayKit(kit) end
end

local function ShowDropAlertWithContext(itemLink, isSelf, looterName, itemID, difficultyID, difficultyName, simulatedIlvl)
  dprint("ShowDropAlertWithContext:", "itemID=", tostring(itemID), "self=", tostring(isSelf), "looter=", tostring(looterName), "diff=", tostring(difficultyID), tostring(difficultyName))
  local meetsTrack = dropMeetsWishlistTrack(itemID, itemLink, simulatedIlvl)
  local note = not meetsTrack and trackShortfallText(itemID, itemLink, simulatedIlvl) or nil
  ShowDropAlert(itemLink, note)
  playDropSound(isSelf, itemID)
  if not meetsTrack then
    -- Not confirmed at any entry's track: highlight the drop, offer no actions
    dprint("drop not confirmed at wishlist track for", tostring(itemID), "- informational alert only")
    hideAllButtons()
    local base = (LootWishlist.Const and LootWishlist.Const.ALERT_FRAME_INITIAL_HEIGHT) or 110
    alertFrame:SetHeight(base + (note and 18 or 0))
    return
  end
  if isSelf then
    configureSelfActions(itemID, itemLink)
  else
    configureOtherActions(looterName, itemID, itemLink)
  end
  currentDifficultyID = difficultyID
  if isSelf and itemID then
    recentSelfAlertAt[itemID] = GetTime()
  end
end

local function isTracked(itemID)
  local t = LootWishlist.GetTracked and LootWishlist.GetTracked()
  return LootParser:IsTracked(t, itemID)
end

local function handleEvent(_, event, ...)
  if event == "CHAT_MSG_LOOT" then
    local msg = ...
    local inRaid = IsInRaid() or (IsInGroup() and IsInInstance() and select(2, IsInInstance()) == "raid")
    local parsed = LootParser:ParseMessage(msg)
    if not parsed then return end
    for _, item in ipairs(parsed.items) do
      local itemID, link = item.itemID, item.link
      if itemID and isTracked(itemID) then
        if isWarboundItemLink(link) then dprint("skip warbound drop", link); return end
        if not inRaid then
          local diffID, diffName = getCurrentInstanceDifficulty()
          if parsed.isSelf then
            ShowDropAlertWithContext(link, true, UnitName("player"), itemID, diffID, diffName)
          else
            ShowDropAlertWithContext(link, false, parsed.looter, itemID, diffID, diffName)
          end
        end
      end
    end
  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    -- encounterID, itemID, itemLink, quantity, playerName, ...
    local _encounterID, itemID, itemLink, _quantity, playerName = ...
    if itemID and isTracked(itemID) then
      local function withLink(l)
        if l and isWarboundItemLink(l) then return end
        local inRaid = IsInRaid() or (IsInGroup() and IsInInstance() and select(2, IsInInstance()) == "raid")
        if inRaid then
          -- In raids, skip the action/party-whisper alert and the simple raid drop banner.
          -- The roll reminder (START_LOOT_ROLL) will handle notifying the player.
          return
        end
        local you = UnitName("player")
        local isSelf = (playerName == nil) or (playerName == you) or (playerName == you.."-"..GetRealmName())
        local diffID, diffName = getCurrentInstanceDifficulty()
        ShowDropAlertWithContext(l, isSelf, playerName, itemID, diffID, diffName)
      end
      if itemLink then withLink(itemLink) else getItemLinkAsync(itemID, withLink) end
    end
  elseif event == "START_LOOT_ROLL" then
    -- rollID, rollTime
    local rollID = ...
  local st = LootWishlist.GetSettings and LootWishlist.GetSettings() or (LootWishlistDB and LootWishlistDB.settings) or {}
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
  if isWarboundItemLink(itemLink) then return end
    -- Only alert for wishlist-tracked items
    local itemID = LootParser:ParseItemID(itemLink)
    if not itemID then return end
    if not isTracked(itemID) then return end
    ShowRaidRollAlert(itemLink)
    playDropSound(false, itemID)
  elseif event == "PLAYER_ENTERING_WORLD" then
    bagGraceUntil = GetTime() + 5
  elseif event == "BAG_UPDATE_DELAYED" then
    dprint("event: BAG_UPDATE_DELAYED")
    -- Detect when a tracked item newly appears in your bags (e.g., trade),
    -- and prompt to remove it from the wishlist with a self-style alert.
    local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked() or nil
    if not tracked or not next(tracked) then dprint("no tracked items; skipping bag scan"); return end
    -- Bags populate in waves around every loading screen, so a single early
    -- baseline reads partial counts and the next wave looks like a gain,
    -- re-announcing items already in your bags. Every scan inside the grace
    -- window only (re)records baselines; the last wave wins.
    if GetTime() < bagGraceUntil then
      for _, info in pairs(tracked) do
        local iid = info and info.id
        if type(iid) == "number" then bagCounts[iid] = getInventoryCount(iid) end
      end
      dprint("bag baselines recorded (loading grace)")
      return
    end
    for _, info in pairs(tracked) do
      local iid = info and info.id or nil
      if type(iid) == "number" then
        local current, bagLink = getInventoryCount(iid)
        local prev = bagCounts[iid]
        dprint("scan item:", tostring(iid), "prev=", tostring(prev), "now=", tostring(current))
        if prev == nil then
          -- Establish baseline without alerting the first time we see it
          bagCounts[iid] = current
          dprint("baseline set for", tostring(iid), "=", tostring(current))
        else
          if (current or 0) > (prev or 0) then
            dprint("count increased for", tostring(iid), tostring(prev), "->", tostring(current))
            bagCounts[iid] = current
            -- Avoid duplicate prompt immediately after a self-loot alert
            local last = recentSelfAlertAt[iid] or 0
            if (GetTime() - last) > 8 then
              local function withLink(l)
                if l and isWarboundItemLink(l) then dprint("skip warbound bag gain for", tostring(iid)); return end
                local diffID, diffName = getCurrentInstanceDifficulty()
                dprint("triggering self remove alert for", tostring(iid), "diff=", tostring(diffID), tostring(diffName), "link=", tostring(l))
                ShowDropAlertWithContext(l or ("item:"..tostring(iid)), true, UnitName("player"), iid, diffID, diffName)
              end
              -- Prefer the actual bag copy's link so warbound and track checks
              -- see the item you received, not the wishlist entry's version.
              -- A "[]" name means the item isn't cached yet; use the entry's
              -- link rather than display an empty name.
              if bagLink and not bagLink:find("[]", 1, true) then
                withLink(bagLink)
              elseif info and info.link then
                withLink(info.link)
              else
                getItemLinkAsync(iid, withLink)
              end
            else
              dprint("suppressed due to recent self alert: item", tostring(iid), "age=", string.format("%.2f", GetTime() - last))
            end
          else
            -- Keep baseline up to date
            bagCounts[iid] = current
          end
        end
      end
    end
  end
end

-- Public API
function Alerts:Init(database)
  db = database
  if eventFrame then return end

  eventFrame = CreateFrame("Frame")
  eventFrame:RegisterEvent("CHAT_MSG_LOOT")
  eventFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
  eventFrame:RegisterEvent("START_LOOT_ROLL")
  eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  eventFrame:SetScript("OnEvent", handleEvent)
end

-- Replay the login bag sequence: arm the grace window, fake a partial first
-- wave by zeroing baselines, then scan inside and after the window. Items
-- already in your bags must stay silent; an alert means the guard regressed.
function Alerts.TestLogin()
  local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked() or nil
  if not tracked or not next(tracked) then
    print("Loot Wishlist: testlogin needs a tracked item, ideally one in your bags")
    return
  end
  handleEvent(nil, "PLAYER_ENTERING_WORLD")
  for _, info in pairs(tracked) do
    if info and type(info.id) == "number" then bagCounts[info.id] = 0 end
  end
  handleEvent(nil, "BAG_UPDATE_DELAYED")
  print("Loot Wishlist: login sim running, result in 6s...")
  C_Timer.After(6, function()
    handleEvent(nil, "BAG_UPDATE_DELAYED")
    print("Loot Wishlist: login sim done. No alert appeared = grace guard held.")
  end)
end

function Alerts.TestDrop(input, forceNot)
  local itemID, link, simIlvl
  if type(input) == "string" then input, simIlvl = stripTrackArg(input) end
  if type(input) == "number" then itemID = input end
  if not itemID and type(input) == "string" then
    local num = tonumber(input)
    if num then itemID = num end
    if not itemID then
      link = input
      itemID = LootParser:ParseItemID(link)
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
    ShowDropAlertWithContext(l, true, UnitName("player"), itemID, nil, nil, simIlvl)
    printTrackGate(itemID, l, simIlvl)
  end
  link = link or trackedEntryLink(itemID)
  if link then show(link) else getItemLinkAsync(itemID, show) end
end

function Alerts.TestDropOther(input)
  -- input can be: "<itemID|link> [looterName] [track|ilvl]"
  local simIlvl
  input, simIlvl = stripTrackArg(input)
  local itemArg, looterName = input:match("^%s*(.-)%s+([^%s].*)$")
  if not itemArg then itemArg = input end
  local itemID, link
  local num = tonumber(itemArg)
  if num then itemID = num else link = itemArg; itemID = LootParser:ParseItemID(link) end
  if not itemID then
    print("Loot Wishlist: testdrop-other requires an itemID or item link")
    return
  end
  if not isTracked(itemID) then return end
  local function show(l)
    ShowDropAlertWithContext(l, false, looterName or "Teammate", itemID, nil, nil, simIlvl)
    printTrackGate(itemID, l, simIlvl)
  end
  link = link or trackedEntryLink(itemID)
  if link then show(link) else getItemLinkAsync(itemID, show) end
end
