-- luacheck: ignore 111 121

LootWishlist = {}
LootWishlistDB = { settings = {} }

C_Timer = { After = function() end }

-- Anything a frame, texture or font string is asked for answers with another
-- stub, so the dialog can be built and painted outside the game.
local function stub()
    return setmetatable({ shown = false }, {
        __index = function(_, key)
            if key == "Show" then return function(self) self.shown = true end end
            if key == "Hide" then return function(self) self.shown = false end end
            if key == "IsShown" then return function(self) return self.shown end end
            return function() return stub() end
        end,
    })
end
function CreateFrame() return stub() end
UIParent = stub()
UISpecialFrames = {}
STANDARD_TEXT_FONT = "font"
function tinsert(t, v) table.insert(t, v) end
function GetLocale() return "enUS" end
function CreateColor() return stub() end
function LuckyIcon() return stub() end

local ROSTER = {}
function IsInRaid() return true end
function GetNumGroupMembers() return #ROSTER end
function UnitClass(unit)
    if unit == "player" then return "Druid", "DRUID" end
    local classFile = ROSTER[tonumber(unit:match("%d+"))]
    return classFile, classFile
end

local ARMOUR_NAMES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
Enum = { ItemClass = { Armor = 4 } }
C_Item = {
    GetItemSubClassInfo = function(classID, subClassID)
        return classID == Enum.ItemClass.Armor and ARMOUR_NAMES[subClassID] or nil
    end,
}

local CLASSES = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK",
    "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/Luckys_Utils/LuckyUI.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Constants.lua")
dofile("src/LootWishlist_TokenOdds.lua")

local TokenOdds = LootWishlist.TokenOdds
local ARMOURS = LootWishlist.Const.TIER_TOKEN_ARMOURS
local passed = 0

