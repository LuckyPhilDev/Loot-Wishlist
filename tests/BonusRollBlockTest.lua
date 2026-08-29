-- luacheck: ignore 111 121

LootWishlist = {}
LootWishlistCharDB = {}

local instance = { name = "Somewhere", type = "none", difficulty = 0 }
function GetInstanceInfo() return instance.name, instance.type, instance.difficulty end
function GetDifficultyInfo() return nil, nil, false, nil, false, false end

local keystone = 0
C_ChallengeMode = { GetActiveKeystoneInfo = function() return keystone end }
C_Timer = { After = function() end }
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function() end }
end

dofile("src/LootWishlist_BonusRollBlock.lua")

local Block = LootWishlist.BonusRollBlock
local passed = 0

local function check(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
    passed = passed + 1
end

local function inInstance(instanceType, difficulty, keyLevel)
    instance.type, instance.difficulty = instanceType, difficulty
    keystone = keyLevel or 0
end

-- Context detection
inInstance("party", 8)
check(Block.DetectContext(), "mythicplus", "a keystone difficulty reads as Mythic+")
inInstance("party", 23, 12)
check(Block.DetectContext(), "mythicplus", "an active keystone reads as Mythic+ whatever the difficulty")
inInstance("party", 2)
check(Block.DetectContext(), "dungeon", "a party instance with no key is a dungeon")
inInstance("raid", 15)
check(Block.DetectContext(), "raidHeroic", "difficulty 15 is a Heroic raid")
inInstance("raid", 233)
check(Block.DetectContext(), "raidMythic", "the flexible Mythic difficulty is a Mythic raid")
inInstance("none", 216)
check(Block.DetectContext(), "delve", "a delve difficulty is a delve")
inInstance("none", 0)
check(Block.DetectContext(), "hunts", "open world falls back to hunts")

-- An unlisted raid difficulty is classified from the game's own display flags
inInstance("raid", 999)
GetDifficultyInfo = function() return nil, nil, false, nil, false, true end
check(Block.DetectContext(), "raidMythic", "an unknown raid difficulty flagged Mythic reads as Mythic")
GetDifficultyInfo = function() return nil, nil, false, nil, false, false end
check(Block.DetectContext(), nil, "an unclassifiable raid difficulty has no context")

-- Dismissal
local s = {}
Block.ApplyDefaults(s)

check(Block.ShouldDismiss(s, "dungeon", 0), false, "off by default, nothing is dismissed")

s.bonusRollAutoDismiss = true
check(Block.ShouldDismiss(s, nil, 0), false, "an unidentified context is never dismissed")
check(Block.ShouldDismiss(s, "dungeon", 0), true, "dungeons are not kept by default")
check(Block.ShouldDismiss(s, "raidHeroic", 0), false, "Heroic raids are kept by default")
check(Block.ShouldDismiss(s, "mythicplus", 10), false, "a key at the minimum level is kept")
check(Block.ShouldDismiss(s, "mythicplus", 9), true, "a key below the minimum level is dismissed")

s.bonusRollKeepInRaids = false
check(Block.ShouldDismiss(s, "raidHeroic", 0), true, "the raid master toggle overrides its difficulties")

s.bonusRollKeepInMythicPlus = false
check(Block.ShouldDismiss(s, "mythicplus", 20), true, "Mythic+ off dismisses whatever the key level")

-- Only keep for flagged bosses
local flag = {}
Block.ApplyDefaults(flag)
flag.bonusRollAutoDismiss = true
check(Block.ShouldDismiss(flag, "raidHeroic", 0, false), false, "off, an unflagged boss in kept content stays")

flag.bonusRollOnlyFlagged = true
check(Block.ShouldDismiss(flag, "raidHeroic", 0, true), false, "a flagged boss in kept content stays")
check(Block.ShouldDismiss(flag, "raidHeroic", 0, false), true, "an unflagged boss in kept content is passed")
check(Block.ShouldDismiss(flag, "raidHeroic", 0, nil), false, "a boss the game named no journal entry for stays")
check(Block.ShouldDismiss(flag, "dungeon", 0, true), true, "a flagged boss in unkept content is still passed")

-- Reading the roll's journal IDs off Blizzard's frame. The flag lives on a
-- wishlist item, so these run against the real BonusRoll module.
LootWishlistCharDB.bonusRollItems = { [200000] = true }
local tracked = {
  { id = 200000, encounterID = 2888, instanceID = 1320, isRaid = true },
  { id = 200001, encounterID = 2874, instanceID = 1320, isRaid = true },
}
function LootWishlist.GetTracked() return tracked end
LootWishlist.Strings = { bonusRoll = {} }
dofile("src/LootWishlist_BonusRoll.lua")

check(Block.FlaggedForRoll(nil), nil, "no frame means no verdict")
check(Block.FlaggedForRoll({ encounterID = 0, instanceID = 0 }), nil, "a roll with no journal IDs has no verdict")
check(Block.FlaggedForRoll({ encounterID = 2888, instanceID = 1320 }), true, "the flagged boss is recognised")
check(Block.FlaggedForRoll({ encounterID = 2874, instanceID = 1320 }),
    false, "an unflagged boss in a raid holding a flag elsewhere is not kept")
check(Block.FlaggedForRoll({ encounterID = 0, instanceID = 1320 }),
    true, "a keystone roll with no encounter falls back to the instance")

-- Migration keeps the flags the player set in Lucky's Grab-bag
local target = {}
check(Block.MigrateFromGrabBag(nil, target), false, "no Grab-bag database means no migration")
check(Block.MigrateFromGrabBag({ bonusRollAutoDismiss = true, bonusRollKeepInHunts = true }, target),
    true, "Grab-bag flags migrate across")
check(target.bonusRollAutoDismiss, true, "the master toggle carried over")
check(target.bonusRollKeepInHunts, true, "a keep flag carried over")
check(Block.MigrateFromGrabBag({ bonusRollAutoDismiss = false }, target),
    false, "an already migrated character is left alone")
check(target.bonusRollAutoDismiss, true, "the second migration did not overwrite")

print(string.format("BonusRollBlockTest: %d checks passed", passed))
