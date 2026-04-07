# Changelog

All notable changes to Loot Wishlist will be documented in this file.

## [1.6.0] - 2026-04-07

### Added
- When you add an item from Normal difficulty, Heroic and Mythic are automatically tracked too — so your wishlist stays complete without clicking each difficulty separately. Can be turned off in settings.

### Improved
- Items tracked across multiple difficulties now appear as a single row in your wishlist with combined difficulty tags (e.g. `[N·H·M]`), keeping the list clean and easy to scan
- Settings panel is now scrollable, so all options are accessible regardless of screen size

## [1.5.5] - 2026-04-07

### Added
- Minimap button toggle in the settings panel — show or hide the minimap button without reloading
- Adjustable opacity for the summary window when your mouse isn't over it, so it can fade into the background
- Spec reminder support for the three Midnight raids: The Voidspire, The Dreamrift, and March on Quel'Danas

### Improved
- Minimap button initialization is now more resilient to addon load order timing

## [1.5.4] - 2026-04-02

### Fixed
- Switching gear sets no longer triggers a false loot alert for wishlisted items that were equipped

## [1.5.1] - 2026-03-24

### Fixed
- Fixed "table index is secret" errors when targeting bosses in raids (Midnight taint changes)

### Improved
- Spec reminders in raids now trigger automatically based on which bosses are still alive, instead of requiring you to target them
- After a boss kill, the next spec reminder is delayed so it doesn't compete with loot rolls
- Non-linear raid layouts are now supported — the addon knows which bosses are available based on what you've already killed

### Added
- Minimap button — left-click to toggle the wishlist, right-click for settings, middle-click for dev mode
- Configurable delay (0–30 seconds) for how long to wait after a boss kill before showing the next spec reminder

## [1.5.0] - 2026-03-23

### Improved
- Completely redesigned interface with a fresh look that matches the Lucky Phil addon suite
- Wishlist now scrolls much more smoothly, especially with lots of tracked items
- Faster UI updates when adding or removing items
- Consistent button sizes and styling across the whole addon

### Added
- Debug mode toggle in settings for troubleshooting performance issues

## [1.4.2] - 2026-03-10

### Added
- Settings option to hide the sticky summary window
- "Open Wishlist" button in settings to open the full wishlist from the options panel

## [1.4.0] - 2026-02-01

### Changed
- Updated Interface version to 120000 for Midnight expansion support
- Spec reminders now show all valid specs for multi-spec items (e.g., "Windwalker or Brewmaster" instead of just "Windwalker")
- Renamed internal file LootWishlist_EJ.lua to LootWishlist_EncounterJournal.lua for clarity
- Improved Clear All button positioning to mirror Close button layout

### Fixed
- Fixed Clear All button positioning in main window

## [1.3.3] - 2025-10-31

### Fixed
- Fixed automated release workflow zip packaging structure - addon folder now properly extracts to AddOns directory
- Fixed GitHub Actions parameter warning (body_file → body_path)

### Changed
- Improved CI/CD workflow for cleaner release packaging

## [1.3.1] - 2025-10-31

### Added
- CI/CD implementation, test release

## [1.3.0] - 2025-10-15

### Added
- Initial public release
- Track items from Adventure Guide
- Spec-aware tracking with automatic spec detection
- Drop alerts with Remove/Keep actions for self-looted items
- Whisper/Party/Dismiss actions when others loot tracked items
- Spec reminders for dungeons and raids
- Group assist suggestions (dungeons only)
- Sticky summary window
- Custom message templates with placeholders
- Raid roll reminder alerts
- Multiple difficulty support

### Known Issues
- Item data sometimes loads asynchronously; spec tags and links may appear a moment later
