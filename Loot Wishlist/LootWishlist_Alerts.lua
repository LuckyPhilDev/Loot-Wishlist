-- Loot Wishlist - Drop Alerts

LootWishlist = LootWishlist or {}
LootWishlist.Alerts = LootWishlist.Alerts or {}

local Alerts = LootWishlist.Alerts
local alertFrame, alertFS, alertHideAt
local raidDropFrame, raidDropFS, raidDropHideAt
local rollAlertFrame, rollAlertFS, rollHideAt
local specReminderFrame, specReminderFS, specReminderHideAt
local assistFrame, assistFS, assistHideAt, assistBtnWhisper, assistBtnParty
local lastAssistTargetName, lastAssistMessageWhisper, lastAssistMessageParty
local dungeonReminded = {}
local bossReminded = {}
local assistDungeonReminded = {}
local assistBossReminded = {}
-- Track previous instance state so we can reset dedupers when leaving
local lastInInstance, lastInstanceType

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
local recentSelfAlertAt = {}
-- Current instance difficulty helper (module scope)
local function getCurrentInstanceDifficulty()
  if GetInstanceInfo then
    local _, _, difficultyID, difficultyName = GetInstanceInfo()
    return difficultyID, difficultyName
  end
  return nil, nil
end

-- Current loot specialization helpers --------------------------------------
local function getCurrentSpecID()
  if GetSpecialization then
    local idx = GetSpecialization()
    if idx then
      local ok, specID = pcall(GetSpecializationInfo, idx)
      if ok and type(specID) == "number" then return specID end
    end
  end
  return nil
end

local function getLootSpecID()
  if GetLootSpecialization then
    local sid = GetLootSpecialization()
    if sid and sid ~= 0 then return sid end
  end
  return getCurrentSpecID()
end

local function getSpecNameByID(specID)
  if not specID then return nil end
  local ok, _sid, name = pcall(GetSpecializationInfoByID, specID)
  if ok and type(name) == "string" and name ~= "" then return name end
  return tostring(specID)
end

-- Player specialization set and coverage helpers ----------------------------
local function getPlayerSpecIDs()
  local out = {}
  if GetNumSpecializations and GetSpecializationInfo then
    local count = GetNumSpecializations()
    if type(count) == "number" and count > 0 then
      for i = 1, count do
        local ok, id = pcall(GetSpecializationInfo, i)
        if ok and type(id) == "number" then table.insert(out, id) end
      end
    end
  end
  return out
end

local function isAnySpecForPlayer(specs)
  if type(specs) ~= "table" or not next(specs) then return true end -- no restriction means any spec
  local playerSpecs = getPlayerSpecIDs()
  if #playerSpecs == 0 then return false end
  local set = {}
  for _, sid in ipairs(specs) do set[sid] = true end
  for _, ps in ipairs(playerSpecs) do if not set[ps] then return false end end
  return true
end

-- Instance mapping helpers --------------------------------------------------
local function normalizeName(s)
  if type(s) ~= "string" then return s end
  s = s:lower()
  s = s:gsub("[%s%p]", "")
  return s
end

