-- Loot Wishlist - Tier token competition.
-- Midnight splits tier tokens by armour type, four ways, so a quarter of a raid
-- is the even share of any one of them. More of the raid than that in your
-- armour and every token it drops is fought over harder than the game intends.

LootWishlist = LootWishlist or {}
LootWishlist.TokenOdds = LootWishlist.TokenOdds or {}
local TokenOdds = LootWishlist.TokenOdds
local S = LootWishlist.Strings.tokenOdds

local SETTLE_DELAY = 5  -- seconds for a roster to stop churning before speaking

local function armours()
  return LootWishlist.Const.TIER_TOKEN_ARMOURS
end

local function armourOf(classFile)
  return classFile and LootWishlist.Const.TIER_TOKEN_ARMOUR[classFile]
end

function TokenOdds.Tally(classFiles)
  local tally = { size = 0, counts = {} }
  for _, classFile in ipairs(classFiles) do
    local armour = armourOf(classFile)
    if armour then
      tally.size = tally.size + 1
      tally.counts[armour] = (tally.counts[armour] or 0) + 1
    end
  end
  return tally
end

function TokenOdds.Count(tally, armour)
  if not (tally and armour) then return nil end
  return tally.counts[armour] or 0
end

-- Compared as whole numbers so the verdict can never disagree with the
-- percentage the same numbers round to.
function TokenOdds.Verdict(tally, armour)
  local count = TokenOdds.Count(tally, armour)
  if not count or tally.size == 0 then return nil end
  local share = count * #armours()
  if share > tally.size then return "worse" end
  if share < tally.size then return "better" end
  return "even"
end

-- Every token of your armour is split between everyone wearing it, yourself
-- included, so eight of you is one chance in eight.
function TokenOdds.YourOdds(tally, armour)
  local count = TokenOdds.Count(tally, armour)
  if not count or count == 0 then return 0 end
  return 1 / count
end

-- The same odds had the group split evenly across the four armour types, which
-- is why a bigger group is worth less to any one player in it.
function TokenOdds.FairOdds(tally)
  if not tally or tally.size == 0 then return 0 end
  return #armours() / tally.size
end

-- A tenth of a percent is as fine as these ever get, one chance in eight being
-- 12.5%, and a whole number keeps its decimal off.
function TokenOdds.PercentText(fraction)
  local value = math.floor(fraction * 1000 + 0.5) / 10
  if value == math.floor(value) then return S.pctWhole:format(value) end
  return S.pctTenth:format(value)
end

local armourNames = {}
local function armourName(armour)
  if armourNames[armour] then return armourNames[armour] end
  local name = C_Item and C_Item.GetItemSubClassInfo
    and C_Item.GetItemSubClassInfo(Enum.ItemClass.Armor, armour)
  armourNames[armour] = name or tostring(armour)
  return armourNames[armour]
end

function TokenOdds.Standing(tally, armour)
  local count = TokenOdds.Count(tally, armour)
  if not count or count == 0 then return nil end
  local others, name = count - 1, armourName(armour)
  if others == 0 then return S.alone:format(name, tally.size) end
  if others == 1 then return S.oneOther:format(name, tally.size) end
  return S.manyOthers:format(others, name, tally.size)
end

