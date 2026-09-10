-- Loot Wishlist: pure planning logic for loot-spec and group-assist reminders.

LootWishlist = LootWishlist or {}
LootWishlist.ReminderPlanner = LootWishlist.ReminderPlanner or {}

local Planner = LootWishlist.ReminderPlanner
local S = LootWishlist.Strings.planner

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

local function specLabel(specs, getSpecName)
    local names = {}
    for _, specID in ipairs(sortedSpecIDs(specs)) do
        local name = getSpecName(specID)
        if name and name ~= "" then table.insert(names, name) end
    end
    table.sort(names)
    return #names > 0 and table.concat(names, " or ") or S.appropriateSpec
end

local function matchesDungeon(planner, item, context)
    if item.isRaid then return false end
    if context.instanceID and item.instanceID then
        return context.instanceID == item.instanceID
    end
    return item.dungeon == context.instanceName
        or planner:NormalizeName(item.dungeon) == planner:NormalizeName(context.instanceName or "")
end

-- One entry per upcoming boss you track something on: the items themselves, and
-- the loot spec to move to when your current one cannot be given them.
function Planner:BuildBossRows(trackedItems, context)
    local perBoss = {}

    for _, item in pairs(trackedItems or {}) do
        if type(item) == "table" and item.boss and context.availableBosses[item.boss] then
            local row = perBoss[item.boss]
            if not row then
                row = {
                    boss = item.boss,
                    encounterID = context.availableBosses[item.boss],
                    items = {},
                    seen = {},
                    labels = {},
                    switchSpecs = {},
                }
                perBoss[item.boss] = row
            end
            local needsSwitch = not lootSpecMatches(item.specs, context.lootSpecID)
            local label = needsSwitch and specLabel(item.specs, context.getSpecName) or nil

            -- An item tracked on several difficulties is several entries with
            -- one item id, and one icon is what the player wants to see. The
            -- entries themselves are the saved wishlist, so a view is built
            -- rather than the switch being written back onto them.
            if not row.seen[item.id] then
                row.seen[item.id] = true
                table.insert(row.items, {
                    id = item.id,
                    link = item.link,
                    needsSwitch = needsSwitch,
                    specLabel = label,
                })
            end
            if needsSwitch then
                row.labels[label] = true
                for _, specID in ipairs(sortedSpecIDs(item.specs)) do
                    row.switchSpecs[specID] = true
                end
            end
        end
    end

    local rows = {}
    for _, row in pairs(perBoss) do
        local labels = {}
        for label in pairs(row.labels) do table.insert(labels, label) end
        table.sort(labels)
        local switchSpecIDs = {}
        for specID in pairs(row.switchSpecs) do table.insert(switchSpecIDs, specID) end
        table.sort(switchSpecIDs)

        row.labels = nil
        row.seen = nil
        row.switchSpecs = nil
        row.switchSpecIDs = switchSpecIDs
        row.switchTo = #labels > 0 and table.concat(labels, " or ") or nil
        table.sort(row.items, function(a, b) return (a.id or 0) < (b.id or 0) end)
        table.insert(rows, row)
    end
    table.sort(rows, function(a, b) return a.boss < b.boss end)
    return rows
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

    local lines = { S.askGroup }
    for _, name in ipairs(names) do
        local suggestion = suggestions[name]
        table.sort(suggestion.items)
        table.insert(lines, S.askGroupLine:format(
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
