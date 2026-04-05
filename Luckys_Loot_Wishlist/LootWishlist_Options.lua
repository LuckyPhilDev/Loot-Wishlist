-- Loot Wishlist - Options Panel
-- Uses LuckyUI colors and fonts for consistent styling with Character Mount.

LootWishlist = LootWishlist or {}
LootWishlist.Options = LootWishlist.Options or {}

local Options = LootWishlist.Options
local C = LuckyUI.C
local panel
local settingsCategory
local DevLog = LuckyLog:New("[Lwl-Opts][debug]", function()
  return LootWishlist.DEBUG and LootWishlist.DEBUG()
end)

local function GetSettings()
  if LootWishlist.GetSettings then return LootWishlist.GetSettings() end
  return (LootWishlistDB and LootWishlistDB.settings) or (LootWishlistCharDB and LootWishlistCharDB.settings)
end

local function CreateMultiLineEditBox(parent, label, width, height)
  local title = parent:CreateFontString(nil, "OVERLAY")
  title:SetFont(LuckyUI.TITLE_FONT, 14)
  title:SetTextColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3])
  title:SetText(label)

  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(width, height)
  box:SetBackdrop(LuckyUI.Backdrop)
  box:SetBackdropColor(C.bgInput[1], C.bgInput[2], C.bgInput[3], C.bgInput[4])
  box:SetBackdropBorderColor(C.borderDark[1], C.borderDark[2], C.borderDark[3])

  local edit = CreateFrame("EditBox", nil, box)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFont(LuckyUI.BODY_FONT, 13, "")
  edit:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  edit:SetPoint("TOPLEFT", 8, -6)
  edit:SetPoint("BOTTOMRIGHT", -8, 6)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  edit:SetScript("OnEditFocusGained", function()
    box:SetBackdropBorderColor(C.goldMuted[1], C.goldMuted[2], C.goldMuted[3])
  end)
  edit:SetScript("OnEditFocusLost", function()
    box:SetBackdropBorderColor(C.borderDark[1], C.borderDark[2], C.borderDark[3])
  end)

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
  panel:SetSize(600, 400)
  panel:Hide()
  panel.name = "Loot Wishlist"

  -- Title
  local title = panel:CreateFontString(nil, "OVERLAY")
  title:SetFont(LuckyUI.TITLE_FONT, 16)
  title:SetTextColor(C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3])
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Loot Wishlist")

  -- Description
  local desc = panel:CreateFontString(nil, "OVERLAY")
  desc:SetFont(LuckyUI.BODY_FONT, 12)
  desc:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  desc:SetWidth(560)
  desc:SetJustifyH("LEFT")
  desc:SetText("Use %item% and %looter% placeholders in message templates.")

  local s = GetSettings() or {}
  local function GetDefaultWhisper() return (LootWishlist.Const and LootWishlist.Const.DEFAULT_WHISPER_TEMPLATE) or "" end
  local function GetDefaultParty()  return (LootWishlist.Const and LootWishlist.Const.DEFAULT_PARTY_TEMPLATE)  or "" end

  -- Message Templates heading
  local templatesHeading = panel:CreateFontString(nil, "OVERLAY")
  templatesHeading:SetFont(LuckyUI.TITLE_FONT, 14)
  templatesHeading:SetTextColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3])
  templatesHeading:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
  templatesHeading:SetText("Message Templates")

  local wTitle, wBox, wEdit = CreateMultiLineEditBox(panel, "Whisper message:", 560, 80)
  wTitle:SetPoint("TOPLEFT", templatesHeading, "BOTTOMLEFT", 0, -10)
  wBox:SetPoint("TOPLEFT", wTitle, "BOTTOMLEFT", 0, -6)
  wEdit:SetText(s.whisperTemplate or GetDefaultWhisper())

  local pTitle, pBox, pEdit = CreateMultiLineEditBox(panel, "Party message:", 560, 80)
  pTitle:SetPoint("TOPLEFT", wBox, "BOTTOMLEFT", 0, -16)
  pBox:SetPoint("TOPLEFT", pTitle, "BOTTOMLEFT", 0, -6)
  pEdit:SetText(s.partyTemplate or GetDefaultParty())

  -- Example text
  local example = panel:CreateFontString(nil, "OVERLAY")
  example:SetFont(LuckyUI.BODY_FONT, 11)
  example:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  example:SetPoint("TOPLEFT", pBox, "BOTTOMLEFT", 0, -8)
  example:SetWidth(560)
  example:SetJustifyH("LEFT")
  example:SetText("Example whisper: " .. applyPlaceholders(s.whisperTemplate or GetDefaultWhisper(), "[Example Item]", "Teammate") .. "\nExample party: " .. applyPlaceholders(s.partyTemplate or GetDefaultParty(), "[Example Item]"))

  -- Options heading
  local optionsHeading = panel:CreateFontString(nil, "OVERLAY")
  optionsHeading:SetFont(LuckyUI.TITLE_FONT, 14)
  optionsHeading:SetTextColor(C.goldAccent[1], C.goldAccent[2], C.goldAccent[3])
  optionsHeading:SetPoint("TOPLEFT", example, "BOTTOMLEFT", 0, -20)
  optionsHeading:SetText("Options")

  -- Minimap button checkbox
  local minimapState = (LootWishlistDB and LootWishlistDB.minimap) or {}
  local minimapCB = LuckyUI.CreateCheckbox(panel, 16)
  minimapCB:SetPoint("TOPLEFT", optionsHeading, "BOTTOMLEFT", 0, -10)
  minimapCB:SetChecked(not minimapState.hide)
  minimapCB:SetScript("OnClick", function(self)
    if LootWishlist.minimapButton then
      LootWishlist.minimapButton:SetShown_Persisted(self:GetChecked())
    end
  end)

  local minimapLabel = panel:CreateFontString(nil, "OVERLAY")
  minimapLabel:SetFont(LuckyUI.BODY_FONT, 13)
  minimapLabel:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  minimapLabel:SetPoint("LEFT", minimapCB, "RIGHT", 8, 0)
  minimapLabel:SetText("Minimap button")

  -- Raid roll alert checkbox
  local rollCB = LuckyUI.CreateCheckbox(panel, 16)
  rollCB:SetPoint("TOPLEFT", minimapCB, "BOTTOMLEFT", 0, -10)
  rollCB:SetChecked(s.enableRaidRollAlert ~= false)

  local rollLabel = panel:CreateFontString(nil, "OVERLAY")
  rollLabel:SetFont(LuckyUI.BODY_FONT, 13)
  rollLabel:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  rollLabel:SetPoint("LEFT", rollCB, "RIGHT", 8, 0)
  rollLabel:SetText("Enable raid roll alert")

  -- Hide summary checkbox
  local summaryCB = LuckyUI.CreateCheckbox(panel, 16)
  summaryCB:SetPoint("TOPLEFT", rollCB, "BOTTOMLEFT", 0, -10)
  summaryCB:SetChecked(s.hideSummaryWindow == true)
  summaryCB:SetScript("OnClick", function(self)
    local val = self:GetChecked() and true or false
    if LootWishlistDB and LootWishlistDB.settings then
      LootWishlistDB.settings.hideSummaryWindow = val
    end
    if LootWishlist.Summary and LootWishlist.Summary.refresh then LootWishlist.Summary.refresh() end
  end)

  local summaryLabel = panel:CreateFontString(nil, "OVERLAY")
  summaryLabel:SetFont(LuckyUI.BODY_FONT, 13)
  summaryLabel:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  summaryLabel:SetPoint("LEFT", summaryCB, "RIGHT", 8, 0)
  summaryLabel:SetText("Hide summary window")

  -- Open Wishlist button
  local openBtn = LuckyUI.CreateButton(panel, "Open Wishlist", 110, 22, "secondary")
  openBtn:SetPoint("LEFT", summaryLabel, "RIGHT", 12, 0)
  openBtn:SetScript("OnClick", function()
    if LootWishlist.Ace and LootWishlist.Ace.open then LootWishlist.Ace.open() end
  end)

  -- Debug mode checkbox
  local debugCB = LuckyUI.CreateCheckbox(panel, 16)
  debugCB:SetPoint("TOPLEFT", summaryCB, "BOTTOMLEFT", 0, -10)
  debugCB:SetChecked(s.debug == true)
  debugCB:SetScript("OnClick", function(self)
    local val = self:GetChecked() and true or false
    if LootWishlist.SetDebug then LootWishlist.SetDebug(val) end
  end)

  local debugLabel = panel:CreateFontString(nil, "OVERLAY")
  debugLabel:SetFont(LuckyUI.BODY_FONT, 13)
  debugLabel:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  debugLabel:SetPoint("LEFT", debugCB, "RIGHT", 8, 0)
  debugLabel:SetText("Debug mode")

  local debugHint = panel:CreateFontString(nil, "OVERLAY")
  debugHint:SetFont(LuckyUI.BODY_FONT, 11)
  debugHint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  debugHint:SetPoint("TOPLEFT", debugCB, "BOTTOMLEFT", 0, -2)
  debugHint:SetText("Print performance logs and diagnostics to chat.")

  -- Boss kill reminder delay slider
  local delayLabel = panel:CreateFontString(nil, "OVERLAY")
  delayLabel:SetFont(LuckyUI.BODY_FONT, 13)
  delayLabel:SetTextColor(C.textLight[1], C.textLight[2], C.textLight[3])
  delayLabel:SetPoint("TOPLEFT", debugHint, "BOTTOMLEFT", 0, -16)
  delayLabel:SetText("Spec reminder delay after boss kill")

  local delayValue = panel:CreateFontString(nil, "OVERLAY")
  delayValue:SetFont(LuckyUI.BODY_FONT, 13)
  delayValue:SetTextColor(C.goldPrimary[1], C.goldPrimary[2], C.goldPrimary[3])

  local delaySlider = CreateFrame("Slider", "LootWishlistDelaySlider", panel, "OptionsSliderTemplate")
  delaySlider:SetPoint("TOPLEFT", delayLabel, "BOTTOMLEFT", 0, -12)
  delaySlider:SetSize(240, 16)
  delaySlider:SetMinMaxValues(0, 30)
  delaySlider:SetValueStep(1)
  delaySlider:SetObeyStepOnDrag(true)
  delaySlider:SetValue(s.bossKillReminderDelay or 10)
  delaySlider.Low:SetText("0s")
  delaySlider.High:SetText("30s")
  delaySlider.Text:SetText("")

  delayValue:SetPoint("LEFT", delaySlider, "RIGHT", 10, 0)
  delayValue:SetText(tostring(math.floor(delaySlider:GetValue())) .. "s")

  delaySlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value + 0.5)
    delayValue:SetText(tostring(value) .. "s")
    local st = GetSettings()
    if st then st.bossKillReminderDelay = value end
  end)

  local delayHint = panel:CreateFontString(nil, "OVERLAY")
  delayHint:SetFont(LuckyUI.BODY_FONT, 11)
  delayHint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  delayHint:SetPoint("TOPLEFT", delaySlider, "BOTTOMLEFT", 0, -4)
  delayHint:SetText("How long to wait after a boss dies before showing the next spec reminder.")

  local function updateExample()
    local wText = wEdit:GetText()
    local pText = pEdit:GetText()
    if wText == "" then wText = GetDefaultWhisper() end
    if pText == "" then pText = GetDefaultParty() end
    example:SetText("Example whisper: " .. applyPlaceholders(wText, "[Example Item]", "Teammate") .. "\nExample party: " .. applyPlaceholders(pText, "[Example Item]"))
  end

  -- Save button
  local save = LuckyUI.CreateButton(panel, "Save", 120, 28, "primary")
  save:SetPoint("TOPLEFT", delayHint, "BOTTOMLEFT", 0, -12)
  save:SetScript("OnClick", function()
    local st = GetSettings()
    if st then
      local wText = wEdit:GetText()
      local pText = pEdit:GetText()
      st.whisperTemplate = (wText ~= "") and wText or GetDefaultWhisper()
      st.partyTemplate = (pText ~= "") and pText or GetDefaultParty()
      st.enableRaidRollAlert = rollCB:GetChecked() and true or false
      st.hideSummaryWindow = summaryCB:GetChecked() and true or false
      if LootWishlist.SetDebug then LootWishlist.SetDebug(debugCB:GetChecked() and true or false) end
      updateExample()
      if LootWishlist.Summary and LootWishlist.Summary.refresh then LootWishlist.Summary.refresh() end
    end
  end)

  -- Reset to Defaults button
  local resetBtn = LuckyUI.CreateButton(panel, "Reset to Defaults", 140, 28, "secondary")
  resetBtn:SetPoint("LEFT", save, "RIGHT", 10, 0)
  resetBtn:SetScript("OnClick", function()
    local defWhisper = GetDefaultWhisper()
    local defParty = GetDefaultParty()
    DevLog("Reset: Const=", tostring(LootWishlist.Const ~= nil), "whisper=", defWhisper, "party=", defParty)
    wEdit:SetText(defWhisper)
    pEdit:SetText(defParty)
    local st = GetSettings()
    if st then
      st.whisperTemplate = defWhisper
      st.partyTemplate = defParty
    end
    updateExample()
  end)

  -- Refresh values when panel is shown
  panel:SetScript("OnShow", function()
    local st = GetSettings() or {}
    wEdit:SetText(st.whisperTemplate or GetDefaultWhisper())
    pEdit:SetText(st.partyTemplate or GetDefaultParty())
    local ms = (LootWishlistDB and LootWishlistDB.minimap) or {}
    minimapCB:SetChecked(not ms.hide)
    rollCB:SetChecked(st.enableRaidRollAlert ~= false)
    summaryCB:SetChecked(st.hideSummaryWindow == true)
    debugCB:SetChecked(st.debug == true)
    delaySlider:SetValue(st.bossKillReminderDelay or 10)
    delayValue:SetText(tostring(math.floor(delaySlider:GetValue())) .. "s")
    updateExample()
  end)

  -- Register with game settings
  settingsCategory = LuckySettings:Register(panel, panel.name)
  return panel
end

function Options.Open()
  CreateOptionsPanel()
  LuckySettings:Open(settingsCategory)
end

-- Ensure panel is created on login
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  CreateOptionsPanel()
end)
