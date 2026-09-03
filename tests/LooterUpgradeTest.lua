-- luacheck: ignore 121

LootWishlist = {}

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_Alerts.lua")

local Alerts = LootWishlist.Alerts
local passed = 0

local function check(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
    passed = passed + 1
end

-- Slot mapping: single slots, paired slots, and things with no slot at all
check(Alerts.SlotsForEquipLoc("INVTYPE_HEAD")[1], 1, "head maps to slot 1")
check(#Alerts.SlotsForEquipLoc("INVTYPE_FINGER"), 2, "rings check both finger slots")
check(Alerts.SlotsForEquipLoc("INVTYPE_2HWEAPON")[1], 16, "two-hander checks main hand only")
check(#Alerts.SlotsForEquipLoc("INVTYPE_WEAPON"), 2, "one-hander checks both weapon slots")
check(Alerts.SlotsForEquipLoc("INVTYPE_NON_EQUIP_IGNORE"), nil, "non-equippable has no slots")
check(Alerts.SlotsForEquipLoc(nil), nil, "nil equip loc has no slots")

-- Verdicts: an upgrade is a drop above the lowest filled slot
local upgrade, worst = Alerts.UpgradeForLooter(489, {480})
check(upgrade, true, "drop above worn level is an upgrade")
check(worst, 480, "worst worn level is reported")
check(Alerts.UpgradeForLooter(480, {480}), false, "equal worn level is tradeable")
check(Alerts.UpgradeForLooter(480, {489}), false, "higher worn level is tradeable")

-- Paired slots: the lowest of the two decides
check(Alerts.UpgradeForLooter(490, {495, 480}), true, "upgrade over the lower of two rings")
check(Alerts.UpgradeForLooter(490, {495, 500}), false, "tradeable when both rings are higher")

-- Empty slots do not vote, unless every slot is empty
check(Alerts.UpgradeForLooter(490, {}), true, "all slots empty is an upgrade outright")
upgrade, worst = Alerts.UpgradeForLooter(490, {})
check(worst, nil, "all slots empty reports no worn level")

-- Unknowable drops stay quiet
check(Alerts.UpgradeForLooter(nil, {480}), false, "no dropped level means no verdict")

print(string.format("LooterUpgradeTest: %d checks passed", passed))
