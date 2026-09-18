-- Loot Wishlist - Roll History notice.
-- Odds and won ticks only know the rolls this addon has seen, so a character
-- who spent charges before installing starts with odds that are too high. This
-- asks once, beside the first window they open rather than mid-game, and takes
-- them to Roll History.
--
-- A card of our own rather than Blizzard's HelpTip: HelpTip goes silent under
-- the Tutorials setting, which the veterans this is for have usually turned off.

LootWishlist = LootWishlist or {}
LootWishlist.RollHistoryNotice = LootWishlist.RollHistoryNotice or {}
local Notice = LootWishlist.RollHistoryNotice
local S = LootWishlist.Strings.rollHistoryNotice

local WIDTH = 280
local PAD   = 14

local card

local function charDB()
  LootWishlistCharDB = LootWishlistCharDB or {}
  return LootWishlistCharDB
end

-- Any history on record means the player has either found the feature or had
-- the addon for every roll they made, and neither needs asking.
function Notice.ShouldShow(db, hasHistory)
  return not db.rollHistoryNoticeDone and not hasHistory
end

function Notice.Acknowledge()
  charDB().rollHistoryNoticeDone = true
  if card then card:Hide() end
end

local function ensureCard()
  if card then return card end
  local UI, C = LuckyUI, LuckyUI.C

  card = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  card:SetWidth(WIDTH)
  card:SetClampedToScreen(true)
  card:EnableMouse(true)
  card:SetBackdrop(UI.Backdrop)
  card:SetBackdropColor(C.bgDark[1], C.bgDark[2], C.bgDark[3], 0.95)
  card:SetBackdropBorderColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3])

  local function text(font, size, color, anchor, gap)
    local fs = card:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font, size)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetWidth(WIDTH - PAD * 2)
    if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
    else fs:SetPoint("TOPLEFT", PAD, -PAD) end
    return fs
  end
  card.title = text(UI.TITLE_FONT, 13, C.goldPrimary)
  card.title:SetText(S.title)
  card.body = text(UI.BODY_FONT, 12, C.textLight, card.title, 8)
  card.body:SetText(S.body)
  card.later = text(UI.BODY_FONT, 11, C.textMuted, card.body, 8)
  card.later:SetText(S.later)

  local fill = UI.CreateButton(card, S.fillIn, 120, 22, "primary")
  fill:SetPoint("BOTTOMLEFT", PAD, PAD)
  fill:SetScript("OnClick", function() LootWishlist.Browser.openHistory() end)

  local dismiss = UI.CreateButton(card, S.dismiss, 120, 22, "secondary")
  dismiss:SetPoint("LEFT", fill, "RIGHT", 8, 0)
  dismiss:SetScript("OnClick", Notice.Acknowledge)

  local textHeight = card.title:GetStringHeight() + card.body:GetStringHeight()
    + card.later:GetStringHeight() + 16
  card:SetHeight(PAD * 3 + textHeight + 22)
  card:Hide()
  return card
end

-- Docks to the window that asked, so it closes with it. A card already on
-- screen stays put rather than jumping to the second window opened. Visible,
-- not shown: a card whose window closed still reads as shown.
function Notice.MaybeShow(owner)
  if not owner then return end
  local Odds = LootWishlist.BonusRollOdds
  if not Notice.ShouldShow(charDB(), Odds and Odds.HasHistory()) then return end
  local c = ensureCard()
  if c:IsVisible() then return end
  c:SetParent(owner)
  c:SetFrameStrata(owner:GetFrameStrata())
  c:SetFrameLevel(owner:GetFrameLevel() + 10)
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
  c:Show()
end
