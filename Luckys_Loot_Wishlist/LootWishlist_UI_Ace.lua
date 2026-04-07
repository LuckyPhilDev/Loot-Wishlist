-- Loot Wishlist - UI (pure WoW API, no AceGUI)
-- Uses LuckyUI for consistent dark/gold styling.

LootWishlist = LootWishlist or {}
LootWishlist.Ace = LootWishlist.Ace or {}

------------------------------------------------------------------------
-- LuckyUI references
------------------------------------------------------------------------
local UI = LuckyUI
local C  = UI.C

------------------------------------------------------------------------
-- Layout constants
------------------------------------------------------------------------
local INSTANCE_ROW_H = 26
local BOSS_ROW_H     = 22
local ITEM_ROW_H     = 44
local SCROLLBAR_W    = 16
local DEFAULT_W      = 520
local DEFAULT_H      = 500
local MIN_W          = 380
local MIN_H          = 300

------------------------------------------------------------------------
-- Module-level state
------------------------------------------------------------------------
local mainFrame
local viewport
local scrollBar
local scrollOffset    = 0
local flatRows        = {}
local totalHeight     = 0
local rowPool         = {}
local statusCountLabel
local clearBtn, closeBtn2

-- Player spec IDs computed once per refresh
local renderPlayerSpecIDs   = {}
local renderPlayerSpecCount = 0

------------------------------------------------------------------------
-- Performance logging
------------------------------------------------------------------------
local perfRefreshCount = 0
local PerfLog = LuckyLog:New("|cffff8800[LWL-perf]|r", function() return LootWishlist.IsDebug and LootWishlist.IsDebug() end)

------------------------------------------------------------------------
-- diffTag
------------------------------------------------------------------------
local function diffTag(id, name)
  if name and name ~= "" then
    local n = name:lower()
    if n:find("raid finder") or n:find("lfr") then return "LFR" end
    if n:find("normal")             then return "N"   end
    if n:find("heroic")             then return "H"   end
    if n:find("mythic%+") or n:find("keystone") then return "+" end
    if n:find("mythic")             then return "M"   end
  end
  if id then
    local map = {
      [1]="N",[2]="H",[8]="+",[23]="M",[24]="TW",
      [14]="N",[15]="H",[16]="M",[17]="LFR",
    }
    return map[id]
  end
end

------------------------------------------------------------------------
-- Encounter order cache
------------------------------------------------------------------------
local encounterOrderCache = {}
local function getEncounterOrder(instanceID)
  if not instanceID then return nil end
  if encounterOrderCache[instanceID] then return encounterOrderCache[instanceID] end
  local EJ_GetEncounterInfoByIndex = _G["EJ_GetEncounterInfoByIndex"]
  if type(EJ_GetEncounterInfoByIndex) ~= "function" then return nil end
  local order
  local EJ_SelectInstance = _G["EJ_SelectInstance"]
  local prevInstance = (EncounterJournal and EncounterJournal.instanceID) or nil
  if type(EJ_SelectInstance) == "function" then
    pcall(EJ_SelectInstance, instanceID)
    order = { id = {}, name = {} }
    for idx = 1, 200 do
      local ename, _, encounterID = EJ_GetEncounterInfoByIndex(idx)
      if not ename then break end
      if encounterID then order.id[encounterID] = idx end
      order.name[ename:lower()] = idx
    end
    if prevInstance and prevInstance ~= instanceID then pcall(EJ_SelectInstance, prevInstance) end
  end
  if not order or not next(order.id) then
    order = { id = {}, name = {} }
    for idx = 1, 200 do
      local ename, _, encounterID = EJ_GetEncounterInfoByIndex(idx, instanceID)
      if not ename then break end
      if encounterID then order.id[encounterID] = idx end
      order.name[ename:lower()] = idx
    end
  end
  encounterOrderCache[instanceID] = order
  return order
end

