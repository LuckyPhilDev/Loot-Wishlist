-- Loot Wishlist - Sticky Summary Window

LootWishlist = LootWishlist or {}
LootWishlist.Summary = LootWishlist.Summary or {}

local Summary = LootWishlist.Summary
local frame, textFS
local isDragging = false

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
  -- Transparent sticky note look
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  frame:SetBackdropColor(0, 0, 0, 0.35)
  frame:SetBackdropBorderColor(1, 1, 1, 0.35)

  -- Non-closable; minimal header with Open button
  textFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  textFS:SetJustifyH("LEFT")
  textFS:SetJustifyV("TOP")
  textFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
  textFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  textFS:SetText("")

  -- Click anywhere to open full list; avoid triggering when dragging
  frame:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and not isDragging then
      if LootWishlist.Ace and LootWishlist.Ace.open then LootWishlist.Ace.open() end
    end
  end)
  frame:HookScript("OnDragStart", function() isDragging = true end)
  frame:HookScript("OnDragStop", function() isDragging = false end)

  -- Restore position if saved
  local w = LootWishlistCharDB and LootWishlistCharDB.summaryWindow
  if w and w.point then
    frame:ClearAllPoints()
    frame:SetPoint(w.point, w.relative and _G[w.relative] or UIParent, w.relativePoint or w.point, w.x or 0, w.y or 0)
  end

  frame:Hide()
  return frame
end

-- Helper: order by instance (raids first, alpha), and bosses by EJ order
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
      local name, _, encounterID = EJ_GetEncounterInfoByIndex(idx)
      if not name then break end
      if encounterID then order.id[encounterID] = idx end
      if name then order.name[name:lower()] = idx end
    end
    if prevInstance and prevInstance ~= instanceID then pcall(EJ_SelectInstance, prevInstance) end
  end
  if not order or not next(order) then
    order = { id = {}, name = {} }
    for idx = 1, 200 do
      local name, _, encounterID = EJ_GetEncounterInfoByIndex(idx, instanceID)
      if not name then break end
      if encounterID then order.id[encounterID] = idx end
      if name then order.name[name:lower()] = idx end
    end
  end
  encounterOrderCache[instanceID] = order
  return order
end

local function buildSummaryLines()
  local items = LootWishlist.GetTracked()
  if not items or not next(items) then return {} end
  -- Group by instance
  local groups = {}
  for id, info in pairs(items) do
    local inst = info.dungeon or "Unknown"
    local g = groups[inst]
    if not g then g = { name = inst, isRaid = info.isRaid and true or false, items = {}, instanceID = info.instanceID }; groups[inst] = g end
    if info.isRaid then g.isRaid = true end
    if info.instanceID and not g.instanceID then g.instanceID = info.instanceID end
    table.insert(g.items, { id = id, info = info })
  end
  local ordered = {}
  for name, g in pairs(groups) do table.insert(ordered, { name = name, g = g }) end
  table.sort(ordered, function(a,b)
    if a.g.isRaid ~= b.g.isRaid then return a.g.isRaid end
    return a.name < b.name
  end)

  local lines = {}
  for _, entry in ipairs(ordered) do
    local g = entry.g
    if g.isRaid then
      -- Raid header
      table.insert(lines, string.format("|cffffd200%s|r", entry.name))
      -- Boss list for raids (one per line under the raid header)
      local bossGroups = {}
      for _, it in ipairs(g.items) do
        local bname = (it.info.boss and it.info.boss ~= "") and it.info.boss or "Unknown Boss"
        local encID = it.info.encounterID or -1
        if not bossGroups[bname] then bossGroups[bname] = {encounterID = encID, items = {}} end
        if encID ~= -1 then bossGroups[bname].encounterID = encID end
        table.insert(bossGroups[bname].items, it)
      end
      local bossOrdered = {}
      for bname, data in pairs(bossGroups) do table.insert(bossOrdered, { name = bname, items = data.items, encounterID = data.encounterID or -1 }) end
      local orderMap = getEncounterOrder(g.instanceID)
      table.sort(bossOrdered, function(a,b)
        local ao = orderMap and (orderMap.id[a.encounterID] or orderMap.name[a.name:lower()]) or nil
        local bo = orderMap and (orderMap.id[b.encounterID] or orderMap.name[b.name:lower()]) or nil
        if ao and bo and ao ~= bo then return ao < bo end
        if ao and not bo then return true end
        if bo and not ao then return false end
        return a.name < b.name
      end)
      for _, b in ipairs(bossOrdered) do
        table.insert(lines, string.format("  - %s (%d)", b.name, #b.items))
      end
    else
      -- Dungeon instances only (one per line)
      table.insert(lines, string.format("|cffffd200%s|r (%d)", entry.name, #g.items))
    end
  end
  return lines
end

local function refresh()
  local f = ensureFrame()
  local lines = buildSummaryLines()
  if not next(lines) then f:Hide(); return end
  local content = table.concat(lines, "\n")
  textFS:SetText(content)
  -- Resize to fit content
  local width = 300 -- slightly wider cap
  if textFS.GetStringWidth then width = math.max(200, math.min(300, textFS:GetStringWidth() + 24)) end
  frame:SetWidth(width)
  local height = 30 + (textFS.GetStringHeight and textFS:GetStringHeight() or 60)
  frame:SetHeight(height)
  f:Show()
end

Summary.refresh = refresh

-- Public helper to force show when items exist
function Summary.showIfNeeded()
  refresh()
end
