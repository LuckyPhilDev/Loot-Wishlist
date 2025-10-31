-- Loot Wishlist - UI Styles and Theming
-- Centralized styling system for consistent visual design

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
-- Color Palette
-- ============================================================================

Styles.Colors = {
  -- Backgrounds
  bg_primary = {0.05, 0.05, 0.08, 0.95},
  bg_secondary = {0.08, 0.08, 0.12, 0.9},
  bg_hover = {0.12, 0.15, 0.20, 0.95},
  bg_selected = {0.15, 0.20, 0.30, 0.95},
  
  -- Accents
  accent_primary = {0.3, 0.6, 1.0, 1.0},      -- Bright blue
  accent_secondary = {0.8, 0.5, 0.2, 1.0},    -- Gold/orange
  accent_tertiary = {0.6, 0.3, 0.9, 1.0},     -- Purple
  
  -- Text
  text_primary = {1.0, 1.0, 1.0, 1.0},        -- White
  text_secondary = {0.7, 0.7, 0.7, 1.0},      -- Gray
  text_muted = {0.5, 0.5, 0.5, 1.0},          -- Dim gray
  text_disabled = {0.3, 0.3, 0.3, 1.0},       -- Very dim
  
  -- Status
  success = {0.2, 0.8, 0.2, 1.0},             -- Green
  warning = {1.0, 0.8, 0.0, 1.0},             -- Yellow
  error = {1.0, 0.2, 0.2, 1.0},               -- Red
  info = {0.3, 0.7, 1.0, 1.0},                -- Blue
  
  -- Quality colors (match WoW item quality)
  quality_poor = {0.62, 0.62, 0.62, 1.0},     -- Gray
  quality_common = {1.0, 1.0, 1.0, 1.0},      -- White
  quality_uncommon = {0.12, 1.0, 0.0, 1.0},   -- Green
  quality_rare = {0.0, 0.44, 0.87, 1.0},      -- Blue
  quality_epic = {0.64, 0.21, 0.93, 1.0},     -- Purple
  quality_legendary = {1.0, 0.5, 0.0, 1.0},   -- Orange
  
  -- Borders
  border_default = {0.4, 0.4, 0.4, 1.0},
  border_hover = {0.6, 0.7, 0.9, 1.0},
  border_active = {0.3, 0.6, 1.0, 1.0},
}

-- ============================================================================
-- Backdrop Templates
-- ============================================================================

Styles.Backdrops = {
  -- Main window backdrop
  window = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
  },
  
  -- Content panel backdrop
  panel = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  },
  
  -- Toolbar backdrop
  toolbar = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = nil,
    tile = true,
    tileSize = 16,
    edgeSize = 0,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  },
  
  -- Item row backdrop (hover)
  row = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = nil,
    tile = false,
    tileSize = 0,
    edgeSize = 0,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  },
  
  -- Button backdrop
  button = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Buttons\\UI-Panel-Button-Up",
    tile = false,
    tileSize = 0,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  },
}

-- ============================================================================
-- Typography
-- ============================================================================

Styles.Fonts = {
  -- Header fonts
  header_large = "Fonts\\FRIZQT__.TTF",
  header_size_large = 16,
  
  header_medium = "Fonts\\FRIZQT__.TTF",
  header_size_medium = 14,
  
  header_small = "Fonts\\FRIZQT__.TTF",
  header_size_small = 12,
  
  -- Body fonts
  body_large = "Fonts\\ARIALN.TTF",
  body_size_large = 14,
  
  body_medium = "Fonts\\ARIALN.TTF",
  body_size_medium = 12,
  
  body_small = "Fonts\\ARIALN.TTF",
  body_size_small = 10,
}

-- ============================================================================
-- Layout Constants
-- ============================================================================

Styles.Layout = {
  -- Spacing
  padding_small = 4,
  padding_medium = 8,
  padding_large = 12,
  padding_xlarge = 16,
  
  -- Item row dimensions
  row_height = 50,
  row_icon_size = 40,
  row_spacing = 2,
  
  -- Window sizes
  window_min_width = 400,
  window_min_height = 300,
  window_default_width = 600,
  window_default_height = 500,
  window_max_width = 900,
  window_max_height = 800,
  
  -- Toolbar
  toolbar_height = 40,
  
  -- Status bar
  statusbar_height = 24,
  
  -- Borders
  border_width = 2,
  border_radius = 8, -- For custom rounded corners
}

-- ============================================================================
-- Animation Settings
-- ============================================================================

Styles.Animation = {
  -- Durations (seconds)
  duration_instant = 0,
  duration_fast = 0.1,
  duration_normal = 0.2,
  duration_slow = 0.3,
  
  -- Easing (for custom animations)
  ease_linear = function(t) return t end,
  ease_in = function(t) return t * t end,
  ease_out = function(t) return t * (2 - t) end,
  ease_in_out = function(t)
    if t < 0.5 then
      return 2 * t * t
    else
      return -1 + (4 - 2 * t) * t
    end
  end,
}

-- ============================================================================
-- Icon Paths
-- ============================================================================