------------------------------------------------------------------------
-- groupItemsByInstance
------------------------------------------------------------------------
local function groupItemsByInstance()
  local groups = {}
  for key, info in pairs(LootWishlist.GetTracked()) do
    local inst = info.dungeon or "Unknown"
    local g = groups[inst]
    if not g then
      g = { name = inst, isRaid = info.isRaid and true or false, items = {}, instanceID = info.instanceID }
      groups[inst] = g
    end
    if info.instanceID and not g.instanceID then g.instanceID = info.instanceID end
    if info.isRaid then g.isRaid = true end
    table.insert(g.items, { key = key, id = info.id or tonumber(key) or 0, info = info })
  end
  local ordered = {}
  for name, g in pairs(groups) do table.insert(ordered, { name = name, g = g }) end
  table.sort(ordered, function(a, b)
    if a.g.isRaid ~= b.g.isRaid then return a.g.isRaid end
    return a.name < b.name
  end)
  return ordered
end

------------------------------------------------------------------------
-- Difficulty sort order (shared between mergeItemsByID and display)
------------------------------------------------------------------------
local DIFF_ORDER = { LFR=1, N=2, H=3, ["+"]=4, M=5 }

------------------------------------------------------------------------
-- mergeItemsByID: collapse same-itemID entries into one row with a
-- sorted diffs array. Input is an ordered list of {key,id,info} items.
------------------------------------------------------------------------
local function mergeItemsByID(items)
  local merged = {}
  local byID   = {}
  for _, it in ipairs(items) do
    local id = it.id
    if not byID[id] then
      byID[id] = { id = id, info = it.info, diffs = {} }
      table.insert(merged, byID[id])
    end
    local tag = diffTag(it.info.difficultyID, it.info.difficultyName)
    table.insert(byID[id].diffs, { diffID = it.info.difficultyID, diffName = it.info.difficultyName, tag = tag })
  end
  for _, m in ipairs(merged) do
    table.sort(m.diffs, function(a, b)
      return (DIFF_ORDER[a.tag] or 99) < (DIFF_ORDER[b.tag] or 99)
    end)
  end
  return merged
end

