-- Loot Wishlist: loot-spec and group-assist reminder runtime.

LootWishlist = LootWishlist or {}
LootWishlist.Reminders = LootWishlist.Reminders or {}

local Reminders = LootWishlist.Reminders
local S = LootWishlist.Strings.reminders
local Planner = LootWishlist.ReminderPlanner

local db
local eventFrame
local dungeonReminderFrame, specText, assistText, divider, hideAt
local whisperButton, partyButton, dismissButton
local assistTargetName, assistWhisperMessage, assistPartyMessage
local dungeonReminded = {}
local bossReminded = {}
local assistDungeonReminded = {}
local lastInInstance
local raidCheckPending = false

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

local function getPlayerSpecIDs()
    local result = {}
    if not (GetNumSpecializations and GetSpecializationInfo) then return result end
    local count = GetNumSpecializations()
    if type(count) ~= "number" then return result end
    for index = 1, count do
        local ok, specID = pcall(GetSpecializationInfo, index)
        if ok and type(specID) == "number" then table.insert(result, specID) end
    end
    return result
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

local function ensureReminderFrame()
    if dungeonReminderFrame then return dungeonReminderFrame end

    dungeonReminderFrame = CreateFrame("Frame", "LootWishlistDungeonReminder", UIParent, "BackdropTemplate")
    dungeonReminderFrame:SetSize(520, 80)
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
        hideAt = nil
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
    dungeonReminderFrame:SetScript("OnUpdate", function()
        if hideAt and GetTime() >= hideAt then
            dungeonReminderFrame:Hide()
            hideAt = nil
        end
    end)
    return dungeonReminderFrame
end

local function showReminder(specLines, assistLines, targetName, targetSpec, items)
    local hasSpec = specLines and #specLines > 0
    local hasAssist = assistLines and #assistLines > 0
    if not hasSpec and not hasAssist then return end

    local frame = ensureReminderFrame()
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

    assistTargetName = targetName
    if targetName and targetSpec and items then
        assistWhisperMessage = S.assistWhisper:format(
            targetName,
            targetSpec,
            items
        )
        assistPartyMessage = S.assistParty:format(
            targetName,
            targetSpec,
            items
        )
    else
        assistWhisperMessage, assistPartyMessage = nil, nil
    end

    frame:SetHeight(math.max(80, math.min(320, 8 + contentHeight + 42)))
    frame:Show()
    hideAt = GetTime() + 12
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

local function collectDungeonSpecLines()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then return nil end
    local instanceName = GetInstanceInfo and select(1, GetInstanceInfo()) or nil
    local instanceID = getCurrentEJInstanceID()
    if not instanceName and not instanceID then return nil end
    local dedupeKey = instanceID or instanceName
    if dungeonReminded[dedupeKey] then return nil end

    local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked()
    if not tracked or not next(tracked) then return nil end
    local lines = Planner:BuildDungeonSpecLines(tracked, {
        instanceName = instanceName,
        instanceID = instanceID,
        lootSpecID = getLootSpecID(),
        playerSpecIDs = getPlayerSpecIDs(),
        getSpecName = getSpecName,
    })
    if lines then dungeonReminded[dedupeKey] = true end
    return lines
end

local function raidBossList(ejInstanceID)
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

    local bosses = raidBossList(ejInstanceID)
    if #bosses == 0 then return nil end

    return availableFrom(ejInstanceID, bosses, killedFromLockout(bosses, instanceName, difficultyID))
end

local function collectRaidSpecLines()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "raid" then return nil end
    local instanceName = GetInstanceInfo and select(1, GetInstanceInfo()) or ""
    local dedupeKey = instanceName .. "|raid"
    if bossReminded[dedupeKey] then return nil end

    local availableBosses = getAvailableRaidBosses()
    if not availableBosses or not next(availableBosses) then return nil end
    local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked()
    if not tracked or not next(tracked) then return nil end

    local lines = Planner:BuildRaidSpecLines(tracked, {
        availableBosses = availableBosses,
        lootSpecID = getLootSpecID(),
        playerSpecIDs = getPlayerSpecIDs(),
        getSpecName = getSpecName,
    })
    if lines then bossReminded[dedupeKey] = true end
    return lines
end

local function runRaidCheck()
    raidCheckPending = false
    local ok, lines = pcall(collectRaidSpecLines)
    if not ok then
        dprint("Raid reminder failed:", lines)
    elseif lines then
        showReminder(lines)
    end
end

local function scheduleRaidCheck(delay)
    if raidCheckPending then return end
    raidCheckPending = true
    C_Timer.After(delay or 1, runRaidCheck)
end

local function tryDungeonReminders()
    local specLines = collectDungeonSpecLines()
    local instanceName = GetInstanceInfo and select(1, GetInstanceInfo()) or nil
    local instanceID = getCurrentEJInstanceID()
    local key = instanceID or instanceName
    local assist
    if key and not assistDungeonReminded[key] then
        assist = collectAssist(instanceName, instanceID)
        if assist then assistDungeonReminded[key] = true end
    end

    if specLines or assist then
        showReminder(
            specLines,
            assist and assist.lines,
            assist and assist.firstTargetName,
            assist and assist.firstSpecName,
            assist and assist.firstItems
        )
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
    dprint("Spec reminder debounce reset")
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
function Reminders:TestNextBoss(ejInstanceID, bossFragments)
    local prefix = "|cffC9A84CLoot Wishlist|r: "
    local function report(line) print(prefix .. line) end

    ejInstanceID = tonumber(ejInstanceID) or getCurrentEJInstanceID()
    if not ejInstanceID then
        report("usage: /wishlist testnextboss inside a raid, or /wishlist testnextboss <journal instance ID> [boss name, boss name] anywhere")
        return nil
    end

    local bosses = raidBossList(ejInstanceID)
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

    local tracked = LootWishlist.GetTracked and LootWishlist.GetTracked()
    local lines = tracked and Planner:BuildRaidSpecLines(tracked, {
        availableBosses = available,
        lootSpecID = getLootSpecID(),
        playerSpecIDs = getPlayerSpecIDs(),
        getSpecName = getSpecName,
    })
    if lines then
        showReminder(lines)
    else
        report("no reminder: nothing you track on an available boss wants a different loot spec")
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
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:SetScript("OnEvent", handleEvent)
end
