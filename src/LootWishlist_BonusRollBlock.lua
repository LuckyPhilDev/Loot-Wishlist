-- Loot Wishlist - Bonus Roll blocking.
-- Hooks BonusRollFrame:OnShow and clicks Pass in content the player has not
-- chosen to keep the popup for. Settings are per-character.

LootWishlist = LootWishlist or {}
LootWishlist.BonusRollBlock = LootWishlist.BonusRollBlock or {}
local Block = LootWishlist.BonusRollBlock

local DEFAULTS = {
  bonusRollAutoDismiss        = false,
  bonusRollUnwantedAction     = "lock",
  bonusRollOnlyFlagged        = false,
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

local function keptByContent(s, ctx, keystoneLevel)
  local keepKey = KEEP_KEYS[ctx]

  if RAID_CONTEXTS[ctx] then
    return (s.bonusRollKeepInRaids and s[keepKey]) == true, "content"
  end

  if ctx == "mythicplus" then
    if not s.bonusRollKeepInMythicPlus then return false, "content" end
    return (keystoneLevel or 0) >= (s.bonusRollMythicPlusMinLevel or 1), "keyLevel"
  end

  return (keepKey and s[keepKey]) == true, "content"
end

-- Returns true and the reason when the player would not have wanted this popup.
-- An unidentifiable context, or a boss the game named no journal entry for, is
-- always wanted: an extra popup is harmless, passing a wanted roll is not.
function Block.IsUnwanted(s, ctx, keystoneLevel, flagged, scope)
  if not s.bonusRollAutoDismiss then return false end
  if not ctx then return false end

  local kept, reason = keptByContent(s, ctx, keystoneLevel)
  if not kept then return true, reason end

  if not s.bonusRollOnlyFlagged then return false end
  if flagged == nil or flagged then return false end
  return true, scope == "instance" and "notFlaggedDungeon" or "notFlaggedBoss"
end

-- Acting on a roll for someone happens behind their back, so it says who did it
-- and which of their own settings decided it.
function Block.ReasonText(s, ctx, reason)
  local S = LootWishlist.Strings.bonusRollBlock
  if reason == "keyLevel" then
    return S.keyLevel:format(s.bonusRollMythicPlusMinLevel or 1)
  end
  if reason == "notFlaggedBoss" then return S.notFlaggedBoss end
  if reason == "notFlaggedDungeon" then return S.notFlaggedDungeon end
  -- Guarded on KEEP_KEYS rather than the lookup: a missing string comes back as
  -- a loud placeholder, not nil, so it would read as a name we recognise.
  if KEEP_KEYS[ctx] then return S.content:format(S.contexts[ctx]) end
  return nil
end

function Block.Message(s, ctx, reason, action)
  local S = LootWishlist.Strings.bonusRollBlock
  local clause = Block.ReasonText(s, ctx, reason)
  if action == "pass" then
    return clause and S.passed:format(clause) or S.passedPlain
  end
  return clause and S.locked:format(clause) or S.lockedPlain
end

function Block.ActionFor(s)
  return s.bonusRollUnwantedAction == "pass" and "pass" or "lock"
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

-- nil means the roll could not be tied to a journal boss or instance, which the
-- caller reads as "do not judge this one on flags". The scope says which of the
-- two was matched, so the wording can name what was actually looked at rather
-- than what the content type suggests.
function Block.FlaggedForRoll(frame)
  local BR = LootWishlist.BonusRoll
  if not (frame and BR and BR.HasFlaggedForRoll) then return nil end

  local encounterID, instanceID = frame.encounterID, frame.instanceID
  if (encounterID or 0) == 0 and (instanceID or 0) == 0 then return nil end

  local scope = (encounterID or 0) ~= 0 and "encounter" or "instance"
  return BR.HasFlaggedForRoll(encounterID, instanceID), scope
end

local function rollButton()
  return BonusRollFrame
    and BonusRollFrame.PromptFrame
    and BonusRollFrame.PromptFrame.RollButton
end

-- The button carries no disabled texture of its own, so being unclickable would
-- look no different from being ready. The greying is ours.
local function paintRollButton(btn, on)
  local tex = btn.GetNormalTexture and btn:GetNormalTexture()
  if not tex then return end
  tex:SetDesaturated(on)
  if on then tex:SetVertexColor(0.5, 0.5, 0.5) else tex:SetVertexColor(1, 1, 1) end
end

-- A disabled button fires no OnEnter, so the reason would have nowhere to live.
-- This sits over the dice and carries both the tooltip and the unlock click.
local lockOverlay
local function ensureOverlay()
  if lockOverlay then return lockOverlay end
  local btn = rollButton()
  if not btn then return nil end

  lockOverlay = CreateFrame("Button", nil, BonusRollFrame.PromptFrame)
  lockOverlay:SetAllPoints(btn)
  lockOverlay:SetFrameLevel(btn:GetFrameLevel() + 1)

  lockOverlay:SetScript("OnEnter", function(self)
    local S = LootWishlist.Strings.bonusRollBlock
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.lockTitle, 1, 0.3, 0.3)
    if self.reason then GameTooltip:AddLine(self.reason, 1, 1, 1, true) end
    GameTooltip:AddLine(S.lockHint, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  lockOverlay:SetScript("OnLeave", function() GameTooltip:Hide() end)
  lockOverlay:SetScript("OnClick", function() Block.Unlock() end)
  lockOverlay:Hide()
  return lockOverlay
end

function Block.Lock(reason)
  local btn = rollButton()
  if not btn then return false end
  btn:Disable()
  paintRollButton(btn, true)

  local overlay = ensureOverlay()
  if overlay then
    overlay.reason = reason
    overlay:Show()
  end
  return true
end

function Block.Unlock()
  local btn = rollButton()
  if btn then
    btn:Enable()
    paintRollButton(btn, false)
  end
  if lockOverlay then
    lockOverlay:Hide()
    if GameTooltip:IsOwned(lockOverlay) then GameTooltip:Hide() end
  end
end

local function onBonusRollShow()
  local s = Block.GetSettings()
  local ctx = Block.DetectContext()
  local flagged, scope = Block.FlaggedForRoll(BonusRollFrame)
  local unwanted, reason = Block.IsUnwanted(s, ctx, getKeystoneLevel(), flagged, scope)
  DevLog("popup shown in", tostring(ctx), "flagged:", tostring(flagged), "reason:", tostring(reason))

  -- A wanted popup still clears the lock: the previous roll may have left one
  -- on, and the buttons are reused rather than rebuilt.
  if not unwanted then return Block.Unlock() end

  local action = Block.ActionFor(s)
  print(LootWishlist.Strings.addon.prefix .. Block.Message(s, ctx, reason, action))

  if action == "pass" then
    -- Defer one frame so the prompt is fully constructed before clicking.
    Block.Unlock()
    C_Timer.After(0, clickPass)
  else
    Block.Lock(Block.ReasonText(s, ctx, reason))
  end
end

local hooked = false
local function tryHook()
  if hooked then return true end
  if not BonusRollFrame then return false end
  BonusRollFrame:HookScript("OnShow", onBonusRollShow)
  BonusRollFrame:HookScript("OnHide", Block.Unlock)
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
