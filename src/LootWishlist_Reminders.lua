-- Loot Wishlist: loot-spec and group-assist reminder runtime.

LootWishlist = LootWishlist or {}
LootWishlist.Reminders = LootWishlist.Reminders or {}

local Reminders = LootWishlist.Reminders
local S = LootWishlist.Strings.reminders
local Planner = LootWishlist.ReminderPlanner

local db
local eventFrame
local dungeonReminderFrame, specText, assistText, divider
local whisperButton, partyButton, dismissButton
local assistTargetName, assistWhisperMessage, assistPartyMessage
local dungeonReminded = {}
local bossReminded = {}
local assistDungeonReminded = {}
local lastInInstance
local raidCheckPending = false
local bossRows = {}
local bossTitle
local shownAssist
local shownIgnoreGates = false
local MAX_ROW_ITEMS = 8
local raidCheckWaits = 0
local scheduleRaidCheck

local MAX_ODDS_WAITS  = 3
local ODDS_WAIT_DELAY = 4
local HIDE_AFTER      = 15

local function dprint(...)
    if not (LootWishlist.IsDebug and LootWishlist.IsDebug()) then return end
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring(select(index, ...))
    end
    print("[LootWishlist] " .. table.concat(parts, " "))
end

local function getCurrentSpecID()
    if not GetSpecialization then return nil end
    local index = GetSpecialization()
    if not index then return nil end
    local ok, specID = pcall(GetSpecializationInfo, index)
    return ok and type(specID) == "number" and specID or nil
end

local function getLootSpecID()
    if GetLootSpecialization then
        local specID = GetLootSpecialization()
        if specID and specID ~= 0 then return specID end
    end
    return getCurrentSpecID()
end

local function getSpecName(specID)
    if not specID then return nil end
    local ok, _, name = pcall(GetSpecializationInfoByID, specID)
    if ok and type(name) == "string" and name ~= "" then return name end
    return tostring(specID)
end

local ownSpecCache

local function ownSpecs()
    if ownSpecCache then return ownSpecCache end

    local specs = {}
    for index = 1, (GetNumSpecializations and GetNumSpecializations() or 0) do
        local ok, specID, name, _, icon = pcall(GetSpecializationInfo, index)
        if ok and type(specID) == "number" then
            table.insert(specs, { id = specID, name = name, icon = icon })
        end
    end

    -- Specs read as none until the character is loaded, so an empty read is not
    -- cached as the answer.
    if #specs > 0 then ownSpecCache = specs end
    return specs
end

local function getSpecInfo(specID)
    if not specID then return nil, nil end
    local ok, _, name, _, _, _, classFile = pcall(GetSpecializationInfoByID, specID)
    if ok then return name, classFile end
    return nil, nil
end