------------------------------------------------------------------------
-- buildFlatRows
------------------------------------------------------------------------
local function buildFlatRows()
  local rows = {}
  local function uniqueItemCount(items)
    local seen = {}
    local n = 0
    for _, it in ipairs(items) do
      if not seen[it.id] then seen[it.id] = true; n = n + 1 end
    end
    return n
  end

  for _, entry in ipairs(groupItemsByInstance()) do
    local g = entry.g
    table.insert(rows, { type = "instance", name = entry.name, count = uniqueItemCount(g.items), isRaid = g.isRaid })

    if g.isRaid then
      local bossGroups = {}
      for _, it in ipairs(g.items) do
        local bname = (it.info.boss and it.info.boss ~= "") and it.info.boss or "Unknown Boss"
        local encID = it.info.encounterID or -1
        if not bossGroups[bname] then bossGroups[bname] = { encounterID = encID, items = {} } end
        if encID ~= -1 then bossGroups[bname].encounterID = encID end
        table.insert(bossGroups[bname].items, it)
      end
      local bossOrdered = {}
      for bname, data in pairs(bossGroups) do
        table.insert(bossOrdered, { name = bname, items = data.items, encounterID = data.encounterID or -1 })
      end
      local orderMap = getEncounterOrder(g.instanceID)
      table.sort(bossOrdered, function(a, b)
        local ao = orderMap and (orderMap.id[a.encounterID] or orderMap.name[a.name:lower()])
        local bo = orderMap and (orderMap.id[b.encounterID] or orderMap.name[b.name:lower()])
        if ao and bo and ao ~= bo then return ao < bo end
        if ao and not bo then return true end
        if bo and not ao then return false end
        if a.encounterID ~= -1 and b.encounterID ~= -1 and a.encounterID ~= b.encounterID then
          return a.encounterID < b.encounterID
        end
        return a.name < b.name
      end)
      for _, boss in ipairs(bossOrdered) do
        table.sort(boss.items, function(a, b)
          if a.id ~= b.id then return a.id < b.id end
          return ((a.info and a.info.difficultyID) or 0) < ((b.info and b.info.difficultyID) or 0)
        end)
        local merged = mergeItemsByID(boss.items)
        table.insert(rows, { type = "boss", name = boss.name, count = #merged })
        for _, m in ipairs(merged) do
          table.insert(rows, { type = "item", id = m.id, info = m.info, diffs = m.diffs, indent = true })
        end
      end
    else
      table.sort(g.items, function(a, b)
        local ab = a.info.boss or ""; local bb = b.info.boss or ""
        if ab ~= bb then return ab < bb end
        if a.id ~= b.id then return a.id < b.id end
        return ((a.info and a.info.difficultyID) or 0) < ((b.info and b.info.difficultyID) or 0)
      end)
      local merged = mergeItemsByID(g.items)
      for _, m in ipairs(merged) do
        table.insert(rows, { type = "item", id = m.id, info = m.info, diffs = m.diffs, indent = false })
      end
    end
  end
  return rows
end

local function getRowHeight(row)
  if row.type == "instance" then return INSTANCE_ROW_H end
  if row.type == "boss"     then return BOSS_ROW_H end
  return ITEM_ROW_H
end

------------------------------------------------------------------------
-- buildSpecText
------------------------------------------------------------------------
local function buildSpecText(info)
  local specs = info.specs
  if type(specs) ~= "table" then return nil end

  if renderPlayerSpecCount > 0 then
    local allCovered
    if not next(specs) then
      allCovered = true
    else
      local specSet = {}
      for _, sid in ipairs(specs) do specSet[sid] = true end
      allCovered = true
      for sid in pairs(renderPlayerSpecIDs) do
        if not specSet[sid] then allCovered = false; break end
      end
    end
    if allCovered then return "|cff8a7e6a{any spec}|r" end
  end

  if not next(specs) then return nil end

  if info._specNamesForSpecs ~= specs then
    local getNames = LootWishlist.GetSpecNames
    local names = (type(getNames) == "function" and getNames(specs)) or {}
    local text = (next(names) and table.concat(names, "/")) or nil
    if not text then
      local tmp = {}
      for _, sid in ipairs(specs) do table.insert(tmp, tostring(sid)) end
      text = table.concat(tmp, "/")
    end
    info._specNamesStr      = text
    info._specNamesForSpecs = specs
  end
  if info._specNamesStr and info._specNamesStr ~= "" then
    return string.format("|cff8a7e6a{%s}|r", info._specNamesStr)
  end
end

------------------------------------------------------------------------
-- createPoolFrame: one reusable row
------------------------------------------------------------------------
local function createPoolFrame(parent)
  local f = CreateFrame("Button", nil, parent)
  f:SetHeight(ITEM_ROW_H)

  -- Alternating row background
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0, 0, 0, 0)

  -- Bottom separator (dark brown)
  f.sep = f:CreateTexture(nil, "BACKGROUND")
  f.sep:SetHeight(1)
  f.sep:SetPoint("BOTTOMLEFT",  0, 0)
  f.sep:SetPoint("BOTTOMRIGHT", 0, 0)
  f.sep:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.6)

  -- Heading text (instances + bosses)
  f.headingLabel = f:CreateFontString(nil, "OVERLAY")
  f.headingLabel:SetFont(UI.TITLE_FONT, 13)
  f.headingLabel:SetPoint("LEFT",  10, 0)
  f.headingLabel:SetPoint("RIGHT", -10, 0)
  f.headingLabel:SetJustifyH("LEFT")
  f.headingLabel:Hide()

  -- Item icon
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(32, 32)
  f.icon:SetPoint("LEFT", 8, 0)
  f.icon:Hide()

  -- Quality colour bar beside icon
  f.qualityBar = f:CreateTexture(nil, "OVERLAY")
  f.qualityBar:SetSize(2, 32)
  f.qualityBar:SetPoint("LEFT", f.icon, "LEFT", -3, 0)
  f.qualityBar:Hide()

  -- Item name / link line
  f.itemLabel = f:CreateFontString(nil, "OVERLAY")
  f.itemLabel:SetFont(UI.BODY_FONT, 12)
  f.itemLabel:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  f.itemLabel:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 6, -2)
  f.itemLabel:SetPoint("RIGHT",   -30, 0)
  f.itemLabel:SetJustifyH("LEFT")
  f.itemLabel:SetWordWrap(false)
  f.itemLabel:Hide()

  -- Sub-label (boss / instance)
  f.subLabel = f:CreateFontString(nil, "OVERLAY")
  f.subLabel:SetFont(UI.BODY_FONT, 10)
  f.subLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  f.subLabel:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 6, 3)
  f.subLabel:SetPoint("RIGHT",      -30, 0)
  f.subLabel:SetJustifyH("LEFT")
  f.subLabel:SetWordWrap(false)
  f.subLabel:Hide()

  -- Remove button (matches Character Mount list style: 24×22 secondary)
  f.removeBtn = UI.CreateButton(f, "\195\151", 24, 22, "secondary")
  f.removeBtn:SetPoint("RIGHT", -4, 0)
  f.removeBtn.label:SetTextColor(C.danger[1], C.danger[2], C.danger[3], 0.6)
  f.removeBtn:SetScript("OnEnter", function(self)
    self.label:SetTextColor(C.danger[1], C.danger[2], C.danger[3], 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Remove from wishlist", 1, 1, 1)
    GameTooltip:Show()
  end)
  f.removeBtn:SetScript("OnLeave", function(self)
    self.label:SetTextColor(C.danger[1], C.danger[2], C.danger[3], 0.6)
    GameTooltip:Hide()
  end)
  f.removeBtn:Hide()

  -- Tooltip on hover
  f:SetScript("OnEnter", function(self)
    if self.itemLink then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self.itemLink)
      GameTooltip:Show()
    end
    if self.rowType == "item" then
      self.bg:SetColorTexture(C.highlight[1], C.highlight[2], C.highlight[3], C.highlight[4])
    end
  end)
  f:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    if self._bgR then
      self.bg:SetColorTexture(self._bgR, self._bgG, self._bgB, self._bgA)
    else
      self.bg:SetColorTexture(0, 0, 0, 0)
    end
  end)

  return f