local function check(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
    passed = passed + 1
end

local function contains(text, needle, label)
    if not text:find(needle, 1, true) then
        error(string.format("%s: %q does not contain %q", label, text, needle))
    end
    passed = passed + 1
end

local function raid(counts)
    local roster = {}
    for classFile, count in pairs(counts) do
        for _ = 1, count do roster[#roster + 1] = classFile end
    end
    return roster
end

local CLOTH, LEATHER, MAIL, PLATE = 1, 2, 3, 4

-- Every class wears one of the four armour types -----------------------------
local seen = {}
for _, classFile in ipairs(CLASSES) do
    local armour = LootWishlist.Const.TIER_TOKEN_ARMOUR[classFile]
    if not armour then error(classFile .. " wears no armour type") end
    seen[armour] = true
end
for _, armour in ipairs(ARMOURS) do
    check(seen[armour], true, ARMOUR_NAMES[armour] .. " has classes")
end
check(#ARMOURS, 4, "four armour types")

-- Tally ----------------------------------------------------------------------
local ROSTER_20 = raid({
    DRUID = 3, ROGUE = 3, MONK = 2,   -- 8 leather
    MAGE = 3, PRIEST = 2,             -- 5 cloth
    HUNTER = 4,                       -- 4 mail
    WARRIOR = 3,                      -- 3 plate
})
local tally = TokenOdds.Tally(ROSTER_20)
check(tally.size, 20, "raid size")
check(TokenOdds.Count(tally, LEATHER), 8, "leather counted across classes")
check(TokenOdds.Count(tally, CLOTH), 5, "cloth counted")
check(TokenOdds.Count(tally, MAIL), 4, "mail counted")
check(TokenOdds.Count(tally, PLATE), 3, "plate counted")
check(TokenOdds.Count(tally, nil), nil, "no armour, no count")

local unknown = TokenOdds.Tally({ "MAGE", "GOBLINPUNCHER" })
check(unknown.size, 1, "a class with no armour type is left out of the raid size")

-- Verdict --------------------------------------------------------------------
check(TokenOdds.Verdict(tally, LEATHER), "worse", "8 of 20 beats the even quarter")
check(TokenOdds.Verdict(tally, CLOTH), "even", "5 of 20 is exactly a quarter")
check(TokenOdds.Verdict(tally, MAIL), "better", "4 of 20")
check(TokenOdds.Verdict(tally, nil), nil, "no armour, no verdict")
check(TokenOdds.Verdict({ size = 0, counts = {} }, CLOTH), nil, "an empty raid has no verdict")

-- A verdict never disagrees with the two percentages beside it.
local seven = TokenOdds.Tally(raid({ MAGE = 7, WARRIOR = 21 }))
check(TokenOdds.Verdict(seven, CLOTH), "even", "7 of 28 is exactly a quarter")
check(TokenOdds.YourOdds(seven, CLOTH), TokenOdds.FairOdds(seven), "so both odds match")

-- Odds ------------------------------------------------------------------------
-- One of eight leather wearers, where an even split of twenty would be five.
check(TokenOdds.YourOdds(tally, LEATHER), 1 / 8, "one chance in eight")
check(TokenOdds.FairOdds(tally), 4 / 20, "a fair split of twenty")
check(TokenOdds.YourOdds(tally, nil), 0, "no armour, no odds")
check(TokenOdds.FairOdds({ size = 0, counts = {} }), 0, "an empty raid has no fair split")

-- The user's example: 8 cloth in a 16 player group is 12.5% against a fair 25%.
local sixteen = TokenOdds.Tally(raid({ MAGE = 8, WARRIOR = 8 }))
check(TokenOdds.PercentText(TokenOdds.YourOdds(sixteen, CLOTH)), "12.5%", "one in eight reads as 12.5%")
check(TokenOdds.PercentText(TokenOdds.FairOdds(sixteen)), "25%", "a whole number drops its decimal")
check(TokenOdds.Verdict(sixteen, CLOTH), "worse", "half the fair odds is worse")

-- Standing --------------------------------------------------------------------
contains(TokenOdds.Standing(tally, LEATHER), "7 other Leather wearers", "others counted without you")
contains(TokenOdds.Standing(tally, LEATHER), "20 player group", "group size named")
contains(TokenOdds.Standing(TokenOdds.Tally({ "MAGE", "PRIEST" }), CLOTH), "1 other Cloth wearer",
    "a single rival is not pluralised")
contains(TokenOdds.Standing(TokenOdds.Tally({ "MAGE", "WARRIOR" }), CLOTH), "No one else",
    "being the only one is said outright")
check(TokenOdds.Standing(tally, nil), nil, "no armour, nothing to say")

-- The raid in front of you ---------------------------------------------------
ROSTER = ROSTER_20
local current, mine = TokenOdds.Current()
check(current.size, 20, "the roster is read from the raid units")
check(mine, LEATHER, "a druid is on leather")

-- The dialog builds and paints outside the game ------------------------------
TokenOdds.Toggle()
TokenOdds.Toggle()

ROSTER = {}
check(TokenOdds.Current().size, 0, "an empty roster still tallies")
TokenOdds.Toggle()  -- paints without dividing by zero
passed = passed + 1

-- /wishlist testtokens --------------------------------------------------------
TokenOdds.Test(16, 8)
local preview, previewArmour = TokenOdds.Current()
check(preview.size, 16, "the preview stands in for the real group")
check(TokenOdds.Count(preview, previewArmour), 8, "at the count asked for")
check(previewArmour, LEATHER, "wearing what the player wears")
check(TokenOdds.PercentText(TokenOdds.YourOdds(preview, previewArmour)), "12.5%", "and reads 12.5%")

TokenOdds.Test(4, 99)
check(TokenOdds.Count(TokenOdds.Current(), LEATHER), 4, "more sharers than players is capped")
TokenOdds.Test()
check(TokenOdds.Current().size, 16, "a bare command previews a sixteen player group")

print(passed .. " token odds tests passed")
