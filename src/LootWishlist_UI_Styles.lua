-- Loot Wishlist - UI Styles and Theming
-- Bridges to LuckyUI for consistent visual design across Lucky Phil's addons.

LootWishlist = LootWishlist or {}
LootWishlist.UI = LootWishlist.UI or {}
LootWishlist.UI.Styles = {}

local Styles = LootWishlist.UI.Styles

-- Debug helper
local function dprint(...)
  local ok = LootWishlist and LootWishlist.IsDebug and LootWishlist.IsDebug()
  if not ok then return end
  local msg = "[LootWishlist][UI] "
  local parts = {}
  for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
  print(msg .. table.concat(parts, " "))
end

-- ============================================================================
-- Color Palette  (delegates to LuckyUI where possible)
-- ============================================================================

local C = LuckyUI and LuckyUI.C or {}

Styles.Colors = {
  -- Backgrounds (from LuckyUI palette)
  bg_primary   = C.bgDark   or { 0.102, 0.071, 0.035, 0.95 },
  bg_secondary = C.bgPanel  or { 0.125, 0.102, 0.055, 0.95 },
  bg_input     = C.bgInput  or { 0.051, 0.039, 0.020, 0.95 },
  bg_hover     = C.highlight or { 0.788, 0.659, 0.298, 0.13 },
  bg_selected  = { 0.15, 0.12, 0.06, 0.95 },

  -- Accents (gold ramp)
  accent_primary   = { C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3], 1.0 },
  accent_secondary = { C.goldAccent[1],  C.goldAccent[2],  C.goldAccent[3],  1.0 },
  accent_muted     = { C.goldMuted[1],   C.goldMuted[2],   C.goldMuted[3],   1.0 },

  -- Text
  text_primary  = { C.textLight[1], C.textLight[2], C.textLight[3], 1.0 },
  text_secondary = C.textMuted or { 0.541, 0.494, 0.416, 1.0 },
  text_muted    = C.textMuted or { 0.541, 0.494, 0.416, 1.0 },
  text_gold     = { C.textGold[1], C.textGold[2], C.textGold[3], 1.0 },
  text_disabled = { 0.3, 0.3, 0.3, 1.0 },

  -- Status
  success = { C.success[1], C.success[2], C.success[3], 1.0 },
  warning = { C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3], 1.0 },
  error   = { C.danger[1], C.danger[2], C.danger[3], 1.0 },
  info    = { C.info[1], C.info[2], C.info[3], 1.0 },

  -- Item quality colors (WoW canonical)
  quality_poor      = { 0.62, 0.62, 0.62, 1.0 },
  quality_common    = { 1.0, 1.0, 1.0, 1.0 },
  quality_uncommon  = { 0.12, 1.0, 0.0, 1.0 },
  quality_rare      = { 0.0, 0.44, 0.87, 1.0 },
  quality_epic      = { 0.64, 0.21, 0.93, 1.0 },
  quality_legendary = { 1.0, 0.5, 0.0, 1.0 },

  -- Borders
  border_default = { C.borderDark[1], C.borderDark[2], C.borderDark[3], 1.0 },
  border_gold    = { C.goldAccent[1], C.goldAccent[2], C.goldAccent[3], 1.0 },
  border_hover   = { C.goldMuted[1],  C.goldMuted[2],  C.goldMuted[3],  1.0 },
  border_active  = { C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3], 1.0 },
}

-- ============================================================================
-- Backdrop Templates  (use LuckyUI.Backdrop for 1px solid borders)
-- ============================================================================

Styles.Backdrops = {
  -- Shared 1px solid backdrop (from LuckyUI)
  solid = LuckyUI.Backdrop,

  -- Legacy tooltip-style backdrop (for alert frames that need higher alpha)
  tooltip = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  },
}

-- ============================================================================
-- Typography  (use LuckyUI fonts - Friz Quadrata throughout)
-- ============================================================================

Styles.Fonts = {
  title   = LuckyUI.TITLE_FONT or "Fonts\\FRIZQT__.TTF",
  body    = LuckyUI.BODY_FONT  or "Fonts\\FRIZQT__.TTF",

  -- Sizes
  size_title      = 16,
  size_heading    = 14,
  size_subheading = 12,
  size_body       = 13,
  size_small      = 11,
  size_hint       = 10,
}

-- ============================================================================
-- Layout Constants
-- ============================================================================

Styles.Layout = {
  -- Spacing
  padding_small  = 4,
  padding_medium = 8,
  padding_large  = 12,
  padding_xlarge = 16,

  -- Item row dimensions
  row_height    = 50,
  row_icon_size = 40,
  row_spacing   = 2,

  -- Window sizes
  window_min_width      = 400,
  window_min_height     = 300,
  window_default_width  = 600,
  window_default_height = 500,
  window_max_width      = 900,
  window_max_height     = 800,

  -- Toolbar
  toolbar_height = 40,

  -- Status bar
  statusbar_height = 24,

  -- Borders
  border_width  = 1,
}

-- ============================================================================
-- Animation Settings
-- ============================================================================

Styles.Animation = {
  duration_instant = 0,
  duration_fast    = 0.1,
  duration_normal  = 0.2,
  duration_slow    = 0.3,

  ease_linear = function(t) return t end,
  ease_in     = function(t) return t * t end,
  ease_out    = function(t) return t * (2 - t) end,
  ease_in_out = function(t)
    if t < 0.5 then return 2 * t * t
    else return -1 + (4 - 2 * t) * t end
  end,
}