local function getCurrentEJInstanceID()
  local mapID = GetInstanceInfo and select(8, GetInstanceInfo()) or nil
  local uiMapID = (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or nil
  local EJ_GetInstanceForMap = _G and _G["EJ_GetInstanceForMap"]
  if type(EJ_GetInstanceForMap) == "function" then
    if mapID then
      local ok, ej = pcall(EJ_GetInstanceForMap, mapID)
      if ok and type(ej) == "number" and ej > 0 then return ej end
    end
    if uiMapID then
      local ok, ej = pcall(EJ_GetInstanceForMap, uiMapID)
      if ok and type(ej) == "number" and ej > 0 then return ej end
    end
  end
  return nil
end

-- Spec reminder UI ----------------------------------------------------------
local function ShowSpecReminder(lines)
  if not lines or #lines == 0 then return end
  if not specReminderFrame then
    specReminderFrame = CreateFrame("Frame", "LootWishlistSpecReminder", UIParent, "BackdropTemplate")
    specReminderFrame:SetSize(520, 80)
    specReminderFrame:SetPoint("TOP", UIParent, "TOP", 0, -340)
    specReminderFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    specReminderFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    specReminderFrame:SetBackdropColor(0, 0, 0, 0.85)
    specReminderFrame:SetBackdropBorderColor(0.4, 1.0, 0.4, 0.95)
    specReminderFrame:EnableMouse(true)
    specReminderFrame:SetMovable(true)
    specReminderFrame:RegisterForDrag("LeftButton")
    specReminderFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    specReminderFrame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      if LootWishlistCharDB and self:GetPoint(1) then
        local p, rel, rp, x, y = self:GetPoint(1)
        LootWishlistCharDB.specReminderWindow = {point=p, relative=rel and rel:GetName(), relativePoint=rp, x=x, y=y}
      end
    end)
    specReminderFS = specReminderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    specReminderFS:SetPoint("CENTER")
    specReminderFS:SetJustifyH("CENTER")
    specReminderFS:SetJustifyV("MIDDLE")
    specReminderFS:SetText("")
    local w = LootWishlistCharDB and LootWishlistCharDB.specReminderWindow
    if w and w.point then
      specReminderFrame:ClearAllPoints()
      specReminderFrame:SetPoint(w.point, w.relative and _G[w.relative] or UIParent, w.relativePoint or w.point, w.x or 0, w.y or 0)
    end
    specReminderFrame:Hide()
    specReminderFrame:SetScript("OnUpdate", function(_, _elapsed)
      if specReminderHideAt and GetTime() >= specReminderHideAt then
        specReminderFrame:Hide()
        specReminderHideAt = nil
      end
    end)
  end
  local text = table.concat(lines, "\n")
  specReminderFS:SetText(text)
  if specReminderFS.SetWidth and specReminderFrame.GetWidth then
    specReminderFS:SetWidth(specReminderFrame:GetWidth() - 20)
  end
  local desiredH = (specReminderFS.GetStringHeight and (specReminderFS:GetStringHeight() + 24)) or 80
  specReminderFrame:SetHeight(math.max(60, math.min(220, desiredH)))
  specReminderFrame:Show()
  specReminderHideAt = GetTime() + 10
end

-- Assist reminder UI --------------------------------------------------------
local function ensureAssistFrame()
  if assistFrame then return assistFrame end
  assistFrame = CreateFrame("Frame", "LootWishlistAssistReminder", UIParent, "BackdropTemplate")
  assistFrame:SetSize(520, 90)
  assistFrame:SetPoint("TOP", UIParent, "TOP", 0, -410)
  assistFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  assistFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  assistFrame:SetBackdropColor(0, 0, 0, 0.85)
  assistFrame:SetBackdropBorderColor(0.4, 0.8, 1.0, 0.95)
  assistFrame:EnableMouse(true)
  assistFrame:SetMovable(true)
  assistFrame:RegisterForDrag("LeftButton")
  assistFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  assistFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if LootWishlistCharDB and self:GetPoint(1) then
      local p, rel, rp, x, y = self:GetPoint(1)
      LootWishlistCharDB.assistReminderWindow = {point=p, relative=rel and rel:GetName(), relativePoint=rp, x=x, y=y}
    end
  end)
  assistFS = assistFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  assistFS:SetPoint("TOP", 0, -8)
  assistFS:SetJustifyH("CENTER")
  assistFS:SetJustifyV("MIDDLE")
  assistFS:SetText("")

  assistBtnWhisper = CreateFrame("Button", nil, assistFrame, "UIPanelButtonTemplate")
  assistBtnParty = CreateFrame("Button", nil, assistFrame, "UIPanelButtonTemplate")
  assistBtnWhisper:SetSize(110, 22)
  assistBtnParty:SetSize(110, 22)
  assistBtnWhisper:SetText("Whisper")
  assistBtnParty:SetText("Party")
  assistBtnWhisper:SetPoint("BOTTOM", assistFrame, "BOTTOM", -70, 10)
  assistBtnParty:SetPoint("BOTTOM", assistFrame, "BOTTOM", 70, 10)

  assistBtnWhisper:SetScript("OnClick", function()
    if not lastAssistTargetName or not lastAssistMessageWhisper then assistFrame:Hide(); return end
    if ChatEdit_ChooseBoxForSend and ChatEdit_SendText and ChatEdit_ActivateChat then
      local eb = ChatEdit_ChooseBoxForSend()
      if eb then
        local prevShown = eb:IsShown()
        ChatEdit_ActivateChat(eb)
        eb:SetText(string.format("/w %s %s", lastAssistTargetName, lastAssistMessageWhisper))
        ChatEdit_SendText(eb, 0)
        eb:SetText("")
        if not prevShown then eb:Hide() end
      end
    end
    assistFrame:Hide()
  end)
  assistBtnParty:SetScript("OnClick", function()
    if not lastAssistMessageParty then assistFrame:Hide(); return end
    -- Compute group chat prefix locally to avoid dependency order issues
    local prefix = "/s"
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then prefix = "/i"
    elseif IsInRaid() then prefix = "/raid"
    elseif IsInGroup() then prefix = "/p" end
    if ChatEdit_ChooseBoxForSend and ChatEdit_SendText and ChatEdit_ActivateChat then
      local eb = ChatEdit_ChooseBoxForSend()
      if eb then
        local prevShown = eb:IsShown()
        ChatEdit_ActivateChat(eb)
        eb:SetText(prefix .. " " .. lastAssistMessageParty)
        ChatEdit_SendText(eb, 0)
        eb:SetText("")
        if not prevShown then eb:Hide() end
      end
    end
    assistFrame:Hide()
  end)

  local w = LootWishlistCharDB and LootWishlistCharDB.assistReminderWindow
  if w and w.point then
    assistFrame:ClearAllPoints()
    assistFrame:SetPoint(w.point, w.relative and _G[w.relative] or UIParent, w.relativePoint or w.point, w.x or 0, w.y or 0)
  end
  assistFrame:Hide()
  assistFrame:SetScript("OnUpdate", function()
    if assistHideAt and GetTime() >= assistHideAt then
      assistFrame:Hide()
      assistHideAt = nil
    end
  end)
  return assistFrame
