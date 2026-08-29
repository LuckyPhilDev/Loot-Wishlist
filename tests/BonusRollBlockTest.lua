-- luacheck: ignore 111 121

LootWishlist = {}
LootWishlistCharDB = {}

local instance = { name = "Somewhere", type = "none", difficulty = 0 }
function GetInstanceInfo() return instance.name, instance.type, instance.difficulty end
function GetDifficultyInfo() return nil, nil, false, nil, false, false end

local keystone = 0
C_ChallengeMode = { GetActiveKeystoneInfo = function() return keystone end }
C_Timer = { After = function() end }

local function newFrame()
    return setmetatable({ scripts = {} }, { __index = function(_, key)
        if key == "SetScript" then
            return function(self, event, fn) self.scripts[event] = fn end
        end
        if key == "GetFrameLevel" then return function() return 1 end end
        return function() end
    end })
end
function CreateFrame() return newFrame() end
GameTooltip = newFrame()

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_BonusRollBlock.lua")

local S = LootWishlist.Strings

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

check(Block.IsUnwanted(s, "dungeon", 0), false, "off by default, nothing is dismissed")

s.bonusRollAutoDismiss = true
check(Block.IsUnwanted(s, nil, 0), false, "an unidentified context is never dismissed")
check(Block.IsUnwanted(s, "dungeon", 0), true, "dungeons are not kept by default")
check(Block.IsUnwanted(s, "raidHeroic", 0), false, "Heroic raids are kept by default")
check(Block.IsUnwanted(s, "mythicplus", 10), false, "a key at the minimum level is kept")
check(Block.IsUnwanted(s, "mythicplus", 9), true, "a key below the minimum level is dismissed")

s.bonusRollKeepInRaids = false
check(Block.IsUnwanted(s, "raidHeroic", 0), true, "the raid master toggle overrides its difficulties")

s.bonusRollKeepInMythicPlus = false
check(Block.IsUnwanted(s, "mythicplus", 20), true, "Mythic+ off dismisses whatever the key level")

-- Only keep for flagged bosses
local flag = {}
Block.ApplyDefaults(flag)
flag.bonusRollAutoDismiss = true
check(Block.IsUnwanted(flag, "raidHeroic", 0, false), false, "off, an unflagged boss in kept content stays")

flag.bonusRollOnlyFlagged = true
check(Block.IsUnwanted(flag, "raidHeroic", 0, true), false, "a flagged boss in kept content stays")
check(Block.IsUnwanted(flag, "raidHeroic", 0, false), true, "an unflagged boss in kept content is passed")
check(Block.IsUnwanted(flag, "raidHeroic", 0, nil), false, "a boss the game named no journal entry for stays")
check(Block.IsUnwanted(flag, "dungeon", 0, true), true, "a flagged boss in unkept content is still passed")

-- Reading the roll's journal IDs off Blizzard's frame. The flag lives on a
-- wishlist item, so these run against the real BonusRoll module.
LootWishlistCharDB.bonusRollItems = { [200000] = true }
local tracked = {
  { id = 200000, encounterID = 2888, instanceID = 1320, isRaid = true },
  { id = 200001, encounterID = 2874, instanceID = 1320, isRaid = true },
}
function LootWishlist.GetTracked() return tracked end
dofile("src/LootWishlist_BonusRoll.lua")

check(Block.FlaggedForRoll(nil), nil, "no frame means no verdict")
check(Block.FlaggedForRoll({ encounterID = 0, instanceID = 0 }), nil, "a roll with no journal IDs has no verdict")
check(Block.FlaggedForRoll({ encounterID = 2888, instanceID = 1320 }), true, "the flagged boss is recognised")
check(Block.FlaggedForRoll({ encounterID = 2874, instanceID = 1320 }),
    false, "an unflagged boss in a raid holding a flag elsewhere is not kept")
check(Block.FlaggedForRoll({ encounterID = 0, instanceID = 1320 }),
    true, "a keystone roll with no encounter falls back to the instance")

-- A passed roll says who passed it and which setting decided
local function reasonFor(settings, ctx, keyLevel, isFlagged)
  local unwanted, reason = Block.IsUnwanted(settings, ctx, keyLevel, isFlagged)
  return unwanted and reason or nil
end

local why = {}
Block.ApplyDefaults(why)
why.bonusRollAutoDismiss = true
check(reasonFor(why, "dungeon", 0), "content", "an unkept content type reports itself")
check(reasonFor(why, "mythicplus", 5), "keyLevel", "a low key reports the key level, not the content")
check(reasonFor(why, "raidHeroic", 0), nil, "a kept boss is not passed and has no reason")

why.bonusRollOnlyFlagged = true
check(reasonFor(why, "raidHeroic", 0, false), "notFlagged", "an unflagged boss reports the flag")

check(Block.Message(why, "dungeon", "content", "pass"),
    "Bonus Roll passed, you do not keep the popup in Dungeons.", "the content message names the content")
check(Block.Message(why, "mythicplus", "keyLevel", "pass"),
    "Bonus Roll passed, this key is below your minimum of 10.", "the key level message names the minimum")
check(Block.Message(why, "somewhere new", "content", "pass"),
    S.bonusRollBlock.passedPlain, "an unnamed context still says the roll was passed")

-- The same reason reads either way round, so locking and passing share it
check(Block.ReasonText(why, "dungeon", "content"),
    "you do not keep the popup in Dungeons", "the reason is a clause on its own")
check(Block.Message(why, "dungeon", "content", "lock"),
    "Bonus Roll locked, you do not keep the popup in Dungeons. Click the dice to unlock it.",
    "locking names the same reason and says how to undo it")
check(Block.Message(why, "somewhere new", "content", "lock"),
    S.bonusRollBlock.lockedPlain, "an unnamed context still says the roll was locked")

-- Locking is the default, so a fresh character cannot lose a roll to a setting
-- they have not understood yet.
local fresh = {}
Block.ApplyDefaults(fresh)
check(Block.ActionFor(fresh), "lock", "a popup nobody configured is locked, not passed")
fresh.bonusRollUnwantedAction = "pass"
check(Block.ActionFor(fresh), "pass", "passing is what the other setting means")
fresh.bonusRollUnwantedAction = "nonsense"
check(Block.ActionFor(fresh), "lock", "an unreadable setting falls back to the safe action")

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

-- Locking the roll. The button carries no disabled art of its own, so the
-- greying has to be applied and taken back off with it.
local normalTexture = { desaturated = false, r = 1 }
BonusRollFrame = { PromptFrame = { RollButton = newFrame() } }
local roll = BonusRollFrame.PromptFrame.RollButton
roll.enabled = true
roll.Enable = function(self) self.enabled = true end
roll.Disable = function(self) self.enabled = false end
roll.GetNormalTexture = function() return {
    SetDesaturated = function(_, on) normalTexture.desaturated = on end,
    SetVertexColor = function(_, r) normalTexture.r = r end,
} end

check(Block.Lock("nothing flagged here"), true, "locking finds the roll button")
check(roll.enabled, false, "the roll button is disabled")
check(normalTexture.desaturated, true, "and greyed, since it has no disabled art")

Block.Unlock()
check(roll.enabled, true, "unlocking gives the roll back")
check(normalTexture.desaturated, false, "and takes the greying off")
check(normalTexture.r, 1, "restoring the colour, not leaving it dimmed")

BonusRollFrame = nil
check(Block.Lock("no frame"), false, "locking without the frame reports failure rather than erroring")

print(string.format("BonusRollBlockTest: %d checks passed", passed))
