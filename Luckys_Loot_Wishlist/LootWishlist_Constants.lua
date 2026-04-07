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

  -- Raid layout graphs: maps EJ instanceID → { [encounterID] = { prereqs } }
  -- prereqs = {} means the boss is available from the start.
  -- prereqs = {id1, id2} means ALL listed bosses must be dead first.
  -- If a raid has no entry here, all alive bosses are treated as available.
  RAID_LAYOUTS = {
    -- Aberrus, the Shadowed Crucible (EJ 1208)
    [1208] = {
      [2522] = {},                  -- Kazzara: entrance boss
      [2529] = {2522},              -- Amalgamation Chamber: after Kazzara
      [2530] = {2529},              -- Forgotten Experiments: after Amalgamation Chamber
      [2524] = {2522},              -- Assault of the Zaqali: after Kazzara
      [2525] = {2524},              -- Rashok: after Assault of the Zaqali
      [2532] = {2525, 2530},        -- Zskarn: after Rashok + Forgotten Experiments
      [2527] = {2532},              -- Magmorax: after Zskarn
      [2523] = {2527},              -- Echo of Neltharion: after Magmorax
      [2520] = {2523},              -- Sarkareth: after Echo
    },
    -- The Voidspire (EJ 1307)
    [1307] = {
      [2733] = {},                  -- Imperator Averzian
      [2734] = {2733},              -- Vorasius
      [2736] = {2733},              -- Fallen-King Salhadaar
      [2735] = {2734,2736},         -- Vaelgor & Ezzorak requires both Vorasius and Fallen-King Salhadaar
      [2737] = {2735},              -- Lightblinded Vanguard
      [2738] = {2737},              -- Crown of the Cosmos
    },
    -- The Dreamrift (EJ 1314) - single boss
    [1314] = {
      [2795] = {},                  -- Chimaerus the Undreamt God
    },
    -- March on Quel'Danas (EJ 1308) - linear
    [1308] = {
      [2739] = {},                  -- Belo'ren, Child of Al'ar
      [2740] = {2739},              -- Midnight Falls
    },
  },
}
