-- Loot Wishlist - Encounter Journal integration

LootWishlist = LootWishlist or {}
LootWishlist.EJ = LootWishlist.EJ or {}

local function IsRaidInstance(instanceID)
  local EJ_GetInstanceByIndex = _G["EJ_GetInstanceByIndex"]
  if not instanceID or type(EJ_GetInstanceByIndex) ~= "function" then return false end
  if not LootWishlist_IsRaidCache then
    LootWishlist_IsRaidCache = {}
    for i = 1, 500 do
      local rid = EJ_GetInstanceByIndex(i, true)
      if not rid then break end
      LootWishlist_IsRaidCache[rid] = true
    end
  end
  return LootWishlist_IsRaidCache[instanceID] or false
end

local function ExtractItemID(lootButton)
  if not lootButton then return nil end
  local id = lootButton.itemID or lootButton.itemIDForSearch
  if id then return id end
  local link = lootButton.link or lootButton.itemLink or (lootButton.Item and lootButton.Item.link)
  if link and type(link) == "string" then
    local idStr = link:match("item:(%d+)")
    if idStr then return tonumber(idStr) end
  end
  if type(lootButton.index) == "number" then
    local EJ_GetLootInfoByIndex = _G["EJ_GetLootInfoByIndex"]
    if type(EJ_GetLootInfoByIndex) == "function" then
      local ok, itemID, _, _, _, _, ejLink = pcall(EJ_GetLootInfoByIndex, lootButton.index, EncounterJournal and EncounterJournal.encounterID)
      if ok then
        if itemID then return itemID end
        if ejLink and type(ejLink)=="string" then
          local idStr = ejLink:match("item:(%d+)")
          if idStr then return tonumber(idStr) end
        end
      end
    end
  end
  if lootButton.GetElementData then
    local ok, data = pcall(lootButton.GetElementData, lootButton)
    if ok and type(data) == "table" then
      if data.itemID then return data.itemID end
      local dlink = data.link or data.itemLink
      if dlink and type(dlink) == "string" then
        local idStr = dlink:match("item:(%d+)")
        if idStr then return tonumber(idStr) end
      end
    end
  end
  return nil
end

local function DetermineEJContext(lootButton)
  local EJ_GetInstanceInfo = _G["EJ_GetInstanceInfo"]
  local EJ_GetEncounterInfo = _G["EJ_GetEncounterInfo"]
  local EJ_GetLootInfoByIndex = _G["EJ_GetLootInfoByIndex"]
  local EJ_GetDifficulty = _G["EJ_GetDifficulty"]
  local EJ_GetDifficultyInfo = _G["EJ_GetDifficultyInfo"]

  local instanceID = EncounterJournal and EncounterJournal.instanceID
  local instanceName = (instanceID and type(EJ_GetInstanceInfo)=="function" and EJ_GetInstanceInfo(instanceID)) or "Unknown"
  local isRaid = IsRaidInstance(instanceID)

  local bossName = nil
  local encounterID = nil
  if isRaid then
    if lootButton and lootButton.encounterID and type(EJ_GetEncounterInfo)=="function" then
      encounterID = lootButton.encounterID
      bossName = EJ_GetEncounterInfo(lootButton.encounterID)
    elseif lootButton and type(lootButton.index) == "number" and type(EJ_GetLootInfoByIndex)=="function" then
      local ok, _, _, _, _, _, _, encID, _, _, encounterName = pcall(EJ_GetLootInfoByIndex, lootButton.index, EncounterJournal and EncounterJournal.encounterID)
      if ok then
        encounterID = encID
        bossName = encounterName or (encID and type(EJ_GetEncounterInfo)=="function" and EJ_GetEncounterInfo(encID))
      end
    elseif EncounterJournal and EncounterJournal.encounterID and type(EJ_GetEncounterInfo)=="function" then
      encounterID = EncounterJournal.encounterID
      bossName = EJ_GetEncounterInfo(EncounterJournal.encounterID)
    end
    if not bossName and lootButton and lootButton.GetElementData then
      local ok, data = pcall(lootButton.GetElementData, lootButton)
      if ok and type(data) == "table" then
        if data.encounterID and type(EJ_GetEncounterInfo)=="function" then encounterID = data.encounterID; bossName = EJ_GetEncounterInfo(data.encounterID) end
        if not bossName and data.encounterName then bossName = data.encounterName end
      end
    end
  end

  -- Difficulty context
  local diffID = type(EJ_GetDifficulty)=="function" and EJ_GetDifficulty() or nil
  local diffName = nil
  if diffID and type(EJ_GetDifficultyInfo)=="function" then
    local name = EJ_GetDifficultyInfo(diffID)
    if type(name)=="string" and name ~= "" then diffName = name end
  end

  return isRaid, bossName, instanceName, encounterID, instanceID, diffID, diffName
end

