-- Loot Wishlist: pure parsing helpers for localized loot chat messages.

LootWishlist = LootWishlist or {}
LootWishlist.LootParser = LootWishlist.LootParser or {}

local Parser = LootWishlist.LootParser

local function escapeLuaPattern(value)
    return value and value:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1") or value
end

local function globalStringPattern(value)
    if not value then return nil end
    local pattern = escapeLuaPattern(value)
    pattern = pattern:gsub("%%s", "(.+)")
    return "^" .. pattern .. "$"
end

local function matchAny(message, formats)
    for _, formatString in ipairs(formats) do
        local pattern = globalStringPattern(formatString)
        if pattern then
            local first = message:match(pattern)
            if first then return first end
        end
    end
    return nil
end

function Parser:ExtractLinks(message)
    local links = {}
    if type(message) ~= "string" then return links end

    for link in message:gmatch("|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r") do
        table.insert(links, link)
    end
    return links
end

function Parser:ParseItemID(link)
    if type(link) ~= "string" then return nil end
    local itemID = link:match("item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

function Parser:ParseMessage(message)
    if type(message) ~= "string" then return nil end

    local selfFormats = {
        LOOT_ITEM_SELF,
        LOOT_ITEM_SELF_MULTIPLE,
        LOOT_ITEM_PUSHED_SELF,
        LOOT_ITEM_BONUS_ROLL,
    }
    local otherFormats = {
        LOOT_ITEM,
        LOOT_ITEM_MULTIPLE,
        LOOT_ITEM_PUSHED,
    }

    local isSelf
    local looter
    if matchAny(message, selfFormats) then
        isSelf = true
        looter = UnitName("player")
    else
        looter = matchAny(message, otherFormats)
        if not looter then return nil end
        isSelf = false
    end

    local items = {}
    for _, link in ipairs(self:ExtractLinks(message)) do
        local itemID = self:ParseItemID(link)
        if itemID then
            table.insert(items, { itemID = itemID, link = link })
        end
    end

    return {
        isSelf = isSelf,
        looter = looter,
        items = items,
    }
end

function Parser:IsTracked(trackedItems, itemID)
    if type(trackedItems) ~= "table" or type(itemID) ~= "number" then return false end

    for key, value in pairs(trackedItems) do
        if type(value) == "table" and value.id == itemID then return true end
        if type(key) == "number" and key == itemID then return true end
        if type(key) == "string" and tonumber(key) == itemID then return true end
    end
    return false
end
