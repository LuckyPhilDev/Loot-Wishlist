LootWishlist = {}

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

local lines = Planner:BuildDungeonSpecLines(tracked, {
    instanceName = "The Example Vault",
    instanceID = 501,
    lootSpecID = 72,
    playerSpecIDs = { 71, 72, 73 },
    getSpecName = getSpecName,
})

assertEqual(#lines, 4, "dungeon line count")
assertEqual(lines[1], "Wrong loot spec for wishlist items:", "dungeon heading")
assertEqual(lines[2], "- Switch Arms for [Switch Item]", "switch line")
assertEqual(lines[3], "- Stay Fury for [Stay Item]", "stay line")
assertEqual(lines[4], "- OK in any spec: [Any Item]", "any-spec line")
passed = passed + 1

local raidLines = Planner:BuildRaidSpecLines({
    first = { id = 2001, link = "[Boss Item]", boss = "First Boss", isRaid = true, specs = { 71 } },
    locked = { id = 2002, link = "[Locked Item]", boss = "Locked Boss", isRaid = true, specs = { 71 } },
}, {
    availableBosses = { ["First Boss"] = 9001 },
    lootSpecID = 72,
    playerSpecIDs = { 71, 72, 73 },
    getSpecName = getSpecName,
})

assertEqual(#raidLines, 2, "raid line count")
assertEqual(raidLines[1], "Wrong loot spec for upcoming bosses:", "raid heading")
assertEqual(raidLines[2], "- First Boss: switch Arms for [Boss Item]", "raid switch line")
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
