-- luacheck: ignore 111 121
-- A tier token has no equip slot and the journal's class filter does not reach
-- it, so the browser reads both facts off the token's own tooltip.

LootWishlist = {}
LuckyUI = { C = {}, WC = {} }

local function noop() end
function CreateFrame()
  return setmetatable({}, { __index = function() return noop end })
end

INVTYPE_HEAD = "Head"
INVTYPE_SHOULDER = "Shoulder"
INVTYPE_CHEST = "Chest"
INVTYPE_HAND = "Hands"
INVTYPE_LEGS = "Legs"
INVTYPE_WEAPONMAINHAND = "Main Hand"
INVTYPE_WEAPON = "One-Hand"

ITEM_SPELL_TRIGGER_ONUSE = "Use:"
ITEM_CLASSES_ALLOWED = "Classes: %s"
-- The live client numbers this line 43, the local UI source 21. The reader must
-- not care either way, so the tests give it the number it does not expect.
Enum = { TooltipDataLineType = { RestrictedRaceClass = 21 } }

local CLASSES = {
  { name = "Hunter", id = 3 },
  { name = "Rogue", id = 4 },
  { name = "Monk", id = 10 },
  { name = "Demon Hunter", id = 12 },
}
function GetNumClasses() return #CLASSES end
function GetClassInfo(i)
  local c = CLASSES[i]
  if c then return c.name, c.name:upper(), c.id end
end

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Browser.lua")

local readToken = LootWishlist.Browser.readToken

local function lines(...)
  local out = {}
  for _, l in ipairs({ ... }) do out[#out + 1] = l end
  return out
end

local function use(text) return { leftText = text } end
-- Type 43 is what the live client reports, and deliberately not the value the
-- RestrictedRaceClass enum carries here.
local function restriction(text) return { leftText = text, type = 43 } end

-- The slot the token turns into, read off its Use line.
local head = readToken(lines(
  use("Use: Create a soulbound set head item appropriate for your class."),
  restriction("Classes: Rogue, Monk, Demon Hunter")
))
assert(head.slot == "Head", "head token slot: " .. tostring(head.slot))

-- Plural paperdoll labels match a singular Use line.
local hands = readToken(lines(use("Use: Create a soulbound set hand item appropriate for your class.")))
assert(hands.slot == "Hands", "hand token slot: " .. tostring(hands.slot))

-- A longer label wins, so a main hand token is not filed under Hands.
local mainHand = readToken(lines(use("Use: Create a soulbound set main hand item.")))
assert(mainHand.slot == "Main Hand", "main hand token slot: " .. tostring(mainHand.slot))

-- Only the Use line names a slot; flavour text elsewhere does not.
local flavour = readToken(lines({ leftText = "Torn from the head of the beast." }))
assert(flavour.slot == false, "flavour text named a slot: " .. tostring(flavour.slot))

-- The class list is exact: a Demon Hunter token is not a Hunter token.
assert(head.classes[10] == true, "Monk missing from the token's classes")
assert(head.classes[12] == true, "Demon Hunter missing from the token's classes")
assert(head.classes[3] == nil, "Hunter read out of Demon Hunter")

-- A restriction line naming races only leaves the token unrestricted.
local races = readToken(lines(
  use("Use: Create a soulbound set chest item."),
  restriction("Races: Dwarf, Gnome")
))
assert(races.classes == false, "a race restriction read as a class restriction")

-- The real Venomous Effigy, read exactly as the live client reports it: the
-- class list arrives on a line type the local UI source does not know.
local effigy = readToken(lines(
  { leftText = "Venomcured Effigy", type = 22 },
  { leftText = "Item Level 219", type = 31 },
  { leftText = "Binds when picked up", type = 20 },
  { leftText = "Use: Create a soulbound set head item appropriate for your class.", type = 44 },
  { leftText = "Classes: Rogue, Monk, Druid, Demon Hunter", type = 43 }
))
assert(effigy.slot == "Head", "effigy slot: " .. tostring(effigy.slot))
assert(effigy.classes and effigy.classes[10] == true, "Monk should be able to use the effigy")
assert(effigy.classes[3] == nil, "Hunter read out of Demon Hunter on the effigy")

print("9 browser token tests passed")