end

local function ShowAssistReminder(lines, firstTargetName, firstSpecName, itemsList)
  if not lines or #lines == 0 then return end
  local f = ensureAssistFrame()
  local text = table.concat(lines, "\n")
  assistFS:SetText(text)
  if assistFS.SetWidth and f.GetWidth then
    assistFS:SetWidth(f:GetWidth() - 20)
  end
  local desiredH = (assistFS.GetStringHeight and (assistFS:GetStringHeight() + 40)) or 90
  f:SetHeight(math.max(80, math.min(240, desiredH)))
  -- Prepare default messages targeting the first suggestion
  lastAssistTargetName = firstTargetName
  if firstTargetName and firstSpecName and itemsList then
    lastAssistMessageWhisper = string.format("Hey %s, could you set your loot spec to %s for %s? It's on my wishlist.", firstTargetName, firstSpecName, itemsList)
    lastAssistMessageParty = string.format("%s, could you set loot spec to %s for %s?", firstTargetName, firstSpecName, itemsList)
  else
    lastAssistMessageWhisper, lastAssistMessageParty = nil, nil
  end
  f:Show()
  assistHideAt = GetTime() + 12
end

-- Group assist suggestion builder ------------------------------------------
local function getSpecInfoByID(specID)
  if not specID then return nil,nil,nil end
  local ok, _id, name, _desc, _icon, _role, classFile = pcall(GetSpecializationInfoByID, specID)
  if ok then return name, classFile, _id end
  return nil,nil,nil
end

local function iterateGroupUnits()
  local units = {}
  if IsInRaid() then
    local n = GetNumGroupMembers() or 0
    for i=1,n do table.insert(units, "raid"..i) end
  elseif IsInGroup() then
    local n = GetNumGroupMembers() or 0
    for i=1,math.max(0,n-1) do table.insert(units, "party"..i) end -- party1..4; player excluded below
  end
  return units
end

