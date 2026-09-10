-- luacheck: ignore 111 121
-- Folding an instance or a boss heading hides what sits under it, and only
-- that. A search shows every match, so folds are ignored while filtering.

LootWishlist = {}
LuckyUI = { C = {}, WC = {}, DOT = "\194\183" }
LuckyLog = { New = function() return function() end end }
C_Item = {}

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Constants.lua")
dofile("src/LootWishlist_UI.lua")

LootWishlistDB = { settings = {} }

local function item(id, boss)
  return { key = tostring(id), id = id, info = { id = id, boss = boss, dungeon = "Manaforge Omega" } }
end

LootWishlist.GetTracked = function() return {} end
LootWishlist.Layout = {
  Build = function()
    return {
      { name = "Manaforge Omega", isRaid = true, count = 2, bosses = {
        { name = "Plexus Sentinel", count = 1, items = { item(1, "Plexus Sentinel") } },
        { name = "Loom'ithar",      count = 1, items = { item(2, "Loom'ithar") } },
      } },
    }
  end,
}

local build = LootWishlist.UI.BuildRows
local toggle = LootWishlist.UI.ToggleCollapsed
LootWishlist.UI.refresh = function() end

local function countRows(rows, kind)
  local n = 0
  for _, r in ipairs(rows) do if r.type == kind then n = n + 1 end end
  return n
end

local function check(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local rows = build()
check(countRows(rows, "instance"), 1, "expanded instances")
check(countRows(rows, "boss"), 2, "expanded bosses")
check(countRows(rows, "item"), 2, "expanded items")

toggle("Manaforge Omega::Loom'ithar")
rows = build()
check(countRows(rows, "boss"), 2, "folded boss still lists both headings")
check(countRows(rows, "item"), 1, "folded boss hides only its own item")
check(rows[4].collapsed, true, "folded boss row is marked collapsed")

toggle("Manaforge Omega")
rows = build()
check(#rows, 1, "folded instance leaves only its heading")
check(rows[1].collapsed, true, "folded instance row is marked collapsed")

toggle("Manaforge Omega")
rows = build()
check(countRows(rows, "item"), 1, "unfolding an instance keeps the boss folded")

toggle("Manaforge Omega::Loom'ithar")
rows = build()
check(countRows(rows, "item"), 2, "unfolding the boss brings its item back")
check(next(LootWishlistDB.settings.collapsed), nil, "unfolding clears the saved key")

print("CollapseTest: passed")
