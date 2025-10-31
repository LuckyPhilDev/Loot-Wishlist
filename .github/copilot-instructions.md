# GitHub Copilot Instructions for Loot Wishlist

## Project Overview
Loot Wishlist is a World of Warcraft addon that helps players track desired loot from the Adventure Guide. It provides spec-aware tracking, drop alerts, and smart reminders for optimal loot specialization.

## Code Style & Conventions

### Lua Standards
- **Lua Version**: Lua 5.1 (WoW's embedded version)
- **Line Length**: 120 characters maximum
- **Indentation**: 2 spaces (no tabs)
- **Comments**: Use `--` for single-line, document complex logic
- **String Quotes**: Prefer double quotes `"` for user-facing strings, single quotes `'` for internal keys

### Naming Conventions
```lua
-- Global addon table (PascalCase)
LootWishlist = {}

-- Module tables (PascalCase)
LootWishlist.Alerts = {}
LootWishlist.EJ = {}

-- Public functions (PascalCase)
function LootWishlist.AddTrackedItem() end
function LootWishlist.RemoveTrackedItem() end

-- Local/private functions (camelCase)
local function parseItemIDFromLink() end
local function getCurrentInstanceDifficulty() end

-- Constants (UPPER_SNAKE_CASE)
local MAX_RETRIES = 3
local DEFAULT_TIMEOUT = 5

-- Variables (camelCase)
local trackedItems = {}
local bagCounts = {}
```

### File Organization
```
Loot Wishlist/
├── LootWishlist_Constants.lua   -- Constants, default values
├── LootWishlist_Core.lua         -- Core logic, saved variables, public API
├── LootWishlist_Alerts.lua       -- Drop alerts, spec reminders, event handling
├── LootWishlist_EJ.lua           -- Encounter Journal integration
├── LootWishlist_Options.lua      -- Settings panel
├── LootWishlist_UI_Ace.lua       -- Main UI window (AceGUI)
├── LootWishlist_Summary.lua      -- Sticky summary window
└── libs/                         -- Third-party libraries (don't edit)
```

## WoW API Patterns

### Safe API Calls
Always use pcall for potentially failing WoW APIs:
```lua
local ok, result = pcall(C_Item.GetItemSpecInfo, itemID)
if ok and result then
  -- use result
end
```

### Event Handling
```lua
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    -- handle login
  elseif event == "BAG_UPDATE_DELAYED" then
    -- handle bag update
  end
end)
```

### Async Item Data
Item data loads asynchronously. Always handle this:
```lua
local function getItemLinkAsync(itemID, callback)
  if Item and Item.CreateFromItemID then
    local item = Item:CreateFromItemID(itemID)
    if item then
      item:ContinueOnItemLoad(function()
        local link = item:GetItemLink()
        callback(link or ("item:"..itemID))
      end)
      return
    end
  end
  -- Fallback
  callback("item:"..itemID)
end
```

## Addon-Specific Patterns

### Difficulty-Aware Tracking
Items are keyed by `itemID@difficultyID` for multi-difficulty support:
```lua
-- Add item with difficulty
local key = difficultyID and (tostring(itemID).."@"..tostring(difficultyID)) or tostring(itemID)
trackedItems[key] = { id = itemID, difficultyID = difficultyID, ... }

-- Remove considering difficulty
if difficultyID == nil then
  -- Remove all difficulties for this item
else
  -- Remove only this difficulty
end
```

### Debug Logging
Always use the debug helper for verbose logging:
```lua
local function dprint(...)
  local ok = LootWishlist and LootWishlist.IsDebug and LootWishlist.IsDebug()
  if not ok then return end
  local msg = "[LootWishlist] "
  local parts = {}
  for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
  print(msg .. table.concat(parts, " "))
end

-- Usage
dprint("Tracking item:", itemID, "difficulty:", difficultyID)
```

### SavedVariables
```lua
-- Per-character data
LootWishlistCharDB = {
  trackedItems = {},     -- The wishlist
  settings = {},         -- Per-character settings
  windowPositions = {},  -- UI positions
}

-- Account-wide data
LootWishlistDB = {
  settings = {
    whisperTemplate = "...",
    partyTemplate = "...",
    enableRaidRollAlert = true,
    debug = false,
  }
}
```

## Testing & Debugging

### Manual Testing Commands
```lua
/wishlist debug              -- Toggle debug logging
/wishlist testdrop 246273    -- Simulate self drop
/wishlist testdrop-other ... -- Simulate other player drop
/wishlist list               -- Count tracked items
/wishlist clear              -- Reset wishlist
```

### Adding New Test Commands
```lua
-- In LootWishlist_Core.lua slash command handler
elseif msg:match("^mytest ") then
  local arg = msg:match("^mytest%s+(.+)$")
  if arg then
    -- Test code here
    print("Testing:", arg)
  end
end
```

## Common Pitfalls to Avoid

### ❌ Don't: Modify frames from widget pool
```lua
-- Bad: Modifying AceGUI frames directly
local button = AceGUI:Create("Button")
button.frame:SetSize(100, 50)  -- Don't do this!
```

### ✅ Do: Use widget methods
```lua
-- Good: Use AceGUI methods
local button = AceGUI:Create("Button")
button:SetWidth(100)
button:SetHeight(50)
```

### ❌ Don't: Assume API availability
```lua
-- Bad: Direct call without checking
local specs = C_Item.GetItemSpecInfo(itemID)
```

### ✅ Do: Check for API existence
```lua
-- Good: Check and pcall
if C_Item and C_Item.GetItemSpecInfo then
  local ok, specs = pcall(C_Item.GetItemSpecInfo, itemID)
  if ok and specs then
    -- use specs
  end
end
```

### ❌ Don't: Use global variables without declaration
```lua
-- Bad: Implicit global
myVariable = 123
```

### ✅ Do: Use local or explicit globals
```lua
-- Good: Explicit scope
local myVariable = 123
-- Or if truly global:
LootWishlist.myVariable = 123
```

## Architecture Principles

### Module Separation
- **Core**: Data management, public API, SavedVariables
- **Alerts**: Event-driven notifications and UI popups
- **EJ**: Read-only integration with Blizzard's Encounter Journal
- **UI**: User-facing windows and interactions
- **Options**: Settings configuration

### Event Flow
```
PLAYER_LOGIN
  → Initialize SavedVariables
  → Migrate legacy data
  → Register other events

BAG_UPDATE_DELAYED
  → Check for tracked items in bags
  → Show removal prompt if found

CHAT_MSG_LOOT / ENCOUNTER_LOOT_RECEIVED
  → Parse loot message
  → Check if tracked
  → Show appropriate alert (self/other)

PLAYER_ENTERING_WORLD / ZONE_CHANGED_NEW_AREA
  → Check instance context
  → Show spec reminders
  → Reset deduplication flags on zone leave
```

### Data Flow
```
User adds item via EJ button
  → LootWishlist.AddTrackedItem()
  → Compute specs asynchronously
  → Update SavedVariables
  → Refresh all UI windows

Item drops in-game
  → WoW event fires
  → Check trackedItems table
  → Show alert with actions
  → User clicks Remove
  → LootWishlist.RemoveTrackedItem()
  → Update SavedVariables
  → Refresh all UI windows
```

## TOC File Requirements

When adding new Lua files, update `Loot Wishlist.toc`:
```toc
## Interface: 110205
## Title: Loot Wishlist
## Notes: Track loot from the Adventure Guide
## Version: 1.3.3
## OptionalDeps: Ace3
## SavedVariablesPerCharacter: LootWishlistCharDB
## SavedVariables: LootWishlistDB

embeds.xml

LootWishlist_Constants.lua
LootWishlist_Core.lua
LootWishlist_NewFile.lua  ← Add here in load order
...
```

## Performance Considerations

- **Throttle high-frequency events**: Use debouncing for `BAG_UPDATE`, `OnUpdate`
- **Cache EJ queries**: Don't repeatedly call `EJ_GetLootInfoByIndex` in loops
- **Lazy-load item data**: Use async patterns, don't block on `GetItemInfo`
- **Limit table iterations**: Use indexed loops when order matters, avoid `pairs()` in hot paths

## Git Workflow

### Commit Messages
Follow conventional commits:
```bash
feat: add priority system for wishlist items
fix: correct difficulty matching in removal logic
docs: update README with new slash commands
chore: bump version to 1.4.0
ci: improve release workflow packaging
```

### Release Process
```bash
# 1. Update CHANGELOG.md with new version
# 2. Commit changes
git add CHANGELOG.md
git commit -m "docs: update changelog for v1.4.0"

# 3. Push to main
git push origin main

# 4. Create and push tag
git tag v1.4.0
git push origin v1.4.0

# 5. GitHub Actions automatically:
#    - Updates TOC version
#    - Creates release package
#    - Publishes to GitHub Releases
```

## When providing plans
Do not provide specific implementation detail. 
We're looking for high-level plans and outlines only.
Provide plans as markdown files and place them in the Feature plans directory.

## When Making Changes

1. **Check for existing patterns** - Look at similar code in other files
2. **Test in-game** - Use test commands to verify behavior
3. **Enable debug logging** - Use `/wishlist debug` to see what's happening
4. **Handle edge cases** - nil checks, empty tables, API failures
5. **Update documentation** - README.md and inline comments, Also update CHANGELOG.md when changes are likely to be user-visible
6. **Verify TOC load order** - Ensure dependencies are loaded first

## Resources

- [WoW API Documentation](https://wowpedia.fandom.com/wiki/World_of_Warcraft_API)
- [Ace3 Documentation](https://www.wowace.com/projects/ace3)
- [Lua 5.1 Reference](https://www.lua.org/manual/5.1/)
- [Keep a Changelog](https://keepachangelog.com/)
- [Semantic Versioning](https://semver.org/)
