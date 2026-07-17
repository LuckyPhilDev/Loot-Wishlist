-- Loot Wishlist: pure planning logic for loot-spec and group-assist reminders.

LootWishlist = LootWishlist or {}
LootWishlist.ReminderPlanner = LootWishlist.ReminderPlanner or {}

local Planner = LootWishlist.ReminderPlanner

function Planner:NormalizeName(value)
    if type(value) ~= "string" then return value end
    return value:lower():gsub("[%s%p]", "")
end

local function itemLink(item)
    return item.link or ("item:" .. tostring(item.id))
end

local function sortedSpecIDs(specs)
    local result = {}
    local seen = {}
    if type(specs) ~= "table" then return result end

    for _, specID in pairs(specs) do
        if type(specID) == "number" and not seen[specID] then
            seen[specID] = true
            table.insert(result, specID)
        end
    end
    table.sort(result)
    return result
end

local function lootSpecMatches(specs, lootSpecID)
    local specIDs = sortedSpecIDs(specs)
    if #specIDs == 0 or not lootSpecID then return true end
    for _, specID in ipairs(specIDs) do
        if specID == lootSpecID then return true end
    end
    return false
end

local function coversAllPlayerSpecs(specs, playerSpecIDs)
    local specIDs = sortedSpecIDs(specs)
    if #specIDs == 0 then return true end
    if type(playerSpecIDs) ~= "table" or #playerSpecIDs == 0 then return false end

    local available = {}
    for _, specID in ipairs(specIDs) do available[specID] = true end
    for _, playerSpecID in ipairs(playerSpecIDs) do
        if not available[playerSpecID] then return false end
    end
    return true
end

local function specLabel(specs, getSpecName)
    local names = {}
    for _, specID in ipairs(sortedSpecIDs(specs)) do
        local name = getSpecName(specID)
        if name and name ~= "" then table.insert(names, name) end
    end
    table.sort(names)
    return #names > 0 and table.concat(names, " or ") or "appropriate spec"
end

local function classifyItem(item, context, bucket)
    local specs = item.specs
    local link = itemLink(item)
    if type(specs) ~= "table" or not next(specs) then
        table.insert(bucket.stayAny, link)
        return false
    end

    if lootSpecMatches(specs, context.lootSpecID) then
        if coversAllPlayerSpecs(specs, context.playerSpecIDs) then
            table.insert(bucket.stayAny, link)
        else
            table.insert(bucket.stayStrict, link)
        end
        return false
    end

    local label = specLabel(specs, context.getSpecName)
    bucket.bySpec[label] = bucket.bySpec[label] or {}
    table.insert(bucket.bySpec[label], link)
    return true
end

local function matchesDungeon(planner, item, context)
    if item.isRaid then return false end
    if context.instanceID and item.instanceID then
        return context.instanceID == item.instanceID
    end
    return item.dungeon == context.instanceName
        or planner:NormalizeName(item.dungeon) == planner:NormalizeName(context.instanceName or "")
end

function Planner:BuildDungeonSpecLines(trackedItems, context)
    local bucket = { bySpec = {}, stayStrict = {}, stayAny = {} }
    local hasSwitch = false

    for _, item in pairs(trackedItems or {}) do
        if type(item) == "table" and matchesDungeon(self, item, context) then
            hasSwitch = classifyItem(item, context, bucket) or hasSwitch
        end
    end

    if not hasSwitch then return nil end

    local lines = { "Wrong loot spec for wishlist items:" }
    local labels = {}
    for label in pairs(bucket.bySpec) do table.insert(labels, label) end
    table.sort(labels)
    for _, label in ipairs(labels) do
        table.sort(bucket.bySpec[label])
        table.insert(lines, string.format("- Switch %s for %s", label, table.concat(bucket.bySpec[label], ", ")))
    end
    if context.lootSpecID and #bucket.stayStrict > 0 then
        table.sort(bucket.stayStrict)
        local currentName = context.getSpecName(context.lootSpecID) or "current spec"
        table.insert(lines, string.format("- Stay %s for %s", currentName, table.concat(bucket.stayStrict, ", ")))
    end
    if #bucket.stayAny > 0 then
        table.sort(bucket.stayAny)
        table.insert(lines, "- OK in any spec: " .. table.concat(bucket.stayAny, ", "))
    end
    return lines