local function AddTrackButtonToLootButton(lootButton)
  if not lootButton then return end
  -- Determine if this row represents a real loot item (not headers like 'Bonus Loot')
  local itemID = ExtractItemID(lootButton)

  -- Create button if missing
  local btn = lootButton.LootWishlistTrackButton
  if not btn then
    btn = CreateFrame("Button", nil, lootButton)
    btn:SetSize(50, 20)
    btn:SetText("Wishlist")
    btn:SetNormalFontObject("GameFontNormalSmall")
    btn:SetPoint("TOPRIGHT", lootButton, "TOPRIGHT", -4, -5)
    btn:SetFrameLevel(lootButton:GetFrameLevel() + 5)
    btn:SetFrameStrata("HIGH")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    btn:SetScript("OnEnter", function(self)
      bg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Track this item")
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
      bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
      GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
      local idNow = ExtractItemID(lootButton)
      local itemLink = lootButton.link or lootButton.itemLink
      if not itemLink and type(lootButton.index) == "number" then
        local EJ_GetLootInfoByIndex = _G["EJ_GetLootInfoByIndex"]
        if type(EJ_GetLootInfoByIndex)=="function" then
          local ok, _, _, _, _, _, link = pcall(EJ_GetLootInfoByIndex, lootButton.index, EncounterJournal and EncounterJournal.encounterID)
          if ok then itemLink = link end
        end
      end
      local isRaid, bossName, instanceName, encounterID, instanceID, diffID, diffName = DetermineEJContext(lootButton)
      if idNow then
        LootWishlist.AddTrackedItem(idNow, bossName, instanceName, isRaid, itemLink, encounterID, instanceID, diffID, diffName)
        if LootWishlist.IsDebug and LootWishlist.IsDebug() then print("Loot Wishlist: Tracked", idNow, isRaid and ("boss="..tostring(bossName)) or "") end
      else
        print("Loot Wishlist: Could not find item ID for this item")
      end
    end)

    lootButton.LootWishlistTrackButton = btn
  end

  -- Show only for item rows; hide for headers like 'Bonus Loot'
  if itemID then
    btn:Show()
  else
    btn:Hide()
  end
end

local function GetLootScrollBox()
  local info = EncounterJournal and EncounterJournal.encounter and EncounterJournal.encounter.info
  if not info then return nil end
  return (info.LootContainer and (info.LootContainer.ScrollBox or info.LootContainer.scrollBox))
      or (info.lootScroll and (info.lootScroll.ScrollBox or info.lootScroll.scrollBox))
      or (info.LootScroll and (info.LootScroll.ScrollBox or info.LootScroll.scrollBox))
      or rawget(info, "ScrollBox")
end

local function EnumerateVisibleLootButtons()
  local results = {}
  if not EncounterJournal or not EncounterJournal.encounter or not EncounterJournal.encounter.info then
    return results
  end

  local scrollBox = GetLootScrollBox()
  if scrollBox then
    local target = scrollBox.ScrollTarget or scrollBox.scrollTarget or scrollBox
    if target and target.GetChildren then
      for _, child in ipairs({ target:GetChildren() }) do
        if child and child:IsShown() and child.GetObjectType and child:GetObjectType() == "Button" then
          table.insert(results, child)
        end
      end
    end
  end

  if #results == 0 then
    local lootScroll = EncounterJournal.encounter.info.lootScroll or EncounterJournal.encounter.info.LootContainer
    if lootScroll and lootScroll.buttons then
      for _, b in ipairs(lootScroll.buttons) do
        if b and b:IsShown() then table.insert(results, b) end
      end
    end
    if #results == 0 then
      for i = 1, 80 do
        local b = _G["EncounterJournalEncounterFrameInfoLootScrollFrameButton"..i]
            or _G["EncounterJournalEncounterFrameInfoLootScrollFrameScrollChildButton"..i]
            or _G["EncounterJournalEncounterFrameInfoLootScrollFrameScrollChildLootItem"..i]
            or _G["EncounterJournalEncounterFrameInfoLootScrollChildButton"..i]
        if b and b:IsShown() then table.insert(results, b) end
      end
    end
  end

  if LootWishlist.IsDebug() then print("Loot Wishlist: found loot buttons:", #results) end
  return results
end

local function HookEncounterJournalLoot()
  local function TryHookLootScrollBox()
    local scrollBox = GetLootScrollBox()
    if not scrollBox or scrollBox.LootWishlistHooked then return end
    scrollBox.LootWishlistHooked = true
    if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
      ScrollUtil.AddAcquiredFrameCallback(scrollBox, function(_, row)
        AddTrackButtonToLootButton(row)
      end, nil, true)
      if LootWishlist.IsDebug() then print("Loot Wishlist: Hooked EJ ScrollBox") end
    else
      scrollBox:HookScript("OnUpdate", function()
        for _, b in ipairs(EnumerateVisibleLootButtons()) do
          AddTrackButtonToLootButton(b)
        end
      end)
      if LootWishlist.IsDebug() then print("Loot Wishlist: ScrollUtil missing; using OnUpdate fallback") end
    end
  end

  hooksecurefunc("EncounterJournal_LootUpdate", function()
    for _, lootItem in ipairs(EnumerateVisibleLootButtons()) do
      AddTrackButtonToLootButton(lootItem)
    end
    TryHookLootScrollBox()
  end)

  for _, fname in ipairs({
    "EncounterJournal_SetItem",
    "EncounterJournal_SetLootButton",
    "EncounterJournal_SetLootInfo",
  }) do
    if type(_G[fname]) == "function" then
      hooksecurefunc(fname, function(self)
        if type(self) == "table" and self.GetObjectType and self:GetObjectType() == "Button" then
          AddTrackButtonToLootButton(self)
        end
        TryHookLootScrollBox()
      end)
    end
  end

  if EncounterJournal and not EncounterJournal.LootWishlistShowHook then
    EncounterJournal.LootWishlistShowHook = true
    EncounterJournal:HookScript("OnShow", TryHookLootScrollBox)
  end

  TryHookLootScrollBox()
end

LootWishlist.EJ.hook = HookEncounterJournalLoot
