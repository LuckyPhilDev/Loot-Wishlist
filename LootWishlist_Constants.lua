-- Loot Wishlist - Constants

LootWishlist = LootWishlist or {}
LootWishlist.Const = {
  -- Defaults for templates
  DEFAULT_WHISPER_TEMPLATE = "Hey %looter%. If %item% is tradeable and you don’t need it, could I roll on it? Been after that one.",
  DEFAULT_PARTY_TEMPLATE = "If %item% can be traded and isn't an upgrade for you, I'd really appreciate it.",

  -- Alert frame layout
  ALERT_FRAME_INITIAL_WIDTH = 480,
  ALERT_FRAME_INITIAL_HEIGHT = 110,
  ALERT_TOP_OFFSET = -160,
  ALERT_BG_ALPHA = 0.7,
  ALERT_BORDER_COLOR_DEFAULT = {1, 1, 1, 0.8},
  ALERT_BORDER_COLOR_WISHLIST = {0.2, 1.0, 0.2, 0.9},
  ALERT_BORDER_COLOR_NOT = {0.7, 0.7, 0.7, 0.9},
  ALERT_TEXT_PREFIX_WISHLIST = "Wishlist item dropped:",
  ALERT_AUTOHIDE_SECONDS = 6,
  ALERT_WIDTH_MIN_DEFAULT = 360,
  ALERT_WIDTH_MAX_DEFAULT = 700,
  ALERT_WIDTH_PAD = 80,
  ALERT_MIN_WIDTH_SELF = 460,
  ALERT_MIN_WIDTH_OTHER = 540,
  ALERT_HEIGHT_WITH_BUTTONS = 130,

  -- Options UI appearance
  OPTIONS_EDITBOX_BG = {0, 0, 0, 0.35},
  OPTIONS_EDITBOX_BORDER = {0.3, 0.6, 1.0, 0.9},
}
