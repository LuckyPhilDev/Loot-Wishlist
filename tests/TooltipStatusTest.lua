-- luacheck: ignore 111 112 113 121 122 131
-- Drives the wishlist line LootWishlist_Tooltips.lua puts on an item's tooltip:
-- what it says for a raid drop, a dungeon drop and a manual add, how several
-- sources stack, and which tooltips are left alone (comparisons, the wishlist
-- window's own rows, the setting turned off).

local function noop() end
local stubMeta = { __index = function() return noop end }

local function frame(fields)
  local f = setmetatable(fields or {}, stubMeta)
  f.lootWishlistWindow = rawget(f, "lootWishlistWindow") or false
  f.parent = rawget(f, "parent") or false
  f.name = rawget(f, "name") or false
  f.GetParent = function(self) return self.parent end
  f.GetName = function(self) return self.name or nil end
  return f
end

local function tooltip()
  local t = frame({ lines = {}, shoppingTooltips = {}, owner = false })
  t.AddLine = function(self, text, r, g, b) self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b } end
  t.GetOwner = function(self) return self.owner or nil end
  t.Clear = function(self) self.lines = {} end
  return t
end

------------------------------------------------------------------------
-- Load the module
------------------------------------------------------------------------
local postCall
LuckyLog = { New = function() return noop end }
LuckyUI = {
  C = { textLight = { 0.91, 0.863, 0.784 }, goldPrimary = { 1, 0.82, 0 } },
  WC = { goldPrimary = "|cffffd100", textMuted = "|cff8a7e6a", reset = "|r" },
}
UIParent = frame()
GameTooltip = tooltip()
GameTooltip.shoppingTooltips = { tooltip(), tooltip() }
ItemRefTooltip = tooltip()
ItemRefTooltip.shoppingTooltips = { tooltip() }
EmbeddedItemTooltip = tooltip()
C_Timer = { After = noop }
TooltipComparisonManager = { Initialize = noop, AnchorShoppingTooltips = noop }
TooltipDataProcessor = { AddTooltipPostCall = function(dataType, fn) postCall = { dataType = dataType, fn = fn } end }
Enum = { TooltipDataType = { Item = 10 } }
function CreateFrame() return frame() end
function hooksecurefunc() end
function GetScreenWidth() return 1366 end

LootWishlistDB = { settings = { enableTooltipStatus = true } }

local tracked = {}
LootWishlist = { GetTracked = function() return tracked end }
dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Constants.lua")
dofile("src/LootWishlist_Tooltips.lua")

assert(postCall and postCall.dataType == Enum.TooltipDataType.Item, "the module hooks item tooltips")

local checks = 0
local function check(condition, why)
  assert(condition, why)
  checks = checks + 1
end

local function entry(id, boss, dungeon, isRaid, difficultyID)
  return { id = id, boss = boss, dungeon = dungeon, isRaid = isRaid,
    difficultyID = difficultyID, difficultyName = LootWishlist.Const.DIFFICULTY_NAMES[difficultyID] }
end

-- A raid piece tracked on Heroic and Mythic, a dungeon piece from Normal
-- through Mythic+, a manual add with no source at all, and an item tracked
-- from two sources at once.
tracked = {
  ["1@15"] = entry(1, "The Coiled Altar", "The Venomous Abyss", true, 15),
  ["1@16"] = entry(1, "The Coiled Altar", "The Venomous Abyss", true, 16),
  ["2@8"]  = entry(2, "Kyrakka and Erkhart Stormvein", "Ruby Life Pools", false, 8),
  ["2@23"] = entry(2, "Kyrakka and Erkhart Stormvein", "Ruby Life Pools", false, 23),
  ["2@1"]  = entry(2, "Kyrakka and Erkhart Stormvein", "Ruby Life Pools", false, 1),
  ["3"]    = { id = 3, dungeon = "Manually Added", isRaid = false },
  ["4@14"] = entry(4, "Nek'zali the Soulcoiler", "The Venomous Abyss", true, 14),
  ["4"]    = { id = 4, dungeon = "Manually Added", isRaid = false },
}

local function hover(tt, data, owner)
  tt:Clear()
  tt.owner = owner or false
  postCall.fn(tt, data)
  return tt.lines
end

