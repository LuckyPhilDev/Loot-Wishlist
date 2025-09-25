# Loot Wishlist

Track Wishlist items directly from the Adventure Guide, see a compact plan of what to run, and get actionable alerts when your targets drop.

## Highlights
- Add from the Adventure Guide: A "Wishlist" button appears on each loot row. Click to track.
- Smart list UI (Ace3): Main window groups by instance; raids also group by boss in Encounter Journal order. Hover item links for tooltips. Per‑character storage.
- Sticky summary: A small always-on-top “sticky note” shows dungeons/raid bosses that still have wishlist items. Click to open the full list. Position is remembered.
- Drop alerts with actions:
	- If you loot it: Remove or Keep the item on your wishlist.
	- If someone else loots it: Whisper, Party announce, or Dismiss.
	- Alerts only trigger for items currently in your wishlist. They show the clickable item link and remember position.
    - Optional: Raid roll alert – when a group loot roll starts in a raid for an item on your wishlist, a small popup reminds you to roll.
- Custom messages: Configure Whisper and Party templates with placeholders: `%item%`, `%looter%`.
- Slash aliases: `/wishlist`, `/lwl`, and legacy `/remindme`.

Ace3 is recommended for the full UI window. The Encounter Journal button and tracking work without it, but the list window uses AceGUI.

## Installation
1. Copy the `RemindMe` folder into your `World of Warcraft/_retail_/Interface/AddOns/` directory.
2. (Recommended) Install the Ace3 library addon if you don’t have it.
3. Launch WoW and enable "Loot Wishlist" in the AddOns menu.

## Using the addon
1. Open the Adventure Guide (Shift‑J) and browse to a boss.
2. In the loot list, click the "Wishlist" button on any row to add that item.
3. View your wishlist:
	 - Type `/wishlist show`, or
	 - Click the sticky summary to open the full window.
4. Remove items:
	 - Click the remove icon next to an item in the list, or
	 - When you loot it, choose "Remove" in the alert, or
	 - Use `/wishlist remove <itemID>`.

## Alerts behavior
- Only shows when the dropped item is on your wishlist.
- Self‑loot: Choose "Remove" (deletes from wishlist) or "Keep".
- Other looter: "Whisper" (auto‑sends a polite ask), "Party" (auto‑sends to your current group channel if grouped), or "Dismiss".
- The alert uses a clickable item link and expands for buttons when needed.

## Settings (message templates)
- Open via `/wishlist options` (or `/wishlist settings`) or Interface → AddOns → Loot Wishlist.
- Templates support:
	- `%item%` → the clickable item link.
	- `%looter%` → the player who looted (Whisper only).
- Defaults provided; you can replace them with your own wording.
 - Toggle: “Enable raid roll alert” – on by default. Turn off if you don’t want a popup when a raid loot roll begins for a wishlist item.

## Commands
- `/wishlist show` – Show the main list window
- `/wishlist hide` – Hide the main list window
- `/wishlist list` – Print the number of tracked items
- `/wishlist remove <itemID>` – Remove a specific item
- `/wishlist clear` – Remove all tracked items
- `/wishlist options` – Open settings panel
- `/wishlist debug` – Toggle Encounter Journal hook debug
- Testing (for alerts):
	- `/wishlist testdrop <itemID|itemLink>` – Simulate that you looted it
	- `/wishlist testdrop-not <itemID|itemLink>` – Simulate a non‑wishlist item (no alert)
	- `/wishlist testdrop-other <itemID|itemLink> [looterName]` – Simulate someone else looting it
- Aliases: `/lwl`, `/remindme`

## Tips & Troubleshooting
- If the Wishlist button doesn’t appear in the Adventure Guide:
	- Try `/wishlist debug` then re‑open the Adventure Guide.
	- Ensure `Blizzard_EncounterJournal` is loaded; the addon hooks after it loads.
- Alerts only trigger for items on your wishlist (by design).
- The sticky summary and alert windows remember where you drag them.

## Data & Migration
- Data is saved per character.
- If you used the earlier RemindMe version, tracked items are imported automatically on first run.