end

------------------------------------------------------------------------
-- populatePoolFrame
------------------------------------------------------------------------
local function populatePoolFrame(f, row, rowIndex)
  f.headingLabel:Hide()
  f.icon:Hide()
  f.qualityBar:Hide()
  f.itemLabel:Hide()
  f.subLabel:Hide()
  f.removeBtn:Hide()
  f.removeBtn:SetScript("OnClick", nil)
  f.itemLink = nil
  f.rowType  = row.type
  f._bgR, f._bgG, f._bgB, f._bgA = nil, nil, nil, nil
  f.bg:SetColorTexture(0, 0, 0, 0)

  if row.type == "instance" then
    f:SetHeight(INSTANCE_ROW_H)
    local raidTag = row.isRaid and ("  |cffff8000[Raid]|r") or ""
    f.headingLabel:SetFont(UI.TITLE_FONT, 13, "OUTLINE")
    f.headingLabel:SetText(string.format("|cffffd100%s|r  (%d)%s", row.name, row.count, raidTag))
    f.headingLabel:Show()
    -- Dark warm background for instance headers
    f.bg:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.6)
    f._bgR, f._bgG, f._bgB, f._bgA = C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.6
    -- Gold separator
    f.sep:SetColorTexture(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 0.4)

  elseif row.type == "boss" then
    f:SetHeight(BOSS_ROW_H)
    f.headingLabel:SetFont(UI.TITLE_FONT, 11, "")
    f.headingLabel:SetText(string.format("   |cffc9a84c%s|r  (%d)", row.name, row.count))
    f.headingLabel:Show()
    f.bg:SetColorTexture(C.bgPanel[1], C.bgPanel[2], C.bgPanel[3], 0.5)
    f._bgR, f._bgG, f._bgB, f._bgA = C.bgPanel[1], C.bgPanel[2], C.bgPanel[3], 0.5
    f.sep:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.4)

  else -- "item"
    f:SetHeight(ITEM_ROW_H)
    -- Subtle alternating row tint using bgDark/bgPanel
    local isEven = (rowIndex % 2 == 0)
    local r, g, b, a
    if isEven then
      r, g, b, a = C.bgPanel[1], C.bgPanel[2], C.bgPanel[3], 0.3
    else
      r, g, b, a = C.bgDark[1], C.bgDark[2], C.bgDark[3], 0.2
    end
    f.bg:SetColorTexture(r, g, b, a)
    f._bgR, f._bgG, f._bgB, f._bgA = r, g, b, a
    f.sep:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.3)

    local info   = row.info
    local itemID = row.id

    f.icon:ClearAllPoints()
    f.icon:SetPoint("LEFT", f, "LEFT", row.indent and 24 or 8, 0)

    -- Icon texture
    local iconTex = info.icon
    if not iconTex and C_Item and C_Item.GetItemIconByID then
      iconTex = C_Item.GetItemIconByID(itemID)
    end
    if iconTex then
      f.icon:SetTexture(iconTex)
    else
      f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      local ItemAPI = _G["Item"]
      if type(ItemAPI) == "table" and ItemAPI.CreateFromItemID then
        local obj = ItemAPI:CreateFromItemID(itemID)
        if obj and obj.ContinueOnItemLoad then
          obj:ContinueOnItemLoad(function()
            local ilink = obj.GetItemLink and obj:GetItemLink()
            if ilink then info.link = ilink end
            local ic = obj.GetItemIcon and obj:GetItemIcon()
            if ic then info.icon = ic end
            local q = obj.GetItemQuality and obj:GetItemQuality()
            if q then info.quality = q end
            if LootWishlist.Ace.deferredRefresh then LootWishlist.Ace.deferredRefresh() end
          end)
        end
      elseif C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
      end
    end
    f.icon:Show()

    -- Quality bar
    local quality = info.quality
    if not quality and C_Item and C_Item.GetItemQualityByID then
      quality = C_Item.GetItemQualityByID(itemID)
      if quality then info.quality = quality end
    end
    if quality then
      local qr, qg, qb = GetItemQualityColor(quality)
      if qr then
        f.qualityBar:SetColorTexture(qr, qg, qb, 1)
        f.qualityBar:Show()
      end
    end

    -- Item label
    local link = info.link or ("item:" .. tostring(itemID))
    local parts = { link }
    if row.diffs and #row.diffs > 0 then
      local tags = {}
      for _, d in ipairs(row.diffs) do
        if d.tag then table.insert(tags, d.tag) end
      end
      if #tags > 0 then
        table.insert(parts, string.format("|cff8a7e6a[%s]|r", table.concat(tags, "\194\183")))
      end
    end
    local specText = buildSpecText(info)
    if specText then table.insert(parts, specText) end
    f.itemLabel:SetText(table.concat(parts, "  "))
    f.itemLabel:Show()
    f.itemLink = link

    -- Sub-label
    local meta = {}
    if info.boss and info.boss ~= "" then table.insert(meta, "|cff8a7e6a" .. info.boss .. "|r") end
    if info.dungeon and info.dungeon ~= "" and info.dungeon ~= info.boss then
      table.insert(meta, "|cff8a7e6a" .. info.dungeon .. "|r")
    end
    if #meta > 0 then
      f.subLabel:SetText(table.concat(meta, " \194\183 "))
      f.subLabel:Show()
    end

    -- Remove button — removes all difficulties for this item in one call
    local itemIDForRemove = row.id
    f.removeBtn:SetScript("OnClick", function() LootWishlist.RemoveTrackedItem(itemIDForRemove) end)
    f.removeBtn:Show()
  end
