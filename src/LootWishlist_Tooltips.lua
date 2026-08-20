-- Loot Wishlist - Tooltips
-- Keeps the item tooltip, and Blizzard's Equipped comparison tooltips,
-- off the wishlist windows they are describing.

LootWishlist = LootWishlist or {}
LootWishlist.UI = LootWishlist.UI or {}

------------------------------------------------------------------------
-- Which side of the window the tooltips open on
------------------------------------------------------------------------
-- A tooltip anchored to the hovered row opens across the window as soon as the
-- window sits on the right of the screen, and Blizzard then stacks the Equipped
-- comparisons back over the list. The window's centre picks the side instead: a
-- window on the left half of the screen opens its tooltips to the right, one on
-- the right half opens them to the left, and the comparisons carry on outwards
-- from the tooltip.
local tooltipSide = "right"

-- The manager slides the tooltip sideways when the comparisons run out of room,
-- which would drag it back over the window. It slides whichever anchor frame it
-- was handed, so hand it a stand-in over the tooltip that swallows the slide.
local anchorProxy = CreateFrame("Frame", nil, UIParent)
anchorProxy.SetAnchorType = function() end

local TipLog = LuckyLog:New("|cff88ff88[LWL-tip]|r", function() return LootWishlist.IsDebug and LootWishlist.IsDebug() end)

local function comparisonWindowFor(region)
  while region do
    if region.lootWishlistWindow then return region end
    region = region:GetParent()
  end
end

-- Opens GameTooltip beside the window the owner sits in. Callers fill and show
-- the tooltip themselves, exactly as they would after their own SetOwner.
function LootWishlist.UI.AnchorItemTooltip(owner)
  local win = comparisonWindowFor(owner)
  if not win then
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    return
  end

  tooltipSide = ((win:GetLeft() + win:GetRight()) / 2 < GetScreenWidth() / 2) and "right" or "left"
  GameTooltip:SetOwner(owner, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  if tooltipSide == "right" then
    GameTooltip:SetPoint("TOPLEFT", win, "TOPRIGHT", 4, 0)
  else
    GameTooltip:SetPoint("TOPRIGHT", win, "TOPLEFT", -4, 0)
  end
  TipLog(string.format("tooltip to the %s of the window", tooltipSide))
end

hooksecurefunc(TooltipComparisonManager, "Initialize", function(mgr)
  if not comparisonWindowFor(mgr.tooltip:GetOwner()) then return end
  anchorProxy:ClearAllPoints()
  anchorProxy:SetPoint("TOPLEFT", mgr.tooltip)
  anchorProxy:SetPoint("BOTTOMRIGHT", mgr.tooltip)
  mgr.anchorFrame = anchorProxy
end)

-- Blizzard picks the comparison side from numbers read before the tooltip has
-- been sized, so place them again once it has finished, running outwards from
-- the tooltip on the side the window chose.
hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", function(mgr)
  if not (mgr.tooltip and comparisonWindowFor(mgr.tooltip:GetOwner())) then return end

  local point, relativePoint = "TOPLEFT", "TOPRIGHT"
  if tooltipSide == "left" then point, relativePoint = "TOPRIGHT", "TOPLEFT" end

  local relativeTo, placed = mgr.tooltip, 0
  for _, comparison in ipairs(mgr.tooltip.shoppingTooltips) do
    if comparison:IsShown() then
      comparison:ClearAllPoints()
      comparison:SetPoint(point, relativeTo, relativePoint, 0, relativeTo == mgr.tooltip and -10 or 0)
      relativeTo, placed = comparison, placed + 1
    end
  end
  TipLog(string.format("%d comparisons to the %s", placed, tooltipSide))
end)