------------------------------------------------------------------------
-- The raid in front of you
------------------------------------------------------------------------
local function rosterClasses()
  local classes = {}
  for index = 1, (GetNumGroupMembers() or 0) do
    local _, classFile = UnitClass("raid" .. index)
    if classFile then classes[#classes + 1] = classFile end
  end
  return classes
end

-- A made-up group standing in for the real one while /wishlist testtokens is
-- driving the window. Dropped when the window closes.
local preview

function TokenOdds.Current()
  if preview then return preview.tally, preview.armour end
  return TokenOdds.Tally(rosterClasses()), armourOf((select(2, UnitClass("player"))))
end

function TokenOdds.Enabled()
  local settings = (LootWishlistDB and LootWishlistDB.settings) or {}
  return settings.raidTokenOdds ~= false
end

------------------------------------------------------------------------
-- The dialog
------------------------------------------------------------------------
local PANEL_W, PANEL_H = 300, 180
local BAR_LEFT, BAR_RIGHT, BAR_H = 100, -72, 12
local BAR_W = PANEL_W - BAR_LEFT + BAR_RIGHT
local ROW_TOP, ROW_GAP = -86, 24
local HIDE_AFTER = 5    -- seconds a window that opened itself stays up

local panel

local function createRow(frame, index, label)
  local c = LuckyUI.C
  local y = ROW_TOP - (index - 1) * ROW_GAP
  local row = {}

  row.label = frame:CreateFontString(nil, "OVERLAY")
  row.label:SetFont(LuckyUI.BODY_FONT, 12)
  row.label:SetPoint("TOPLEFT", 14, y)
  row.label:SetJustifyH("LEFT")
  row.label:SetTextColor(c.textLight[1], c.textLight[2], c.textLight[3])
  row.label:SetText(label)

  row.track = frame:CreateTexture(nil, "ARTWORK")
  row.track:SetPoint("TOPLEFT", BAR_LEFT, y - 1)
  row.track:SetSize(BAR_W, BAR_H)
  row.track:SetColorTexture(c.bgInput[1], c.bgInput[2], c.bgInput[3], 1)

  row.fill = frame:CreateTexture(nil, "OVERLAY")
  row.fill:SetPoint("TOPLEFT", row.track, "TOPLEFT")
  row.fill:SetHeight(BAR_H)

  row.value = frame:CreateFontString(nil, "OVERLAY")
  row.value:SetFont(LuckyUI.BODY_FONT, 12)
  row.value:SetPoint("TOPRIGHT", -14, y)
  row.value:SetJustifyH("RIGHT")

  return row
end

local function buildPanel()
  local c = LuckyUI.C
  local frame = LuckyUI.CreatePanel("LootWishlistTokenOddsPanel", UIParent, PANEL_W, PANEL_H)
  frame:SetFrameStrata("DIALOG")
  LootWishlistCharDB = LootWishlistCharDB or {}
  LuckyUI.EnableDrag(frame, { db = LootWishlistCharDB, key = "tokenOddsWindow" })
  frame:Hide()
  frame:HookScript("OnHide", function() preview = nil end)
  tinsert(UISpecialFrames, frame:GetName())
  LuckyUI.CreateHeader(frame, S.title)

  frame.standing = frame:CreateFontString(nil, "OVERLAY")
  frame.standing:SetFont(LuckyUI.BODY_FONT, 12)
  frame.standing:SetTextColor(c.textLight[1], c.textLight[2], c.textLight[3])
  frame.standing:SetPoint("TOPLEFT", 14, -42)
  frame.standing:SetPoint("TOPRIGHT", -14, -42)
  frame.standing:SetJustifyH("LEFT")
  frame.standing:SetSpacing(2)

  frame.yours = createRow(frame, 1, S.yourOdds)
  frame.fair = createRow(frame, 2, S.fairOdds)

  frame.verdict = frame:CreateFontString(nil, "OVERLAY")
  frame.verdict:SetFont(LuckyUI.BODY_FONT, 12)
  frame.verdict:SetTextColor(c.textLight[1], c.textLight[2], c.textLight[3])
  frame.verdict:SetPoint("BOTTOMLEFT", 14, 14)
  frame.verdict:SetPoint("BOTTOMRIGHT", -14, 14)
  frame.verdict:SetJustifyH("LEFT")
  frame.verdict:SetSpacing(2)

  LuckyUI.EnableAutoHide(frame, HIDE_AFTER)

  return frame
end

-- Both bars are drawn against the longer of the two, so the shorter one reads
-- as the fraction of the other it actually is.
local function paintRow(row, odds, longest, color)
  row.value:SetText(TokenOdds.PercentText(odds))
  row.value:SetTextColor(color[1], color[2], color[3])
  row.fill:SetWidth(longest > 0 and math.max(1, BAR_W * odds / longest) or 1)
  row.fill:SetColorTexture(color[1], color[2], color[3], 1)
end

local function refresh()
  if not (panel and panel:IsShown()) then return end
  local c = LuckyUI.C
  local tally, mine = TokenOdds.Current()
  local verdict = TokenOdds.Verdict(tally, mine)
  local yours, fair = TokenOdds.YourOdds(tally, mine), TokenOdds.FairOdds(tally)

  panel.standing:SetText(TokenOdds.Standing(tally, mine) or S.noToken)
  paintRow(panel.yours, yours, math.max(yours, fair),
    verdict == "worse" and c.danger or c.success)
  paintRow(panel.fair, fair, math.max(yours, fair), c.goldMuted)
  panel.verdict:SetText(verdict and S[verdict] or "")
end

-- A window that opened itself takes itself away again. One you asked for stays
-- until you close it.
local function show(timed)
  panel = panel or buildPanel()
  panel:Show()
  refresh()
  if timed then panel:StartAutoHide() else panel:StopAutoHide() end
end

function TokenOdds.Toggle()
  if panel and panel:IsShown() then
    panel:Hide()
    return
  end
  if not IsInRaid() then
    print(LootWishlist.Strings.addon.prefix .. S.notInRaid)
    return
  end
  show(false)
end

-- /wishlist testtokens [group size] [wearing your armour]
function TokenOdds.Test(size, sharing)
  size = math.max(1, tonumber(size) or 16)
  sharing = math.min(size, math.max(1, tonumber(sharing) or math.floor(size / 2)))
  local mine = armourOf((select(2, UnitClass("player")))) or armours()[1]
  preview = {
    armour = mine,
    tally = { size = size, counts = { [mine] = sharing } },
  }
  show(true)
  print(("Loot Wishlist: token odds preview, %d of %d wearing %s.")
    :format(sharing, size, armourName(mine)))
end

------------------------------------------------------------------------
-- Opening itself as the raid fills
------------------------------------------------------------------------
-- The settle delay collapses a burst of joins into one opening, so a raid
-- filling ten at a time is answered once rather than ten times.
local function rosterSettled()
  if not IsInRaid() then
    if panel then panel:Hide() end
    return
  end
  -- A window arriving mid-pull is worse than no window, so combat only
  -- repaints one already open. The next join opens it.
  if TokenOdds.Enabled() and not InCombatLockdown() then show(true) else refresh() end
end

local settling = false
local f = CreateFrame("Frame")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
  if settling then return end
  settling = true
  C_Timer.After(SETTLE_DELAY, function()
    settling = false
    rosterSettled()
  end)
end)
