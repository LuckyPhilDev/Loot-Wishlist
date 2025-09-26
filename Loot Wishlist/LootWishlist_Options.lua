-- Loot Wishlist - Options Panel

LootWishlist = LootWishlist or {}
LootWishlist.Options = LootWishlist.Options or {}

local Options = LootWishlist.Options
local panel
local settingsCategory -- DF Settings category object

local function GetSettings()
  return LootWishlist.GetSettings and LootWishlist.GetSettings() or (LootWishlistCharDB and LootWishlistCharDB.settings)
end

local function CreateMultiLineEditBox(parent, label, width, height)
  local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetText(label)

  -- Backdrop container for clear visual separation
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(width, height)
  box:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  do
    local C = LootWishlist.Const or {}
    local bg = C.OPTIONS_EDITBOX_BG or {0,0,0,0.35}
    local br = C.OPTIONS_EDITBOX_BORDER or {0.3, 0.6, 1.0, 0.9}
    box:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    box:SetBackdropBorderColor(br[1], br[2], br[3], br[4])
  end

  local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6) -- leave room for scrollbar

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(width - 40)
  edit:SetHeight(height - 16)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(edit)

  -- Return the container (with backdrop) so callers can position it
  return title, box, edit
end

local function applyPlaceholders(template, itemLink, looterName)
  if not template then return "" end
  local out = template:gsub("%%item%%", itemLink or "[item]")
  out = out:gsub("%%looter%%", looterName or "player")
  return out
end

local function CreateOptionsPanel()
  if panel then return panel end
  panel = CreateFrame("Frame")
  panel.name = "Loot Wishlist"

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Loot Wishlist Settings")

  local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  help:SetJustifyH("LEFT")
  help:SetWidth(560)
  help:SetText("Use %item% and %looter% placeholders. Examples are sent when alerts trigger.")

  local s = GetSettings() or {}

  local wTitle, wScroll, wEdit = CreateMultiLineEditBox(panel, "Whisper message template:", 560, 80)
  wTitle:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -10)
  wScroll:SetPoint("TOPLEFT", wTitle, "BOTTOMLEFT", 0, -6)
  wEdit:SetText(s.whisperTemplate or "")

  local pTitle, pScroll, pEdit = CreateMultiLineEditBox(panel, "Party message template:", 560, 80)
  pTitle:SetPoint("TOPLEFT", wScroll, "BOTTOMLEFT", 0, -20)
  pScroll:SetPoint("TOPLEFT", pTitle, "BOTTOMLEFT", 0, -6)
  pEdit:SetText(s.partyTemplate or "")

  local example = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  example:SetPoint("TOPLEFT", pScroll, "BOTTOMLEFT", 0, -12)
  example:SetWidth(560)
  example:SetJustifyH("LEFT")
  example:SetText("Example whisper: " .. applyPlaceholders(s.whisperTemplate or "", "[Example Item]", "Teammate") .. "\nExample party: " .. applyPlaceholders(s.partyTemplate or "", "[Example Item]"))

  local rollCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
  rollCB:SetPoint("TOPLEFT", example, "BOTTOMLEFT", 0, -12)
  rollCB.Text:SetText("Enable raid roll alert")
  rollCB:SetChecked(s.enableRaidRollAlert ~= false)

  local save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  save:SetSize(120, 22)
  save:SetPoint("TOPLEFT", rollCB, "BOTTOMLEFT", 0, -10)
  save:SetText("Save")
  save:SetScript("OnClick", function()
    local st = GetSettings()
    if st then
      st.whisperTemplate = wEdit:GetText() or st.whisperTemplate
      st.partyTemplate = pEdit:GetText() or st.partyTemplate
      st.enableRaidRollAlert = rollCB:GetChecked() and true or false
      example:SetText("Example whisper: " .. applyPlaceholders(st.whisperTemplate or "", "[Example Item]", "Teammate") .. "\nExample party: " .. applyPlaceholders(st.partyTemplate or "", "[Example Item]"))
    end
  end)

  -- Prefer Dragonflight Settings API; fallback to legacy Interface Options
  local SettingsTbl = rawget(_G, "Settings")
  if SettingsTbl and SettingsTbl.RegisterCanvasLayoutCategory and SettingsTbl.RegisterAddOnCategory then
    settingsCategory = SettingsTbl.RegisterCanvasLayoutCategory(panel, panel.name)
    if settingsCategory then
      SettingsTbl.RegisterAddOnCategory(settingsCategory)
    end
  else
    local IO_Add = rawget(_G, "InterfaceOptions_AddCategory")
    if IO_Add then IO_Add(panel) end
  end
  return panel
end

function Options.Open()
  local p = CreateOptionsPanel()
  local SettingsTbl = rawget(_G, "Settings")
  if p and SettingsTbl and SettingsTbl.OpenToCategory then
    -- Dragonflight+ Settings UI
    if settingsCategory then
      SettingsTbl.OpenToCategory(settingsCategory)
    else
      SettingsTbl.OpenToCategory(p.name)
    end
  else
    -- Fallback to legacy Interface Options
    local OpenLegacy = rawget(_G, "InterfaceOptionsFrame_OpenToCategory")
    if OpenLegacy then
      OpenLegacy(p)
      OpenLegacy(p)
    end
  end
end

-- Ensure panel is created on login
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  CreateOptionsPanel()
end)
