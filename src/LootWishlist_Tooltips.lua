-- Loot Wishlist - Tooltips
-- Keeps the item tooltip, and Blizzard's Equipped comparison tooltips,
-- off the wishlist windows they are describing.

LootWishlist = LootWishlist or {}
LootWishlist.UI = LootWishlist.UI or {}

------------------------------------------------------------------------
-- Which side of the window the tooltips open on
------------------------------------------------------------------------
-- A tooltip anchored to the hovered row opens across the window as soon as the
-- window sits on the right of the screen, and the Equipped comparisons then
-- stack back over the list. The window's centre picks the side instead: a window
-- on the left half of the screen opens its tooltips to the right, one on the
-- right half opens them to the left, and the comparisons run on outwards from
-- the tooltip.
local TipLog = LuckyLog:New("|cff88ff88[LWL-tip]|r", function() return LootWishlist.IsDebug and LootWishlist.IsDebug() end)

local function windowFor(region)
  while region do
    if region.lootWishlistWindow then return region end
    region = region:GetParent()
  end
end

local function sideFor(win)
  local centre = (win:GetLeft() + win:GetRight()) / 2
  return centre < GetScreenWidth() / 2 and "right" or "left"
end

-- Opens GameTooltip beside the window the owner sits in. Callers fill and show
-- the tooltip themselves, exactly as they would after their own SetOwner.
function LootWishlist.UI.AnchorItemTooltip(owner)
  local win = windowFor(owner)
  if not win then
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    return
  end

  local side = sideFor(win)
  GameTooltip:SetOwner(owner, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  if side == "right" then
    GameTooltip:SetPoint("TOPLEFT", win, "TOPRIGHT", 4, 0)
  else
    GameTooltip:SetPoint("TOPRIGHT", win, "TOPLEFT", -4, 0)
  end
  TipLog(string.format("tooltip to the %s of the window", side))
end

-- Whoever placed the comparisons measured the GameTooltip alone, which lands them
-- back over the window whenever the tooltip opened on the window's far side.
-- Re-anchor them outwards from the tooltip instead, on the side the window chose.
-- Public because the client decides when comparisons appear, so every path that
-- can raise one calls this once the tooltip is up.
function LootWishlist.UI.PlaceComparisonTooltips()
  local win = windowFor(GameTooltip:GetOwner())
  if not win then return end

  local side = sideFor(win)
  local point, relativePoint = "TOPLEFT", "TOPRIGHT"
  if side == "left" then point, relativePoint = "TOPRIGHT", "TOPLEFT" end

  local relativeTo, placed = GameTooltip, 0
  for _, comparison in ipairs(GameTooltip.shoppingTooltips or {}) do
    if comparison:IsShown() then
      comparison:ClearAllPoints()
      comparison:SetPoint(point, relativeTo, relativePoint, 0, relativeTo == GameTooltip and -10 or 0)
      relativeTo, placed = comparison, placed + 1
    end
  end
  TipLog(string.format("%d of %d comparisons to the %s", placed, #(GameTooltip.shoppingTooltips or {}), side))
end

------------------------------------------------------------------------
-- Triggers
------------------------------------------------------------------------
-- Holding the compare modifier raises the comparisons without the row's OnEnter
-- running again, so catch them as they show. Their own placement happens after
-- OnShow, hence the frame's wait.
for _, comparison in ipairs(GameTooltip.shoppingTooltips or {}) do
  comparison:HookScript("OnShow", function()
    C_Timer.After(0, LootWishlist.UI.PlaceComparisonTooltips)
  end)
end

-- Where the comparison manager still drives this, take its placement as it lands
-- rather than a frame later, and stop it sliding the tooltip: it slides whichever
-- anchor frame it was handed, so hand it a stand-in over the tooltip.
if type(TooltipComparisonManager) == "table" then
  if TooltipComparisonManager.Initialize then
    local anchorProxy = CreateFrame("Frame", nil, UIParent)
    anchorProxy.SetAnchorType = function() end
    hooksecurefunc(TooltipComparisonManager, "Initialize", function(mgr)
      if not windowFor(mgr.tooltip:GetOwner()) then return end
      anchorProxy:ClearAllPoints()
      anchorProxy:SetPoint("TOPLEFT", mgr.tooltip)
      anchorProxy:SetPoint("BOTTOMRIGHT", mgr.tooltip)
      mgr.anchorFrame = anchorProxy
    end)
  end
  if TooltipComparisonManager.AnchorShoppingTooltips then
    hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", LootWishlist.UI.PlaceComparisonTooltips)
  end
end