local function collectAssistForContext(isRaidContext, bossName, instName, ejID)
  local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked() or nil
  if not tracked or not next(tracked) then return nil end
  local units = iterateGroupUnits()
  if #units == 0 then return nil end
  local suggestions = {} -- name -> {specName, items{}}
  local firstName, firstSpec, firstItems
  -- Precompute group member classes
  local memberClass = {}
  for _, unit in ipairs(units) do
    if UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
      local name = UnitName(unit)
      local _, classFile = UnitClass(unit)
      if name and classFile then memberClass[name] = classFile end
    end
  end
  if not next(memberClass) then return nil end

  local function addSuggest(name, specName, link)
    if not suggestions[name] then suggestions[name] = {specName = specName, items = {}} end
    table.insert(suggestions[name].items, link)
  end

  for _, v in pairs(tracked) do
    if type(v) == "table" then
      local contextOK = false
      if isRaidContext then
        contextOK = v.isRaid and (v.boss == bossName)
      else
        if v.isRaid then contextOK = false else
          if ejID and v.instanceID then contextOK = (v.instanceID == ejID) else contextOK = (v.dungeon == instName) or (normalizeName(v.dungeon) == normalizeName(instName or "")) end
        end
      end
      if contextOK then
        local specs = v.specs
        if type(specs) == "table" and next(specs) then
          for _, sid in ipairs(specs) do
            local specName, classFile = getSpecInfoByID(sid)
            if specName and classFile then
              for mName, mClass in pairs(memberClass) do
                if mClass == classFile then
                  addSuggest(mName, specName, v.link or ("item:"..tostring(v.id)))
                  if not firstName then firstName, firstSpec, firstItems = mName, specName, v.link or ("item:"..tostring(v.id)) end
                end
              end
            end
          end
        end
      end
    end
  end

  if not next(suggestions) then return nil end
  -- Build lines
  local lines = { "Ask group to help with wishlist items:" }
  local sortedNames = {}
  for name in pairs(suggestions) do table.insert(sortedNames, name) end
  table.sort(sortedNames)
  for _, name in ipairs(sortedNames) do
    local s = suggestions[name]
    table.sort(s.items)
    table.insert(lines, string.format("- %s (%s): %s", name, s.specName or "Spec", table.concat(s.items, ", ")))
  end
  return lines, firstName, firstSpec, firstItems
end

-- Matching logic ------------------------------------------------------------
local function playerLootSpecMatches(specs)
  if type(specs) ~= "table" then return true end
  if not next(specs) then return true end -- treat empty as any spec
  local lsid = getLootSpecID()
  if not lsid then return true end
  for _, sid in ipairs(specs) do if sid == lsid then return true end end
  return false
end

