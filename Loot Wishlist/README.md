**Loot Wishlist** is a lightweight wishlist tracker for World of Warcraft that lets you add items straight from the Adventure Guide, plan your runs at a glance, and get smart spec-aware alerts when your targets drop.

![Loot Wishlist](images/loot_wishlist.png)

---

### ✨ Features

- 📘 Add from the Adventure Guide: A “Wishlist” button appears on each loot row — click to track. The button only shows on item rows (not headers like “Bonus Loot”). Works for all tiers/older raids.
- 🗂️ Smart list (Ace3): Groups by instance and, for raids, by boss in Encounter Journal order. Item links are hoverable. Per‑character entries; account‑level settings.
- 🧠 Spec‑aware items: The addon records which specializations can loot each item and shows spec names inline in the list. When an item is usable in every spec it’s tagged as `{any spec}`.
- 🔔 Drop alerts with actions:
	- If you loot it: Remove or Keep the item on your list.
	- If someone else loots it: Whisper, Party announce, or Dismiss.
	- Raid roll reminder popup (optional) when a group loot roll starts for a wishlist item.
	- Warbound items are filtered out (no alerts or messages for “Warbound until equipped”).
- 🎯 Spec reminders (contextual):
	- Dungeons: on zone‑in, if your loot spec doesn’t match tracked items, a banner summarizes:
		- Switch <Spec> for …
		- Stay <Current Spec> for …
		- OK in any spec: …
		- Not eligible: … (red, for non‑class items)
	- Raids: the same summary shows when you target a boss that drops your tracked items.
	- Reminders show once per instance/boss and reset when you leave (or via a command).
- 🤝 Group assist suggestions: Suggests party/raid members who could set their loot spec to help you funnel a tracked item, with one‑click Whisper/Party prompts.
- 📝 Sticky summary: A compact, draggable “sticky note” shows dungeons/raid bosses that still have wishlist items. Click to open the full list. Position is remembered.
- ✉️ Custom messages: Configure Whisper and Party templates with placeholders: `%item%`, `%looter%`.
- ⌨️ Slash commands: `/wishlist`, `/lwl` (see below).

Ace3 is recommended for the full UI window. The Encounter Journal button and tracking work without it, but the list window uses AceGUI.

---

### 📋 How to Use

1. Open the Adventure Guide (Shift‑J) and browse to a boss.
2. In the loot list, click the “Wishlist” button on any row to add the item.
3. View your list:
	 - Type `/wishlist show`, or
	 - Click the sticky summary to open the full window.
4. Remove items:
	 - Click the remove icon next to the item in the list, or
	 - When you loot it, choose “Remove” in the alert, or
	 - Use `/wishlist remove <itemID>`.
5. Customize messages or toggle raid roll alerts via `/wishlist options` (Interface → AddOns → Loot Wishlist).
6. Group assist: In a group, zone into a tracked dungeon or target a tracked raid boss to see who can switch their loot spec to help.

---

### 🛎️ Alerts behavior

- Alerts show only when the dropped item is on your wishlist (by design).
- If you looted it: choose “Remove” (deletes from wishlist) or “Keep”.
- If someone else looted it: “Whisper” (auto‑sends a polite ask), “Party” (posts to your group), or “Dismiss”.
- Alerts use a clickable item link and auto‑size to content. Windows remember their positions.
- Warbound items (“Warbound until equipped”) are ignored by alerts and messaging.
- Spec reminders show once per instance/boss and reset on leaving the instance (or via a slash command).

---

### ⚙️ Settings & Templates

- Open via `/wishlist options` (or `/wishlist settings`) or Interface → AddOns → Loot Wishlist.
- Template placeholders:
	- `%item%` → clickable item link
	- `%looter%` → the player who looted (Whisper only)
- Toggle: “Enable raid roll alert” — on by default.
- Account‑wide settings: whisper/party templates, raid roll alert toggle, debug flag.

---

### ⌨️ Slash Commands

- `/wishlist show` — open the main window
- `/wishlist hide` — hide the main window
- `/wishlist options` — open options in Interface → AddOns
- `/wishlist list` — number of tracked items
- `/wishlist remove <itemID>` — remove a single item
- `/wishlist clear` — remove all tracked items
- `/wishlist debug` — toggle verbose debug logging
- `/wishlist reset-spec` — reset spec and group‑assist reminder de‑dupers so popups can re‑show
- `/wishlist testdrop <itemID|itemLink>` — simulate a self‑drop for a tracked item
- `/wishlist testdrop-not <itemID|itemLink>` — simulate a drop for an untracked item (should not alert)
- `/wishlist testdrop-other <itemID|itemLink> [player]` — simulate someone else looting

`/lwl` is a short alias for all of the above.

---

### 🛑 Known Issues & Notes

- Item data sometimes loads asynchronously; spec tags and links may appear a moment later.
- Group assist suggestions are class/spec based; they assume teammates can set loot spec even if not currently in that spec.
- Warbound detection uses tooltip text; if Blizzard wording changes in the future, behavior may need an update.

---

With **Loot Wishlist**, you’ll always know what to chase — and you’ll get timely, spec‑aware nudges when it finally drops.
