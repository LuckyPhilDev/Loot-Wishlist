-- luacheck: ignore 111 121
-- The minimap left-click plan: which window opens or closes for each of the
-- three configurable actions.

LootWishlist = {}
dofile("src/LootWishlist_Constants.lua")

local plan = LootWishlist.Const.MinimapClickPlan
local checks = 0

local function check(action, wishlistShown, browserShown, hasItems, wantWishlist, wantBrowser, why)
  local gotWishlist, gotBrowser = plan(action, wishlistShown, browserShown, hasItems)
  assert(gotWishlist == wantWishlist and gotBrowser == wantBrowser,
    string.format("%s: got %s/%s, wanted %s/%s",
      why, tostring(gotWishlist), tostring(gotBrowser), tostring(wantWishlist), tostring(wantBrowser)))
  checks = checks + 1
end

-- Wishlist only: toggles the list, never touches the browser.
check("wishlist", false, false, false, "open", nil, "wishlist opens even when empty")
check("wishlist", true, false, true, "close", nil, "wishlist closes when shown")
check("wishlist", false, true, true, "open", nil, "an open browser is left alone")

-- Browser only: toggles the browser, never touches the list.
check("browser", false, false, false, nil, "open", "browser opens")
check("browser", false, true, true, nil, "close", "browser closes when shown")
check("browser", true, false, true, nil, "open", "an open wishlist is left alone")

-- Both: opens the pair, but an empty wishlist stays shut.
check("both", false, false, true, "open", "open", "both open when the list has items")
check("both", false, false, false, nil, "open", "an empty wishlist stays shut")
check("both", true, true, true, "close", "close", "both close when both are shown")
check("both", false, true, true, nil, "close", "only what is shown gets closed")
check("both", true, false, true, "close", nil, "one shown window closes rather than the other opening")

assert(LootWishlist.Const.MinimapActionLabel("browser") == "Loot browser only", "labels resolve by key")
assert(LootWishlist.Const.MinimapActionLabel(nil) == "Wishlist and loot browser", "an unset action reads as both")
checks = checks + 2

print(string.format("MinimapClickTest: %d checks passed", checks))
