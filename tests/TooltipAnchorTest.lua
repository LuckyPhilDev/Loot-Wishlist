-- luacheck: ignore 111 112 113 121 122 131
-- Drives LootWishlist_Tooltips.lua with stub frames: the side the window's centre
-- picks for the tooltip, and where the Equipped comparison tooltips end up once
-- the addon has placed them. Frames clamp on screen the way the client clamps
-- them, and the check that matters is that neither the tooltip nor its
-- comparisons land on the wishlist window.

local screenWidth = 1366
local WINDOW_W = 520
local TOOLTIP_W = 240
local COMPARISON_W = 236

function GetScreenWidth() return screenWidth end

local function noop() end
local stubMeta = { __index = function() return noop end }

local function edgeOf(frame, point)
  return point:find("LEFT") and frame.left or frame.right
end

-- A tooltip: fixed width, one anchor point, clamped on screen like GameTooltip
-- and the comparison tooltips are.
local function box(width)
  return setmetatable({
    width = width,
    shown = true,
    IsShown = function(self) return self.shown end,
    GetWidth = function(self) return self.width end,
    SetOwner = function(self, owner, anchor)
      self.owner, self.anchor = owner, anchor
      self.left, self.right = nil, nil
    end,
    GetOwner = function(self) return self.owner end,
    ClearAllPoints = function(self) self.left, self.right = nil, nil end,
    SetPoint = function(self, point, rel, relPoint, x)
      local edge = edgeOf(rel, relPoint) + (x or 0)
      local left = point:find("LEFT") and edge or edge - self.width
      left = math.max(0, math.min(left, screenWidth - self.width))
      self.left, self.right = left, left + self.width
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
-- Load the module
------------------------------------------------------------------------
local hooks, timers, shownScripts = {}, {}, {}
LuckyLog = { New = function() return noop end }
UIParent = frame()
GameTooltip = box(TOOLTIP_W)
GameTooltip.shoppingTooltips = { box(COMPARISON_W), box(COMPARISON_W) }
GameTooltip.shoppingTooltips[1].HookScript = function(self, script, fn) shownScripts[script] = fn end
GameTooltip.shoppingTooltips[2].HookScript = function() end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
TooltipComparisonManager = { Initialize = noop, AnchorShoppingTooltips = noop }
function CreateFrame() return setmetatable({}, stubMeta) end
function hooksecurefunc(target, name, fn) hooks[name] = fn end

dofile("src/LootWishlist_Tooltips.lua")
assert(LootWishlist.UI.AnchorItemTooltip and LootWishlist.UI.PlaceComparisonTooltips,
  "the module exposes the tooltip anchor and the comparison placement")
assert(hooks.Initialize and hooks.AnchorShoppingTooltips,
  "the comparison manager is still hooked where the client has one")
assert(shownScripts.OnShow, "comparisons that appear on their own are caught as they show")

------------------------------------------------------------------------
-- Hover a row with the window at each position on screen
------------------------------------------------------------------------
local function hoverRow(windowLeft, comparisonCount)
  local window = frame({ left = windowLeft, right = windowLeft + WINDOW_W, lootWishlistWindow = true })
  local row = frame({ left = windowLeft, right = window.right, parent = window })
  GameTooltip.shoppingTooltips[2].shown = comparisonCount > 1

  LootWishlist.UI.AnchorItemTooltip(row)
  LootWishlist.UI.PlaceComparisonTooltips()
  return window
end

local function covers(tooltip, window)
  return tooltip.left < window.right and tooltip.right > window.left
end

local checks = 0
for _, width in ipairs({ 1366, 1024 }) do
  screenWidth = width
  for _, windowLeft in ipairs({ 0, 48, 200, 420, screenWidth - WINDOW_W }) do
    for comparisonCount = 1, 2 do
      local window = hoverRow(windowLeft, comparisonCount)
      local onTheLeftHalf = (window.left + window.right) / 2 < screenWidth / 2
      local where = string.format("at %dx, window left %d, %d shown", screenWidth, windowLeft, comparisonCount)

      assert(onTheLeftHalf == (GameTooltip.left >= window.right),
        "the window's centre picks the side the tooltip opens on, " .. where)
      assert(not covers(GameTooltip, window), "the tooltip stays off the window, " .. where)
      checks = checks + 2

      for i, comparison in ipairs(GameTooltip.shoppingTooltips) do
        if comparison.shown then
          assert(not covers(comparison, window),
            string.format("comparison %d stays off the window, %s", i, where))
          checks = checks + 1
        end
      end
    end
  end
end

-- The comparisons chain outwards from the tooltip, not back across it.
screenWidth = 1366
hoverRow(0, 2)
assert(GameTooltip.shoppingTooltips[1].left == GameTooltip.right
  and GameTooltip.shoppingTooltips[2].left == GameTooltip.shoppingTooltips[1].right,
  "with the window on the left the comparisons run rightwards from the tooltip")
hoverRow(screenWidth - WINDOW_W, 2)
assert(GameTooltip.shoppingTooltips[1].right == GameTooltip.left
  and GameTooltip.shoppingTooltips[2].right == GameTooltip.shoppingTooltips[1].left,
  "with the window on the right they run leftwards")
checks = checks + 2

-- A comparison raised on its own, with no row hovered since, is placed a frame later.
shownScripts.OnShow()
assert(#timers == 1, "showing a comparison queues the placement")
timers[1]()
checks = checks + 1

-- A tooltip owned by anything else is left to Blizzard.
LootWishlist.UI.AnchorItemTooltip(frame({ left = 0, right = 100 }))
assert(GameTooltip.anchor == "ANCHOR_RIGHT", "a row outside our windows keeps Blizzard's anchor")
local before = GameTooltip.shoppingTooltips[1].left
LootWishlist.UI.PlaceComparisonTooltips()
assert(GameTooltip.shoppingTooltips[1].left == before, "and its comparisons are left where they were")
checks = checks + 2

print(string.format("TooltipAnchorTest: %d checks passed", checks))
