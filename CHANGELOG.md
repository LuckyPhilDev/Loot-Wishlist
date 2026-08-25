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
