-- Loot Wishlist - UI (pure WoW API, no AceGUI)

LootWishlist = LootWishlist or {}
LootWishlist.Ace = LootWishlist.Ace or {}

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
local mainFrame          -- the movable/resizable window
local viewport           -- clipped content area
local scrollBar          -- slider
local scrollOffset    = 0
local flatRows        = {}
local totalHeight     = 0
local rowPool         = {}
local statusCountLabel
local clearBtn

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
-- buildFlatRows
------------------------------------------------------------------------
local function buildFlatRows()
  local rows = {}
  for _, entry in ipairs(groupItemsByInstance()) do
    local g = entry.g
    table.insert(rows, { type = "instance", name = entry.name, count = #g.items, isRaid = g.isRaid })

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
        table.insert(rows, { type = "boss", name = boss.name, count = #boss.items })
        table.sort(boss.items, function(a, b)
          if a.id ~= b.id then return a.id < b.id end
          return ((a.info and a.info.difficultyID) or 0) < ((b.info and b.info.difficultyID) or 0)
        end)
        for _, it in ipairs(boss.items) do
          table.insert(rows, { type = "item", key = it.key, id = it.id, info = it.info, indent = true })
        end
      end
    else
      table.sort(g.items, function(a, b)
        local ab = a.info.boss or ""; local bb = b.info.boss or ""
        if ab ~= bb then return ab < bb end
        if a.id ~= b.id then return a.id < b.id end
        return ((a.info and a.info.difficultyID) or 0) < ((b.info and b.info.difficultyID) or 0)
      end)
      for _, it in ipairs(g.items) do
        table.insert(rows, { type = "item", key = it.key, id = it.id, info = it.info, indent = false })
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
    if allCovered then return "|cffa0a0a0{any spec}|r" end
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
    return string.format("|cffa0a0a0{%s}|r", info._specNamesStr)
  end
end

------------------------------------------------------------------------
-- createPoolFrame: one reusable row (raw Button, no libraries)
------------------------------------------------------------------------
local function createPoolFrame(parent)
  local f = CreateFrame("Button", nil, parent)
  f:SetHeight(ITEM_ROW_H)

  -- Alternating row background
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0, 0, 0, 0)

  -- Bottom separator
  f.sep = f:CreateTexture(nil, "BACKGROUND")
  f.sep:SetHeight(1)
  f.sep:SetPoint("BOTTOMLEFT",  0, 0)
  f.sep:SetPoint("BOTTOMRIGHT", 0, 0)
  f.sep:SetColorTexture(1, 1, 1, 0.06)

  -- Heading text (instances + bosses)
  f.headingLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
  f.itemLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.itemLabel:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 6, -2)
  f.itemLabel:SetPoint("RIGHT",   -30, 0)
  f.itemLabel:SetJustifyH("LEFT")
  f.itemLabel:SetWordWrap(false)
  f.itemLabel:Hide()

  -- Sub-label (boss • instance)
  f.subLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.subLabel:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 6, 3)
  f.subLabel:SetPoint("RIGHT",      -30, 0)
  f.subLabel:SetJustifyH("LEFT")
  f.subLabel:SetWordWrap(false)
  f.subLabel:Hide()

  -- Remove button
  f.removeBtn = CreateFrame("Button", nil, f)
  f.removeBtn:SetSize(20, 20)
  f.removeBtn:SetPoint("RIGHT", -4, 0)
  f.removeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  f.removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
  f.removeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
  f.removeBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Remove from wishlist", 1, 1, 1)
    GameTooltip:Show()
  end)
  f.removeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.removeBtn:Hide()

  -- Tooltip on hover
  f:SetScript("OnEnter", function(self)
    if self.itemLink then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self.itemLink)
      GameTooltip:Show()
    end
    if self.rowType == "item" then
      self.bg:SetColorTexture(0.15, 0.13, 0.08, 0.6)
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
    local raidTag = row.isRaid and "  |cffff7f00[Raid]|r" or ""
    f.headingLabel:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    f.headingLabel:SetText(string.format("|cffffd200%s|r  (%d)%s", row.name, row.count, raidTag))
    f.headingLabel:Show()
    f.bg:SetColorTexture(0.10, 0.07, 0.02, 0.9)
    f._bgR, f._bgG, f._bgB, f._bgA = 0.10, 0.07, 0.02, 0.9
    f.sep:SetColorTexture(0.79, 0.66, 0.30, 0.4)

  elseif row.type == "boss" then
    f:SetHeight(BOSS_ROW_H)
    f.headingLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    f.headingLabel:SetText(string.format("   |cffffbf00%s|r  (%d)", row.name, row.count))
    f.headingLabel:Show()
    f.bg:SetColorTexture(0.06, 0.04, 0.01, 0.7)
    f._bgR, f._bgG, f._bgB, f._bgA = 0.06, 0.04, 0.01, 0.7
    f.sep:SetColorTexture(1, 1, 1, 0.06)

  else -- "item"
    f:SetHeight(ITEM_ROW_H)
    -- Subtle alternating row tint
    local alt = (rowIndex % 2 == 0) and 0.04 or 0.02
    f.bg:SetColorTexture(alt, alt * 0.8, alt * 0.4, 0.5)
    f._bgR, f._bgG, f._bgB, f._bgA = alt, alt * 0.8, alt * 0.4, 0.5
    f.sep:SetColorTexture(1, 1, 1, 0.06)

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
      -- Request async load
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
      local r, g, b = GetItemQualityColor(quality)
      if r then
        f.qualityBar:SetColorTexture(r, g, b, 1)
        f.qualityBar:Show()
      end
    end

    -- Item label
    local link = info.link or ("item:" .. tostring(itemID))
    local tag  = diffTag(info.difficultyID, info.difficultyName)
    local parts = { link }
    if tag then table.insert(parts, string.format("|cffa0a0a0[%s]|r", tag)) end
    local specText = buildSpecText(info)
    if specText then table.insert(parts, specText) end
    f.itemLabel:SetText(table.concat(parts, "  "))
    f.itemLabel:Show()
    f.itemLink = link

    -- Sub-label
    local meta = {}
    if info.boss and info.boss ~= "" then table.insert(meta, "|cff888888" .. info.boss .. "|r") end
    if info.dungeon and info.dungeon ~= "" and info.dungeon ~= info.boss then
      table.insert(meta, "|cff666666" .. info.dungeon .. "|r")
    end
    if #meta > 0 then
      f.subLabel:SetText(table.concat(meta, " • "))
      f.subLabel:Show()
    end

    -- Remove button
    local rowKey = row.key
    f.removeBtn:SetScript("OnClick", function() LootWishlist.RemoveTrackedItem(rowKey) end)
    f.removeBtn:Show()
  end
