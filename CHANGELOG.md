## [Unreleased]

### Added
- **Search and filters on the wishlist** A search box at the top of the wishlist window narrows the list by item, boss or instance, and the funnel icon beside it filters to one gear slot.
- **Boss order** The layers icon on the wishlist window, and a setting in the Summary group, order bosses either the way the Adventure Guide lists them or by most wishlist items first. The summary window follows the same order.
- **Trade check on drop alerts** When a teammate loots an item you track, the alert checks what they have equipped in that slot and warns you when the drop is likely an upgrade they cannot trade.

### Fixed
- The summary window counts an item tracked on several difficulties once, matching the wishlist window.

## [1.15.1] - 2026-08-29

### Fixed
- Opening the Loot Browser no longer raises Blizzard's blocked-addon popup, which was also leaving dungeon tables empty and the filters dead until a second open. (Thanks for the report Grelle)

## [1.15.0] - 2026-08-29

### Added
- **Auto-dismiss Bonus Roll** Handle the Bonus Roll popup for you, keeping it only in the content you tick under Alerts. Chat says which setting acted on each roll. Moved here from Lucky's Grab-bag along with the choices you already made.
- **Lock the roll** An unwanted popup stays on screen with the dice greyed out and the reason on hover, so a setting you have not got right yet cannot cost you a roll. Click the dice to unlock it. Passing automatically is the other option.
- **Only keep for flagged bosses** Narrows Auto-dismiss Bonus Roll to the bosses you flagged a wishlist item on with the bonus roll button, so the popup is only left alone where the roll could land something you want.
- **Warning on Auto-dismiss Bonus Roll** A red icon sits beside the setting when it is set to pass, saying every popup passed is a bonus roll you never make. Set it to lock instead and the icon turns amber.

## [1.14.4] - 2026-08-26

### Fixed
- Settings and windows open again where an older copy of Lucky's Utils is installed alongside the addon, which the last update did not fully cover. (Thanks for the report Serroc)

## [1.14.3] - 2026-08-26

### Improved
- **Silver vault star** A Great Vault reward that is a wishlist item on a lower track than you track wears a silver star instead of a gold one. Hover it and the tooltip names the track your wishlist is at.
- Drop alerts read a dropped item's upgrade track from the item itself, so a Hero copy upgraded past a Mythic one no longer counts as the Mythic piece you track.

### Fixed
- A dungeon the game was slow to answer for no longer shows an empty or half-filled table in the Loot Browser for the rest of the session; the loot fills in as soon as the data arrives.
- Raid bosses in the wishlist and summary windows keep their kill order when the game answers slowly at login, instead of sorting alphabetically for the rest of the session.
- The settings window opens again where an old standalone copy of Lucky's Utils was installed alongside the addon. (Thanks for the report Serroc)

### Removed
- The Hide the Wardrobe model preview setting in the Wishlist settings group. Lucky's Wardrobe no longer previews an item on your character when you hover a row in the wishlist or the Loot Browser, and the preview still works everywhere else in the game.

## [1.14.2] - 2026-08-25

### Fixed
- The Loot Browser and the wishlist show item, boss and dungeon names on a Russian client, instead of empty boxes. (Thanks for the report Grelle)
- The dot separating label parts in the Loot Browser, the wishlist and the bonus roll reminder is a hyphen on a Russian client, whose font has no glyph for it and drew an empty box.

## [1.14.1] - 2026-08-23

### Added
- **Stat filter** Ask the Loot Browser for pieces carrying the secondary stats you pick, and choose whether a piece needs any of them, all of them, or nothing but them.
- **Wishlist status on item tooltips** Any item on your wishlist says so on its tooltip, in a bag, at a vendor or in a chat link, naming the boss it drops from and the difficulties you track it at. A toggle in the Wishlist settings group turns it off.

### Improved
- **Filter and group icons** The Loot Browser's class, spec, slot and stat filters share one funnel icon beside the search box, lit while a filter is on, with Reset Filters at the foot of its menu. The By Source and By Slot dropdown is now a one-click toggle next to it.

## [1.14.0] - 2026-08-23

### Added
- **Mark as obtained** A tick on each wishlist row greys the item out and stops its alerts and reminders, so a second drop stays quiet without deleting the record. Hide obtained items entirely from the Wishlist settings group.

### Improved
- **Wishlist row buttons** Bonus roll and remove are icons now rather than lettered buttons, and the Loot Browser's add and remove match them.
- **Secondary stats in the Loot Browser** A row reads its stats before the slot, largest first, so a Head piece shows as Haste/Crit Head. Armour type has gone from the row, the class filter having already settled it, and still answers a search.
- **Loot Browser sources** A dungeon drop leads with the dungeon and a raid drop with the boss, the other half of the pair following in a quieter tone.

### Fixed
- Moving the mouse between the buttons on a wishlist row no longer flashes the item tooltip on the way past.
- Tier tokens land under the slot they create the first time a Loot Browser table is opened, instead of sitting under Other until something else loaded the token.
- The Loot Browser's class filter reads a tier token's class list again, so a token no class you are browsing can use stays off the list.
