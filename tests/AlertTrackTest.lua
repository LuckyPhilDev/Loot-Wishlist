-- luacheck: ignore 121

LootWishlist = {}

-- Fake links encode their ilvl as "item:<id>:<ilvl>"
C_Item = {
    GetDetailedItemLevelInfo = function(link)
        return tonumber(link:match("^item:%d+:(%d+)$"))
    end,
}

dofile("src/LootWishlist_Alerts.lua")

local meets = LootWishlist.Alerts.DropMeetsWishlistTrack
local passed = 0

local function check(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
    passed = passed + 1
end

local tracked
function LootWishlist.GetTracked() return tracked end

-- Tracked at Myth only: a Champion-track copy offers no removal
tracked = { ["100@16"] = { id = 100, link = "item:100:318" } }
check(meets(100, "item:100:292"), false, "lower track drop")
check(meets(100, "item:100:318"), true, "matching track drop")
check(meets(100, "item:100:330"), true, "higher track drop")

-- Tracked at Champion and Myth: a Champion copy satisfies the Champion entry
tracked = {
    ["100@14"] = { id = 100, link = "item:100:292" },
    ["100@16"] = { id = 100, link = "item:100:318" },
}
check(meets(100, "item:100:292"), true, "drop meets lowest of two entries")

-- Unknowable ilvls stay highlight-only: actions need a confirmed track match
tracked = { ["100@16"] = { id = 100, link = "item:100:318" } }
check(meets(100, "item:100"), false, "malformed drop link parses to no ilvl")
check(meets(100, nil), false, "no drop link")
tracked = { ["100@16"] = { id = 100 } }
check(meets(100, "item:100:292"), false, "entry without link")
tracked = {}
check(meets(100, "item:100:292"), false, "item not in tracked table")

-- A test drop uses the tracked entry's own link, so it clears its own gate
local entryLink = LootWishlist.Alerts.TrackedEntryLink

tracked = {
    ["100@14"] = { id = 100, link = "item:100:292" },
    ["100@16"] = { id = 100, link = "item:100:318" },
}
check(entryLink(100), "item:100:318", "highest tracked copy wins")
check(meets(100, entryLink(100)), true, "test drop clears the track gate")
check(entryLink(999), nil, "untracked item has no entry link")
tracked = { ["100@16"] = { id = 100 } }
check(entryLink(100), nil, "entry without a link")

-- A simulated item level stands in for the dropped copy's own
tracked = { ["100@16"] = { id = 100, link = "item:100:318" } }
check(meets(100, "item:100:292", 330), true, "simulated level clears the gate")
check(meets(100, "item:100:318", 200), false, "simulated level below the track")

-- Track words come from the Loot Browser's picker, so no second vocabulary
LootWishlist.Const = { TRACKS = {
    { key = "Veteran" },
    { key = "Hero", trackIlvl = 305 },
    { key = "Myth", trackIlvl = 318 },
} }
local resolve = LootWishlist.Alerts.ResolveSimulatedIlvl
check(resolve("myth"), 318, "track word, any case")
check(resolve("305"), 305, "bare item level")
check(resolve("Veteran"), nil, "track carrying no season item level")
check(resolve("Teammate"), nil, "a looter name is not a track")

-- Only a real track argument is taken off the end of a test command
local strip = LootWishlist.Alerts.StripTrackArg
local rest, ilvl = strip("100 myth")
check(rest .. "/" .. tostring(ilvl), "100/318", "track stripped off the item")
rest, ilvl = strip("100 Teammate")
check(rest .. "/" .. tostring(ilvl), "100 Teammate/nil", "looter name left alone")
rest, ilvl = strip("|Hitem:100|h[Big Sword]|h")
check(rest .. "/" .. tostring(ilvl), "|Hitem:100|h[Big Sword]|h/nil", "link with spaces left alone")

print(string.format("AlertTrackTest: %d checks passed", passed))
