-- Loot Wishlist - UI (pure WoW API, no AceGUI)
-- Uses LuckyUI for consistent dark/gold styling.

LootWishlist = LootWishlist or {}
LootWishlist.UI = LootWishlist.UI or {}

------------------------------------------------------------------------
-- LuckyUI references
------------------------------------------------------------------------
local UI = LuckyUI
local S = LootWishlist.Strings.wishlist
local C  = UI.C

------------------------------------------------------------------------
-- Layout constants
------------------------------------------------------------------------
local INSTANCE_ROW_H = 26
local BOSS_ROW_H     = 22
local ITEM_ROW_H     = 44
local SCROLLBAR_W    = 16
local ICON_SIZE      = 18
local ICON_GAP       = 6
-- The gaps between the row's icons are dead space, and crossing one hands the
-- mouse back to the row itself, which flashes the item tooltip. Each button's
-- hit region grows by half a gap to meet its neighbours and by the rest of the
-- row height, so the whole action strip belongs to the icons.
local ICON_HIT_X     = ICON_GAP / 2
local ICON_HIT_Y     = (ITEM_ROW_H - ICON_SIZE) / 2
-- Borderless row actions, the icon button format Lucky's Wardrobe uses. These
-- name the shared set in Luckys_Utils, which the button resolves and tints.
local ICONS = {
  obtained  = "check",
  bonusRoll = "dice",
  remove    = "x",
}
local TOOLBAR_H      = 32
local DEFAULT_W      = 520
local DEFAULT_H      = 500
local MIN_W          = 440
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
local clearBtn
local searchBox
local filterBtn
local filter = { search = "", slot = nil }

-- Player spec IDs computed once per refresh
local renderPlayerSpecIDs   = {}
local renderPlayerSpecCount = 0

------------------------------------------------------------------------
-- Performance logging
------------------------------------------------------------------------
local perfRefreshCount = 0
local PerfLog = LuckyLog:New("|cffff8800[LWL-perf]|r", function() return LootWishlist.IsDebug and LootWishlist.IsDebug() end)

------------------------------------------------------------------------
-- trackKeyForEntry: which gear track a wishlist entry is stored at.
-- Raids carry one difficulty per track. Dungeon Veteran and Champion own
-- a difficulty each; Hero and Myth share the keystone difficulty and are
-- told apart by the track bonus in the entry's link, or by its item
-- level for entries recorded without one.
------------------------------------------------------------------------
local function trackKeyForEntry(info)
  local diffID = info and info.difficultyID
  if not diffID then return nil end
  local link = info.link
  local tracks = LootWishlist.Const.TRACKS
  for _, t in ipairs(tracks) do
    if info.isRaid then
      if t.raidDiff == diffID then return t.key end
    elseif t.dungeonTrackDiff == diffID then
      if not t.trackBonus then return t.key end
      if link and link:find(":" .. t.trackBonus .. "%f[%D]") then return t.key end
    end
  end
  if info.isRaid or not link then return nil end
  local ilvl = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
  if type(ilvl) ~= "number" then return nil end
  for i = #tracks, 1, -1 do
    local t = tracks[i]
    if t.dungeonTrackDiff == diffID and t.trackIlvl and ilvl >= t.trackIlvl then return t.key end
  end
  return nil
end

------------------------------------------------------------------------
-- Filters: a search over name, boss, instance and slot, and one slot
------------------------------------------------------------------------
local function slotOf(entry)
  local equipLoc = C_Item and C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(entry.id))
  return (equipLoc and equipLoc ~= "" and _G[equipLoc]) or S.otherSlot
end

local function itemName(entry)
  local cached = LuckyItem and LuckyItem:GetCached(entry.id)
  if cached and cached.name then return cached.name end
  return (entry.info.link or ""):match("%[(.-)%]") or ""
end

local function filtersActive()
  return filter.search ~= "" or filter.slot ~= nil
end

local function paintFilterIcon()
  local c = filter.slot and C.goldIcon or C.goldMuted
  filterBtn:SetIconColor(c[1], c[2], c[3])
end