Styles.Icons = {
  -- UI Icons
  search = "Interface\\Common\\UI-SearchBox-Icon",
  filter = "Interface\\ChatFrame\\ChatFrameExpandArrow",
  sort = "Interface\\Buttons\\UI-SortArrow",
  settings = "Interface\\Buttons\\UI-OptionsButton",
  stats = "Interface\\Icons\\INV_Misc_Note_01",
  help = "Interface\\Common\\help-i",
  close = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
  
  -- Action Icons  
  remove = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
  priority_star = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
  menu = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
  check = "Interface\\Buttons\\UI-CheckBox-Check",
  
  -- Placeholder icons
  item_placeholder = "Interface\\Icons\\INV_Misc_QuestionMark",
  boss_placeholder = "Interface\\Icons\\Achievement_Boss_Archimonde",
  dungeon_placeholder = "Interface\\Icons\\Achievement_Dungeon_GloryoftheRaider",
}

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Apply a backdrop to a frame with optional color override
function Styles.ApplyBackdrop(frame, backdropKey, bgColor, borderColor)
  if not frame or not backdropKey then return end
  
  local backdrop = Styles.Backdrops[backdropKey]
  if not backdrop then
    dprint("Unknown backdrop key:", backdropKey)
    return
  end
  
  frame:SetBackdrop(backdrop)
  
  -- Apply colors
  if bgColor then
    frame:SetBackdropColor(unpack(bgColor))
  else
    -- Default background
    frame:SetBackdropColor(unpack(Styles.Colors.bg_primary))
  end
  
  if borderColor then
    frame:SetBackdropBorderColor(unpack(borderColor))
  else
    -- Default border
    frame:SetBackdropBorderColor(unpack(Styles.Colors.border_default))
  end
end

-- Create a FontString with specified style
function Styles.CreateFontString(parent, layer, style, color)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  
  -- Apply font based on style
  local fontPath, fontSize
  if style == "header_large" then
    fontPath, fontSize = Styles.Fonts.header_large, Styles.Fonts.header_size_large
  elseif style == "header_medium" then
    fontPath, fontSize = Styles.Fonts.header_medium, Styles.Fonts.header_size_medium
  elseif style == "header_small" then
    fontPath, fontSize = Styles.Fonts.header_small, Styles.Fonts.header_size_small
  elseif style == "body_large" then
    fontPath, fontSize = Styles.Fonts.body_large, Styles.Fonts.body_size_large
  elseif style == "body_small" then
    fontPath, fontSize = Styles.Fonts.body_small, Styles.Fonts.body_size_small
  else -- Default to body_medium
    fontPath, fontSize = Styles.Fonts.body_medium, Styles.Fonts.body_size_medium
  end
  
  fs:SetFont(fontPath, fontSize)
  
  -- Apply color
  if color then
    fs:SetTextColor(unpack(color))
  else
    fs:SetTextColor(unpack(Styles.Colors.text_primary))
  end
  
  -- Add shadow for better readability
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetShadowOffset(1, -1)
  
  return fs
end

-- Fade a frame in or out
function Styles.FadeFrame(frame, fadeIn, duration, onComplete)
  if not frame then return end
  
  duration = duration or Styles.Animation.duration_normal
  
  if fadeIn then
    UIFrameFadeIn(frame, duration, frame:GetAlpha(), 1.0)
  else
    UIFrameFadeOut(frame, duration, frame:GetAlpha(), 0.0)
  end
  
  -- Call completion callback if provided
  if onComplete and C_Timer then
    C_Timer.After(duration, onComplete)
  end
end

-- Apply hover effect to a frame
function Styles.ApplyHoverEffect(frame, bgColor, hoverBgColor, borderColor, hoverBorderColor)
  if not frame then return end
  
  -- Store original colors
  frame.originalBgColor = bgColor or Styles.Colors.bg_secondary
  frame.hoverBgColor = hoverBgColor or Styles.Colors.bg_hover
  frame.originalBorderColor = borderColor or Styles.Colors.border_default
  frame.hoverBorderColor = hoverBorderColor or Styles.Colors.border_hover
  
  frame:SetScript("OnEnter", function(self)
    if self:GetBackdrop() then
      self:SetBackdropColor(unpack(self.hoverBgColor))
      if self.hoverBorderColor then
        self:SetBackdropBorderColor(unpack(self.hoverBorderColor))
      end
    end
  end)
  
  frame:SetScript("OnLeave", function(self)
    if self:GetBackdrop() then
      self:SetBackdropColor(unpack(self.originalBgColor))
      if self.originalBorderColor then
        self:SetBackdropBorderColor(unpack(self.originalBorderColor))
      end
    end
  end)
end

-- Get item quality color
function Styles.GetQualityColor(quality)
  if quality == 0 then return Styles.Colors.quality_poor
  elseif quality == 1 then return Styles.Colors.quality_common
  elseif quality == 2 then return Styles.Colors.quality_uncommon
  elseif quality == 3 then return Styles.Colors.quality_rare
  elseif quality == 4 then return Styles.Colors.quality_epic
  elseif quality == 5 then return Styles.Colors.quality_legendary
  else return Styles.Colors.text_primary
  end
end

-- ============================================================================
-- Settings Integration
-- ============================================================================

-- Get current UI settings
function Styles.GetSettings()
  local settings = LootWishlistDB and LootWishlistDB.settings and LootWishlistDB.settings.ui
  if not settings then
    -- Return defaults
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

-- Check if modern styling is enabled
function Styles.IsModernStyleEnabled()
  local settings = Styles.GetSettings()
  return settings.modernStyle ~= false -- Default to true
end

-- Check if animations are enabled (and not in combat if that setting is on)
function Styles.AreAnimationsEnabled()
  local settings = Styles.GetSettings()
  if not settings.enableAnimations then return false end
  if settings.disableAnimationsInCombat and InCombatLockdown() then return false end
  return true
end

dprint("UI Styles module loaded")

