-- luacheck: ignore 111 112 113 121 122 131
-- Drives the comparison anchoring in LootWishlist_UI.lua with stub frames, so the
-- Equipped tooltips are placed by the addon's own hook rather than by Blizzard's
-- guess. Frames clamp to the screen the way the client clamps them, and the check
-- is the one that matters: the comparisons never land on the wishlist window.

local screenWidth = 1366
local WINDOW_W = 520
local TOOLTIP_W = 240
local COMPARISON_W = 236

function GetScreenWidth() return screenWidth end

local function noop() end
local stubMeta = { __index = function() return noop end }

local function edgeOf(frame, point)
  if point:find("LEFT") then return frame.left end
  return frame.right
end

-- The span frame the addon anchors to the window and tooltip: two points set its
-- edges, so it has no width of its own.
local function spanFrame()
  return setmetatable({
    ClearAllPoints = function(self) self.left, self.right = nil, nil end,
    SetPoint = function(self, point, rel, relPoint)
      if point == "TOPLEFT" then self.left = rel.left end
      if point == "RIGHT" then self.right = edgeOf(rel, relPoint or point) end
    end,
    GetLeft = function(self) return self.left end,
    GetRight = function(self) return self.right end,
  }, stubMeta)
end

-- A comparison tooltip: fixed width, clamped on screen like ShoppingTooltip1/2.
local function comparisonFrame()
  return setmetatable({
    shown = true,
    IsShown = function(self) return self.shown end,
    GetWidth = function() return COMPARISON_W end,
    SetPoint = function(self, point, rel, relPoint)
      local left = edgeOf(rel, relPoint)
      if point:find("RIGHT") then left = left - COMPARISON_W end
      left = math.max(0, math.min(left, screenWidth - COMPARISON_W))
      self.left, self.right = left, left + COMPARISON_W
    end,
  }, stubMeta)
end

local function frame(fields)
  local f = setmetatable(fields or {}, stubMeta)
  -- Explicit falses: the stub metatable answers every other field with a function.
  f.lootWishlistWindow = rawget(f, "lootWishlistWindow") or false
  f.parent = rawget(f, "parent") or false
  f.GetLeft = function(self) return self.left end
  f.GetRight = function(self) return self.right end
  f.GetParent = function(self) return self.parent end
  return f
end

------------------------------------------------------------------------
-- Load the addon's hooks
------------------------------------------------------------------------
local hooks = {}
LootWishlist = { Const = setmetatable({}, stubMeta) }
LuckyUI = setmetatable({ C = setmetatable({}, { __index = function() return { 0, 0, 0, 1 } end }) }, stubMeta)
LuckyLog = { New = function() return noop end }
UIParent = frame()
TooltipComparisonManager = { Initialize = noop, AnchorShoppingTooltips = noop }
function CreateFrame() return spanFrame() end
function hooksecurefunc(target, name, fn) hooks[name] = fn end

dofile("src/LootWishlist_UI.lua")
assert(hooks.Initialize and hooks.AnchorShoppingTooltips, "the UI hooks the comparison manager")

------------------------------------------------------------------------
-- Hover a row with the window at each position on screen
------------------------------------------------------------------------
local function hoverRow(windowLeft, comparisonCount)
  local window = frame({ left = windowLeft, right = windowLeft + WINDOW_W, lootWishlistWindow = true })
  local row = frame({ left = windowLeft, right = window.right, parent = window })
  -- The row tooltip on ANCHOR_RIGHT, clamped on screen as the client clamps it.
  local tooltipLeft = math.min(window.right, screenWidth - TOOLTIP_W)
  local comparisons = { comparisonFrame(), comparisonFrame() }
  comparisons[2].shown = comparisonCount > 1
  local tooltip = frame({
    left = tooltipLeft,
    right = tooltipLeft + TOOLTIP_W,
    shoppingTooltips = comparisons,
    GetOwner = function() return row end,
  })

  local mgr = { tooltip = tooltip, anchorFrame = tooltip }
  hooks.Initialize(mgr)
  assert(mgr.anchorFrame ~= tooltip and mgr.anchorFrame:GetLeft() == window.left,
    "the manager is handed a span covering the window, so it cannot slide the tooltip over it")
  hooks.AnchorShoppingTooltips(mgr)
  return window, comparisons
end

local function covers(comparison, window)
  return comparison.shown and comparison.left < window.right and comparison.right > window.left
end

local checks = 0
for _, width in ipairs({ 1366, 1024 }) do
  screenWidth = width
  for _, windowLeft in ipairs({ 0, 48, 200, 420, screenWidth - WINDOW_W }) do
    for comparisonCount = 1, 2 do
      local window, comparisons = hoverRow(windowLeft, comparisonCount)
      for i, comparison in ipairs(comparisons) do
        assert(not covers(comparison, window),
          string.format("comparison %d stays off the window at %dx, window left %d, %d shown",
            i, screenWidth, windowLeft, comparisonCount))
        checks = checks + 1
      end
    end
  end
end

-- A tooltip owned by anything else is left to Blizzard.
screenWidth = 1366
local outsider = frame({ left = 400, right = 640, shoppingTooltips = { comparisonFrame() },
  GetOwner = function() return frame({ left = 0, right = 100 }) end })
local mgr = { tooltip = outsider, anchorFrame = outsider }
hooks.Initialize(mgr)
assert(mgr.anchorFrame == outsider, "a tooltip outside our windows keeps Blizzard's anchor")
checks = checks + 1

print(string.format("TooltipAnchorTest: %d checks passed", checks))
