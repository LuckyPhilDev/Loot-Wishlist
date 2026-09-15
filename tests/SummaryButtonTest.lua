-- luacheck: ignore 111 112 113 121 122
-- The summary window is folded into a button, always open, or hidden: the
-- button shows and hides it, moves on a right-click hold, fades until hovered,
-- and the window opens toward the middle of the screen.

local function noop() end

local methods = setmetatable({}, { __index = function() return noop end })
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(shown) self.shown = shown and true or false end
function methods:IsShown() return self.shown end
function methods:IsMouseOver() return false end
function methods:ClearAllPoints() self.points = {} end
function methods:SetPoint(point, rel, relPoint, x, y)
  self.points[#self.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
end
function methods:GetPoint(i)
  local p = self.points[i]
  if p then return p.point, p.rel, p.relPoint, p.x, p.y end
end
function methods:GetCenter() return self.x, self.y end
function methods:GetName() return self.name end
function methods:GetStringWidth() return 180 end
function methods:GetStringHeight() return 40 end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:HookScript(event, fn)
  local original = self.scripts[event]
  self.scripts[event] = function(...)
    if original then original(...) end
    fn(...)
  end
end
function methods:SetAlpha(alpha) self.alpha = alpha end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:CreateFontString() return setmetatable({ points = {}, scripts = {} }, { __index = methods }) end

CreateFrame = function(_, name)
  local f = setmetatable({ name = name, points = {}, scripts = {}, shown = true, moving = false }, { __index = methods })
  if name then _G[name] = f end
  return f
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent.GetWidth = function() return 1920 end
UIParent.GetHeight = function() return 1080 end

local button
local colour = setmetatable({}, { __index = function() return { 1, 1, 1 } end })
LuckyUI = {
  Backdrop = {},
  C = colour,
  WC = { goldPrimary = "", textMuted = "", reset = "" },
  CreateIconButton = function()
    button = CreateFrame("Button")
    return button
  end,
}
LuckyMedia = function(file) return file end
C_Timer = { After = function(_, fn) fn() end }

local inCombat = false
InCombatLockdown = function() return inCombat end

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Constants.lua")

LootWishlist.Layout = {
  Build = function()
    return { { name = "Priory of the Sacred Flame", count = 1, items = { { info = {} } } } }
  end,
}

local settings = { summaryMode = "button", hideSummaryInCombatAndMythicPlus = true }
LootWishlistDB = { settings = settings }
LootWishlistCharDB = {
  summaryWindow = { point = "TOPLEFT", relative = "UIParent", relativePoint = "TOPLEFT", x = 40, y = -60 },
}

dofile("src/LootWishlist_Summary.lua")

local refresh = LootWishlist.Summary.refresh
local summary
local checks = 0

local function check(condition, why)
  assert(condition, why)
  checks = checks + 1
end

local function anchor()
  local point, rel, relPoint, _, y = summary:GetPoint(1)
  return point, rel, relPoint, y
end

refresh()
summary = LootWishlistSummary
check(button.shown and not summary.shown, "the summary starts folded behind its button")
check(button:GetPoint(1) == "TOPLEFT" and select(5, button:GetPoint(1)) == -60,
  "a first button sits where the summary window was left")

button.scripts.OnMouseDown(button, "LeftButton")
check(not button.moving, "a left press stays a click")
button.scripts.OnMouseDown(button, "RightButton")
check(button.moving, "holding right-click picks the button up straight away")
button.scripts.OnMouseUp(button, "RightButton")
check(not button.moving and LootWishlistCharDB.summaryButton, "letting go puts it down and remembers the spot")

settings.summaryButtonUnhoveredAlpha = 0.4
refresh()
check(button.alpha == 0.4, "the button fades while the mouse is away")
button.scripts.OnEnter(button)
check(button.alpha == 1, "hovering brings it back to full")
button.scripts.OnLeave(button)
check(button.alpha == 0.4, "and leaving fades it again")

button.x, button.y = 100, 1000
button.scripts.OnClick()
local point, rel, relPoint, y = anchor()
check(summary.shown, "clicking the button opens the summary")
check(point == "TOPLEFT" and rel == button and relPoint == "BOTTOMLEFT" and y < 0,
  "a button near the top left opens the summary below it, left edges lined up")

button.x, button.y = 1800, 100
refresh()
point, rel, relPoint, y = anchor()
check(point == "BOTTOMRIGHT" and rel == button and relPoint == "TOPRIGHT" and y > 0,
  "a button near the bottom right opens the summary above it, right edges lined up")

summary.scripts.OnDragStart(summary)
check(button.moving and not summary.moving, "dragging the open summary moves its button")
summary.scripts.OnDragStop(summary)

button.scripts.OnClick()
check(button.shown and not summary.shown, "clicking again folds it away")

settings.summaryMode = "window"
refresh()
point, rel = anchor()
check(summary.shown and not button.shown, "always open shows the window and drops the button")
check(point == "TOPLEFT" and rel == UIParent, "and the window is back where it was left")

settings.summaryMode = "button"
button.scripts.OnClick()
inCombat = true
refresh()
check(not summary.shown and not button.shown, "combat hides the button along with the summary")
inCombat = false

settings.summaryMode = "hidden"
refresh()
check(not summary.shown and not button.shown, "hidden takes the button away along with the window")

print(string.format("SummaryButtonTest: %d checks passed", checks))
