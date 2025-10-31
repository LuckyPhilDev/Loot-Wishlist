-- Loot Wishlist - AceGUI UI

local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
LootWishlist = LootWishlist or {}
LootWishlist.Ace = LootWishlist.Ace or {}

local AceView = { frame = nil, scroll = nil }

local function diffTag(id, name)
  -- Prefer name, fallback to id mapping
  if name and name ~= "" then
    local n = name:lower()
    if n:find("raid finder") or n:find("lfr") then return "LFR" end
    if n:find("normal") then return "N" end
    if n:find("heroic") then return "H" end
    if n:find("mythic%+") or n:find("keystone") then return "+" end
    if n:find("mythic") then return "M" end
  end
  if id then
    local map = {
      [1] = "N",   -- Normal (5)
      [2] = "H",   -- Heroic (5)
      [8] = "+",   -- Mythic Keystone
      [23] = "M",  -- Mythic (5)
      [24] = "TW", -- Timewalking (5)
      [14] = "N",  -- Normal (Raid)
      [15] = "H",  -- Heroic (Raid)
      [16] = "M",  -- Mythic (Raid)
      [17] = "LFR",-- LFR
    }
    return map[id]
  end
  return nil
end

local function groupItemsByInstance()
  local groups = {}
  for key, info in pairs(LootWishlist.GetTracked()) do
    local inst = info.dungeon or "Unknown"
    local g = groups[inst]
    if not g then g = { name = inst, isRaid = info.isRaid and true or false, items = {}, instanceID = info.instanceID }; groups[inst] = g end
    if info.instanceID and not g.instanceID then g.instanceID = info.instanceID end
    if info.isRaid then g.isRaid = true end
    table.insert(g.items, { key = key, id = info.id or tonumber(key) or 0, info = info })
  end
  local ordered = {}
  for name, g in pairs(groups) do table.insert(ordered, { name = name, g = g }) end
  table.sort(ordered, function(a,b)
    if a.g.isRaid ~= b.g.isRaid then return a.g.isRaid end
    return a.name < b.name
  end)
  return ordered
end

-- Cache for EJ encounter order per instance
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
    local ok = pcall(EJ_SelectInstance, instanceID)
    order = { id = {}, name = {} }
    for idx = 1, 200 do
      local name, _, encounterID = EJ_GetEncounterInfoByIndex(idx)
      if not name then break end
      if encounterID then order.id[encounterID] = idx end
      if name then order.name[name:lower()] = idx end
    end
    if prevInstance and prevInstance ~= instanceID then pcall(EJ_SelectInstance, prevInstance) end
  end
  -- Fallback: pass instanceID directly if selection approach failed or empty
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