local function collectDungeonSpecSuggestions()
  local inInstance, instType = IsInInstance()
  dprint("collectDungeonSpecSuggestions inInstance=", inInstance, "type=", instType)
  if not inInstance or instType ~= "party" then return nil end
  local instName = GetInstanceInfo and (select(1, GetInstanceInfo())) or nil
  local ejID = getCurrentEJInstanceID()
  dprint("instance=", instName or "nil", "ejID=", tostring(ejID or "nil"))
  if not instName and not ejID then return nil end
  local deDupeKey = ejID or instName
  if dungeonReminded[deDupeKey] then dprint("already reminded for", deDupeKey); return nil end
  local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked() or nil
  local tcount = 0; if tracked then for _ in pairs(tracked) do tcount = tcount + 1 end end
  dprint("tracked items=", tcount)
  if not tracked or not next(tracked) then return nil end
  local bySpec = {}
  local haveAny = false
  local lsid = getLootSpecID()
  local stayStrictItems, stayAnyItems = {}, {}
  for _, v in pairs(tracked) do
    if type(v) == "table" and (not v.isRaid) then
      local match
      if ejID and v.instanceID then
        match = (v.instanceID == ejID)
      else
        match = (v.dungeon == instName) or (normalizeName(v.dungeon) == normalizeName(instName or ""))
      end
      if match then
        dprint("candidate item", v.id, "dungeon=", v.dungeon, "instanceID=", tostring(v.instanceID or "nil"), "link=", v.link or ("item:"..tostring(v.id)))
        local specs = v.specs
        if type(specs) == "table" and next(specs) then
          dprint("specs=", table.concat((function() local tmp={} for _,sid in ipairs(specs) do table.insert(tmp, tostring(sid)) end return tmp end)(), ","), "lootSpec=", tostring(lsid or "nil"))
          if not playerLootSpecMatches(specs) then
            local suggestID
            for _, sid in ipairs(specs) do suggestID = sid; break end
            if not suggestID then -- fallback if table isn't array-like
              for _, sid in pairs(specs) do if type(sid)=="number" then suggestID = sid; break end end
            end
            local name = getSpecNameByID(suggestID) or "appropriate spec"
            if name == "" then name = "appropriate spec" end
            bySpec[name] = bySpec[name] or {}
            table.insert(bySpec[name], v.link or ("item:"..tostring(v.id)))
            haveAny = true
          else
            -- Matches current loot spec; accumulate to show a 'stay' recommendation alongside switches
            local link = v.link or ("item:"..tostring(v.id))
            if isAnySpecForPlayer(specs) then
              table.insert(stayAnyItems, link)
            else
              table.insert(stayStrictItems, link)
            end
          end
        else
          dprint("no specific specs (any spec) for", v.id)
          -- Treat as any-spec eligible
          local link = v.link or ("item:"..tostring(v.id))
          table.insert(stayAnyItems, link)
        end
      else
        dprint("skip item", v.id, "(instance mismatch)", "v.dungeon=", tostring(v.dungeon), "inst=", tostring(instName), "norm=", normalizeName(v.dungeon or ""), "vs", normalizeName(instName or ""), "v.instanceID=", tostring(v.instanceID or "nil"), "ejID=", tostring(ejID or "nil"))
      end
    end
  end
  if not haveAny then return nil end
  local lines = { "Wrong loot spec for wishlist items:" }
  for specName, items in pairs(bySpec) do
    table.sort(items)
    table.insert(lines, string.format("- Switch %s for %s", specName, table.concat(items, ", ")))
  end
  if lsid and #stayStrictItems > 0 then
    table.sort(stayStrictItems)
    local curName = getSpecNameByID(lsid) or "current spec"
    table.insert(lines, string.format("- Stay %s for %s", curName, table.concat(stayStrictItems, ", ")))
  end
  if #stayAnyItems > 0 then
    table.sort(stayAnyItems)
    table.insert(lines, string.format("- OK in any spec: %s", table.concat(stayAnyItems, ", ")))
  end
  dungeonReminded[deDupeKey] = true
  return lines
end

local function collectRaidTargetSpecSuggestions()
  local inInstance, instType = IsInInstance()
  dprint("collectRaidTargetSpecSuggestions inInstance=", inInstance, "type=", instType)
  if not inInstance or instType ~= "raid" then return nil end
  if not UnitExists("target") then dprint("no target"); return nil end
  local targetName = UnitName("target")
  if not targetName then return nil end
  local instName = GetInstanceInfo and (select(1, GetInstanceInfo())) or ""
  local key = instName .. "|" .. targetName
  if bossReminded[key] then dprint("already reminded for", key); return nil end
  local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked() or nil
  if not tracked or not next(tracked) then return nil end
  local bySpec = {}
  local haveAny = false
  local lsid = getLootSpecID()
  local stayStrictItems, stayAnyItems = {}, {}
  for _, v in pairs(tracked) do
    if type(v) == "table" and v.isRaid and (v.boss == targetName) then
      local specs = v.specs
      if type(specs) == "table" and next(specs) then
        dprint("boss item", v.id, "specs:", table.concat((function() local tmp={} for _,sid in ipairs(specs) do table.insert(tmp, tostring(sid)) end return tmp end)(), ","), "lootSpec=", tostring(lsid or "nil"))
        if not playerLootSpecMatches(specs) then
          local suggestID
          for _, sid in ipairs(specs) do suggestID = sid; break end
          if not suggestID then -- fallback if table isn't array-like
            for _, sid in pairs(specs) do if type(sid)=="number" then suggestID = sid; break end end
          end
          local name = getSpecNameByID(suggestID) or "appropriate spec"
          if name == "" then name = "appropriate spec" end
          bySpec[name] = bySpec[name] or {}
          table.insert(bySpec[name], v.link or ("item:"..tostring(v.id)))
          haveAny = true
        else
          local link = v.link or ("item:"..tostring(v.id))
          if isAnySpecForPlayer(specs) then
            table.insert(stayAnyItems, link)
          else
            table.insert(stayStrictItems, link)
          end
        end
      else
        dprint("no specific specs (any spec) for", v.id)
        local link = v.link or ("item:"..tostring(v.id))
        table.insert(stayAnyItems, link)
      end
    end
  end
  if not haveAny then return nil end
  local lines = { "Wrong loot spec for wishlist items:" }
  for specName, items in pairs(bySpec) do
    table.sort(items)
    table.insert(lines, string.format("- Switch %s for %s", specName, table.concat(items, ", ")))
  end
  if lsid and #stayStrictItems > 0 then
    table.sort(stayStrictItems)
    local curName = getSpecNameByID(lsid) or "current spec"
    table.insert(lines, string.format("- Stay %s for %s", curName, table.concat(stayStrictItems, ", ")))
  end
  if #stayAnyItems > 0 then
    table.sort(stayAnyItems)
    table.insert(lines, string.format("- OK in any spec: %s", table.concat(stayAnyItems, ", ")))
  end
  bossReminded[key] = true
  return lines