end

------------------------------------------------------------------------
-- renderVisibleRows: virtual scroll — only creates frames for visible rows
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
  -- Hide unused pool frames
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

  -- Compute player spec IDs once
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

  -- Rebuild flat row list
  flatRows    = buildFlatRows()
  totalHeight = 0
  for _, row in ipairs(flatRows) do totalHeight = totalHeight + getRowHeight(row) end

  updateScrollRange()

  -- Status bar
  local count = 0
  if LootWishlist.GetTracked then
    for _ in pairs(LootWishlist.GetTracked()) do count = count + 1 end
  end
  if statusCountLabel then
    if count == 0 then
      statusCountLabel:SetText("|cff888888No items in wishlist|r")
    elseif count == 1 then
      statusCountLabel:SetText("|cffffffff1 item|r in wishlist")
    else
      statusCountLabel:SetText(string.format("|cffffffff%d items|r in wishlist", count))
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
-- createMainFrame: builds the movable/resizable window once
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
  f:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true,
    tileSize = 16,
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0.1, 0.07, 0.04, 0.95)
  f:SetBackdropBorderColor(0.79, 0.66, 0.30, 0.8)

  -- Title bar (drag region)
  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetHeight(28)
  titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  6, -4)
  titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -4)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
  titleBar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    -- Save position
    local pos = LootWishlistCharDB.windowPos or {}
    pos.point, _, pos.relPoint, pos.x, pos.y = f:GetPoint(1)
    pos.w, pos.h = f:GetSize()
    LootWishlistCharDB.windowPos = pos
  end)

  local titleText = titleBar:CreateFontString(nil, "OVERLAY")
  titleText:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
  titleText:SetPoint("CENTER", titleBar, "CENTER")
  titleText:SetTextColor(1, 0.82, 0)
  titleText:SetText("Loot Wishlist")

  -- Close button
  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  closeBtn:SetScript("OnClick", function() f:Hide(); LootWishlist.Ace.isOpen = false end)

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
  viewport:SetPoint("TOPLEFT",     f, "TOPLEFT",     8,  -34)
  viewport:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(8 + SCROLLBAR_W + 2), 40)
  viewport:SetClipsChildren(true)

  -- Scrollbar
  scrollBar = CreateFrame("Slider", "LootWishlistScrollBar", f, "UIPanelScrollBarTemplate")
  scrollBar:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -8,  -50)
  scrollBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8,   56)
  scrollBar:SetWidth(SCROLLBAR_W)
  scrollBar:SetMinMaxValues(0, 0)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(ITEM_ROW_H)
  scrollBar:SetScript("OnValueChanged", function(_, value)
    scrollOffset = value
    renderVisibleRows()
  end)

  -- Mouse wheel on viewport
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
  statusBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  8,  8)
  statusBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)

  clearBtn = CreateFrame("Button", nil, statusBar, "UIPanelButtonTemplate")
  clearBtn:SetText("Clear All")
  clearBtn:SetSize(100, 22)
  clearBtn:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
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

  -- Close button (status bar)
  local closeBtn2 = CreateFrame("Button", nil, statusBar, "UIPanelButtonTemplate")
  closeBtn2:SetText("Close")
  closeBtn2:SetSize(80, 22)
  closeBtn2:SetPoint("RIGHT", statusBar, "RIGHT", -2, 0)
  closeBtn2:SetScript("OnClick", function() f:Hide(); LootWishlist.Ace.isOpen = false end)

  statusCountLabel = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  statusCountLabel:SetPoint("CENTER", statusBar, "CENTER")
  statusCountLabel:SetTextColor(0.8, 0.8, 0.8, 1)

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
