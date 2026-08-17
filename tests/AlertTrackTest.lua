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

print(string.format("AlertTrackTest: %d checks passed", passed))