-- Renders one item row inside the scroll list (modern version with enhanced visuals)
local function renderItemRow(parent, itemKey, itemID, info, indent)
  -- Get Styles module
  local Styles = LootWishlist.UI and LootWishlist.UI.Styles
  local useModernStyle = Styles and Styles.IsModernStyleEnabled()
  
  if not info.link then
    local ItemAPI = _G["Item"]
    if type(ItemAPI)=="table" and ItemAPI.CreateFromItemID then
      local itemObj = ItemAPI:CreateFromItemID(itemID)
      if itemObj and itemObj.ContinueOnItemLoad then
        itemObj:ContinueOnItemLoad(function()
          local ilink = itemObj.GetItemLink and itemObj:GetItemLink()
          if ilink then info.link = ilink end
          local iconTex = itemObj.GetItemIcon and itemObj:GetItemIcon()
          if iconTex then info.icon = iconTex end
          local quality = itemObj.GetItemQuality and itemObj:GetItemQuality()
          if quality then info.quality = quality end
          if AceGUI and AceView.frame then LootWishlist.Ace.refresh() end
        end)
      end
    elseif C_Item and C_Item.RequestLoadItemDataByID then
      C_Item.RequestLoadItemDataByID(itemID)
    end
  end
  
  -- Try to get quality if not cached
  if not info.quality and C_Item and C_Item.GetItemQualityByID then
    local quality = C_Item.GetItemQualityByID(itemID)
    if quality then info.quality = quality end
  end
  local link = info.link or ("item:"..tostring(itemID))
  
  -- Single header group to minimize vertical padding
  local header = AceGUI:Create("SimpleGroup"); header["SetLayout"](header, "Flow"); header["SetFullWidth"](header, true)
  
  if indent then
    local spacer = AceGUI:Create("Label"); spacer["SetText"](spacer, " "); spacer["SetWidth"](spacer, 16)
    header["AddChild"](header, spacer)
  end
  
  -- Item icon (larger if modern style enabled)
  local iconWidget = AceGUI:Create("Icon")
  local iconTex = info.icon
  if not iconTex and C_Item and C_Item.GetItemIconByID then iconTex = C_Item.GetItemIconByID(itemID) end
  if not iconTex then iconTex = (Styles and Styles.Icons.item_placeholder) or "Interface\\Icons\\INV_Misc_QuestionMark" end
  iconWidget["SetImage"](iconWidget, iconTex)
  
  -- Add tooltip to icon
  iconWidget["SetCallback"](iconWidget, "OnEnter", function(widget)
    if link then
      GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink(link)
      GameTooltip:Show()
    end
  end)
  iconWidget["SetCallback"](iconWidget, "OnLeave", function()
    GameTooltip:Hide()
  end)
  
  if useModernStyle then
    iconWidget["SetImageSize"](iconWidget, 40, 40)
    iconWidget["SetWidth"](iconWidget, 44)
    
    -- Apply quality border color if we have quality info
    if info.quality and iconWidget.frame then
      local qualityColor = Styles.GetQualityColor(info.quality)
      -- Create a border frame around the icon
      local border = iconWidget.frame.qualityBorder
      if not border then
        border = CreateFrame("Frame", nil, iconWidget.frame)
        border:SetAllPoints(iconWidget.image or iconWidget.frame)
        border:SetFrameLevel((iconWidget.frame:GetFrameLevel() or 0) + 1)
        iconWidget.frame.qualityBorder = border
      end
      if border.SetBackdrop then
        border:SetBackdrop({
          edgeFile = "Interface\\Buttons\\WHITE8X8",
          edgeSize = 2,
          insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        border:SetBackdropBorderColor(unpack(qualityColor))
      end
    end
  else
    iconWidget["SetImageSize"](iconWidget, 16, 16)
    iconWidget["SetWidth"](iconWidget, 20)
  end
  
  header["AddChild"](header, iconWidget)
  local tag = diffTag(info.difficultyID, info.difficultyName)
  -- Build spec names text if available; show {any spec} when unrestricted for player's class
  local specText
  do
    local specs = info and info.specs
    -- Helper: build player's specID set
    local playerSpecIDs = {}
    local psCount = 0
    local numSpecs = _G.GetNumSpecializations and _G.GetNumSpecializations() or 0
    if type(numSpecs) == "number" and numSpecs > 0 then
      for i = 1, numSpecs do
        local ok, specID = pcall(_G.GetSpecializationInfo, i)
        if ok and type(specID) == "number" then playerSpecIDs[specID] = true; psCount = psCount + 1 end
      end
    end

    local function allPlayerSpecsCovered()
      if psCount == 0 then return false end
      if type(specs) ~= "table" or not next(specs) then return true end -- no specific info: treat as any spec
      local specSet = {}
      for _, sid in ipairs(specs) do specSet[sid] = true end
      for sid in pairs(playerSpecIDs) do
        if not specSet[sid] then return false end
      end
      return true
    end

    if allPlayerSpecsCovered() then
      specText = "|cffa0a0a0{any spec}|r"
    elseif type(specs) == "table" and next(specs) then
      local getNames = LootWishlist and LootWishlist.GetSpecNames
      local names = (type(getNames) == "function" and getNames(specs)) or {}
      local text = (type(names) == "table" and next(names) and table.concat(names, "/")) or nil
      if not text then
        -- Fallback to spec ID list if names not available
        local tmp = {}
        for _, sid in ipairs(specs) do table.insert(tmp, tostring(sid)) end
        text = table.concat(tmp, "/")
      end
      if text and text ~= "" then specText = string.format("|cffa0a0a0{%s}|r", text) end
    end
  end
  
  -- Build label text with metadata
  local parts = { link }
  if tag then table.insert(parts, string.format("|cffa0a0a0[%s]|r", tag)) end
  if specText then table.insert(parts, specText) end
  
  -- Add boss/instance metadata in modern style
  if useModernStyle then
    local metadata = {}
    if info.boss and info.boss ~= "" then
      table.insert(metadata, "|cff888888" .. info.boss .. "|r")
    end
    if info.dungeon and info.dungeon ~= "" and info.dungeon ~= info.boss then
      table.insert(metadata, "|cff666666" .. info.dungeon .. "|r")
    end
    if #metadata > 0 then
      table.insert(parts, table.concat(metadata, " • "))
    end
  end
  
  local labelText = table.concat(parts, "  ")
  local label = AceGUI:Create("InteractiveLabel")
  label["SetText"](label, labelText)
  label["SetRelativeWidth"](label, indent and 0.75 or 0.77)
  label["SetCallback"](label, "OnEnter", function(widget)
    if link then
      GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink(link)
      GameTooltip:Show()
    end
    -- Apply hover effect in modern style
    if useModernStyle and widget.frame and widget.frame.SetBackdrop then
      Styles.ApplyBackdrop(widget.frame, "row", Styles.Colors.bg_hover)
    end
  end)
  label["SetCallback"](label, "OnLeave", function(widget)
    GameTooltip:Hide()
    -- Remove hover effect
    if useModernStyle and widget.frame and widget.frame.SetBackdrop then
      widget.frame:SetBackdrop(nil)
    end
  end)
  header["AddChild"](header, label)
  local remove = AceGUI:Create("Icon")
  local removeIcon = (useModernStyle and Styles and Styles.Icons.remove) or "Interface\\Buttons\\UI-Panel-MinimizeButton-Up"
  remove["SetImage"](remove, removeIcon)
  
  if useModernStyle then
    remove["SetImageSize"](remove, 24, 24)
    remove["SetWidth"](remove, 28)
    
    -- Add hover effect to remove button
    if remove.frame then
      local origAlpha = remove.frame:GetAlpha()
      remove["SetCallback"](remove, "OnEnter", function(widget)
        if widget.frame then widget.frame:SetAlpha(1.0) end
        GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
        GameTooltip:SetText("Remove from wishlist", 1, 1, 1)
        GameTooltip:Show()
      end)
      remove["SetCallback"](remove, "OnLeave", function(widget)
        if widget.frame then widget.frame:SetAlpha(origAlpha) end
        GameTooltip:Hide()
      end)
    end
  else
    remove["SetImageSize"](remove, 22, 22)
    remove["SetWidth"](remove, 24)
  end
  
  remove["SetCallback"](remove, "OnClick", function() LootWishlist.RemoveTrackedItem(itemKey) end)
  header["AddChild"](header, remove)
  
  -- Apply row background in modern style
  if useModernStyle and header.frame and header.frame.SetBackdrop then
    Styles.ApplyBackdrop(header.frame, "row", {0.08, 0.08, 0.12, 0.5})
    Styles.ApplyHoverEffect(header.frame, {0.08, 0.08, 0.12, 0.5}, Styles.Colors.bg_hover)
  end
  
  parent["AddChild"](parent, header)
end

-- Renders all items for a single boss subsection within a raid
local function renderRaidBossSection(scroll, boss)
  local blabel = AceGUI:Create("Label"); blabel["SetFullWidth"](blabel, true); blabel["SetText"](blabel, string.format("  |cffffbf00%s|r (%d)", boss.name, #boss.items))
  scroll["AddChild"](scroll, blabel)
  table.sort(boss.items, function(a,b)
    if a.id ~= b.id then return a.id < b.id end
    local ad = (a.info and a.info.difficultyID) or 0
    local bd = (b.info and b.info.difficultyID) or 0
    return ad < bd
  end)
  for _, it in ipairs(boss.items) do renderItemRow(scroll, it.key, it.id, it.info, true) end
end

-- Renders the whole raid group (grouped by boss in EJ order)
local function renderRaidGroup(scroll, g)
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
    if a.encounterID ~= -1 and b.encounterID ~= -1 and a.encounterID ~= b.encounterID then
      return a.encounterID < b.encounterID
    end
    return a.name < b.name
  end)
  for _, b in ipairs(bossOrdered) do renderRaidBossSection(scroll, b) end
end

-- Renders a non-raid group (flat list)
local function renderDungeonGroup(scroll, g)
  table.sort(g.items, function(a,b)
    local ab = a.info.boss or ""; local bb = b.info.boss or ""
    if ab ~= bb then return ab < bb end
    if a.id ~= b.id then return a.id < b.id end
    local ad = (a.info and a.info.difficultyID) or 0
    local bd = (b.info and b.info.difficultyID) or 0
    return ad < bd
  end)
  for _, it in ipairs(g.items) do renderItemRow(scroll, it.key, it.id, it.info, true) end
end

local function refresh()
  if not AceGUI or not AceView.frame or not AceView.scroll then return end
  AceView.scroll["ReleaseChildren"](AceView.scroll)
  local ordered = groupItemsByInstance()
  local hasAny = false; for _ in pairs(LootWishlist.GetTracked() or {}) do hasAny = true; break end
  if AceView.clearBtn then
    if AceView.clearBtn.SetEnabled then
      AceView.clearBtn:SetEnabled(hasAny)
    else
      if hasAny and AceView.clearBtn.Enable then AceView.clearBtn:Enable() end
      if (not hasAny) and AceView.clearBtn.Disable then AceView.clearBtn:Disable() end
    end
  end

  for _, entry in ipairs(ordered) do
    local g = entry.g
    local count = #g.items
    local heading = AceGUI:Create("Heading"); heading["SetText"](heading, string.format("|cffffd200%s|r (%d)%s", entry.name, count, g.isRaid and "  |cffff7f00[Raid]|r" or "")); heading["SetFullWidth"](heading, true)
    AceView.scroll["AddChild"](AceView.scroll, heading)

    if g.isRaid then
      renderRaidGroup(AceView.scroll, g)
    else
      renderDungeonGroup(AceView.scroll, g)
    end
  end
end

local function open()
  if not AceGUI then print("Loot Wishlist: AceGUI-3.0 not found; using basic window."); LootWishlist.trackerWindow:Show(); return end
  -- Ensure basic window is hidden if present
  if LootWishlist.trackerWindow and LootWishlist.trackerWindow.Hide then LootWishlist.trackerWindow:Hide() end
  if AceView.frame then AceView.frame["Show"](AceView.frame); LootWishlist.Ace.isOpen = true; refresh(); return end
  local frame = AceGUI:Create("Frame")
  frame["SetTitle"](frame, "Loot Wishlist")
  frame["SetLayout"](frame, "List")
  LootWishlistCharDB.aceStatus = LootWishlistCharDB.aceStatus or {}
  frame["SetStatusTable"](frame, LootWishlistCharDB.aceStatus)
  frame["SetCallback"](frame, "OnClose", function(widget)
    if AceView.clearBtn and AceView.clearBtn.Hide then AceView.clearBtn:Hide() end
    AceView.clearBtn = nil
    AceGUI:Release(widget); AceView.frame=nil; AceView.scroll=nil; LootWishlist.Ace.isOpen=false
  end)
  
  -- Apply modern styling if available and enabled
  local Styles = LootWishlist.UI and LootWishlist.UI.Styles
  if Styles and Styles.IsModernStyleEnabled() then
    local frameWidget = rawget(frame, "frame")
    if frameWidget and frameWidget.SetBackdrop then
      Styles.ApplyBackdrop(frameWidget, "window", Styles.Colors.bg_primary, Styles.Colors.border_default)
    end
  end

  local scroll = AceGUI:Create("ScrollFrame"); scroll["SetLayout"](scroll, "List"); scroll["SetFullWidth"](scroll, true); scroll["SetFullHeight"](scroll, true)
  frame["AddChild"](frame, scroll)

  -- Hide bottom status area (gray)
  local _sbg = rawget(frame, "statusbg"); if _sbg and _sbg.Hide then _sbg:Hide() end
  local _st = rawget(frame, "statustext"); if _st and _st.Hide then _st:Hide() end

  AceView.frame, AceView.scroll = frame, scroll
  LootWishlist.Ace.isOpen = true
  -- Create a native Clear All button anchored next to the bottom Close button
  local closeBtn = rawget(frame, "button") or rawget(frame, "closebutton")
  local parent
  if (not closeBtn) then
    -- Try to find the Close button by scanning the widget frame's children
    local base = rawget(frame, "frame")
    if base and base.GetChildren then
      local children = { base:GetChildren() }
  local closeText = "Close"
      for _, child in ipairs(children) do
        if child and child.GetObjectType and child:GetObjectType() == "Button" then
          local txt = child.GetText and child:GetText()
          if txt == closeText or txt == "Close" then
            closeBtn = child
            break
          end
        end
      end
      parent = base
    end
  end
  if closeBtn and closeBtn.GetParent then parent = closeBtn:GetParent() end
  parent = parent or UIParent
  do
    local cab = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    cab:SetText("Clear All")
    cab:SetSize(100, 22)
    cab:ClearAllPoints()
    if closeBtn then
      cab:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
      cab:SetPoint("BOTTOM", closeBtn, "BOTTOM", 0, 0)
    else
      -- Fallback: bottom-right of the frame if Close button not found
      local base = rawget(frame, "frame")
      if base then
        cab:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", -120, 8)
      else
        cab:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -120, 8)
      end
    end
    
    -- Check if we have any items to determine initial enabled state
    local hasItems = false
    for _ in pairs(LootWishlist.GetTracked() or {}) do hasItems = true; break end
    cab:SetEnabled(hasItems)
    
    -- Apply modern button styling
    if Styles and Styles.IsModernStyleEnabled() and cab.SetBackdrop then
      Styles.ApplyBackdrop(cab, "button", Styles.Colors.bg_secondary, Styles.Colors.border_default)
      -- Set normal font color
      if cab.GetFontString then
        local fs = cab:GetFontString()
        if fs then fs:SetTextColor(unpack(Styles.Colors.text_primary)) end
      end
    end
    
    cab:SetScript("OnClick", function()
      StaticPopupDialogs["LOOTWISHLIST_CLEAR_ALL"] = {
        text = "This will remove ALL wishlist items for this character. Are you sure?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
          if LootWishlist.ClearAllTracked then
            LootWishlist.ClearAllTracked()
            -- Refresh the UI after clearing
            if AceView and AceView.frame and LootWishlist.Ace.refresh then
              LootWishlist.Ace.refresh()
            end
          end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
      }
      StaticPopup_Show("LOOTWISHLIST_CLEAR_ALL")
    end)
    AceView.clearBtn = cab
  end
  refresh()
end

local function hide()
  if AceView.frame then AceView.frame["Hide"](AceView.frame); LootWishlist.Ace.isOpen = false end
end

LootWishlist.Ace.refresh = refresh
LootWishlist.Ace.open = open
LootWishlist.Ace.hide = hide
