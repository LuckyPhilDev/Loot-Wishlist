-- luacheck: ignore 111 121
-- The stat filter asks whether a piece carries the picked secondaries, under
-- "any of these" or "all of these".

LootWishlist = {}
LuckyUI = { C = { textLight = { 0.910, 0.863, 0.784 } }, WC = {},
           DOT = "\194\183" }

local function noop() end
function CreateFrame()
  return setmetatable({}, { __index = function() return noop end })
end

Enum = {}
ITEM_SPELL_TRIGGER_ONUSE = "Use:"
ITEM_CLASSES_ALLOWED = "Classes: %s"
function GetNumClasses() return 0 end
function GetClassInfo() end

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Browser.lua")

local statMatch = LootWishlist.Browser.statMatch

local CRIT  = "ITEM_MOD_CRIT_RATING_SHORT"
local HASTE = "ITEM_MOD_HASTE_RATING_SHORT"
local MAST  = "ITEM_MOD_MASTERY_RATING_SHORT"

local hasteCrit = { [HASTE] = true, [CRIT] = true }

-- No stats picked: everything passes, whatever the mode.
assert(statMatch(hasteCrit, {}, "any"), "empty filter blocked a piece")
assert(statMatch(nil, {}, "all"), "empty filter blocked an unread piece")

-- Any: one carried stat is enough.
assert(statMatch(hasteCrit, { [HASTE] = true, [MAST] = true }, "any"), "any missed a carried stat")
assert(not statMatch(hasteCrit, { [MAST] = true }, "any"), "any passed a piece carrying none of the picks")

-- All: every picked stat must be carried.
assert(statMatch(hasteCrit, { [HASTE] = true, [CRIT] = true }, "all"), "all blocked a full match")
assert(not statMatch(hasteCrit, { [HASTE] = true, [MAST] = true }, "all"), "all passed a partial match")

-- Only: nothing on the piece outside the picks. A subset passes, an extra
-- stat fails, whether or not the picks are all covered.
assert(statMatch(hasteCrit, { [HASTE] = true, [CRIT] = true }, "only"), "only blocked an exact match")
assert(statMatch({ [HASTE] = true }, { [HASTE] = true, [CRIT] = true }, "only"), "only blocked a subset")
assert(not statMatch(hasteCrit, { [HASTE] = true }, "only"), "only passed a piece carrying an extra stat")
assert(not statMatch({ [MAST] = true }, { [HASTE] = true, [CRIT] = true }, "only"), "only passed a piece outside the picks")

-- A piece whose stats have not been read yet fails a live filter rather than
-- flashing in and out of the list.
assert(not statMatch(nil, { [HASTE] = true }, "any"), "unread piece passed an any filter")
assert(not statMatch(nil, { [HASTE] = true }, "all"), "unread piece passed an all filter")
assert(not statMatch(nil, { [HASTE] = true }, "only"), "unread piece passed an only filter")

-- A piece read and carrying no secondaries (a tier token) has nothing to
-- offer "any" or "all", but carries nothing outside the picks either.
assert(not statMatch(false, { [CRIT] = true }, "any"), "statless piece passed an any filter")
assert(not statMatch(false, { [CRIT] = true }, "all"), "statless piece passed an all filter")
assert(statMatch(false, { [CRIT] = true }, "only"), "statless piece failed an only filter")

print("16 browser stat filter tests passed")
