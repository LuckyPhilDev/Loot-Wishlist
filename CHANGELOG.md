## [Unreleased]

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

## [1.13.1] - 2026-08-21

### Fixed
- Tier tokens in the Loot Browser now sit under the slot they create, so a head token lists under Head in the Slot filter instead of Other.
- The Loot Browser's class filter now hides tier tokens the selected class cannot use.

## [1.13.0] - 2026-08-20

### Added
- **Export and Import** Buttons at the bottom of the wishlist window turn your list into a string you can pass to someone else, and importing one asks whether to add it to your list or replace it.

### Improved
- **New settings panel** Settings sit in groups behind a nav rail, each with a description as you hover it. The Save button is gone, every change writes as you make it.
- **Mythic+ tag** Keystone items on the wishlist, the summary and the vault now read M+ instead of a bare plus sign.

### Fixed
- Hovering a row on the wishlist opens its tooltip on whichever side of the screen the window leaves free, instead of landing back across the list.
- Comparison tooltips no longer open on top of the wishlist window.
