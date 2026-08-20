-- luacheck: ignore 111 121

LootWishlist = {}
LuckyUI = { C = {}, WC = {} }
LuckyLog = { New = function() return function() end end }

-- Fake links encode their ilvl as "item:<id>:<ilvl>[:bonus...]"
C_Item = {
    GetDetailedItemLevelInfo = function(link)
        return tonumber(link:match("^item:%d+:(%d+)"))
    end,
}

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Constants.lua")
dofile("src/LootWishlist_UI.lua")

local track = LootWishlist.UI.TrackKeyForEntry
local passed = 0

local function check(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
    passed = passed + 1
end

-- Raids: one difficulty per track
check(track({ isRaid = true, difficultyID = 17 }), "Veteran", "LFR raid")
check(track({ isRaid = true, difficultyID = 14 }), "Champion", "normal raid")
check(track({ isRaid = true, difficultyID = 15 }), "Hero", "heroic raid")
check(track({ isRaid = true, difficultyID = 16 }), "Myth", "mythic raid")

-- Dungeons: Veteran and Champion own a difficulty each
check(track({ difficultyID = 2 }), "Veteran", "heroic dungeon")
check(track({ difficultyID = 23 }), "Champion", "mythic dungeon")

-- Keystone entries: the link's track bonus decides Hero vs Myth
check(track({ difficultyID = 8, link = "item:100:305:12841:1674" }), "Hero", "hero bonus")
check(track({ difficultyID = 8, link = "item:100:318:12849:1674" }), "Myth", "myth bonus")

-- A longer bonus must not be misread as a track bonus (128491 vs 12849);
-- the item level fallback decides instead
check(track({ difficultyID = 8, link = "item:100:305:128491" }), "Hero", "long bonus ignored")

-- Keystone entries without a track bonus fall back to item level
check(track({ difficultyID = 8, link = "item:100:318" }), "Myth", "ilvl at myth")
check(track({ difficultyID = 8, link = "item:100:305" }), "Hero", "ilvl at hero")
check(track({ difficultyID = 8, link = "item:100:292" }), nil, "ilvl below hero")
check(track({ difficultyID = 8 }), nil, "keystone entry without link")

-- Difficulties outside the track model stay untracked
check(track({ difficultyID = 1 }), nil, "normal dungeon")
check(track({ difficultyID = 24 }), nil, "timewalking")
check(track({}), nil, "no difficulty")

print(string.format("TrackNameTest: %d checks passed", passed))
