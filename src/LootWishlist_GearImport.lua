-- Loot Wishlist - Gear list import
-- Paste a best-in-slot table copied from a guide site (Wowhead, Icy Veins,
-- Archon) or any item links, and track whatever matches this season's loot.
-- None of those sites exports item IDs, so names are matched against the
-- Loot Browser's season scan, which also supplies the boss and instance.

LootWishlist = LootWishlist or {}
LootWishlist.GearImport = {}

local GearImport = LootWishlist.GearImport
local S = LootWishlist.Strings.gearImport
local P = LootWishlist.Strings.addon.prefix

local PANEL_W, PANEL_H = 460, 340
local MAX_CELL  = 120   -- longer than any item name; keeps prose out of the name pool
local MAX_ITEMS = 500   -- same ceiling as a share-string import
local POLL      = 0.5   -- seconds between checks while the season scan runs
local WAIT      = 60    -- seconds before giving up on the scan

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isID(n)
  return n and n > 0 and n < 2147483648
end

-- Item IDs from anything link-shaped (Wowhead URLs, chat item links, SimC
-- lines), plus every line or tab-separated cell as a candidate item name.
-- Wowhead tables copy as tab-separated rows, Icy Veins grids as one field
-- per line; slot words and boss names ride along and simply never match.
function GearImport.Parse(text)
  local ids, names, seen = {}, {}, {}
  local function takeID(s)
    local id = tonumber(s)
    if isID(id) and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  for id in text:gmatch("item[=:](%d+)") do takeID(id) end
  for id in text:gmatch(",id=(%d+)") do takeID(id) end
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    for cell in (line .. "\t"):gmatch("([^\t]*)\t") do
      local name = trim(cell)
      if name ~= "" and #name <= MAX_CELL and not name:find("[=:,]%d") then
        local key = name:lower()
        if not seen[key] then
          seen[key] = true
          names[#names + 1] = key
        end
      end
    end
  end
  return { ids = ids, names = names }
end

local function isWordChar(ch)
  return ch ~= "" and ch:match("%w") ~= nil
end

-- Every index name that appears whole inside the cell. A cell is rarely just
-- the name: Wowhead copies the icon's title beside the link text, so the
-- name comes doubled, and a paste that loses its tabs runs the slot, name
-- and source together on one line.
local function namesIn(index, cell, take)
  local exact = index.byName[cell]
  if exact then take(exact); return end
  for name, entry in pairs(index.byName) do
    local s, f = cell:find(name, 1, true)
    while s do
      if not isWordChar(cell:sub(s - 1, s - 1)) and not isWordChar(cell:sub(f + 1, f + 1)) then
        take(entry)
        break
      end
      s, f = cell:find(name, f + 1, true)
    end
  end
end

-- Match parsed cells against the season index. Names resolve only through
-- the index; IDs the index does not know come back as loose IDs, which still
-- import but without a source.
function GearImport.Resolve(parsed, index)
  local entries, loose, seen = {}, {}, {}
  local function take(entry)
    if seen[entry.itemID] then return end
    seen[entry.itemID] = true
    entries[#entries + 1] = entry
  end
  for _, id in ipairs(parsed.ids) do
    local entry = index.byID[id]
    if entry then
      take(entry)
    elseif not seen[id] then
      seen[id] = true
      loose[#loose + 1] = id
    end
  end
  for _, cell in ipairs(parsed.names) do
    namesIn(index, cell, take)
  end
  return entries, loose
end

local function isTracked(tracked, itemID)
  for _, v in pairs(tracked) do
    if type(v) == "table" and v.id == itemID then return true end
  end
  return false
end

local function apply(entries, loose)
  local tracked = LootWishlist.GetTracked() or {}
  local names = LootWishlist.Const.DIFFICULTY_NAMES
  local added, existing = 0, 0
  local function count(itemID)
    if isTracked(tracked, itemID) then existing = existing + 1 else added = added + 1 end
  end
  for _, e in ipairs(entries) do
    count(e.itemID)
    LootWishlist.AddTrackedItemWithChain(e.itemID, e.boss, e.instanceName, e.isRaid, e.link,
      e.encounterID, e.instanceID, e.diffID, names[e.diffID], true)
  end
  for _, id in ipairs(loose) do
    if C_Item.DoesItemExistByID(id) then
      count(id)
      LootWishlist.AddTrackedItemQuiet(id, nil, LootWishlist.Strings.wishlist.manuallyAdded, false)
    end
  end
  return added, existing
end

local function countText(n)
  local share = LootWishlist.Strings.share
  return n == 1 and share.oneItem or share.manyItems:format(n)
end

local panel, busy

local function setStatus(text, danger)
  local c = danger and LuckyUI.C.danger or LuckyUI.C.textMuted
  panel.status:SetTextColor(c[1], c[2], c[3])
  panel.status:SetText(text)
end

local function finish(entries, loose)
  local added, existing = apply(entries, loose)
  panel:Hide()
  if added == 0 then
    print(P .. S.allExisting)
  elseif existing > 0 then
    print(P .. S.addedExisting:format(countText(added), existing))
  else
    print(P .. S.added:format(countText(added)))
  end
  if LootWishlist.UI and LootWishlist.UI.open then LootWishlist.UI.open() end
end

local function importText(text)
  local parsed = GearImport.Parse(text)
  if #parsed.ids == 0 and #parsed.names == 0 then
    setStatus(S.nothingPasted, true)
    return
  end
  local started = GetTime()
  busy = true
  local function attempt()
    if not busy or not panel:IsShown() then busy = false; return end
    -- ponytail: polls the browser's scan rather than subscribing to it
    local index = LootWishlist.Browser.SeasonIndex()
    if not index then
      if GetTime() - started > WAIT then
        busy = false
        setStatus(S.tablesTimedOut, true)
        return
      end
      local journalOpen = EncounterJournal and EncounterJournal:IsShown()
      setStatus(journalOpen and S.waitingForJournal or S.readingTables)
      C_Timer.After(POLL, attempt)
      return
    end
    busy = false
    local entries, loose = GearImport.Resolve(parsed, index)
    local total = #entries + #loose
    if total == 0 then
      setStatus(S.noMatches, true)
    elseif total > MAX_ITEMS then
      setStatus(S.tooMany:format(MAX_ITEMS), true)
    else
      finish(entries, loose)
    end
  end
  attempt()
end

local function buildPanel()
  local c = LuckyUI.C
  local frame = LuckyUI.CreatePanel("LootWishlistGearImportPanel", UIParent, PANEL_W, PANEL_H)
  frame:SetFrameStrata("DIALOG")
  frame:SetPoint("CENTER")
  frame:Hide()
  tinsert(UISpecialFrames, frame:GetName())
  frame:SetScript("OnHide", function() busy = false end)

  LuckyUI.CreateHeader(frame, S.title)

  local hint = frame:CreateFontString(nil, "OVERLAY")
  hint:SetFont(LuckyUI.BODY_FONT, 12)
  hint:SetTextColor(c.textMuted[1], c.textMuted[2], c.textMuted[3])
  hint:SetPoint("TOPLEFT", 14, -40)
  hint:SetPoint("TOPRIGHT", -14, -40)
  hint:SetJustifyH("LEFT")
  hint:SetText(S.hint)

  local scrollBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  scrollBg:SetBackdrop(LuckyUI.Backdrop)
  scrollBg:SetBackdropColor(c.bgInput[1], c.bgInput[2], c.bgInput[3], c.bgInput[4])
  scrollBg:SetBackdropBorderColor(c.borderDark[1], c.borderDark[2], c.borderDark[3])
  scrollBg:SetPoint("TOPLEFT", 14, -90)
  scrollBg:SetPoint("BOTTOMRIGHT", -14, 52)

  local scroll = CreateFrame("ScrollFrame", nil, scrollBg, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -26, 6)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFont(LuckyUI.BODY_FONT, 12, "")
  edit:SetTextColor(c.textLight[1], c.textLight[2], c.textLight[3])
  edit:SetWidth(PANEL_W - 60)
  edit:SetScript("OnEscapePressed", function() frame:Hide() end)
  scroll:SetScrollChild(edit)
  frame.edit = edit

  local status = frame:CreateFontString(nil, "OVERLAY")
  status:SetFont(LuckyUI.BODY_FONT, 12)
  status:SetPoint("BOTTOMLEFT", 14, 18)
  status:SetPoint("BOTTOMRIGHT", -200, 18)
  status:SetJustifyH("LEFT")
  frame.status = status

  local primary = LuckyUI.CreateButton(frame, S.importButton, 100, 26, "primary")
  primary:SetPoint("BOTTOMRIGHT", -14, 12)
  primary:SetScript("OnClick", function()
    if not busy then importText(edit:GetText() or "") end
  end)

  local close = LuckyUI.CreateButton(frame, S.close, 80, 26, "secondary")
  close:SetPoint("RIGHT", primary, "LEFT", -8, 0)
  close:SetScript("OnClick", function() frame:Hide() end)

  return frame
end

function GearImport.Show()
  panel = panel or buildPanel()
  busy = false
  panel.status:SetText("")
  panel.edit:SetText("")
  panel:Show()
  panel.edit:SetFocus()
end