end

-- Get the number of a given itemID in the player's bags (excluding bank)
local function getInventoryCount(itemID)
  if not itemID then return 0 end
  local total = 0
  if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
    local maxBag = (NUM_BAG_SLOTS or 4)
    for bag = 0, maxBag do
      local slots = C_Container.GetContainerNumSlots(bag) or 0
      for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID == itemID then
          total = total + (info.stackCount or 1)
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
        end
      end
    end
    return total
  end
  return 0
end
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
local currentDifficultyID, currentDifficultyName

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
      if LootWishlist.RemoveTrackedItem then LootWishlist.RemoveTrackedItem(itemID, currentDifficultyID) end
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

local function ShowDropAlertWithContext(itemLink, isSelf, looterName, itemID, difficultyID, difficultyName)
  ShowDropAlert(itemLink)
  if isSelf then
    configureSelfActions(itemID, itemLink)
  else
    configureOtherActions(looterName, itemID, itemLink)
  end
  currentItemID, currentItemLink, currentLooter, currentIsSelf = itemID, itemLink, looterName, isSelf
  currentDifficultyID, currentDifficultyName = difficultyID, difficultyName
  if isSelf and itemID then
    recentSelfAlertAt[itemID] = GetTime()
  end
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
  if not t then return false end
  for k, v in pairs(t) do
    local vid = (type(v) == "table" and v.id) or nil
    if vid and vid == itemID then return true end
    -- Back-compat: legacy numeric or string keys without id field
    if type(k) == "number" and k == itemID then return true end
    if type(k) == "string" then
      local nk = tonumber(k)
      if nk and nk == itemID then return true end
    end
  end
  return false
end