local LABEL = "|cffffd100On your wishlist:|r "

------------------------------------------------------------------------
-- What the line says
------------------------------------------------------------------------
local lines = hover(GameTooltip, { id = 1 })
check(#lines == 1, "one source is one line")
check(lines[1].text == LABEL .. "The Coiled Altar|cff8a7e6a - The Venomous Abyss|r [H, M]",
  "a raid drop leads with the boss and lists the difficulties tracked, got " .. lines[1].text)
check(lines[1].r == 0.91 and lines[1].g == 0.863 and lines[1].b == 0.784, "the line is drawn in the light text tone")

lines = hover(GameTooltip, { id = 2 })
check(lines[1].text == LABEL .. "Ruby Life Pools|cff8a7e6a - Kyrakka and Erkhart Stormvein|r [N, M, M+]",
  "a dungeon drop leads with the dungeon and orders its tags low to high, got " .. lines[1].text)

lines = hover(GameTooltip, { id = 3 })
check(lines[1].text == LABEL .. "Manually Added", "a manual add names its group with no brackets, got " .. lines[1].text)

lines = hover(GameTooltip, { id = 4 })
check(#lines == 3, "two sources put the label on its own line, got " .. #lines)
check(lines[1].text == "On your wishlist:" and lines[1].r == 1 and lines[1].g == 0.82 and lines[1].b == 0,
  "the label line is gold")
check(lines[2].text == "  Manually Added", "sources are indented and sorted, first " .. lines[2].text)
check(lines[3].text == "  Nek'zali the Soulcoiler|cff8a7e6a - The Venomous Abyss|r [N]", "second " .. lines[3].text)

check(#hover(GameTooltip, { id = 99 }) == 0, "an item off the wishlist gets nothing")
check(#hover(GameTooltip, {}) == 0 and #hover(GameTooltip, nil) == 0, "no item, no line, no error")

------------------------------------------------------------------------
-- Which tooltips carry it
------------------------------------------------------------------------
check(#hover(ItemRefTooltip, { id = 1 }) == 1, "a chat link's tooltip carries it")
check(#hover(EmbeddedItemTooltip, { id = 1 }) == 1, "an embedded item tooltip carries it")
check(#hover(GameTooltip.shoppingTooltips[2], { id = 1 }) == 0, "an Equipped comparison does not")
check(#hover(ItemRefTooltip.shoppingTooltips[1], { id = 1 }) == 0, "nor a chat link's comparison")

local wishlist = frame({ lootWishlistWindow = true, name = "LootWishlistMainFrame" })
local browser = frame({ lootWishlistWindow = true, name = "LootWishlistBrowserFrame" })
check(#hover(GameTooltip, { id = 1 }, frame({ parent = wishlist })) == 0, "a wishlist row's tooltip is left alone")
check(#hover(GameTooltip, { id = 1 }, frame({ parent = browser })) == 1, "a Loot Browser row's tooltip carries it")
check(#hover(GameTooltip, { id = 1 }, frame({ parent = UIParent })) == 1, "as does anything else's")

LootWishlistDB.settings.enableTooltipStatus = false
check(#hover(GameTooltip, { id = 1 }) == 0, "the setting turns it off")
LootWishlistDB.settings.enableTooltipStatus = true

-- An obtained item has left the tracked table, so it reads as untracked here.
tracked["1@15"], tracked["1@16"] = nil, nil
check(#hover(GameTooltip, { id = 1 }) == 0, "an obtained item says nothing")

------------------------------------------------------------------------
-- The Vault badge draws the same lines under its own label
------------------------------------------------------------------------
local badgeTip = tooltip()
LootWishlist.UI.AddWishlistLines(badgeTip, LootWishlist.UI.WishlistLines(2), "This reward matches an item on your wishlist:")
check(badgeTip.lines[1].text == "|cffffd100This reward matches an item on your wishlist:|r "
  .. "Ruby Life Pools|cff8a7e6a - Kyrakka and Erkhart Stormvein|r [N, M, M+]", "the badge shares the line builder")
LootWishlist.UI.AddWishlistLines(badgeTip, {}, "label")
check(#badgeTip.lines == 1, "nothing to say adds no label")

print(string.format("TooltipStatusTest: %d checks passed", checks))
