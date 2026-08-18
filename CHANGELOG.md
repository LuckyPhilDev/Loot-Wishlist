## [1.12.0] - 2026-08-18

### Added
- **Drop sound** A wishlist item dropping plays a sound, with a different one for your own drop and for someone else's. (Thanks for the suggestion Serroc)
- **Loot Browser grouping** The Loot Browser groups items by source or by gear slot, switched from the dropdown beside the track buttons.
- **Gear track on wishlist rows** Each row names the track it is tracked at, so a Hero entry and a Myth entry read apart at a glance.

### Improved
- **Drop alerts** Keep and Remove appear only when the drop reaches the gear track on your wishlist, and the alert tells you when the same item dropped on a lower track.
- **Under the hood** A tidy-up of the addon's internals. Nothing changes in how it looks or plays.
- **Lucky's Utils bundled** The shared library now ships inside the addon, so there is no separate download from CurseForge. If you have the standalone Lucky's Utils installed, you can remove it as long as no other Lucky addon still needs it.

### Fixed
- The Loot Browser no longer lists the season pages that only repeat loot the real dungeons and raids already carry.