end

------------------------------------------------------------------------
-- renderVisibleRows: virtual scroll
------------------------------------------------------------------------
local function renderVisibleRows()
  if not viewport then return end
  local viewH = viewport:GetHeight()
  if viewH <= 0 then return end

  local poolIdx   = 1
  local y         = 0
  local itemIndex = 0
  for _, row in ipairs(flatRows) do
    local h = getRowHeight(row)
    if row.type == "item" then itemIndex = itemIndex + 1 end
    if y + h > scrollOffset and y < scrollOffset + viewH then
      if not rowPool[poolIdx] then
        rowPool[poolIdx] = createPoolFrame(viewport)
      end
      local pf = rowPool[poolIdx]
      pf:ClearAllPoints()
      pf:SetPoint("TOPLEFT",  viewport, "TOPLEFT",  0, -(y - scrollOffset))
      pf:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, -(y - scrollOffset))
      pf:SetHeight(h)
      populatePoolFrame(pf, row, itemIndex)
      pf:Show()
      poolIdx = poolIdx + 1
    end
    y = y + h
    if y >= scrollOffset + viewH then break end
  end
  for i = poolIdx, #rowPool do rowPool[i]:Hide() end
end

------------------------------------------------------------------------
-- updateScrollRange
------------------------------------------------------------------------
local function updateScrollRange()
  if not viewport or not scrollBar then return end
  local viewH     = viewport:GetHeight()
  local maxScroll = math.max(0, totalHeight - viewH)
  scrollBar:SetMinMaxValues(0, maxScroll)
  scrollOffset = math.min(scrollOffset, maxScroll)
  scrollBar:SetValue(scrollOffset)