local function getCurrentEJInstanceID()
    local mapID = GetInstanceInfo and select(8, GetInstanceInfo()) or nil
    local uiMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local getInstanceForMap = _G and _G.EJ_GetInstanceForMap
    if type(getInstanceForMap) ~= "function" then return nil end

    local candidates = {}
    if mapID then candidates[#candidates + 1] = mapID end
    if uiMapID and uiMapID ~= mapID then candidates[#candidates + 1] = uiMapID end

    for _, candidate in ipairs(candidates) do
        if candidate then
            local ok, instanceID = pcall(getInstanceForMap, candidate)
            if ok and type(instanceID) == "number" and instanceID > 0 then return instanceID end
        end
    end
    return nil
end

LootWishlist.GetCurrentEJInstanceID = getCurrentEJInstanceID

local function ensureReminderFrame()
    if dungeonReminderFrame then return dungeonReminderFrame end

    dungeonReminderFrame = CreateFrame("Frame", "LootWishlistDungeonReminder", UIParent, "BackdropTemplate")
    dungeonReminderFrame:SetSize(560, 80)
    dungeonReminderFrame:SetPoint("TOP", UIParent, "TOP", 0, -340)
    dungeonReminderFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    dungeonReminderFrame:SetBackdrop(LuckyUI.Backdrop)
    dungeonReminderFrame:SetBackdropColor(LuckyUI.C.bgDark[1], LuckyUI.C.bgDark[2], LuckyUI.C.bgDark[3], 0.95)
    dungeonReminderFrame:EnableMouse(true)
    dungeonReminderFrame:SetMovable(true)
    dungeonReminderFrame:RegisterForDrag("LeftButton")
    dungeonReminderFrame:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    dungeonReminderFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        if db and frame:GetPoint(1) then
            local point, relative, relativePoint, x, y = frame:GetPoint(1)
            db.dungeonReminderWindow = {
                point = point,
                relative = relative and relative:GetName(),
                relativePoint = relativePoint,
                x = x,
                y = y,
            }
        end
    end)

    bossTitle = dungeonReminderFrame:CreateFontString(nil, "OVERLAY")
    bossTitle:SetFont(LuckyUI.TITLE_FONT, 14)
    bossTitle:SetTextColor(LuckyUI.C.goldAccent[1], LuckyUI.C.goldAccent[2], LuckyUI.C.goldAccent[3])
    bossTitle:SetPoint("TOP", 0, -8)
    bossTitle:Hide()

    specText = dungeonReminderFrame:CreateFontString(nil, "OVERLAY")
    specText:SetFont(LuckyUI.BODY_FONT, 13)
    specText:SetTextColor(LuckyUI.C.textLight[1], LuckyUI.C.textLight[2], LuckyUI.C.textLight[3])
    specText:SetPoint("TOP", 0, -8)
    specText:SetJustifyH("CENTER")
    specText:SetJustifyV("TOP")

    divider = dungeonReminderFrame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.23, 0.18, 0.10, 0.8)
    divider:SetHeight(1)
    divider:SetPoint("LEFT", 12, 0)
    divider:SetPoint("RIGHT", -12, 0)
    divider:Hide()

    assistText = dungeonReminderFrame:CreateFontString(nil, "OVERLAY")
    assistText:SetFont(LuckyUI.BODY_FONT, 13)
    assistText:SetTextColor(LuckyUI.C.textLight[1], LuckyUI.C.textLight[2], LuckyUI.C.textLight[3])
    assistText:SetJustifyH("CENTER")
    assistText:SetJustifyV("TOP")

    whisperButton = LuckyUI.CreateButton(dungeonReminderFrame, "Whisper", 110, 22, "primary")
    partyButton = LuckyUI.CreateButton(dungeonReminderFrame, "Party", 110, 22, "secondary")
    dismissButton = LuckyUI.CreateButton(dungeonReminderFrame, "Dismiss", 110, 22, "secondary")

    whisperButton:SetScript("OnClick", function()
        if not assistTargetName or not assistWhisperMessage then
            dungeonReminderFrame:Hide()
            return
        end
        if ChatEdit_ChooseBoxForSend and ChatEdit_SendText and ChatEdit_ActivateChat then
            local editBox = ChatEdit_ChooseBoxForSend()
            if editBox then
                local wasShown = editBox:IsShown()
                ChatEdit_ActivateChat(editBox)
                editBox:SetText(string.format("/w %s %s", assistTargetName, assistWhisperMessage))
                ChatEdit_SendText(editBox, 0)
                editBox:SetText("")
                if not wasShown then editBox:Hide() end
            end
        end
        dungeonReminderFrame:Hide()
    end)

    partyButton:SetScript("OnClick", function()
        if not assistPartyMessage then
            dungeonReminderFrame:Hide()
            return
        end
        local prefix = "/s"
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then prefix = "/i"
        elseif IsInRaid() then prefix = "/raid"
        elseif IsInGroup() then prefix = "/p" end

        if ChatEdit_ChooseBoxForSend and ChatEdit_SendText and ChatEdit_ActivateChat then
            local editBox = ChatEdit_ChooseBoxForSend()
            if editBox then
                local wasShown = editBox:IsShown()
                ChatEdit_ActivateChat(editBox)
                editBox:SetText(prefix .. " " .. assistPartyMessage)
                ChatEdit_SendText(editBox, 0)
                editBox:SetText("")
                if not wasShown then editBox:Hide() end
            end
        end
        dungeonReminderFrame:Hide()
    end)

    dismissButton:SetScript("OnClick", function()
        dungeonReminderFrame:StopAutoHide()
        dungeonReminderFrame:Hide()
    end)

    local position = db and (db.dungeonReminderWindow or db.specReminderWindow)
    if position and position.point then
        dungeonReminderFrame:ClearAllPoints()
        dungeonReminderFrame:SetPoint(
            position.point,
            position.relative and _G[position.relative] or UIParent,
            position.relativePoint or position.point,
            position.x or 0,
            position.y or 0
        )
    end

    dungeonReminderFrame:Hide()
    LuckyUI.EnableAutoHide(dungeonReminderFrame, HIDE_AFTER)
    return dungeonReminderFrame
end

local ROW_HEIGHT   = 60
local ROW_INSET    = 14
local BOSS_ICON    = ROW_HEIGHT - 4  -- fills the row's height, so the two cannot drift apart
local ITEM_ICON    = 28
local ITEM_GAP     = 3
local NAME_INSET   = BOSS_ICON + 10
local TITLE_HEIGHT = 26
local BLOCKED_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

-- The journal's instance art is 175x95 inside a 256x128 file and the rest is
-- empty, which is why drawing the whole file leaves the dungeon in a corner of
-- its own icon. Blizzard reads it at 0.684 by 0.742; this is that art's middle
-- square, so it fills a square slot without squashing.
local INSTANCE_ART = { 0.15625, 0.52734375, 0, 0.7421875 }

local function bossIconTexture(encounterID)
    local ok, _, _, _, _, iconImage = pcall(EJ_GetCreatureInfo, 1, encounterID)
    return (ok and iconImage) or "Interface\\EncounterJournal\\UI-EJ-BOSS-Default"
end

local function itemIconTexture(itemID)
    local texture = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    return texture or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function itemButton(row, index)
    local button = row.itemButtons[index]
    if button then return button end

    button = CreateFrame("Button", nil, row)
    button:SetSize(ITEM_ICON, ITEM_ICON)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Greying alone reads as "already have it", so what your loot spec cannot be
    -- given is struck through as well.
    button.blocked = button:CreateTexture(nil, "OVERLAY")
    button.blocked:SetTexture(BLOCKED_ICON)
    button.blocked:SetSize(ITEM_ICON * 0.8, ITEM_ICON * 0.8)
    button.blocked:SetPoint("CENTER")
    button.blocked:Hide()
    button:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        if self.specLabel then
            GameTooltip:AddLine(S.needsSpec:format(self.specLabel),
                LuckyUI.C.goldPrimary[1], LuckyUI.C.goldPrimary[2], LuckyUI.C.goldPrimary[3])
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.itemButtons[index] = button
    return button
