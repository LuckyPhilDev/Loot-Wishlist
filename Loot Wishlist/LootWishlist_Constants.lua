-- Loot Wishlist - Constants

LootWishlist = LootWishlist or {}
LootWishlist.Const = {
  -- Defaults for templates
  DEFAULT_WHISPER_TEMPLATE = "Hey %looter%. If %item% is tradeable and you don't need it, could I roll on it? Been after that one.",
  DEFAULT_PARTY_TEMPLATE = "If %item% can be traded and isn't an upgrade for you, I'd really appreciate it.",

  -- Alert frame layout
  ALERT_FRAME_INITIAL_WIDTH = 480,
  ALERT_FRAME_INITIAL_HEIGHT = 110,
  ALERT_TOP_OFFSET = -160,
  ALERT_BG_ALPHA = 0.92,
  ALERT_BORDER_COLOR_DEFAULT  = {0.788, 0.659, 0.298, 0.8},   -- goldAccent
  ALERT_BORDER_COLOR_WISHLIST = {0.412, 0.859, 0.486, 0.9},    -- success
  ALERT_BORDER_COLOR_NOT      = {0.541, 0.494, 0.416, 0.9},    -- textMuted
  ALERT_TEXT_PREFIX_WISHLIST = "Wishlist item dropped:",
  ALERT_AUTOHIDE_SECONDS = 6,
  ALERT_WIDTH_MIN_DEFAULT = 360,
  ALERT_WIDTH_MAX_DEFAULT = 700,
  ALERT_WIDTH_PAD = 80,
  ALERT_MIN_WIDTH_SELF = 460,
  ALERT_MIN_WIDTH_OTHER = 540,
  ALERT_HEIGHT_WITH_BUTTONS = 130,
}
