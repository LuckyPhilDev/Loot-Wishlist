LootWishlist = {}

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_ReminderPlanner.lua")

local Planner = LootWishlist.ReminderPlanner
local passed = 0

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local specNames = {
    [71] = "Arms",
    [72] = "Fury",
    [73] = "Protection",
}

local function getSpecName(specID)
    return specNames[specID]
end

local tracked = {
    switch = {
        id = 1001,
        link = "[Switch Item]",
        dungeon = "The Example Vault",
        instanceID = 501,
        isRaid = false,
        specs = { 71 },
    },
    stay = {
        id = 1002,
        link = "[Stay Item]",
        dungeon = "The Example Vault",
        instanceID = 501,
        isRaid = false,
        specs = { 72 },
    },
    any = {
        id = 1003,
        link = "[Any Item]",
        dungeon = "The Example Vault",
        instanceID = 501,
        isRaid = false,
        specs = {},
    },
    other = {
        id = 1004,
        link = "[Other Dungeon]",
        dungeon = "Somewhere Else",
        instanceID = 999,
        isRaid = false,
        specs = { 71 },
    },
}

local bossRows = Planner:BuildBossRows({
    first = { id = 2001, link = "[Boss Item]", boss = "First Boss", isRaid = true, specs = { 71 } },
    second = { id = 2000, link = "[Shared Item]", boss = "First Boss", isRaid = true, specs = { 71, 72 } },
    open = { id = 2003, link = "[Open Item]", boss = "First Boss", isRaid = true, specs = {} },
    locked = { id = 2002, link = "[Locked Item]", boss = "Locked Boss", isRaid = true, specs = { 71 } },
}, {
    availableBosses = { ["First Boss"] = 9001 },
    lootSpecID = 72,
    getSpecName = getSpecName,
})

assertEqual(#bossRows, 1, "a boss that is not available gets no row")
assertEqual(bossRows[1].boss, "First Boss", "the row names its boss")
assertEqual(bossRows[1].encounterID, 9001, "the row carries the encounter id")
assertEqual(#bossRows[1].items, 3, "every tracked item on the boss rides the row")
assertEqual(bossRows[1].items[1].id, 2000, "items are ordered by id")
assertEqual(bossRows[1].switchTo, "Arms", "the item your loot spec cannot be given names its spec")
assertEqual(#bossRows[1].switchSpecIDs, 1, "only the spec that would help is offered")
assertEqual(bossRows[1].switchSpecIDs[1], 71, "and it is offered by id, ready to be set")

local function itemWithID(row, id)
    for _, item in ipairs(row.items) do
        if item.id == id then return item end
    end
end

assertEqual(itemWithID(bossRows[1], 2001).needsSwitch, true, "the item out of reach is marked")
assertEqual(itemWithID(bossRows[1], 2001).specLabel, "Arms", "and carries the spec it needs")
assertEqual(itemWithID(bossRows[1], 2000).needsSwitch, false, "an item your loot spec covers is not")
assertEqual(itemWithID(bossRows[1], 2000).specLabel, nil, "and names no spec")
assertEqual(itemWithID(bossRows[1], 2003).needsSwitch, false, "nor is one open to every spec")
passed = passed + 1

local duplicateRows = Planner:BuildBossRows({
    normal = { id = 2001, link = "[Boss Item]", boss = "First Boss", isRaid = true, specs = { 71 } },
    heroic = { id = 2001, link = "[Boss Item]", boss = "First Boss", isRaid = true, specs = { 71 } },
    mythic = { id = 2001, link = "[Boss Item]", boss = "First Boss", isRaid = true, specs = { 71 } },
}, {
    availableBosses = { ["First Boss"] = 9001 },
    lootSpecID = 72,
    getSpecName = getSpecName,
})

assertEqual(#duplicateRows[1].items, 1, "an item tracked on three difficulties is one icon")
passed = passed + 1

local coveredRows = Planner:BuildBossRows({
    shared = { id = 2004, link = "[Shared Item]", boss = "First Boss", isRaid = true, specs = { 71, 72 } },
}, {
    availableBosses = { ["First Boss"] = 9001 },
    lootSpecID = 72,
    getSpecName = getSpecName,
})

assertEqual(#coveredRows, 1, "a boss you track something on still gets a row")
assertEqual(coveredRows[1].switchTo, nil, "a loot spec that can be given everything is asked to switch to nothing")
assertEqual(#coveredRows[1].switchSpecIDs, 0, "and is offered no switch button")
passed = passed + 1

local assist = Planner:BuildAssistSuggestions({
    wanted = {
        id = 3001,
        link = "[Mage Item]",
        dungeon = "The Example Vault",
        instanceID = 501,
        isRaid = false,
        specs = { 62 },
    },
}, {
    isRaid = false,
    instanceName = "The Example Vault",
    instanceID = 501,
    members = {
        { name = "HelpfulMage", classFile = "MAGE" },
    },
    getSpecInfo = function(specID)
        if specID == 62 then return "Arcane", "MAGE" end
    end,
})

assertEqual(assist.lines[1], "Ask group to help with wishlist items:", "assist heading")
assertEqual(assist.lines[2], "- HelpfulMage (Arcane): [Mage Item]", "assist line")
assertEqual(assist.firstTargetName, "HelpfulMage", "assist target")
assertEqual(assist.firstSpecName, "Arcane", "assist spec")
passed = passed + 1

print(string.format("%d reminder planner tests passed", passed))