end

local function ensureRow(index)
    local row = bossRows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, dungeonReminderFrame)
    row:SetHeight(ROW_HEIGHT)
    row.itemButtons = {}

    row.bossIcon = row:CreateTexture(nil, "ARTWORK")
    row.bossIcon:SetSize(BOSS_ICON, BOSS_ICON)
    row.bossIcon:SetPoint("LEFT", 0, 0)
    -- Journal creature art is twice as wide as it is tall, so a square frame
    -- squashes it. The middle square is taken instead, which is where the boss is.
    row.bossIcon:SetTexCoord(0.25, 0.75, 0, 1)

    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFont(LuckyUI.TITLE_FONT, 13)
    row.name:SetTextColor(LuckyUI.C.goldPrimary[1], LuckyUI.C.goldPrimary[2], LuckyUI.C.goldPrimary[3])
    row.name:SetPoint("TOPLEFT", NAME_INSET, -6)
    row.name:SetJustifyH("LEFT")

    row.odds = row:CreateFontString(nil, "OVERLAY")
    row.odds:SetFont(LuckyUI.BODY_FONT, 12)
    row.odds:SetTextColor(LuckyUI.C.goldAccent[1], LuckyUI.C.goldAccent[2], LuckyUI.C.goldAccent[3])
    row.odds:SetPoint("TOPRIGHT", 0, -5)
    row.odds:SetJustifyH("RIGHT")

    row.advice = row:CreateFontString(nil, "OVERLAY")
    row.advice:SetFont(LuckyUI.BODY_FONT, 12)
    row.advice:SetTextColor(LuckyUI.C.textLight[1], LuckyUI.C.textLight[2], LuckyUI.C.textLight[3])
    row.advice:SetJustifyH("LEFT")
    -- Anchored to both edges of what the icons leave, so a long spec list clips
    -- rather than wrapping down into the next row.
    row.advice:SetWordWrap(false)

    bossRows[index] = row
    return row
end

-- What the charge is worth where you stand, and what it would be worth after
-- taking the switch this row is asking for.
local function oddsText(data)
    local odds = data.odds
    if not odds then return "" end
    if not odds.best then
        return odds.wanted > 0 and S.rollOdds:format(odds.percent) or ""
    end
    return S.rollOddsSpec:format(odds.percent, odds.best.percent, odds.best.name)
end

local function paintRow(row, data)
    if data.icon then
        row.bossIcon:SetTexCoord(unpack(INSTANCE_ART))
    else
        row.bossIcon:SetTexCoord(0.25, 0.75, 0, 1)
    end
    row.bossIcon:SetTexture(data.icon or bossIconTexture(data.encounterID))
    row.name:SetText(data.boss)
    row.odds:SetText(oddsText(data))

    local shown, marked = 0, 0
    for index, item in ipairs(data.items) do
        if index > MAX_ROW_ITEMS then break end
        local button = itemButton(row, index)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", NAME_INSET + (index - 1) * (ITEM_ICON + ITEM_GAP), -28)
        button.link = item.link or ("item:" .. tostring(item.id))
        button.specLabel = item.specLabel
        button.icon:SetTexture(itemIconTexture(item.id))
        button.icon:SetDesaturated(item.needsSwitch and true or false)
        button.blocked:SetShown(item.needsSwitch and true or false)
        button:Show()
        shown = index
        if item.needsSwitch then marked = marked + 1 end
    end
    for index = shown + 1, #row.itemButtons do row.itemButtons[index]:Hide() end

    local parts = {}
    local hidden = #data.items - shown
    if hidden > 0 then table.insert(parts, S.moreItems:format(hidden)) end
    -- Naming the marked items rather than telling the player to switch: the
    -- other spec buys those and gives up whatever is not marked, which is a
    -- trade only they can weigh.
    if data.switchTo and marked > 0 then
        local phrase = marked == 1 and S.markedOne or S.markedMany
        table.insert(parts, phrase:format(data.switchTo))
    end

    row.advice:SetText(table.concat(parts, "  "))
    row.advice:ClearAllPoints()
    row.advice:SetPoint("TOPLEFT", NAME_INSET + shown * (ITEM_ICON + ITEM_GAP) + 8, -35)
    row.advice:SetPoint("TOPRIGHT", 0, -35)
end

local SPEC_ICON   = 30
local SPEC_GAP    = 10
local SPEC_BOTTOM = 40
local specButtons = {}