end

------------------------------------------------------------------------
-- refresh
------------------------------------------------------------------------
local function refresh()
  if not viewport then return end

  perfRefreshCount = perfRefreshCount + 1
  local refreshID = perfRefreshCount
  local t0 = debugprofilestop()

  renderPlayerSpecIDs   = {}
  renderPlayerSpecCount = 0
  local numSpecs = _G.GetNumSpecializations and _G.GetNumSpecializations() or 0
  if type(numSpecs) == "number" and numSpecs > 0 then
    for i = 1, numSpecs do
      local ok, specID = pcall(_G.GetSpecializationInfo, i)
      if ok and type(specID) == "number" then
        renderPlayerSpecIDs[specID] = true
        renderPlayerSpecCount = renderPlayerSpecCount + 1
      end
    end
  end

  flatRows    = buildFlatRows()
  totalHeight = 0
  for _, row in ipairs(flatRows) do totalHeight = totalHeight + getRowHeight(row) end

  updateScrollRange()

  local count = 0
  if LootWishlist.GetTracked then
    for _ in pairs(LootWishlist.GetTracked()) do count = count + 1 end
  end
  if statusCountLabel then
    if count == 0 then
      statusCountLabel:SetText("|cff8a7e6aNo items in wishlist|r")
    elseif count == 1 then
      statusCountLabel:SetText("|cffe8dcc81 item|r in wishlist")
    else
      statusCountLabel:SetText(string.format("|cffe8dcc8%d items|r in wishlist", count))
    end
  end
  if clearBtn then
    if count > 0 then clearBtn:Enable() else clearBtn:Disable() end
  end

  renderVisibleRows()

  local tEnd = debugprofilestop()
  PerfLog(string.format(
    "refresh #%d | %d items | %d flatRows | %d poolFrames | total=%.1fms",
    refreshID, count, #flatRows, #rowPool, tEnd - t0
  ))
end

