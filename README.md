# Lucky's Loot Wishlist

Track loot from the Adventure Guide and manage a per-character wishlist with spec-aware alerts.

![Loot Wishlist](images/loot_wishlist.png)

## Features

- **Adventure Guide integration** — a "Wishlist" button appears on each loot row in the Encounter Journal; click to track any item across all tiers and difficulties
- **Spec-aware tracking** — records which specs can loot each item and shows them inline; items usable by all specs are tagged accordingly
- **Drop alerts** — notifies you when a tracked item drops, with context-sensitive actions:
  - *Self-looted:* Remove from wishlist or Keep tracking
  - *Looted by others:* Whisper the looter, announce to Party, or Dismiss
  - *Raid rolls:* reminder popup when a group loot roll starts for a wishlisted item
  - Warbound items ("Warbound until equipped") are automatically filtered out of alerts
- **Spec reminders** — on entering a dungeon or targeting a raid boss, shows a summary of what to switch to:
  - Switch to a different spec for specific items
  - Stay in your current spec for others
  - Items usable in any spec
  - Items your class can't use (highlighted in red)
  - Reminders show once per instance or boss and reset when you leave
- **Group assist suggestions** — in dungeons, suggests party members who could switch loot spec to help funnel a tracked item, with one-click Whisper or Party prompts
- **Multi-difficulty tracking** — adding an item on Normal automatically tracks it on Heroic and Mythic too; items tracked across difficulties appear as a single row with combined tags (e.g. `[N·H·M]`) so the list stays clean
- **Sticky summary window** — a compact, draggable overview of dungeons and raid bosses with remaining wishlist items; click to open the full list; position is remembered between sessions
- **Custom message templates** — configure Whisper and Party messages with `%item%` and `%looter%` placeholders
- **Multiple difficulty support** — track items across Normal, Heroic, Mythic, and LFR

## Installation

Install from [CurseForge](https://www.curseforge.com/wow/addons/luckys-loot-wishlist) or extract the release zip into your `Interface/AddOns` folder.

### Dependencies

- **LuckyUtils** — shared UI library (bundled automatically in CurseForge releases)

## Usage

1. Open the **Adventure Guide** (Shift+J) and browse to a boss
2. Click the **Wishlist** button on any loot row to track it
3. Open your wishlist with `/wishlist show` or `/lwl show`
4. Alerts appear automatically when tracked items drop in your group
5. Customise templates and toggles via `/wishlist settings` or **ESC > Options > AddOns > Lucky's Loot Wishlist**

## Slash Commands

`/wishlist` and `/lwl` accept the same subcommands:

| Command | Action |
|---------|--------|
| `/wishlist show` | Open the wishlist window |
| `/wishlist hide` | Hide the wishlist window |
| `/wishlist settings` | Open the settings panel (also accepts `options`) |
| `/wishlist list` | Print the number of tracked items |
| `/wishlist remove <itemID>` | Remove a single item by ID |
| `/wishlist clear` | Remove all tracked items |
| `/wishlist reset-spec` | Reset spec reminder debounce so they trigger again |
| `/wishlist debug` | Toggle debug logging |

## Settings

Access via `/wishlist settings` or **ESC > Options > AddOns > Lucky's Loot Wishlist**.

- Toggle the minimap button
- Toggle the sticky summary window
- Adjust summary window opacity when your mouse isn't hovering over it
- Toggle automatic multi-difficulty tracking (on by default)
- Toggle raid roll reminder alerts
- Configure the delay before spec reminders show after a boss kill
- Enable debug mode for troubleshooting
- Customise Whisper and Party message templates (`%item%`, `%looter%`)

## Known Issues

- Item data sometimes loads asynchronously — spec tags and links may appear a moment after opening the list
- Group assist suggestions are based on class and spec; they assume teammates can set loot spec even if not currently in that spec

## Author

**Lucky Phil**