local function specButton(index)
    local button = specButtons[index]
    if button then return button end

    button = CreateFrame("Button", nil, dungeonReminderFrame)
    button:SetSize(SPEC_ICON, SPEC_ICON)

    button.ring = button:CreateTexture(nil, "BACKGROUND")
    button.ring:SetColorTexture(LuckyUI.C.goldAccent[1], LuckyUI.C.goldAccent[2], LuckyUI.C.goldAccent[3])
    button.ring:SetPoint("TOPLEFT", -2, 2)
    button.ring:SetPoint("BOTTOMRIGHT", 2, -2)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.specName or "")
        local line = self.specID == getLootSpecID() and S.currentLootSpec
            or S.switchToSpec:format(self.specName or "")
        GameTooltip:AddLine(line, LuckyUI.C.goldPrimary[1], LuckyUI.C.goldPrimary[2], LuckyUI.C.goldPrimary[3])
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self)
        if self.specID then SetLootSpecialization(self.specID) end
    end)

    specButtons[index] = button
    return button
end

local function hideSpecStrip()
    for _, button in ipairs(specButtons) do button:Hide() end
end

-- Every loot spec the character has, so the switch the rows are asking for is a
-- click rather than a trip to the talent frame. The one in use is ringed and the
-- rest greyed. Returns the height taken.
local function layoutSpecStrip(frame)
    local specs = ownSpecs()
    if #specs == 0 then
        hideSpecStrip()
        return 0
    end

    local width = #specs * SPEC_ICON + (#specs - 1) * SPEC_GAP
    local current = getLootSpecID()
    local x = (SPEC_ICON - width) / 2

    for index, spec in ipairs(specs) do
        local button = specButton(index)
        button.specID = spec.id
        button.specName = spec.name
        button.icon:SetTexture(spec.icon)
        button.icon:SetDesaturated(spec.id ~= current)
        button.ring:SetShown(spec.id == current)
        button:ClearAllPoints()
        button:SetPoint("BOTTOM", frame, "BOTTOM", x, SPEC_BOTTOM)
        button:Show()
        x = x + SPEC_ICON + SPEC_GAP
    end
    for index = #specs + 1, #specButtons do specButtons[index]:Hide() end
    return SPEC_ICON + 8
end

local function setAssistMessages(targetName, targetSpec, items)
    assistTargetName = targetName
    if targetName and targetSpec and items then
        assistWhisperMessage = S.assistWhisper:format(targetName, targetSpec, items)
        assistPartyMessage = S.assistParty:format(targetName, targetSpec, items)
    else
        assistWhisperMessage, assistPartyMessage = nil, nil
    end
end

local function hideBossRows()
    for _, row in ipairs(bossRows) do row:Hide() end
    if bossTitle then bossTitle:Hide() end
    hideSpecStrip()
end

