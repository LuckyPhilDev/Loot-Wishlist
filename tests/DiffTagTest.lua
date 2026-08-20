-- luacheck: ignore 111 121

LootWishlist = {}

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Constants.lua")

local tag = LootWishlist.Const.DiffTag
local passed = 0

local function check(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
    passed = passed + 1
end

-- Difficulty name wins where one was recorded
check(tag("Raid Finder"), "LFR", "raid finder name")
check(tag("Normal"), "N", "normal name")
check(tag("Heroic"), "H", "heroic name")
check(tag("Mythic"), "M", "mythic name")
check(tag("Mythic+"), "M+", "mythic plus name")
check(tag("Keystone"), "M+", "keystone name")

-- Difficulty ID is the fallback
check(tag(nil, 17), "LFR", "lfr raid id")
check(tag(nil, 14), "N", "normal raid id")
check(tag(nil, 15), "H", "heroic raid id")
check(tag(nil, 16), "M", "mythic raid id")
check(tag(nil, 1), "N", "normal dungeon id")
check(tag(nil, 2), "H", "heroic dungeon id")
check(tag(nil, 23), "M", "mythic dungeon id")
check(tag(nil, 8), "M+", "keystone id")
check(tag(nil, 24), "TW", "timewalking id")

check(tag("", 8), "M+", "empty name falls back to id")
check(tag(nil, 999), nil, "unknown id")
check(tag(nil, nil), nil, "nothing to read")

-- Every tag the helper can return sorts in the display order
for _, t in ipairs({ "LFR", "N", "H", "M", "M+" }) do
    check(type(LootWishlist.Const.DIFF_TAG_ORDER[t]), "number", "sort order for " .. t)
end

print(string.format("DiffTagTest: %d checks passed", passed))
