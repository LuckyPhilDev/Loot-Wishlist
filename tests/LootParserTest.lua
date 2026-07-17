-- luacheck: ignore 121

LootWishlist = {}

LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_BONUS_ROLL = "You receive bonus loot: %s."
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_ITEM_PUSHED = "%s receives item: %s."

function UnitName()
    return "Lucky"
end

dofile("src/LootWishlist_LootParser.lua")

local Parser = LootWishlist.LootParser
local passed = 0

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local link = "|cffa335ee|Hitem:12345::::::::80:::::|h[Wanted Trinket]|h|r"

local selfResult = Parser:ParseMessage("You receive loot: " .. link .. ".")
assertEqual(selfResult.isSelf, true, "self loot")
assertEqual(selfResult.looter, "Lucky", "self looter")
assertEqual(#selfResult.items, 1, "self item count")
assertEqual(selfResult.items[1].itemID, 12345, "self item id")
assertEqual(selfResult.items[1].link, link, "self link")
passed = passed + 1

local otherResult = Parser:ParseMessage("Raider-Silvermoon receives loot: " .. link .. ".")
assertEqual(otherResult.isSelf, false, "other loot")
assertEqual(otherResult.looter, "Raider-Silvermoon", "other looter")
assertEqual(otherResult.items[1].itemID, 12345, "other item id")
passed = passed + 1

assertEqual(Parser:ParseMessage("A system message"), nil, "unrelated message")
passed = passed + 1

local tracked = {
    ["12345@16"] = { id = 12345 },
    [67890] = true,
    ["24680"] = true,
}
assertEqual(Parser:IsTracked(tracked, 12345), true, "table entry")
assertEqual(Parser:IsTracked(tracked, 67890), true, "numeric legacy key")
assertEqual(Parser:IsTracked(tracked, 24680), true, "string legacy key")
assertEqual(Parser:IsTracked(tracked, 11111), false, "missing item")
passed = passed + 1

print(string.format("%d loot parser tests passed", passed))
