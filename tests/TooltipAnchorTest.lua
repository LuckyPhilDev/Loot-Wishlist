-- luacheck: ignore 111 112 113 121 122 131
-- Drives LootWishlist_Tooltips.lua with stub frames: the side
-- the window's centre picks, and where the Equipped comparison tooltips end up
-- once the comparison manager has run. Frames clamp on screen the way the client
-- clamps them, and the check that matters is that neither the tooltip nor its
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
-- and ShoppingTooltip1/2 are.
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
-- Load the addon's hooks
------------------------------------------------------------------------
local hooks = {}
LuckyLog = { New = function() return noop end }
UIParent = frame()
GameTooltip = box(TOOLTIP_W)
TooltipComparisonManager = { Initialize = noop, AnchorShoppingTooltips = noop }
function CreateFrame() return setmetatable({}, stubMeta) end
function hooksecurefunc(target, name, fn) hooks[name] = fn end

dofile("src/LootWishlist_Tooltips.lua")
assert(hooks.Initialize and hooks.AnchorShoppingTooltips, "the UI hooks the comparison manager")
assert(LootWishlist.UI.AnchorItemTooltip, "the UI exposes the tooltip anchor")

------------------------------------------------------------------------
-- Hover a row with the window at each position on screen
------------------------------------------------------------------------
local function hoverRow(windowLeft, comparisonCount)
  local window = frame({ left = windowLeft, right = windowLeft + WINDOW_W, lootWishlistWindow = true })
  local row = frame({ left = windowLeft, right = window.right, parent = window })

  local comparisons = { box(COMPARISON_W), box(COMPARISON_W) }
  comparisons[2].shown = comparisonCount > 1
  GameTooltip.shoppingTooltips = comparisons

  LootWishlist.UI.AnchorItemTooltip(row)

  local mgr = { tooltip = GameTooltip, anchorFrame = GameTooltip }
  hooks.Initialize(mgr)
  assert(mgr.anchorFrame ~= GameTooltip,
    "the manager gets a stand-in anchor, so its slide cannot drag the tooltip over the window")
  hooks.AnchorShoppingTooltips(mgr)
  return window, comparisons
end

local function covers(tooltip, window)
  return tooltip.left < window.right and tooltip.right > window.left
end

local checks = 0
for _, width in ipairs({ 1366, 1024 }) do
  screenWidth = width
  for _, windowLeft in ipairs({ 0, 48, 200, 420, screenWidth - WINDOW_W }) do
    for comparisonCount = 1, 2 do
      local window, comparisons = hoverRow(windowLeft, comparisonCount)
      local onTheLeftHalf = (window.left + window.right) / 2 < screenWidth / 2
      local where = string.format("at %dx, window left %d, %d shown", screenWidth, windowLeft, comparisonCount)

      assert(onTheLeftHalf == (GameTooltip.left >= window.right),
        "the window's centre picks the side the tooltip opens on, " .. where)
      assert(not covers(GameTooltip, window), "the tooltip stays off the window, " .. where)
      checks = checks + 2

      for i, comparison in ipairs(comparisons) do
        if comparison.shown then
          assert(not covers(comparison, window),
            string.format("comparison %d stays off the window, %s", i, where))
          checks = checks + 1
        end
      end
    end
  end
end

-- A tooltip owned by anything else is left to Blizzard.
screenWidth = 1366
LootWishlist.UI.AnchorItemTooltip(frame({ left = 0, right = 100 }))
assert(GameTooltip.anchor == "ANCHOR_RIGHT", "a row outside our windows keeps Blizzard's anchor")
local mgr = { tooltip = GameTooltip, anchorFrame = GameTooltip }
hooks.Initialize(mgr)
assert(mgr.anchorFrame == GameTooltip, "and the manager is left alone with it")
checks = checks + 2

print(string.format("TooltipAnchorTest: %d checks passed", checks))