end

function Planner:BuildRaidSpecLines(trackedItems, context)
    local perBoss = {}
    local hasSwitch = false

    for _, item in pairs(trackedItems or {}) do
        if type(item) == "table" and item.isRaid and item.boss and context.availableBosses[item.boss] then
            local boss = perBoss[item.boss]
            if not boss then
                boss = { bySpec = {}, stayStrict = {}, stayAny = {} }
                perBoss[item.boss] = boss
            end

            hasSwitch = classifyItem(item, context, boss) or hasSwitch
        end
    end

    if not hasSwitch then return nil end

    local lines = { "Wrong loot spec for upcoming bosses:" }
    local bossNames = {}
    for bossName in pairs(perBoss) do table.insert(bossNames, bossName) end
    table.sort(bossNames)
    for _, bossName in ipairs(bossNames) do
        local boss = perBoss[bossName]
        local labels = {}
        for label in pairs(boss.bySpec) do table.insert(labels, label) end
        table.sort(labels)
        for _, label in ipairs(labels) do
            table.sort(boss.bySpec[label])
            table.insert(lines, string.format(
                "- %s: switch %s for %s",
                bossName,
                label,
                table.concat(boss.bySpec[label], ", ")
            ))
        end
        if context.lootSpecID and #boss.stayStrict > 0 then
            table.sort(boss.stayStrict)
            local currentName = context.getSpecName(context.lootSpecID) or "current spec"
            table.insert(lines, string.format(
                "- %s: stay %s for %s",
                bossName,
                currentName,
                table.concat(boss.stayStrict, ", ")
            ))
        end
        if #boss.stayAny > 0 then
            table.sort(boss.stayAny)
            table.insert(lines, string.format(
                "- %s: OK in any spec: %s",
                bossName,
                table.concat(boss.stayAny, ", ")
            ))
        end
    end
    return lines
end

local function matchesAssistContext(planner, item, context)
    if context.isRaid then
        return item.isRaid and item.boss == context.bossName
    end
    return matchesDungeon(planner, item, context)
end

function Planner:BuildAssistSuggestions(trackedItems, context)
    local suggestions = {}

    for _, item in pairs(trackedItems or {}) do
        if type(item) == "table" and matchesAssistContext(self, item, context) then
            for _, specID in ipairs(sortedSpecIDs(item.specs)) do
                local specName, classFile = context.getSpecInfo(specID)
                if specName and classFile then
                    for _, member in ipairs(context.members or {}) do
                        if member.classFile == classFile then
                            local suggestion = suggestions[member.name]
                            if not suggestion then
                                suggestion = { specName = specName, items = {}, seenItems = {} }
                                suggestions[member.name] = suggestion
                            end
                            local link = itemLink(item)
                            if not suggestion.seenItems[link] then
                                suggestion.seenItems[link] = true
                                table.insert(suggestion.items, link)
                            end
                        end
                    end
                end
            end
        end
    end

    if not next(suggestions) then return nil end

    local names = {}
    for name in pairs(suggestions) do table.insert(names, name) end
    table.sort(names)

    local lines = { "Ask group to help with wishlist items:" }
    for _, name in ipairs(names) do
        local suggestion = suggestions[name]
        table.sort(suggestion.items)
        table.insert(lines, string.format(
            "- %s (%s): %s",
            name,
            suggestion.specName or "Spec",
            table.concat(suggestion.items, ", ")
        ))
    end

    local firstName = names[1]
    local first = suggestions[firstName]
    return {
        lines = lines,
        firstTargetName = firstName,
        firstSpecName = first.specName,
        firstItems = table.concat(first.items, ", "),
    }
end
