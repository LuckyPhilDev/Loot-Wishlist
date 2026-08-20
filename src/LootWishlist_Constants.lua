-- Loot Wishlist - Constants

LootWishlist = LootWishlist or {}

-- Settings added in this version or later carry a NEW badge and a What's New
-- card in the settings panel.
LootWishlist.WHATS_NEW_MIN_VERSION = "1.12.0"

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
  -- Shown when the drop is the wishlisted item at a track below the one you
  -- track, which is why the alert offers nothing to do with it.
  ALERT_TEXT_LOWER_TRACK = "Same item, on a lower track than the %s copy on your wishlist.",
  ALERT_TEXT_LOWER_TRACK_UNNAMED = "Same item, on a lower track than the copy on your wishlist.",
  ALERT_AUTOHIDE_SECONDS = 6,
  ALERT_WIDTH_MIN_DEFAULT = 360,
  ALERT_WIDTH_MAX_DEFAULT = 700,
  ALERT_WIDTH_PAD = 80,
  ALERT_MIN_WIDTH_SELF = 460,
  ALERT_MIN_WIDTH_OTHER = 540,
  ALERT_HEIGHT_WITH_BUTTONS = 130,

  -- Difficulty chains: ordered lowest → highest for raids and dungeons.
  -- Used to determine which difficulties to add when "track higher" is enabled.
  DIFFICULTY_CHAINS = {
    raid    = {17, 14, 15, 16},  -- LFR, Normal, Heroic, Mythic
    dungeon = {1, 2, 23, 8},     -- Normal, Heroic, Mythic, Mythic+
  },
  -- Canonical display names for difficulty IDs (used when auto-adding extra difficulties).
  DIFFICULTY_NAMES = {
    [1]  = "Normal",      -- dungeon
    [2]  = "Heroic",      -- dungeon
    [23] = "Mythic",      -- dungeon (Mythic 0)
    [8]  = "Mythic+",     -- Mythic+
    [14] = "Normal",      -- raid
    [15] = "Heroic",      -- raid
    [16] = "Mythic",      -- raid
    [17] = "Raid Finder", -- LFR
  },
  -- Display order for difficulty tags. Raids never carry "M+" so both source
  -- types read low → high with M0 before M+.
  DIFF_TAG_ORDER = { LFR=1, N=2, H=3, M=4, ["M+"]=5 },

  -- Gear-track picker for the Loot Browser, Midnight-era track model.
  --
  -- Raids carry one EJ difficulty per track, so raidDiff is both what the
  -- journal is read at and what a wishlist entry is stored as.
  --
  -- Dungeons have no Hero or Myth table in the journal at all. The same items
  -- drop from every key, at a higher track from harder keys and from the
  -- vault, so those tracks read the Mythic table (dungeonScanDiff) and each
  -- item is rebuilt as the track's own version: trackBonus is the bonus ID
  -- that marks an item "<track> 1/6" and trackIlvl the item level that rank
  -- carries. Both are season data (Midnight Season 2 here) and need a refresh
  -- each season; keystoneLevel is only the tooltip's "from +N" label.
  -- dungeonTrackDiff is what a wishlist entry is recorded at.
  TRACKS = {
    { key = "Veteran",  dungeonScanDiff = 2,  dungeonTrackDiff = 2,  raidDiff = 17 },
    { key = "Champion", dungeonScanDiff = 23, dungeonTrackDiff = 23, raidDiff = 14 },
    { key = "Hero",     dungeonScanDiff = 23, dungeonTrackDiff = 8, keystone = true,
      keystoneLevel = 6,  raidDiff = 15, trackIlvl = 305, trackBonus = 12841 },
    { key = "Myth",     dungeonScanDiff = 23, dungeonTrackDiff = 8, keystone = true,
      keystoneLevel = 10, raidDiff = 16, trackIlvl = 318, trackBonus = 12849 },
  },

  -- Season-tab journal pages the EJ lists as instances but which only group
  -- loot that real instances already carry; the Loot Browser skips them.
  -- 1319 "Keystone Dungeons" holds the M+ rotation, 1312 "Midnight" the
  -- season raids. Season data, refresh alongside TRACKS.
  EXCLUDED_JOURNAL_INSTANCES = { [1319] = true, [1312] = true },

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
    -- The Venomous Abyss (EJ 1320). Nek'zali opens the vault, the Vile Crypt
    -- and the Crypt of the Soulcoilers are cleared in either order, and the
    -- raid converges on the Twin Fangs for the last three.
    [1320] = {
      [2888] = {},                  -- Nek'zali the Soulcoiler: entrance boss
      [2874] = {2888},              -- Entombed Sentinels: Vile Crypt
      [2882] = {2874},              -- Vashnik the Malignant: after Entombed Sentinels
      [2894] = {2888},              -- The Lost Explorers: Crypt of the Soulcoilers
      [2871] = {2894},              -- Sszorak: after The Lost Explorers
      [2887] = {2882, 2871},        -- The Twin Fangs: after both crypts
      [2883] = {2887},              -- The Coiled Altar: after The Twin Fangs
      [2895] = {2883},              -- Ula'tek: after The Coiled Altar
    },
    -- The Tidebound Grotto has one boss, Nymrissa Wavecaller, so there is
    -- nothing to gate and no entry to keep.
  },
}

-- Minimap left-click: what a plain, Ctrl- or Shift-click acts on. Settings
-- store the key; the label is what the options panel and tooltip show.
LootWishlist.Const.MINIMAP_CLICK_ACTIONS = {
  { key = "both",     label = "Wishlist and Loot Browser" },
  { key = "wishlist", label = "Wishlist only" },
  { key = "browser",  label = "Loot Browser only" },
}

function LootWishlist.Const.MinimapActionLabel(key)
  for _, action in ipairs(LootWishlist.Const.MINIMAP_CLICK_ACTIONS) do
    if action.key == key then return action.label end
  end
  return LootWishlist.Const.MINIMAP_CLICK_ACTIONS[1].label
end

-- What a minimap left-click does to each window: "open", "close" or nil.
-- Pure, so the toggle rules can be checked without the game running.
function LootWishlist.Const.MinimapClickPlan(action, wishlistShown, browserShown, wishlistHasItems)
  if action == "wishlist" then
    return wishlistShown and "close" or "open", nil
  elseif action == "browser" then
    return nil, browserShown and "close" or "open"
  end
  if wishlistShown or browserShown then
    return wishlistShown and "close" or nil, browserShown and "close" or nil
  end
  -- An empty wishlist adds nothing to a browsing session, so it stays shut.
  return wishlistHasItems and "open" or nil, "open"
end

-- The short difficulty tag shown beside an item, from the difficulty name where
-- one was recorded and the difficulty ID otherwise.
function LootWishlist.Const.DiffTag(name, id)
  if name and name ~= "" then
    local n = name:lower()
    if n:find("raid finder") or n:find("lfr") then return "LFR" end
    if n:find("normal") then return "N" end
    if n:find("heroic") then return "H" end
    if n:find("mythic%+") or n:find("keystone") then return "M+" end
    if n:find("mythic") then return "M" end
  end
  if id then
    local map = { [1]="N", [2]="H", [8]="M+", [23]="M", [24]="TW", [14]="N", [15]="H", [16]="M", [17]="LFR" }
    return map[id]
  end
  return nil
end