local function showBossReminder(opts)
    local rows = opts.rows
    if not rows or #rows == 0 then return end
    shownAssist = opts.assist

    local frame = ensureReminderFrame()
    specText:SetText("")
    specText:Hide()
    divider:Hide()
    frame:SetBackdropBorderColor(LuckyUI.C.goldAccent[1], LuckyUI.C.goldAccent[2], LuckyUI.C.goldAccent[3], 0.9)

    bossTitle:SetText(S.upcomingTitle)
    bossTitle:Show()

    local top = TITLE_HEIGHT

    for index, data in ipairs(rows) do
        local row = ensureRow(index)
        row:ClearAllPoints()
        local y = -(top + (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", ROW_INSET, y)
        row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -ROW_INSET, y)
        paintRow(row, data)
        row:Show()
    end
    for index = #rows + 1, #bossRows do bossRows[index]:Hide() end

    local height = top + #rows * ROW_HEIGHT
    local assist = opts.assist
    if assist then
        assistText:SetWidth(frame:GetWidth() - 20)
        assistText:SetText(table.concat(assist.lines, "\n"))
        assistText:ClearAllPoints()
        assistText:SetPoint("TOP", frame, "TOP", 0, -(height + 8))
        assistText:Show()
        height = height + 8 + assistText:GetStringHeight()
        setAssistMessages(assist.firstTargetName, assist.firstSpecName, assist.firstItems)

        whisperButton:ClearAllPoints()
        partyButton:ClearAllPoints()
        dismissButton:ClearAllPoints()
        whisperButton:SetPoint("BOTTOM", frame, "BOTTOM", -120, 10)
        partyButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
        dismissButton:SetPoint("BOTTOM", frame, "BOTTOM", 120, 10)
        whisperButton:Show()
        partyButton:Show()
    else
        assistText:SetText("")
        assistText:Hide()
        whisperButton:Hide()
        partyButton:Hide()
        setAssistMessages(nil)
        dismissButton:ClearAllPoints()
        dismissButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    end

    frame:SetHeight(height + 42 + layoutSpecStrip(frame))
    frame:Show()
    frame:StartAutoHide(HIDE_AFTER)
end

local function showReminder(specLines, assistLines, targetName, targetSpec, items)
    local hasSpec = specLines and #specLines > 0
    local hasAssist = assistLines and #assistLines > 0
    if not hasSpec and not hasAssist then return end

    local frame = ensureReminderFrame()
    hideBossRows()
    local textWidth = frame:GetWidth() - 20
    if hasSpec and hasAssist then
        frame:SetBackdropBorderColor(LuckyUI.C.goldAccent[1], LuckyUI.C.goldAccent[2], LuckyUI.C.goldAccent[3], 0.9)
    elseif hasSpec then
        frame:SetBackdropBorderColor(LuckyUI.C.success[1], LuckyUI.C.success[2], LuckyUI.C.success[3], 0.9)
    else
        frame:SetBackdropBorderColor(LuckyUI.C.info[1], LuckyUI.C.info[2], LuckyUI.C.info[3], 0.9)
    end

    local contentHeight = 0
    if hasSpec then
        specText:SetWidth(textWidth)
        specText:SetText(table.concat(specLines, "\n"))
        specText:Show()
        contentHeight = contentHeight + specText:GetStringHeight()
    else
        specText:SetText("")
        specText:Hide()
    end

    if hasSpec and hasAssist then
        divider:ClearAllPoints()
        divider:SetPoint("TOP", specText, "BOTTOM", 0, -6)
        divider:Show()
        assistText:ClearAllPoints()
        assistText:SetPoint("TOP", divider, "BOTTOM", 0, -6)
        contentHeight = contentHeight + 12
    elseif hasAssist then
        divider:Hide()
        assistText:ClearAllPoints()
        assistText:SetPoint("TOP", frame, "TOP", 0, -8)
    else
        divider:Hide()
    end

    if hasAssist then
        assistText:SetWidth(textWidth)
        assistText:SetText(table.concat(assistLines, "\n"))
        assistText:Show()
        contentHeight = contentHeight + assistText:GetStringHeight()
    else
        assistText:SetText("")
        assistText:Hide()
    end

    if hasAssist then
        whisperButton:ClearAllPoints()
        partyButton:ClearAllPoints()
        dismissButton:ClearAllPoints()
        whisperButton:SetPoint("BOTTOM", frame, "BOTTOM", -120, 10)
        partyButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
        dismissButton:SetPoint("BOTTOM", frame, "BOTTOM", 120, 10)
        whisperButton:Show()
        partyButton:Show()
    else
        dismissButton:ClearAllPoints()
        dismissButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
        whisperButton:Hide()
        partyButton:Hide()
    end

    setAssistMessages(targetName, targetSpec, items)

    frame:SetHeight(math.max(80, math.min(320, 8 + contentHeight + 42)))
    frame:Show()
    frame:StartAutoHide(HIDE_AFTER)
end

local function groupMembers()
    local units = {}
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() or 0 do table.insert(units, "raid" .. index) end
    elseif IsInGroup() then
        for index = 1, math.max(0, (GetNumGroupMembers() or 0) - 1) do
            table.insert(units, "party" .. index)
        end
    end

    local members = {}
    for _, unit in ipairs(units) do
        if UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
            local name = UnitName(unit)
            local _, classFile = UnitClass(unit)
            if name and classFile then table.insert(members, { name = name, classFile = classFile }) end
        end
    end
    return members
end

local function collectAssist(instanceName, instanceID)
    local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked()
    if not tracked or not next(tracked) then return nil end
    local members = groupMembers()
    if #members == 0 then return nil end
    return Planner:BuildAssistSuggestions(tracked, {
        isRaid = false,
        instanceName = instanceName,
        instanceID = instanceID,
        members = members,
        getSpecInfo = getSpecInfo,
    })
end

local function bossList(ejInstanceID)
    EJ_SelectInstance(ejInstanceID)
    local bosses = {}
    local index = 1
    while true do
        local name, _, encounterID = EJ_GetEncounterInfoByIndex(index, ejInstanceID)
        if not name then break end
        table.insert(bosses, { encounterID = encounterID, name = name })
        index = index + 1
    end
    return bosses
end

local function killedFromLockout(bosses, instanceName, difficultyID)
    local killedNames = {}
    for savedIndex = 1, GetNumSavedInstances() do
        local savedName, _, _, savedDifficulty = GetSavedInstanceInfo(savedIndex)
        if savedName == instanceName and savedDifficulty == difficultyID then
            for encounterIndex = 1, 20 do
                local bossName, _, killed = GetSavedInstanceEncounterInfo(savedIndex, encounterIndex)
                if not bossName then break end
                if killed then killedNames[bossName] = true end
            end
        end
    end

    local killedIDs = {}
    for _, boss in ipairs(bosses) do
        if killedNames[boss.name] then killedIDs[boss.encounterID] = true end
    end
    return killedIDs
end

-- Alive bosses whose prerequisites are all dead. A raid with no layout has no
-- prerequisites to meet, so everything still alive counts as available.
local function availableFrom(ejInstanceID, bosses, killedIDs)
    local layout = LootWishlist.Const.RAID_LAYOUTS[ejInstanceID]
    local available = {}
    for _, boss in ipairs(bosses) do
        if not killedIDs[boss.encounterID] then
            local prerequisites = layout and layout[boss.encounterID]
            local allMet = true
            for _, requiredID in ipairs(prerequisites or {}) do
                if not killedIDs[requiredID] then
                    allMet = false
                    break
                end
            end
            if allMet then available[boss.name] = boss.encounterID end
        end
    end
    return available
end

local function getAvailableRaidBosses()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "raid" then return nil end

    local instanceName, _, difficultyID = GetInstanceInfo()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID or not EJ_GetInstanceForMap then return nil end
    local ok, ejInstanceID = pcall(EJ_GetInstanceForMap, mapID)
    if not ok or type(ejInstanceID) ~= "number" or ejInstanceID <= 0 then return nil end

    local bosses = bossList(ejInstanceID)
    if #bosses == 0 then return nil end

    return availableFrom(ejInstanceID, bosses, killedFromLockout(bosses, instanceName, difficultyID))
end

local function collectBonusRollOdds(availableBosses, ignoreCharges)
    local Odds = LootWishlist.BonusRollOdds
    local BR = LootWishlist.BonusRoll
    if not (Odds and Odds.ForUpcoming and Odds.Enabled() and BR) then return nil, true end
    if not ignoreCharges and BR.GetCharges() < BR.RAID_COST then return nil, true end

    local bosses = {}
    for name, encounterID in pairs(availableBosses) do
        table.insert(bosses, { name = name, encounterID = encounterID })
    end
    table.sort(bosses, function(a, b) return a.name < b.name end)
    return Odds.ForUpcoming(getCurrentEJInstanceID(), bosses)
end

-- A boss earns a row when its loot needs a different spec, or when a charge
-- would buy something there. A boss you track nothing on says nothing.
local function worthShowing(row)
    if row.switchTo then return true end
    local odds = row.odds
    return odds ~= nil and (odds.wanted > 0 or odds.best ~= nil)
end

local function buildBossRows(availableBosses, odds, keepAll)
    local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked()
    if not tracked or not next(tracked) then return {} end

    local rows = Planner:BuildBossRows(tracked, {
        availableBosses = availableBosses,
        lootSpecID = getLootSpecID(),
        getSpecName = getSpecName,
    })

    local kept = {}
    for _, row in ipairs(rows) do
        row.odds = odds and odds[row.encounterID]
        if keepAll or worthShowing(row) then table.insert(kept, row) end
    end
    return kept
end

-- giveUp drops the odds rather than waiting any longer on a loot table the
-- journal is still reading, so the spec advice is not held up by them.
local function keystoneLevel()
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local level = C_ChallengeMode.GetActiveKeystoneInfo()
        if type(level) == "number" then return level end
    end
    return 0
end

-- A keystone roll buys the whole dungeon, so the odds belong over the rows
-- rather than against a boss that cannot be rolled on by itself.
local function dungeonRollOdds(instanceID, ignoreGates)
    local Odds = LootWishlist.BonusRollOdds
    local BR = LootWishlist.BonusRoll
    if not (Odds and Odds.ForInstance and Odds.Enabled() and BR) then return nil, true end
    if not ignoreGates then
        if BR.GetCharges() < BR.DUNGEON_COST then return nil, true end
        if keystoneLevel() < BR.MIN_KEYSTONE_LEVEL then return nil, true end
    end
    return Odds.ForInstance(instanceID)
end

-- A keystone charge buys the whole dungeon, so its wishlist items sit on one
-- row under the dungeon rather than split across bosses that cannot be rolled
-- on by themselves.
local function mergeDungeonRow(rows, name, icon, odds)
    if #rows == 0 then return nil end

    local merged = { boss = name, icon = icon, items = {}, odds = odds }
    local seen, labels, specs = {}, {}, {}
    for _, row in ipairs(rows) do
        for _, item in ipairs(row.items) do
            if not seen[item.id] then
                seen[item.id] = true
                table.insert(merged.items, item)
            end
        end
        if row.switchTo then labels[row.switchTo] = true end
        for _, specID in ipairs(row.switchSpecIDs or {}) do specs[specID] = true end
    end

    local names = {}
    for label in pairs(labels) do table.insert(names, label) end
    table.sort(names)
    merged.switchTo = #names > 0 and table.concat(names, " or ") or nil

    merged.switchSpecIDs = {}
    for specID in pairs(specs) do table.insert(merged.switchSpecIDs, specID) end
    table.sort(merged.switchSpecIDs)
    return merged
end

local function instanceIcon(instanceID)
    local ok, _, _, _, icon = pcall(EJ_GetInstanceInfo, instanceID)
    return ok and icon or nil
end

local function gatherDungeonRows(giveUp, ignoreGates)
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then return nil, true end
    local instanceID = getCurrentEJInstanceID()
    if not instanceID then return nil, true end

    local bosses = bossList(instanceID)
    if #bosses == 0 then return nil, true end

    local odds, ready = dungeonRollOdds(instanceID, ignoreGates)
    if not ready and not giveUp then return nil, false end

    local available = {}
    for _, boss in ipairs(bosses) do available[boss.name] = boss.encounterID end

    local instanceName = GetInstanceInfo and select(1, GetInstanceInfo()) or ""
    local row = mergeDungeonRow(buildBossRows(available, nil, true), instanceName,
        instanceIcon(instanceID), odds)
    if not (row and worthShowing(row)) then return { rows = {} }, true end
    return { rows = { row } }, true
end

local function collectDungeonRows(giveUp)
    local instanceName = GetInstanceInfo and select(1, GetInstanceInfo()) or nil
    local instanceID = getCurrentEJInstanceID()
    local dedupeKey = instanceID or instanceName
    if not dedupeKey or dungeonReminded[dedupeKey] then return nil, true end

    local gathered, ready = gatherDungeonRows(giveUp)
    if not ready then return nil, false end
    if not gathered or #gathered.rows == 0 then return nil, true end

    dungeonReminded[dedupeKey] = true
    return gathered, true
end

local function gatherBossRows(giveUp, ignoreGates)
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "raid" then return nil, true end

    local availableBosses = getAvailableRaidBosses()
    if not availableBosses or not next(availableBosses) then return nil, true end

    local odds, ready = collectBonusRollOdds(availableBosses, ignoreGates)
    if not ready and not giveUp then return nil, false end

    return { rows = buildBossRows(availableBosses, odds) }, true
end

local function collectRaidRows(giveUp)
    local instanceName = GetInstanceInfo and select(1, GetInstanceInfo()) or ""
    local dedupeKey = instanceName .. "|raid"
    if bossReminded[dedupeKey] then return nil, true end

    local gathered, ready = gatherBossRows(giveUp)
    if not ready then return nil, false end
    if not gathered or #gathered.rows == 0 then return nil, true end

    bossReminded[dedupeKey] = true
    return gathered, true
end

-- The rows are advice about your loot spec, so acting on that advice while they
-- are up has to redraw them. Once nothing is left to say, they go.
local function refreshBossRows()
    if not (dungeonReminderFrame and dungeonReminderFrame:IsShown()) then return end
    if not (bossTitle and bossTitle:IsShown()) then return end

    local _, instanceType = IsInInstance()
    local gather = instanceType == "raid" and gatherBossRows or gatherDungeonRows
    local ok, gathered = pcall(gather, true, shownIgnoreGates)
    if not ok then return dprint("Boss row refresh failed:", gathered) end

    if gathered and #gathered.rows > 0 then
        gathered.assist = shownAssist
        showBossReminder(gathered)
    else
        dungeonReminderFrame:StopAutoHide()
        dungeonReminderFrame:Hide()
    end
end

local function runRaidCheck()
    raidCheckPending = false
    local lastAsk = raidCheckWaits >= MAX_ODDS_WAITS
    local ok, gathered, ready = pcall(collectRaidRows, lastAsk)
    if not ok then
        dprint("Raid reminder failed:", gathered)
        raidCheckWaits = 0
        return
    end
    if not ready then
        raidCheckWaits = raidCheckWaits + 1
        return scheduleRaidCheck(ODDS_WAIT_DELAY)
    end
    raidCheckWaits = 0
    shownIgnoreGates = false
    if gathered then showBossReminder(gathered) end
end

function scheduleRaidCheck(delay)
    if raidCheckPending then return end
    raidCheckPending = true
    C_Timer.After(delay or 1, runRaidCheck)
end

local function tryDungeonReminders()
    shownIgnoreGates = false
    local gathered = collectDungeonRows(true)
    local instanceName = GetInstanceInfo and select(1, GetInstanceInfo()) or nil
    local instanceID = getCurrentEJInstanceID()
    local key = instanceID or instanceName
    local assist
    if key and not assistDungeonReminded[key] then
        assist = collectAssist(instanceName, instanceID)
        if assist then assistDungeonReminded[key] = true end
    end

    if gathered then
        gathered.assist = assist
        showBossReminder(gathered)
        return true
    end
    if assist then
        showReminder(nil, assist.lines, assist.firstTargetName, assist.firstSpecName, assist.firstItems)
        return true
    end
    return false
end

local function handleZoneChanged()
    local nowInInstance = IsInInstance()
    if lastInInstance == nil then
        lastInInstance = nowInInstance
    else
        if lastInInstance and not nowInInstance then Reminders:ResetDebounce() end
        lastInInstance = nowInInstance
    end

    local _, instanceType = IsInInstance()
    if instanceType == "raid" then scheduleRaidCheck() end
    if not tryDungeonReminders() and C_Timer and C_Timer.After then
        C_Timer.After(1, tryDungeonReminders)
    end
end

function Reminders:ResetDebounce()
    wipe(dungeonReminded)
    wipe(bossReminded)
    wipe(assistDungeonReminded)
    lastInInstance = nil
    raidCheckWaits = 0
    dprint("Spec reminder debounce reset")

    -- Resetting is how the reminder gets looked at on purpose, so it runs again
    -- rather than waiting for the next zone change to prove anything.
    local _, instanceType = IsInInstance()
    if instanceType == "raid" then scheduleRaidCheck() else tryDungeonReminders() end
end

local function killedFromNames(bosses, fragments, report)
    local killedIDs = {}
    for entry in fragments:gmatch("[^,]+") do
        local fragment = entry:match("^%s*(.-)%s*$"):lower()
        local matched = false
        for _, boss in ipairs(bosses) do
            if fragment ~= "" and boss.name:lower():find(fragment, 1, true) then
                killedIDs[boss.encounterID] = true
                matched = true
            end
        end
        if not matched then report("no boss matches '" .. fragment .. "'") end
    end
    return killedIDs
end

-- Run the reminder against a raid you are not standing in, so a layout can be
-- checked without a raid night. Kills come from the named bosses, or from your
-- real lockout when none are named. Returns the availability it worked out.
-- Says what the row builder saw, so an empty reminder can be told apart from a
-- boss name that never matched or a loot spec that wanted nothing.
local function reportRows(report, availableBosses, odds)
    local lootSpecID = getLootSpecID()
    report("loot spec: " .. (getSpecName(lootSpecID) or "unset"))

    local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked() or {}
    local rows = Planner:BuildBossRows(tracked, {
        availableBosses = availableBosses,
        lootSpecID = lootSpecID,
        getSpecName = getSpecName,
    })
    if #rows == 0 then
        report("no boss here matched anything on your wishlist")
        return
    end

    for _, row in ipairs(rows) do
        local perBoss = odds and odds[row.encounterID]
        report("  " .. row.boss .. ": " .. #row.items .. " tracked, switch: "
            .. (row.switchTo or "not needed")
            .. (perBoss and (", odds " .. perBoss.wanted .. "/" .. perBoss.total) or ""))
    end
end

-- A keystone roll is on the instance, so a dungeon has no kill list to simulate
-- and the charge and key level gates are dropped rather than worked around.
local function testDungeonReminder(report)
    local instanceID = getCurrentEJInstanceID()
    if not instanceID then
        report("no journal instance for this dungeon")
        return nil
    end

    local bosses = bossList(instanceID)
    report("instance " .. instanceID .. ", " .. #bosses .. " bosses")

    local available = {}
    for _, boss in ipairs(bosses) do
        available[boss.name] = boss.encounterID
        report("  " .. boss.name .. " (" .. tostring(boss.encounterID) .. ")")
    end

    local BR = LootWishlist.BonusRoll
    report(("charges: %d, key level: %d, roll needs %d and %d"):format(
        BR and BR.GetCharges() or 0, keystoneLevel(),
        BR and BR.DUNGEON_COST or 0, BR and BR.MIN_KEYSTONE_LEVEL or 0))
    report("the gates above are dropped for this test, the live reminder obeys them")

    shownIgnoreGates = true
    local gathered, ready = gatherDungeonRows(true, true)
    if not ready then
        report("the loot table is still being read, run this again in a few seconds")
    end
    reportRows(report, available, nil)

    if gathered and #gathered.rows > 0 then
        showBossReminder(gathered)
    else
        report("no reminder drawn")
    end
    return gathered
end

function Reminders:TestNextBoss(ejInstanceID, bossFragments)
    local prefix = "|cffC9A84CLoot Wishlist|r: "
    local function report(line) print(prefix .. line) end

    local _, instanceType = IsInInstance()
    if instanceType == "party" and not tonumber(ejInstanceID) then
        return testDungeonReminder(report)
    end

    ejInstanceID = tonumber(ejInstanceID) or getCurrentEJInstanceID()
    if not ejInstanceID then
        report("usage: /wishlist testnextboss inside a raid, or /wishlist testnextboss <journal instance ID> [boss name, boss name] anywhere")
        return nil
    end

    local bosses = bossList(ejInstanceID)
    if #bosses == 0 then
        report("the journal lists no bosses for instance " .. ejInstanceID)
        return nil
    end

    local killedIDs
    if bossFragments and bossFragments ~= "" then
        killedIDs = killedFromNames(bosses, bossFragments, report)
    else
        local instanceName, _, difficultyID = GetInstanceInfo()
        killedIDs = killedFromLockout(bosses, instanceName, difficultyID)
        report("no bosses named, using your lockout for " .. tostring(instanceName))
    end

    local available = availableFrom(ejInstanceID, bosses, killedIDs)
    report("instance " .. ejInstanceID .. ", " .. #bosses .. " bosses")
    for _, boss in ipairs(bosses) do
        local state = "|cff9d9d9dblocked|r"
        if killedIDs[boss.encounterID] then
            state = "|cffff6b6bdead|r"
        elseif available[boss.name] then
            state = "|cff69db7cavailable|r"
        end
        report("  " .. boss.name .. " (" .. tostring(boss.encounterID) .. "): " .. state)
    end

    -- Charges are not required here: the odds are what is being tested, and a
    -- character short of a roll would never see them.
    shownIgnoreGates = true
    local odds, ready = collectBonusRollOdds(available, true)
    if not ready then
        report("the loot table is still being read, run this again in a few seconds")
    end

    reportRows(report, available, odds)

    local rows = buildBossRows(available, odds)
    if #rows > 0 then
        showBossReminder({ rows = rows })
    else
        report("no reminder: nothing you track on an available boss wants a different loot spec, and no charge would be worth spending on one")
    end
    return available
end

local function handleEvent(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        handleZoneChanged()
    elseif event == "BOSS_KILL" then
        local instanceName = GetInstanceInfo and select(1, GetInstanceInfo()) or ""
        bossReminded[instanceName .. "|raid"] = nil
        local settings = LootWishlist.GetSettings and LootWishlist.GetSettings()
            or (LootWishlistDB and LootWishlistDB.settings)
            or {}
        scheduleRaidCheck(settings.bossKillReminderDelay or 10)
    elseif event == "PLAYER_LOOT_SPEC_UPDATED" then
        refreshBossRows()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == "player" then refreshBossRows() end
    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, groupSize, success = ...
        dprint(
            "ENCOUNTER_END",
            encounterID,
            encounterName,
            difficultyID,
            groupSize,
            success
        )
    end
end

function Reminders:Init(database)
    db = database
    if eventFrame then return end

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("BOSS_KILL")
    eventFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:SetScript("OnEvent", handleEvent)
end
