LootWishlist = {}

dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_LootParser.lua")
dofile("src/LootWishlist_ReminderPlanner.lua")
dofile("src/LootWishlist_Reminders.lua")
dofile("src/LootWishlist_Alerts.lua")

assert(type(LootWishlist.Reminders.Init) == "function", "reminders should expose Init")
assert(type(LootWishlist.Alerts.Init) == "function", "alerts should expose Init")

print("1 module lifecycle test passed")
