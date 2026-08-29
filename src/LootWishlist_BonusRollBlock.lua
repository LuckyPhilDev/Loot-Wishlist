-- Loot Wishlist - Bonus Roll blocking.
-- Hooks BonusRollFrame:OnShow and clicks Pass in content the player has not
-- chosen to keep the popup for. Settings are per-character.

LootWishlist = LootWishlist or {}
LootWishlist.BonusRollBlock = LootWishlist.BonusRollBlock or {}
local Block = LootWishlist.BonusRollBlock

local DEFAULTS = {
  bonusRollAutoDismiss        = false,
  bonusRollKeepInMythicPlus   = true,
  bonusRollMythicPlusMinLevel = 10,
  bonusRollKeepInRaids        = true,
  bonusRollKeepInLFR          = true,
  bonusRollKeepInNormalRaid   = true,
  bonusRollKeepInHeroicRaid   = true,
  bonusRollKeepInMythicRaid   = true,
  bonusRollKeepInDelve        = false,
  bonusRollKeepInDungeon      = false,
  bonusRollKeepInHunts        = false,
}

local KEEP_KEYS = {
  mythicplus = "bonusRollKeepInMythicPlus",
  raidLFR    = "bonusRollKeepInLFR",
  raidNormal = "bonusRollKeepInNormalRaid",
  raidHeroic = "bonusRollKeepInHeroicRaid",
  raidMythic = "bonusRollKeepInMythicRaid",
  delve      = "bonusRollKeepInDelve",
  dungeon    = "bonusRollKeepInDungeon",
  hunts      = "bonusRollKeepInHunts",
}

local RAID_CONTEXTS = {
  raidLFR = true, raidNormal = true, raidHeroic = true, raidMythic = true,
}

-- IDs not listed here are classified at runtime from the game's own difficulty
-- flags, so a newly added difficulty still reads correctly.
local RAID_DIFFICULTY_TO_CONTEXT = {
  [17]  = "raidLFR",
  [7]   = "raidLFR",
  [14]  = "raidNormal",
  [15]  = "raidHeroic",
  [16]  = "raidMythic",
  [233] = "raidMythic",
}

local DELVE_DIFFICULTY_IDS = {
  [208] = true, [215] = true, [216] = true, [217] = true,
  [218] = true, [219] = true, [220] = true,
}

local DevLog = LuckyLog and LuckyLog:New("[Lwl-BRB][debug]", function()
  return LootWishlist.IsDebug and LootWishlist.IsDebug()
end) or function() end

function Block.GetSettings()
  LootWishlistCharDB = LootWishlistCharDB or {}
  LootWishlistCharDB.settings = LootWishlistCharDB.settings or {}
  return LootWishlistCharDB.settings
end

-- Reads the flags the player set while the feature lived in Lucky's Grab-bag,
-- so moving it here does not reset their choices.
function Block.MigrateFromGrabBag(source, target)
  if type(source) ~= "table" then return false end
  if target.bonusRollAutoDismiss ~= nil then return false end
  local migrated = false
  for key in pairs(DEFAULTS) do
    if source[key] ~= nil then
      target[key] = source[key]
      migrated = true
    end
  end
  return migrated
end

function Block.ApplyDefaults(s)
  for key, value in pairs(DEFAULTS) do
    if s[key] == nil then s[key] = value end
  end
end

local function classifyRaidContext(difficultyID)
  local explicit = RAID_DIFFICULTY_TO_CONTEXT[difficultyID]
  if explicit then return explicit end

  local _, _, isHeroic, _, displayHeroic, displayMythic = GetDifficultyInfo(difficultyID)
  if displayMythic then return "raidMythic" end
  if isHeroic or displayHeroic then return "raidHeroic" end
  return nil
end

local function getKeystoneLevel()
  if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
    local level = C_ChallengeMode.GetActiveKeystoneInfo()
    if type(level) == "number" and level > 0 then return level end
  end
  return 0
end

function Block.DetectContext()
  local _, instanceType, difficultyID = GetInstanceInfo()

  if difficultyID == 8 or getKeystoneLevel() > 0 then return "mythicplus" end
  if instanceType == "raid" then return classifyRaidContext(difficultyID) end
  if DELVE_DIFFICULTY_IDS[difficultyID] then return "delve" end
  if instanceType == "party" then return "dungeon" end

  return "hunts"
end

-- Returns true when the popup should be passed. An unidentifiable context is
-- never dismissed: an extra popup is harmless, passing a wanted roll is not.
function Block.ShouldDismiss(s, ctx, keystoneLevel)
  if not s.bonusRollAutoDismiss then return false end
  if not ctx then return false end

  local keepKey = KEEP_KEYS[ctx]

  if RAID_CONTEXTS[ctx] then
    return not (s.bonusRollKeepInRaids and s[keepKey])
  end

  if ctx == "mythicplus" then
    if not s.bonusRollKeepInMythicPlus then return true end
    return (keystoneLevel or 0) < (s.bonusRollMythicPlusMinLevel or 1)
  end

  return not (keepKey and s[keepKey])
end

local function clickPass()
  local btn = BonusRollFrame
    and BonusRollFrame.PromptFrame
    and BonusRollFrame.PromptFrame.PassButton
  if btn then
    btn:Click("LeftButton")
  elseif BonusRollFrame and BonusRollFrame.Hide then
    BonusRollFrame:Hide()
  end
end

local function onBonusRollShow()
  local ctx = Block.DetectContext()
  DevLog("popup shown in", tostring(ctx))
  if not Block.ShouldDismiss(Block.GetSettings(), ctx, getKeystoneLevel()) then return end

  -- Defer one frame so the prompt is fully constructed before clicking.
  C_Timer.After(0, clickPass)
end

local hooked = false
local function tryHook()
  if hooked then return true end
  if not BonusRollFrame then return false end
  BonusRollFrame:HookScript("OnShow", onBonusRollShow)
  hooked = true
  return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local s = Block.GetSettings()
    Block.MigrateFromGrabBag(LuckyGrabbagCharDB, s)
    Block.ApplyDefaults(s)
  end
  if tryHook() then f:UnregisterEvent("ADDON_LOADED") end
end)