------------------------------------------------------------------------
-- createMainFrame
------------------------------------------------------------------------
local function createMainFrame()
  local f = CreateFrame("Frame", "LootWishlistMainFrame", UIParent, "BackdropTemplate")
  f:SetSize(DEFAULT_W, DEFAULT_H)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W, MIN_H)
  end
  f:SetClampedToScreen(true)
  f:SetFrameStrata("MEDIUM")
  f:SetFrameLevel(10)
  f:EnableMouse(true)

  -- LuckyUI solid backdrop with gold border
  f:SetBackdrop(UI.Backdrop)
  f:SetBackdropColor(C.bgDark[1], C.bgDark[2], C.bgDark[3], C.bgDark[4])
  f:SetBackdropBorderColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3])

  -- Header (using LuckyUI.CreateHeader)
  local header = UI.CreateHeader(f, "Loot Wishlist")
  -- Override close to track isOpen state
  local closeBtn = header:GetChildren()
  -- Find the close button (last child of header)
  for _, child in ipairs({ header:GetChildren() }) do
    if child:GetObjectType() == "Button" then
      child:SetScript("OnClick", function() f:Hide(); LootWishlist.Ace.isOpen = false end)
    end
  end

  -- Drag the header to move
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() f:StartMoving() end)
  header:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local pos = LootWishlistCharDB.windowPos or {}
    pos.point, _, pos.relPoint, pos.x, pos.y = f:GetPoint(1)
    pos.w, pos.h = f:GetSize()
    LootWishlistCharDB.windowPos = pos
  end)

  -- Resize grip (bottom-right)
  local resizer = CreateFrame("Button", nil, f)
  resizer:SetSize(16, 16)
  resizer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  resizer:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  resizer:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    local pos = LootWishlistCharDB.windowPos or {}
    pos.point, _, pos.relPoint, pos.x, pos.y = f:GetPoint(1)
    pos.w, pos.h = f:GetSize()
    LootWishlistCharDB.windowPos = pos
    updateScrollRange()
    renderVisibleRows()
  end)

  -- Scroll viewport
  viewport = CreateFrame("Frame", nil, f)
  viewport:SetPoint("TOPLEFT",     f, "TOPLEFT",     2,  -34)
  viewport:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(2 + SCROLLBAR_W + 2), 36)
  viewport:SetClipsChildren(true)

  -- Scrollbar
  scrollBar = CreateFrame("Slider", "LootWishlistScrollBar", f, "UIPanelScrollBarTemplate")
  scrollBar:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -4,  -50)
  scrollBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4,   52)
  scrollBar:SetWidth(SCROLLBAR_W)
  scrollBar:SetMinMaxValues(0, 0)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(ITEM_ROW_H)
  scrollBar:SetScript("OnValueChanged", function(_, value)
    scrollOffset = value
    renderVisibleRows()
  end)

  -- Mouse wheel
  viewport:EnableMouseWheel(true)
  viewport:SetScript("OnMouseWheel", function(_, delta)
    local _, maxVal = scrollBar:GetMinMaxValues()
    local step = ITEM_ROW_H * 3
    local new = math.max(0, math.min(scrollOffset - delta * step, maxVal))
    scrollBar:SetValue(new)
  end)

  viewport:SetScript("OnSizeChanged", function()
    updateScrollRange()
    renderVisibleRows()
  end)

  -- Status bar
  local statusBar = CreateFrame("Frame", nil, f)
  statusBar:SetHeight(28)
  statusBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  2,  4)
  statusBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 4)

  -- Gold divider above status bar
  local statusLine = statusBar:CreateTexture(nil, "ARTWORK")
  statusLine:SetHeight(1)
  statusLine:SetPoint("TOPLEFT")
  statusLine:SetPoint("TOPRIGHT")
  statusLine:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3])

  -- Clear All button (danger variant)
  clearBtn = UI.CreateButton(statusBar, "Clear All", 100, 22, "danger")
  clearBtn:SetPoint("LEFT", statusBar, "LEFT", 4, -2)
  clearBtn:SetScript("OnClick", function()
    StaticPopupDialogs["LOOTWISHLIST_CLEAR_ALL"] = {
      text = "This will remove ALL wishlist items for this character. Are you sure?",
      button1 = "Yes", button2 = "No",
      OnAccept = function()
        if LootWishlist.ClearAllTracked then LootWishlist.ClearAllTracked() end
      end,
      timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("LOOTWISHLIST_CLEAR_ALL")
  end)

  -- Close button (secondary)
  closeBtn2 = UI.CreateButton(statusBar, "Close", 80, 22, "secondary")
  closeBtn2:SetPoint("RIGHT", statusBar, "RIGHT", -4, -2)
  closeBtn2:SetScript("OnClick", function() f:Hide(); LootWishlist.Ace.isOpen = false end)

  -- Item count label
  statusCountLabel = statusBar:CreateFontString(nil, "OVERLAY")
  statusCountLabel:SetFont(UI.BODY_FONT, 11)
  statusCountLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  statusCountLabel:SetPoint("CENTER", statusBar, "CENTER")

  -- Restore saved position
  local pos = LootWishlistCharDB.windowPos
  if pos and pos.point then
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    if pos.w and pos.h then f:SetSize(pos.w, pos.h) end
  end

  -- ESC to close
  table.insert(UISpecialFrames, "LootWishlistMainFrame")

  return f
end

------------------------------------------------------------------------
-- open / hide
------------------------------------------------------------------------
local function open()
  if not mainFrame then
    mainFrame = createMainFrame()
  end
  mainFrame:Show()
  mainFrame:Raise()
  LootWishlist.Ace.isOpen = true
  refresh()
end

local function hide()
  if mainFrame then mainFrame:Hide(); LootWishlist.Ace.isOpen = false end
end

------------------------------------------------------------------------
-- Debounced / deferred refresh
------------------------------------------------------------------------
local refreshPending = false
local DEFERRED_DELAY = 0.5

local function scheduleRefresh()
  if not viewport then return end
  if refreshPending then return end
  refreshPending = true
  C_Timer.After(0, function()
    refreshPending = false
    refresh()
  end)
end

local function deferredRefresh()
  if not viewport then return end
  if refreshPending then return end
  refreshPending = true
  C_Timer.After(DEFERRED_DELAY, function()
    refreshPending = false
    refresh()
  end)
end

LootWishlist.Ace.refresh         = scheduleRefresh
LootWishlist.Ace.deferredRefresh = deferredRefresh
LootWishlist.Ace.open            = open
LootWishlist.Ace.hide            = hide