-- Event handling
local ef = CreateFrame("Frame")
ef:RegisterEvent("CHAT_MSG_LOOT")
ef:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
ef:RegisterEvent("START_LOOT_ROLL")
ef:RegisterEvent("BAG_UPDATE_DELAYED")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ef:RegisterEvent("PLAYER_TARGET_CHANGED")
ef:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_LOOT" then
    local msg = ...
    local inRaid = IsInRaid() or (IsInGroup() and IsInInstance() and select(2, IsInInstance()) == "raid")
    local isSelf, looter = extractLooterFromChat(msg)
    if isSelf == nil then return end -- couldn't determine: avoid false prompts
    for _, link in ipairs(extractLinks(msg)) do
      local itemID = parseItemIDFromLink(link)
      if itemID and isTracked(itemID) then
        if isWarboundItemLink(link) then dprint("skip warbound drop", link); return end
        if inRaid then
          -- In raids, suppress the action/party-whisper alert and the simple raid drop banner.
          -- We'll rely on the START_LOOT_ROLL reminder popup instead.
        else
          local diffID, diffName = getCurrentInstanceDifficulty()
          if isSelf then
            ShowDropAlertWithContext(link, true, UnitName("player"), itemID, diffID, diffName)
          else
            ShowDropAlertWithContext(link, false, looter, itemID, diffID, diffName)
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
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return end
    if not isTracked(itemID) then return end
    ShowRaidRollAlert(itemLink)
  elseif event == "PLAYER_LOGIN" then
    -- Initialize baseline bag counts for tracked items
    local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked() or nil
    if tracked then
      for _, v in pairs(tracked) do
        local iid = v and v.id
        if type(iid) == "number" then bagCounts[iid] = getInventoryCount(iid) end
      end
    end
  elseif event == "BAG_UPDATE_DELAYED" then
    -- Detect when a tracked item newly appears in your bags (e.g., trade),
    -- and prompt to remove it from the wishlist with a self-style alert.
    local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked() or nil
    if not tracked or not next(tracked) then return end
    for _, info in pairs(tracked) do
      local iid = info and info.id or nil
      if type(iid) == "number" then
        local current = getInventoryCount(iid)
        local prev = bagCounts[iid]
        if prev == nil then
          -- Establish baseline without alerting the first time we see it
          bagCounts[iid] = current
        else
          if (current or 0) > (prev or 0) then
            bagCounts[iid] = current
            -- Avoid duplicate prompt immediately after a self-loot alert
            local last = recentSelfAlertAt[iid] or 0
            if (GetTime() - last) > 8 then
              local function withLink(l)
                if l and isWarboundItemLink(l) then return end
                local diffID, diffName = getCurrentInstanceDifficulty()
                ShowDropAlertWithContext(l or ("item:"..tostring(iid)), true, UnitName("player"), iid, diffID, diffName)
              end
              if info and info.link then
                withLink(info.link)
              else
                getItemLinkAsync(iid, withLink)
              end
            end
          else
            -- Keep baseline up to date
            bagCounts[iid] = current
          end
        end
      end
    end
  elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    dprint("event:", event)
    -- Detect leaving an instance and reset de-dupers so re-entry can show again
    local nowIn, nowType = IsInInstance()
    if lastInInstance == nil then
      -- First observation
      lastInInstance, lastInstanceType = nowIn, nowType
    else
      if lastInInstance and not nowIn then
        dprint("left instance; resetting spec reminder dedupers")
        if wipe then
          wipe(dungeonReminded)
          wipe(bossReminded)
        else
          dungeonReminded = {}
          bossReminded = {}
        end
      end
      lastInInstance, lastInstanceType = nowIn, nowType
    end
    local lines = collectDungeonSpecSuggestions()
    if lines then ShowSpecReminder(lines) else
      -- Slight delay retry to allow instance info to settle
      if C_Timer and C_Timer.After then
        C_Timer.After(1.0, function()
          local l2 = collectDungeonSpecSuggestions()
          if l2 then ShowSpecReminder(l2) end
        end)
      end
    end
    -- Assist suggestions for dungeon context
    do
      local instName = GetInstanceInfo and (select(1, GetInstanceInfo())) or nil
      local ejID = getCurrentEJInstanceID()
      local key = ejID or instName
      if key and not assistDungeonReminded[key] then
        local lines2, tName, tSpec, tItems = collectAssistForContext(false, nil, instName, ejID)
        if lines2 then
          ShowAssistReminder(lines2, tName, tSpec, tItems)
          assistDungeonReminded[key] = true
        end
      end
    end
  elseif event == "PLAYER_TARGET_CHANGED" then
    dprint("event: PLAYER_TARGET_CHANGED")
    local lines = collectRaidTargetSpecSuggestions()
    if lines then ShowSpecReminder(lines) end
    -- Assist suggestions for raid boss context
    do
      local targetName = UnitName("target")
      local instName = GetInstanceInfo and (select(1, GetInstanceInfo())) or ""
      local key = instName .. "|" .. tostring(targetName or "")
      if targetName and not assistBossReminded[key] then
        local lines2, tName, tSpec, tItems = collectAssistForContext(true, targetName, instName, nil)
        if lines2 then
          ShowAssistReminder(lines2, tName, tSpec, tItems)
          assistBossReminded[key] = true
        end
      end
    end
  end
end)

-- Public API
function Alerts.ResetSpecReminderDebounce()
  if wipe then
    wipe(dungeonReminded)
    wipe(bossReminded)
    wipe(assistDungeonReminded)
    wipe(assistBossReminded)
  else
    dungeonReminded = {}
    bossReminded = {}
    assistDungeonReminded = {}
    assistBossReminded = {}
  end
  -- Also forget last instance state to avoid immediate re-blocking
  lastInInstance, lastInstanceType = nil, nil
  dprint("Spec reminder debounce reset")
end

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
