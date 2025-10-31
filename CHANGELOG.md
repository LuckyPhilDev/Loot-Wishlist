# Changelog

All notable changes to Loot Wishlist will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.1] - 2025-10-28

### Fixed
- Fixed an issue where clicking "Remove" in the self-loot dialog (e.g., after moving an item from bank to bags) sometimes didn't remove the item if you were outside an instance. The addon now correctly treats "no instance" as no difficulty, so removal applies to all tracked difficulties for that item.

### Improved
- More robust bag-gain detection messaging and internal handling when a tracked item appears in your bags.
- "Warbound Until Equipped" items continue to be ignored by remove prompts (no behavior change), with clearer internal diagnostics.

### Added
- Added optional verbose debug logs to help diagnose edge cases. Toggle with `/wishlist debug`. When enabled, logs show bag scans, alert context, and removal decisions. No impact when off.

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

---

## Template for New Releases

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes to existing functionality

### Fixed
- Bug fixes

### Removed
- Removed features
```