-- ============================================================================
-- Icon Paths
-- ============================================================================

Styles.Icons = {
  search           = "Interface\\Common\\UI-SearchBox-Icon",
  filter           = "Interface\\ChatFrame\\ChatFrameExpandArrow",
  sort             = "Interface\\Buttons\\UI-SortArrow",
  settings         = "Interface\\Buttons\\UI-OptionsButton",
  stats            = "Interface\\Icons\\INV_Misc_Note_01",
  help             = "Interface\\Common\\help-i",
  close            = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
  remove           = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
  priority_star    = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
  menu             = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
  check            = "Interface\\Buttons\\UI-CheckBox-Check",
  item_placeholder = "Interface\\Icons\\INV_Misc_QuestionMark",
}

-- ============================================================================
-- Helper Functions
-- ============================================================================

--- Apply the LuckyUI solid backdrop with optional color overrides.
function Styles.ApplyBackdrop(frame, backdropKey, bgColor, borderColor)
  if not frame then return end
  local bd = Styles.Backdrops[backdropKey or "solid"] or LuckyUI.Backdrop
  frame:SetBackdrop(bd)

  if bgColor then
    frame:SetBackdropColor(unpack(bgColor))
  else
    frame:SetBackdropColor(unpack(Styles.Colors.bg_primary))
  end

  if borderColor then
    frame:SetBackdropBorderColor(unpack(borderColor))
  else
    frame:SetBackdropBorderColor(unpack(Styles.Colors.border_gold))
  end
end

--- Create a FontString using LuckyUI font stack.
function Styles.CreateFontString(parent, layer, style, color)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")

  local fontPath = Styles.Fonts.body
  local fontSize = Styles.Fonts.size_body

  if style == "title" then
    fontPath, fontSize = Styles.Fonts.title, Styles.Fonts.size_title
  elseif style == "heading" then
    fontPath, fontSize = Styles.Fonts.title, Styles.Fonts.size_heading
  elseif style == "subheading" then
    fontPath, fontSize = Styles.Fonts.title, Styles.Fonts.size_subheading
  elseif style == "small" then
    fontPath, fontSize = Styles.Fonts.body, Styles.Fonts.size_small
  elseif style == "hint" then
    fontPath, fontSize = Styles.Fonts.body, Styles.Fonts.size_hint
  end

  fs:SetFont(fontPath, fontSize)

  if color then
    fs:SetTextColor(unpack(color))
  else
    fs:SetTextColor(unpack(Styles.Colors.text_primary))
  end

  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetShadowOffset(1, -1)

  return fs
end

--- Fade a frame in or out.
function Styles.FadeFrame(frame, fadeIn, duration, onComplete)
  if not frame then return end
  duration = duration or Styles.Animation.duration_normal
  if fadeIn then
    UIFrameFadeIn(frame, duration, frame:GetAlpha(), 1.0)
  else
    UIFrameFadeOut(frame, duration, frame:GetAlpha(), 0.0)
  end
  if onComplete and C_Timer then
    C_Timer.After(duration, onComplete)
  end
end

--- Apply hover effect to a frame.
function Styles.ApplyHoverEffect(frame, bgColor, hoverBgColor, borderColor, hoverBorderColor)
  if not frame then return end
  frame.originalBgColor    = bgColor      or Styles.Colors.bg_secondary
  frame.hoverBgColor       = hoverBgColor or Styles.Colors.bg_hover
  frame.originalBorderColor = borderColor  or Styles.Colors.border_default
  frame.hoverBorderColor   = hoverBorderColor or Styles.Colors.border_hover

  frame:SetScript("OnEnter", function(self)
    if self:GetBackdrop() then
      self:SetBackdropColor(unpack(self.hoverBgColor))
      if self.hoverBorderColor then self:SetBackdropBorderColor(unpack(self.hoverBorderColor)) end
    end
  end)
  frame:SetScript("OnLeave", function(self)
    if self:GetBackdrop() then
      self:SetBackdropColor(unpack(self.originalBgColor))
      if self.originalBorderColor then self:SetBackdropBorderColor(unpack(self.originalBorderColor)) end
    end
  end)
end

--- Get item quality color.
function Styles.GetQualityColor(quality)
  if quality == 0 then return Styles.Colors.quality_poor
  elseif quality == 1 then return Styles.Colors.quality_common
  elseif quality == 2 then return Styles.Colors.quality_uncommon
  elseif quality == 3 then return Styles.Colors.quality_rare
  elseif quality == 4 then return Styles.Colors.quality_epic
  elseif quality == 5 then return Styles.Colors.quality_legendary
  else return Styles.Colors.text_primary end
end

-- ============================================================================
-- Settings Integration
-- ============================================================================

function Styles.GetSettings()
  local settings = LootWishlistDB and LootWishlistDB.settings and LootWishlistDB.settings.ui
  if not settings then
    return {
      modernStyle = true,
      showIcons = true,
      showSpecs = true,
      showPriority = false,
      enableAnimations = true,
      disableAnimationsInCombat = false,
      highContrast = false,
      largeText = false,
      scale = 1.0,
      colorScheme = "default",
    }
  end
  return settings
end

function Styles.IsModernStyleEnabled()
  local settings = Styles.GetSettings()
  return settings.modernStyle ~= false
end

function Styles.AreAnimationsEnabled()
  local settings = Styles.GetSettings()
  if not settings.enableAnimations then return false end
  if settings.disableAnimationsInCombat and InCombatLockdown() then return false end
  return true
end

dprint("UI Styles module loaded")
