-- luacheck: ignore 111 112 113 121 122 131
-- Replays Blizzard's comparison anchoring (TooltipComparisonManager:AnchorShoppingTooltips,
-- x axis only, both tooltips clamped to screen as the client clamps them) against the
-- anchor frame LootWishlist_UI.lua hands the manager, and checks the Equipped tooltips
-- land clear of the wishlist window wherever the window sits.

local SCREEN_W = 1366
local WINDOW_W = 520
local TOOLTIP_W = 240
local COMPARISON_W = 236

local function noop() end
local stubMeta = { __index = function() return noop end }

local function frame(fields)
  local f = setmetatable(fields or {}, stubMeta)
  f.points = {}
  f.GetLeft = function(self) return self.left end
  f.GetRight = function(self) return self.right end
  f.GetParent = function(self) return self.parent end
  f.ClearAllPoints = function(self) self.points = {} end
  f.SetPoint = function(self, point, rel, relPoint)
    if point == "TOPLEFT" then self.left = rel.left end
    if point == "RIGHT" and relPoint == "RIGHT" then self.right = rel.right end
  end
  return f
end

------------------------------------------------------------------------
-- Load the addon's hook
------------------------------------------------------------------------
local hooks = {}
LootWishlist = { Const = setmetatable({}, stubMeta) }
LuckyUI = setmetatable({ C = setmetatable({}, { __index = function() return { 0, 0, 0, 1 } end }) }, stubMeta)
LuckyLog = { New = function() return setmetatable({}, stubMeta) end }
UIParent = frame()
TooltipComparisonManager = { Initialize = noop }
function CreateFrame() return frame() end
function hooksecurefunc(target, name, fn) hooks[name] = fn end

dofile("src/LootWishlist_UI.lua")
assert(hooks.Initialize, "the UI hooks TooltipComparisonManager:Initialize")

------------------------------------------------------------------------
-- Blizzard's placement, given whatever anchor frame the manager holds
------------------------------------------------------------------------
local function clamped(left, width)
  if left < 0 then left = 0 end
  if left + width > SCREEN_W then left = SCREEN_W - width end
  return { left = left, right = left + width }
end

local function anchorComparisons(mgr, secondaryShown)
  local tooltip = mgr.tooltip
  local side = mgr.anchorFrame
  local leftPos = math.min(tooltip.left, side.left)
  local rightPos = math.max(tooltip.right, side.right)
  local totalWidth = COMPARISON_W * (secondaryShown and 2 or 1)
  local rightDist = SCREEN_W - rightPos
  local anchorType = tooltip.anchorType

  local placeLeft
  if totalWidth < leftPos and anchorType:find("LEFT") then
    placeLeft = true
  elseif totalWidth < rightDist and anchorType:find("RIGHT") then
    placeLeft = false
  else
    placeLeft = rightDist < leftPos
  end

  -- The slide that would shove the tooltip sideways is absorbed by the anchor
  -- frame's no-op SetAnchorType, so nothing here moves the tooltip.
  local primary, secondary
  if placeLeft then
    primary = clamped(side.left - COMPARISON_W, COMPARISON_W)
    if secondaryShown then secondary = clamped(primary.left - COMPARISON_W, COMPARISON_W) end
  else
    if secondaryShown then
      secondary = clamped(side.right, COMPARISON_W)
      primary = clamped(secondary.right, COMPARISON_W)
    else
      primary = clamped(side.right, COMPARISON_W)
    end
  end
  return primary, secondary
end

------------------------------------------------------------------------
-- Hover a row with the window at each position on screen
------------------------------------------------------------------------
local function hoverRow(windowLeft, secondaryShown)
  local window = frame({ left = windowLeft, right = windowLeft + WINDOW_W, lootWishlistWindow = true })
  local row = frame({ left = windowLeft, right = window.right, parent = window })
  local tooltipLeft = math.min(window.right, SCREEN_W - TOOLTIP_W) -- ANCHOR_RIGHT off the row, clamped
  local tooltip = frame({
    left = tooltipLeft,
    right = tooltipLeft + TOOLTIP_W,
    anchorType = "ANCHOR_RIGHT",
    GetOwner = function() return row end,
  })

  local mgr = { tooltip = tooltip, anchorFrame = tooltip }
  hooks.Initialize(mgr)
  local primary, secondary = anchorComparisons(mgr, secondaryShown)
  return window, primary, secondary
end

local function covers(comparison, window)
  return comparison and comparison.left < window.right and comparison.right > window.left
end

local checks = 0
for _, windowLeft in ipairs({ 0, 48, 420, 700, SCREEN_W - WINDOW_W }) do
  for _, secondaryShown in ipairs({ true, false }) do
    local window, primary, secondary = hoverRow(windowLeft, secondaryShown)
    assert(not covers(primary, window) and not covers(secondary, window),
      string.format("comparisons stay off the window at left=%d with %d shown",
        windowLeft, secondaryShown and 2 or 1))
    checks = checks + 1
  end
end

-- Without the anchor frame the manager stacks the comparisons back over the window,
-- which is the bug this guards.
local window = frame({ left = 420, right = 940, lootWishlistWindow = true })
local tooltip = frame({ left = 940, right = 1180, anchorType = "ANCHOR_RIGHT" })
local primary = anchorComparisons({ tooltip = tooltip, anchorFrame = tooltip }, true)
assert(covers(primary, window), "the unanchored manager is what covers the window")
checks = checks + 1

print(string.format("TooltipAnchorTest: %d checks passed", checks))
