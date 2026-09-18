-- luacheck: ignore 111 121
-- Browsing "All <class>" asks whether any spec of that class can be given the
-- piece, which is what keeps cloth bracers and staves out of a Paladin's list.

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

local classMatch = LootWishlist.Browser.classMatch

local HOLY, PROT, RET = 65, 66, 70
local FIRE, FROST = 63, 64

local paladin = { [HOLY] = true, [PROT] = true, [RET] = true }

-- One spec of the class wanting the piece is enough: a Ret plate belt shows to
-- a Paladin browsing All, and so does a Holy one.
assert(classMatch({ RET }, paladin), "a Retribution piece was hidden from All Paladin")
assert(classMatch({ HOLY, FIRE }, paladin), "a piece shared with another class was hidden")

-- The reported bug: cloth and mail bracers no spec of the class can be given.
assert(not classMatch({ FIRE, FROST }, paladin), "a Mage-only piece passed All Paladin")

-- Weapons cut the same way, since the game answers with specs either way.
assert(not classMatch({ FROST }, paladin), "a staff no Paladin spec wants passed")

-- An unread piece shows rather than vanishing, and appears settled once its
-- data lands. Same for a class whose specs could not be read.
assert(classMatch(nil, paladin), "an unread piece was hidden")
assert(classMatch({ FIRE }, nil), "an unreadable class hid a piece")
assert(classMatch(nil, nil), "two unknowns hid a piece")

-- A piece the game lists no specs for is unrestricted, not restricted to none.
assert(classMatch({}, paladin), "a piece with no spec list was hidden")

print("BrowserClassFilterTest passed")
