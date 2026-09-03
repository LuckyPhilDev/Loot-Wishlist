-- luacheck: ignore 111 121
-- Pasted gear lists: what the parser pulls out of real site copies, and how
-- the cells resolve against a season index.

LootWishlist = {}
dofile("src/Luckys_Utils/LuckyStrings.lua")
dofile("src/LootWishlist_Strings.lua")
dofile("src/LootWishlist_GearImport.lua")

local GI = LootWishlist.GearImport
local checks = 0

local function check(cond, why)
  assert(cond, why)
  checks = checks + 1
end

local function has(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

-- Icy Veins: selecting the BiS grid gives one field per line, with enchant
-- lines indented and empty slots contributing only a slot word.
local ICY = "\nTempered Horns of the Jade Warlord\nHelm\n\nCatalyst or Twin Fangs\n Empowered Rune of Avoidance\n\n"
  .. "Jeweled Gauntlets of the Jade Warlord\nHands\nEntombed Sentinels\n\nAqirbane Reliquary\nNeck\n\n\nUla'tek\n\n"
  .. "Shirt\n\nSpellbreaker's March\nFeet\n\nCrafted by Blacksmithing\n"

-- Wowhead: the guide table copies as tab-separated rows with a header line.
local WOWHEAD = "Item Slot\tName\tSource\r\nHelm\t Tempered Horns of the Jade Warlord\tThe Twin Fangs\t\r\n"
  .. "Neck\t Aqirbane Reliquary\tUla'tek\t\r\nMainhand\t Maze-roa, Warlord's Fury\tThe Coiled Altar\t\r\n"

local LINKS = "https://www.wowhead.com/item=271456/tempered-horns-of-the-jade-warlord?bonus=12854\n"
  .. "|cffa335ee|Hitem:229351::::::::80:105::5:5:6652|h[Bloody Wake]|h|r\n"
  .. "head=tempered_horns,id=271456,bonus_id=12854/1234\n"
  .. "trinket1=voracious_heart,id=999999999999\n"

-- Parse ----------------------------------------------------------------------

local icy = GI.Parse(ICY)
check(#icy.ids == 0, "Icy Veins copy carries no ids")
check(has(icy.names, "tempered horns of the jade warlord"), "first grid item is a candidate")
check(has(icy.names, "spellbreaker's march"), "apostrophes survive")
check(has(icy.names, "empowered rune of avoidance"), "indented enchant line is trimmed")
check(has(icy.names, "helm") and has(icy.names, "ula'tek"), "slot and source words ride along")
check(not has(icy.names, ""), "blank lines are dropped")

local wh = GI.Parse(WOWHEAD)
check(has(wh.names, "tempered horns of the jade warlord"), "tab cells split")
check(has(wh.names, "maze-roa, warlord's fury"), "a comma inside a name is kept")
check(has(wh.names, "the twin fangs"), "source cell is a candidate too")
check(not has(wh.names, "the twin fangs\r"), "carriage returns are trimmed")

local links = GI.Parse(LINKS)
check(has(links.ids, 271456) and has(links.ids, 229351), "wowhead url and chat link ids")
check(#links.ids == 2, "simc id repeats the url id and the oversized id is refused")
check(not has(links.names, "https://www.wowhead.com/item=271456/tempered-horns-of-the-jade-warlord?bonus=12854"),
  "link lines are not name candidates")

local dup = GI.Parse("Aqirbane Reliquary\nAQIRBANE RELIQUARY\naqirbane reliquary")
check(#dup.names == 1, "names dedupe case-insensitively")

check(#GI.Parse("").names == 0 and #GI.Parse("  \n\t\n").names == 0, "whitespace parses to nothing")

local long = string.rep("x", 121)
check(#GI.Parse(long).names == 0 and #GI.Parse(string.rep("x", 120)).names == 1, "cells longer than 120 chars are prose")

-- Resolve --------------------------------------------------------------------

local horns = { itemID = 271456, encounterID = 3101, instanceID = 1320, instanceName = "Vaults", isRaid = true, diffID = 15 }
local reliquary = { itemID = 271500, encounterID = 3102, instanceID = 1320, instanceName = "Vaults", isRaid = true, diffID = 15 }
local index = {
  byID = { [271456] = horns, [271500] = reliquary },
  byName = { ["tempered horns of the jade warlord"] = horns, ["aqirbane reliquary"] = reliquary },
}

local entries, loose = GI.Resolve(icy, index)
check(#entries == 2 and entries[1] == horns and entries[2] == reliquary, "Icy Veins names resolve in order")
check(#loose == 0, "no loose ids from a names-only paste")

entries, loose = GI.Resolve(wh, index)
check(#entries == 2, "Wowhead table names resolve")

entries, loose = GI.Resolve(links, index)
check(#entries == 1 and entries[1] == horns, "a known id resolves through the index")
check(#loose == 1 and loose[1] == 229351, "an unknown id is loose")

entries = GI.Resolve(GI.Parse("item=271456\nTempered Horns of the Jade Warlord"), index)
check(#entries == 1, "the same item by id and by name is one entry")

entries, loose = GI.Resolve(GI.Parse("Helm\nNeck\nCrafted"), index)
check(#entries == 0 and #loose == 0, "nothing matching resolves to nothing")

-- Wowhead's BiS table as it actually pastes: the icon title doubles the link
-- text in the item cell, sometimes with a trailing space.
local DOUBLED = "Slot\tItem\tSource\n"
  .. "Head\tTempered Horns of the Jade Warlord Tempered Horns of the Jade Warlord\tUla'tek\n"
  .. "Neck\tAqirbane Reliquary Aqirbane Reliquary \tUla'tek\n"
  .. "Wrist\tMartyr's Bindings Martyr's Bindings\tCrafting\n"
entries, loose = GI.Resolve(GI.Parse(DOUBLED), index)
check(#entries == 2 and entries[1] == horns and entries[2] == reliquary, "doubled names resolve once each")

-- The same table with its tabs lost, so slot, name and source share a cell
entries = GI.Resolve(GI.Parse((DOUBLED:gsub("\t", " "))), index)
check(#entries == 2, "names are found inside a run-together line")

-- A name inside a longer word is not that item
local band = { itemID = 5, instanceName = "X", isRaid = false, diffID = 8 }
local partial = { byID = {}, byName = { ["band"] = band } }
check(#GI.Resolve(GI.Parse("Bubbleband\nHusband's ring"), partial) == 0, "no match inside a word")
check(#GI.Resolve(GI.Parse("Ring\tBand Band\tSomeone"), partial) == 1, "whole word matches")

print("GearImportTest: " .. checks .. " checks passed")