local function matchesFilters(entry)
  if filter.slot and slotOf(entry) ~= filter.slot then return false end
  if filter.search == "" then return true end
  local info = entry.info
  local hay = table.concat({ itemName(entry), info.boss or "", info.dungeon or "", slotOf(entry) }, "\n"):lower()
  return hay:find(filter.search:lower(), 1, true) ~= nil
end

-- Every slot on the wishlist, in paperdoll order, for the filter menu.
local function slotsOnList()
  local seen, list = {}, {}
  local function collect(source)
    for key, info in pairs(source or {}) do
      local slot = slotOf({ id = info.id or tonumber(key) or 0, info = info })
      if not seen[slot] then
        seen[slot] = true
        list[#list + 1] = slot
      end
    end
  end
  collect(LootWishlist.GetTracked())
  collect(LootWishlist.GetObtained and LootWishlist.GetObtained())
  if filter.slot and not seen[filter.slot] then list[#list + 1] = filter.slot end
  return LootWishlist.Browser.sortSlots(list)
end

------------------------------------------------------------------------
-- Difficulty sort order (shared between mergeItemsByID and display)
------------------------------------------------------------------------
local DIFF_ORDER = LootWishlist.Const.DIFF_TAG_ORDER

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
      byID[id] = { id = id, info = it.info, obtained = it.obtained, diffs = {} }
      table.insert(merged, byID[id])
    end
    local tag = LootWishlist.Const.DiffTag(it.info.difficultyName, it.info.difficultyID)
    table.insert(byID[id].diffs, {
      diffID = it.info.difficultyID, diffName = it.info.difficultyName,
      tag = tag, track = trackKeyForEntry(it.info),
    })
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
  local function itemRows(items, indent)
    for _, m in ipairs(mergeItemsByID(items)) do
      rows[#rows + 1] = { type = "item", id = m.id, info = m.info, diffs = m.diffs, obtained = m.obtained, indent = indent }
    end
  end
  local settings = LootWishlistDB and LootWishlistDB.settings
  local filtering = filtersActive()
  local layout = LootWishlist.Layout.Build({
    includeObtained = not (settings and settings.hideObtained),
    keep = filtering and matchesFilters or nil,
  })
  for _, inst in ipairs(layout) do
    rows[#rows + 1] = { type = "instance", name = inst.name, count = inst.count, isRaid = inst.isRaid }
    if inst.bosses then
      for _, boss in ipairs(inst.bosses) do
        rows[#rows + 1] = { type = "boss", name = boss.name, count = boss.count }
        itemRows(boss.items, true)
      end
    else
      itemRows(inst.items, false)
    end
  end
  if #rows == 0 and filtering then
    rows[1] = { type = "note", text = S.noMatches }
  end
  return rows
end

local function getRowHeight(row)
  if row.type == "instance" then return INSTANCE_ROW_H end
  if row.type == "boss" or row.type == "note" then return BOSS_ROW_H end
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
    if allCovered then return S.anySpec end
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
-- setIconState: a row action reads lit when its state is on, greyed when off
------------------------------------------------------------------------
local function setIconState(btn, on)
  local c = on and C.goldIcon or C.textMuted
  btn:SetIconColor(c[1], c[2], c[3], 1)
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
  f.itemLabel:SetPoint("RIGHT",   -80, 0)
  f.itemLabel:SetJustifyH("LEFT")
  f.itemLabel:SetWordWrap(false)
  f.itemLabel:Hide()

  -- Sub-label (boss / instance)
  f.subLabel = f:CreateFontString(nil, "OVERLAY")
  f.subLabel:SetFont(UI.BODY_FONT, 10)
  f.subLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  f.subLabel:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 6, 3)
  f.subLabel:SetPoint("RIGHT",      -80, 0)
  f.subLabel:SetJustifyH("LEFT")
  f.subLabel:SetWordWrap(false)
  f.subLabel:Hide()

  -- Row actions, right to left: remove, bonus roll, obtained.
  local function rowIcon(icon, color)
    local btn = UI.CreateIconButton(f, { icon = icon, size = ICON_SIZE, color = color })
    btn:SetHitRectInsets(-ICON_HIT_X, -ICON_HIT_X, -ICON_HIT_Y, -ICON_HIT_Y)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:Hide()
    return btn
  end

  f.removeBtn = rowIcon(ICONS.remove, C.danger)
  f.removeBtn:SetPoint("RIGHT", -8, 0)
  f.removeBtn:SetIconColor(C.danger[1], C.danger[2], C.danger[3], 0.75)
  f.removeBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.removeFromWishlist, 1, 1, 1)
    GameTooltip:Show()
  end)

  f.bonusRollBtn = rowIcon(ICONS.bonusRoll)
  f.bonusRollBtn:SetPoint("RIGHT", f.removeBtn, "LEFT", -ICON_GAP, 0)
  f.bonusRollBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.bonusRollTitle, 1, 1, 1)
    GameTooltip:AddLine(S.bonusRollLine1, 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(S.bonusRollLine2, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)

  f.obtainedBtn = rowIcon(ICONS.obtained)
  f.obtainedBtn:SetPoint("RIGHT", f.bonusRollBtn, "LEFT", -ICON_GAP, 0)

  -- Tooltip on hover
  f:SetScript("OnEnter", function(self)
    if self.itemLink then
      LootWishlist.ApplyWardrobePreviewFlag(self)
      LootWishlist.UI.AnchorItemTooltip(self)
      GameTooltip:SetHyperlink(self.itemLink)
      GameTooltip:Show()
      LootWishlist.UI.PlaceComparisonTooltips()
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
  if f.bonusRollBtn then
    f.bonusRollBtn:Hide()
    f.bonusRollBtn:SetScript("OnClick", nil)
  end
  if f.obtainedBtn then
    f.obtainedBtn:Hide()
    f.obtainedBtn:SetScript("OnClick", nil)
  end
  f.itemLink = nil
  f.rowType  = row.type
  f._bgR, f._bgG, f._bgB, f._bgA = nil, nil, nil, nil
  f.bg:SetColorTexture(0, 0, 0, 0)

  if row.type == "instance" then
    f:SetHeight(INSTANCE_ROW_H)
    local raidTag = row.isRaid and S.raidTag or ""
    f.headingLabel:SetFont(UI.TITLE_FONT, 13, "OUTLINE")
    f.headingLabel:SetText(S.instanceHeading:format(row.name, row.count, raidTag))
    f.headingLabel:Show()
    -- Dark warm background for instance headers
    f.bg:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.6)
    f._bgR, f._bgG, f._bgB, f._bgA = C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.6
    -- Gold separator
    f.sep:SetColorTexture(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 0.4)

  elseif row.type == "boss" then
    f:SetHeight(BOSS_ROW_H)
    f.headingLabel:SetFont(UI.TITLE_FONT, 11, "")
    f.headingLabel:SetText(S.bossHeading:format(row.name, row.count))
    f.headingLabel:Show()
    f.bg:SetColorTexture(C.bgPanel[1], C.bgPanel[2], C.bgPanel[3], 0.5)
    f._bgR, f._bgG, f._bgB, f._bgA = C.bgPanel[1], C.bgPanel[2], C.bgPanel[3], 0.5
    f.sep:SetColorTexture(C.borderDark[1], C.borderDark[2], C.borderDark[3], 0.4)

  elseif row.type == "note" then
    f:SetHeight(BOSS_ROW_H)
    f.headingLabel:SetFont(UI.BODY_FONT, 12, "")
    f.headingLabel:SetText("|cff8a7e6a" .. row.text .. "|r")
    f.headingLabel:Show()
    f.sep:SetColorTexture(0, 0, 0, 0)

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

    -- Pull display fields from LuckyItem's session cache. The list warms every
    -- tracked item up front (warmTrackedItems), so by the time a row paints, the
    -- name, icon and quality are usually already present, with no per-row async
    -- load or refresh cascade.
    local cached = LuckyItem and LuckyItem:GetCached(itemID)
    if cached then
      info.link    = info.link    or cached.link
      info.icon    = info.icon    or cached.icon
      info.quality = info.quality or cached.quality
    end

    -- Icon texture
    local iconTex = info.icon
    if not iconTex and C_Item and C_Item.GetItemIconByID then
      iconTex = C_Item.GetItemIconByID(itemID)
    end
    f.icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
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
        local label = d.track or d.tag
        if label then table.insert(tags, label) end
      end
      if #tags > 0 then
        table.insert(parts, string.format("|cff8a7e6a[%s]|r", table.concat(tags, UI.DOT)))
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
      f.subLabel:SetText(table.concat(meta, " " .. UI.DOT .. " "))
      f.subLabel:Show()
    end

    -- An obtained row stays in place, greyed out, so the record of what you
    -- chased survives without competing with what you still want.
    local obtained = row.obtained and true or false
    local dim = obtained and 0.4 or 1
    f.icon:SetAlpha(dim)
    f.qualityBar:SetAlpha(dim)
    f.itemLabel:SetAlpha(dim)
    f.subLabel:SetAlpha(dim)

    -- Remove button — removes all difficulties for this item in one call
    local itemIDForRemove = row.id
    f.removeBtn:SetScript("OnClick", function() LootWishlist.RemoveTrackedItem(itemIDForRemove) end)
    f.removeBtn:Show()

    -- Obtained toggle
    if f.obtainedBtn then
      setIconState(f.obtainedBtn, obtained)
      f.obtainedBtn:SetScript("OnClick", function()
        LootWishlist.SetObtained(itemIDForRemove, not obtained)
      end)
      f.obtainedBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(obtained and S.notObtained or S.markObtained, 1, 1, 1)
        GameTooltip:AddLine(obtained and S.notObtainedLine or S.markObtainedLine, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
      end)
      f.obtainedBtn:Show()
    end

    -- Bonus roll toggle button
    if f.bonusRollBtn and LootWishlist.BonusRoll then
      local idForBR = row.id
      local function paint()
        setIconState(f.bonusRollBtn, LootWishlist.BonusRoll.IsFlagged(idForBR))
      end
      paint()
      f.bonusRollBtn:SetScript("OnClick", function()
        LootWishlist.BonusRoll.Toggle(idForBR)
        paint()
      end)
      f.bonusRollBtn:Show()
    end
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
-- warmTrackedItems
--
-- Batch-load every tracked item through LuckyItem so the session cache is
-- populated before rows paint. Only triggers a load (and a follow-up refresh)
-- when something is actually missing, and guards against re-entry, so the
-- load -> refresh -> warm cycle terminates once everything is cached.
------------------------------------------------------------------------
local warmPending = false
local function warmTrackedItems()
  if not LuckyItem then return end
  local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked()
  if type(tracked) ~= "table" then return end

  local ids, seen, missing = {}, {}, false
  local function collect(source)
    for _, v in pairs(source) do
      if type(v) == "table" and type(v.id) == "number" and not seen[v.id] then
        seen[v.id] = true
        ids[#ids + 1] = v.id
        if not LuckyItem:IsCached(v.id) then missing = true end
      end
    end
  end
  collect(tracked)
  collect(LootWishlist.GetObtained and LootWishlist.GetObtained() or {})

  if not missing or warmPending then return end
  warmPending = true
  LuckyItem:GetMany(ids, function()
    warmPending = false
    if LootWishlist.UI and LootWishlist.UI.refresh then
      LootWishlist.UI.refresh()
    end
  end)
end

------------------------------------------------------------------------
-- refresh
------------------------------------------------------------------------
local function refresh()
  if not viewport then return end

  warmTrackedItems()

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
      statusCountLabel:SetText(S.noItems)
    elseif count == 1 then
      statusCountLabel:SetText(S.oneItem)
    else
      statusCountLabel:SetText(S.manyItems:format(count))
    end
  end
  if clearBtn then
    local obtained = LootWishlist.GetObtained and LootWishlist.GetObtained()
    if count > 0 or (obtained and next(obtained)) then clearBtn:Enable() else clearBtn:Disable() end
  end

  renderVisibleRows()
  if filterBtn then paintFilterIcon() end

  local tEnd = debugprofilestop()
  PerfLog(string.format(
    "refresh #%d | %d items | %d flatRows | %d poolFrames | total=%.1fms",
    refreshID, count, #flatRows, #rowPool, tEnd - t0
  ))
end

------------------------------------------------------------------------
-- Toolbar: search box, then order and filter menus as borderless gold
-- icons, the same row the Loot Browser has.
------------------------------------------------------------------------
local function describeFilters(tip)
  tip:SetText(S.filters, 1, 1, 1)
  tip:AddLine(filter.slot or S.noFilters, 0.8, 0.8, 0.8)
end

local function orderLabel()
  for _, o in ipairs(LootWishlist.Const.WISHLIST_ORDERS) do
    if o.key == LootWishlist.Layout.Order() then return o.label end
  end
end

local function describeOrder(tip)
  tip:SetText(orderLabel() or S.order, 1, 1, 1)
  tip:AddLine(S.orderTip, 0.8, 0.8, 0.8)
end

local function buildOrderMenu(_, root)
  root:CreateTitle(S.order)
  for _, o in ipairs(LootWishlist.Const.WISHLIST_ORDERS) do
    root:CreateRadio(o.label,
      function() return LootWishlist.Layout.Order() == o.key end,
      function() LootWishlist.Layout.SetOrder(o.key) end)
  end
end

local function buildFilterMenu(_, root)
  root:CreateTitle(S.filterSlot)
  local function slotRadio(label, slot)
    root:CreateRadio(label,
      function() return filter.slot == slot end,
      function()
        filter.slot = slot
        LootWishlist.UI.refresh()
      end)
  end
  slotRadio(S.allSlots, nil)
  for _, slot in ipairs(slotsOnList()) do slotRadio(slot, slot) end
  root:CreateDivider()
  root:CreateButton(S.resetFilters, function()
    filter.slot = nil
    searchBox:SetText("")
    LootWishlist.UI.refresh()
  end)
end

local function createToolbar(f)
  local toolbar = CreateFrame("Frame", nil, f)
  toolbar:SetPoint("TOPLEFT",  f, "TOPLEFT",  2, -34)
  toolbar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -34)
  toolbar:SetHeight(TOOLBAR_H)

  local pad = 8
  local function toolbarIcon(icon, tooltip)
    local btn = UI.CreateIconButton(toolbar, { icon = icon, size = ICON_SIZE, tooltip = tooltip, anchor = "ANCHOR_BOTTOM" })
    btn:SetHitRectInsets(-4, -4, -4, -4)
    return btn
  end

  filterBtn = toolbarIcon("filter", describeFilters)
  filterBtn:SetPoint("RIGHT", toolbar, "RIGHT", -pad, 0)
  filterBtn:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, buildFilterMenu)
  end)

  local orderBtn = toolbarIcon("layers", describeOrder)
  orderBtn:SetPoint("RIGHT", filterBtn, "LEFT", -pad, 0)
  orderBtn:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, buildOrderMenu)
  end)

  searchBox = UI.CreateSearchBox(toolbar, {
    height = 24,
    placeholder = S.searchPlaceholder,
    onChange = function(query)
      if query == filter.search then return end
      filter.search = query
      LootWishlist.UI.refresh()
    end,
  })
  searchBox:ClearAllPoints()
  searchBox:SetPoint("LEFT",  toolbar, "LEFT", 6, 0)
  searchBox:SetPoint("RIGHT", orderBtn, "LEFT", -pad, 0)
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
  f.lootWishlistWindow = true

  -- LuckyUI solid backdrop with gold border
  f:SetBackdrop(UI.Backdrop)
  f:SetBackdropColor(C.bgDark[1], C.bgDark[2], C.bgDark[3], C.bgDark[4])
  f:SetBackdropBorderColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3])

  -- Header (using LuckyUI.CreateHeader)
  local header = UI.CreateHeader(f, S.title)
  -- Override close to track isOpen state
  -- Find the close button (last child of header)
  for _, child in ipairs({ header:GetChildren() }) do
    if child:GetObjectType() == "Button" then
      child:SetScript("OnClick", function() f:Hide(); LootWishlist.UI.isOpen = false end)
    end
  end

  -- Item count beside the title, where every window width has room for it
  statusCountLabel = header:CreateFontString(nil, "OVERLAY")
  statusCountLabel:SetFont(UI.BODY_FONT, 11)
  statusCountLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  statusCountLabel:SetPoint("LEFT", f.titleText, "RIGHT", 10, -1)
  statusCountLabel:SetPoint("RIGHT", header, "RIGHT", -36, -1)
  statusCountLabel:SetJustifyH("LEFT")
  statusCountLabel:SetWordWrap(false)

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

  createToolbar(f)

  -- Scroll viewport
  viewport = CreateFrame("Frame", nil, f)
  viewport:SetPoint("TOPLEFT",     f, "TOPLEFT",     2,  -(34 + TOOLBAR_H))
  viewport:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(2 + SCROLLBAR_W + 2), 36)
  viewport:SetClipsChildren(true)

  -- Scrollbar
  scrollBar = CreateFrame("Slider", "LootWishlistScrollBar", f, "UIPanelScrollBarTemplate")
  scrollBar:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -4,  -(50 + TOOLBAR_H))
  scrollBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4,   52)
  scrollBar:SetWidth(SCROLLBAR_W)
  -- Replace the template's OnValueChanged before any value is set: the
  -- default handler calls SetVerticalScroll on the parent, which is only
  -- there when the parent is a ScrollFrame, and ours is a plain frame.
  scrollBar:SetScript("OnValueChanged", function(_, value)
    scrollOffset = value
    renderVisibleRows()
  end)
  scrollBar:SetMinMaxValues(0, 0)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(ITEM_ROW_H)

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
  clearBtn = UI.CreateButton(statusBar, S.clearAll, 100, 22, "danger")
  clearBtn:SetPoint("LEFT", statusBar, "LEFT", 4, -2)
  clearBtn:SetScript("OnClick", function()
    StaticPopupDialogs["LOOTWISHLIST_CLEAR_ALL"] = {
      text = S.clearAllConfirm,
      button1 = "Yes", button2 = "No",
      OnAccept = function()
        if LootWishlist.ClearAllTracked then LootWishlist.ClearAllTracked() end
      end,
      timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("LOOTWISHLIST_CLEAR_ALL")
  end)

  -- Export / Import share-string buttons
  local exportBtn = UI.CreateButton(statusBar, S.export, 60, 22, "secondary")
  exportBtn:SetPoint("LEFT", clearBtn, "RIGHT", 4, 0)
  exportBtn:SetScript("OnClick", function()
    if LootWishlist.Share and LootWishlist.Share.Export then LootWishlist.Share.Export() end
  end)

  local importBtn = UI.CreateButton(statusBar, S.import, 60, 22, "secondary")
  importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 4, 0)
  importBtn:SetScript("OnClick", function()
    if LootWishlist.Share and LootWishlist.Share.Import then LootWishlist.Share.Import() end
  end)

  local pasteBtn = UI.CreateButton(statusBar, S.paste, 70, 22, "secondary")
  pasteBtn:SetPoint("LEFT", importBtn, "RIGHT", 4, 0)
  pasteBtn:SetScript("OnClick", function()
    if LootWishlist.GearImport then LootWishlist.GearImport.Show() end
  end)

  -- Browse Loot button (primary): opens the season drop-table browser
  local browseBtn = UI.CreateButton(statusBar, S.browseLoot, 100, 22, "primary")
  browseBtn:SetPoint("RIGHT", statusBar, "RIGHT", -4, -2)
  browseBtn:SetScript("OnClick", function()
    if LootWishlist.Browser and LootWishlist.Browser.open then LootWishlist.Browser.open() end
  end)

  -- Restore saved position, clamped so a size saved under an older, smaller
  -- minimum cannot restore with the status bar buttons overlapping
  local pos = LootWishlistCharDB.windowPos
  if pos and pos.point then
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    if pos.w and pos.h then f:SetSize(math.max(pos.w, MIN_W), math.max(pos.h, MIN_H)) end
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
  LootWishlist.UI.isOpen = true
  refresh()
end

local function hide()
  if mainFrame then mainFrame:Hide(); LootWishlist.UI.isOpen = false end
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

LootWishlist.UI.TrackKeyForEntry = trackKeyForEntry
LootWishlist.UI.refresh         = scheduleRefresh
LootWishlist.UI.deferredRefresh = deferredRefresh
LootWishlist.UI.open            = open
LootWishlist.UI.hide            = hide
