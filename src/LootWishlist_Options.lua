-- Loot Wishlist - settings panel, built on LuckyRichSettings.

LootWishlist = LootWishlist or {}
LootWishlist.Options = LootWishlist.Options or {}

local Options = LootWishlist.Options
local S = LootWishlist.Strings.settings
local Theme = LuckySettings.Rich.Theme
local FONT = LuckySettings.Rich.Font
local ADDON_FOLDER = "Luckys_Loot_Wishlist"
local VARIABLE_COLOR = "4fc3f7" -- info blue
local panel

local DEFAULT_TEMPLATE_KEYS = {
  whisperTemplate = "DEFAULT_WHISPER_TEMPLATE",
  partyTemplate   = "DEFAULT_PARTY_TEMPLATE",
}

local function settings()
  return LootWishlistDB and LootWishlistDB.settings
end

-- Every key read here is given a value at load, so the fallbacks only matter
-- for a database that has not finished initialising.
local function isOn(key)
  local s = settings()
  return not s or s[key] ~= false
end

local function isOff(key)
  local s = settings()
  return (s and s[key]) == true
end

local function read(key, fallback)
  local s = settings()
  local value = s and s[key]
  if value == nil then return fallback end
  return value
end

local function write(key, value)
  local s = settings()
  if s then s[key] = value end
end

-- Bonus roll blocking is per-character, so it sits beside the account-wide
-- settings rather than in them.
local function charSettings()
  LootWishlistCharDB = LootWishlistCharDB or {}
  LootWishlistCharDB.settings = LootWishlistCharDB.settings or {}
  return LootWishlistCharDB.settings
end

local function refreshSummary()
  if LootWishlist.Summary and LootWishlist.Summary.refresh then
    LootWishlist.Summary.refresh()
  end
end

local function defaultTemplate(key)
  return (LootWishlist.Const or {})[DEFAULT_TEMPLATE_KEYS[key]] or ""
end

local function colorizeVariables(text)
  return ((text or ""):gsub("(%%[%w_]+%%)", "|cff" .. VARIABLE_COLOR .. "%1|r"))
end

local function applyPlaceholders(template, itemLink, looterName)
  local out = (template or ""):gsub("%%item%%", itemLink or "[item]")
  return (out:gsub("%%looter%%", looterName or "player"))
end

-- One labelled box holding a message template. It writes on focus loss, so
-- there is nothing to save, and shows the variables in colour while it is not
-- being typed in: an edit box cannot colour part of its own text, so a font
-- string sits over the top carrying the coloured copy.
local function CreateTemplateEditor(parent, labelText, key, onChanged)
  local title = parent:CreateFontString(nil, "OVERLAY")
  title:SetFont(FONT, 12, "")
  title:SetTextColor(Theme.accentLight[1], Theme.accentLight[2], Theme.accentLight[3])
  title:SetText(labelText)

  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetHeight(72)
  box:SetBackdrop(LuckyUI.Backdrop)
  box:SetBackdropColor(Theme.bg3[1], Theme.bg3[2], Theme.bg3[3], 1)
  box:SetBackdropBorderColor(Theme.border2[1], Theme.border2[2], Theme.border2[3], 1)

  local edit = CreateFrame("EditBox", nil, box)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFont(FONT, 12, "")
  edit:SetTextColor(Theme.text[1], Theme.text[2], Theme.text[3])
  edit:SetPoint("TOPLEFT", 8, -6)
  edit:SetPoint("BOTTOMRIGHT", -8, 6)

  local overlay = box:CreateFontString(nil, "OVERLAY")
  overlay:SetFont(FONT, 12, "")
  overlay:SetTextColor(Theme.text[1], Theme.text[2], Theme.text[3])
  overlay:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, 0)
  overlay:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 0, 0)
  overlay:SetJustifyH("LEFT")
  overlay:SetJustifyV("TOP")

  local function showOverlay()
    overlay:SetText(colorizeVariables(edit:GetText()))
    overlay:Show()
    edit:SetAlpha(0)
  end

  edit:SetScript("OnEscapePressed", edit.ClearFocus)

  edit:SetScript("OnEditFocusGained", function()
    box:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    overlay:Hide()
    edit:SetAlpha(1)
  end)

  edit:SetScript("OnEditFocusLost", function()
    box:SetBackdropBorderColor(Theme.border2[1], Theme.border2[2], Theme.border2[3], 1)
    local text = edit:GetText()
    if text == "" then
      text = defaultTemplate(key)
      edit:SetText(text)
    end
    write(key, text)
    showOverlay()
  end)

  edit:SetScript("OnTextChanged", function()
    if not edit:HasFocus() then showOverlay() end
    if onChanged then onChanged() end
  end)

  edit:SetText(read(key, defaultTemplate(key)))

  local function reset()
    local text = defaultTemplate(key)
    write(key, text)
    edit:SetText(text)
  end

  return title, box, edit, reset
end

-------------------------------------------------------------------------------
-- Groups
-------------------------------------------------------------------------------

local function buildWishlist(g)
  g:Toggle({
    label    = S.trackHigher,
    desc     = S.trackHigherDesc,
    checked  = function() return isOn("addHigherDifficulties") end,
    onToggle = function(checked) write("addHigherDifficulties", checked) end,
  })

  g:Toggle({
    label    = S.hideObtained,
    desc     = S.hideObtainedDesc,
    since    = "1.14.0",
    checked  = function() return isOff("hideObtained") end,
    onToggle = function(checked)
      write("hideObtained", checked)
      if LootWishlist.UI and LootWishlist.UI.refresh then LootWishlist.UI.refresh() end
    end,
  })

  g:Toggle({
    label    = S.vaultStar,
    desc     = S.vaultStarDesc,
    checked  = function() return isOn("enableVaultOverlay") end,
    onToggle = function(checked) write("enableVaultOverlay", checked) end,
  })

  g:Toggle({
    label    = S.tooltipStatus,
    desc     = S.tooltipStatusDesc,
    since    = "1.14.1",
    checked  = function() return isOn("enableTooltipStatus") end,
    onToggle = function(checked) write("enableTooltipStatus", checked) end,
  })
end

local function buildSummary(g)
  g:Toggle({
    label    = S.hideSummary,
    desc     = S.hideSummaryDesc,
    checked  = function() return isOff("hideSummaryWindow") end,
    onToggle = function(checked)
      write("hideSummaryWindow", checked)
      refreshSummary()
    end,
  })

  g:Toggle({
    label    = S.hideSummaryCombat,
    desc     = S.hideSummaryCombatDesc,
    checked  = function() return isOn("hideSummaryInCombatAndMythicPlus") end,
    onToggle = function(checked)
      write("hideSummaryInCombatAndMythicPlus", checked)
      refreshSummary()
    end,
  })

  g:Slider({
    label     = S.summaryOpacity,
    desc      = S.summaryOpacityDesc,
    min       = 0,
    max       = 100,
    step      = 5,
    suffix    = "%",
    value     = function() return math.floor(read("summaryUnhoveredAlpha", 1) * 100 + 0.5) end,
    onChanged = function(value)
      write("summaryUnhoveredAlpha", value / 100)
      refreshSummary()
    end,
  })
end

local function buildAlerts(g)
  g:Section(S.dropSection)

  g:Toggle({
    label    = S.dropSound,
    desc     = S.dropSoundDesc,
    since    = "1.12.0",
    checked  = function() return isOn("enableDropSound") end,
    onToggle = function(checked) write("enableDropSound", checked) end,
  })

  g:Toggle({
    label    = S.raidRollAlert,
    desc     = S.raidRollAlertDesc,
    checked  = function() return isOn("enableRaidRollAlert") end,
    onToggle = function(checked) write("enableRaidRollAlert", checked) end,
  })

  g:Section(S.bonusRollSection)

  g:Toggle({
    label    = S.bonusRollRemind,
    desc     = S.bonusRollRemindDesc,
    checked  = function() return isOn("enableBonusRollReminders") end,
    onToggle = function(checked) write("enableBonusRollReminders", checked) end,
  })

  g:Toggle({
    label    = S.bonusRollSound,
    desc     = S.bonusRollSoundDesc,
    parent   = S.bonusRollRemind,
    checked  = function() return isOn("bonusRollSound") end,
    onToggle = function(checked) write("bonusRollSound", checked) end,
  })

  g:Section(S.blockSection)

  local function charRead(key) return charSettings()[key] end
  local function charWrite(key, value) charSettings()[key] = value end

  g:Toggle({
    label    = S.blockDismiss,
    desc     = S.blockDismissDesc,
    note     = S.blockDismissNote,
    warning  = S.blockDismissWarn,
    since    = "1.15.0",
    checked  = function() return charRead("bonusRollAutoDismiss") == true end,
    onToggle = function(checked) charWrite("bonusRollAutoDismiss", checked) end,
  })

  g:Toggle({
    label    = S.blockOnlyFlagged,
    desc     = S.blockOnlyFlaggedDesc,
    parent   = S.blockDismiss,
    checked  = function() return charRead("bonusRollOnlyFlagged") == true end,
    onToggle = function(checked) charWrite("bonusRollOnlyFlagged", checked) end,
  })

  g:Toggle({
    label    = S.blockKeepMythicPlus,
    desc     = S.blockKeepMythicPlusDesc,
    parent   = S.blockDismiss,
    checked  = function() return charRead("bonusRollKeepInMythicPlus") == true end,
    onToggle = function(checked) charWrite("bonusRollKeepInMythicPlus", checked) end,
  })

  g:Slider({
    label     = S.blockMinKeyLevel,
    desc      = S.blockMinKeyLevelDesc,
    min       = 2,
    max       = 10,
    parent    = S.blockKeepMythicPlus,
    value     = function() return charRead("bonusRollMythicPlusMinLevel") or 10 end,
    onChanged = function(value) charWrite("bonusRollMythicPlusMinLevel", value) end,
  })

  g:Toggle({
    label    = S.blockKeepRaids,
    desc     = S.blockKeepRaidsDesc,
    parent   = S.blockDismiss,
    checked  = function() return charRead("bonusRollKeepInRaids") == true end,
    onToggle = function(checked) charWrite("bonusRollKeepInRaids", checked) end,
  })

  local raidKeyToField = {
    lfr    = "bonusRollKeepInLFR",
    normal = "bonusRollKeepInNormalRaid",
    heroic = "bonusRollKeepInHeroicRaid",
    mythic = "bonusRollKeepInMythicRaid",
  }
  g:MultiSelect({
    label     = S.blockRaidDifficulties,
    desc      = S.blockRaidDifficultiesDesc,
    parent    = S.blockKeepRaids,
    options   = {
      { key = "lfr",    label = S.blockRaidLFR },
      { key = "normal", label = S.blockRaidNormal },
      { key = "heroic", label = S.blockRaidHeroic },
      { key = "mythic", label = S.blockRaidMythic },
    },
    isChecked = function(key) return charRead(raidKeyToField[key]) end,
    onToggle  = function(key, checked) charWrite(raidKeyToField[key], checked) end,
  })

  local function keepRow(label, desc, key)
    g:Toggle({
      label    = label,
      desc     = desc,
      parent   = S.blockDismiss,
      checked  = function() return charRead(key) == true end,
      onToggle = function(checked) charWrite(key, checked) end,
    })
  end

  keepRow(S.blockKeepDelve, S.blockKeepDelveDesc, "bonusRollKeepInDelve")
  keepRow(S.blockKeepDungeon, S.blockKeepDungeonDesc, "bonusRollKeepInDungeon")
  keepRow(S.blockKeepHunts, S.blockKeepHuntsDesc, "bonusRollKeepInHunts")

  g:Section(S.specSection)

  g:Slider({
    label     = S.specDelay,
    desc      = S.specDelayDesc,
    min       = 0,
    max       = 30,
    suffix    = "s",
    value     = function() return read("bossKillReminderDelay", 10) end,
    onChanged = function(value) write("bossKillReminderDelay", value) end,
  })
end

local function buildMinimap(g)
  local function clickRow(label, desc, key, note)
    g:Select({
      label    = label,
      desc     = desc,
      note     = note,
      since    = "1.12.3",
      -- The action names run long, so they get the line to themselves.
      newLine  = true,
      options  = LootWishlist.Const.MINIMAP_CLICK_ACTIONS,
      value    = function() return read(key) end,
      onSelect = function(action) write(key, action) end,
    })
  end

  clickRow(S.clickLeft, S.clickLeftDesc, "minimapClick", S.clickLeftNote)
  clickRow(S.clickCtrl, S.clickCtrlDesc, "minimapCtrlClick")
  clickRow(S.clickShift, S.clickShiftDesc, "minimapShiftClick")

  g:Section(S.otherClicks)
  g:Label({ label = S.clickRight, value = S.clickRightValue })
  g:Label({ label = S.clickMiddle, value = S.clickMiddleValue })
  g:Label({ label = S.clickDrag, value = S.clickDragValue })
end

local function buildMessages(g)
  local resetWhisper, resetParty

  g:Button({
    label   = S.resetMessages,
    onClick = function()
      if resetWhisper then resetWhisper() end
      if resetParty then resetParty() end
    end,
  })

  local content = g:Fill()
  -- Fill scrolls whatever it is given, so the height is set rather than measured.
  content:SetHeight(340)

  local hint = content:CreateFontString(nil, "OVERLAY")
  hint:SetFont(FONT, 11, "")
  hint:SetTextColor(Theme.textDim[1], Theme.textDim[2], Theme.textDim[3])
  hint:SetPoint("TOPLEFT", 4, -4)
  hint:SetPoint("RIGHT", -4, 0)
  hint:SetJustifyH("LEFT")
  hint:SetSpacing(3)
  hint:SetText(S.messagesHint)

  local wEdit, pEdit, example

  local function updateExample()
    if not (wEdit and pEdit and example) then return end
    local whisper = wEdit:GetText()
    local party = pEdit:GetText()
    if whisper == "" then whisper = defaultTemplate("whisperTemplate") end
    if party == "" then party = defaultTemplate("partyTemplate") end
    example:SetText(S.examplePreview:format(
      applyPlaceholders(whisper, S.exampleItem, S.exampleLooter),
      applyPlaceholders(party, S.exampleItem)))
  end

  local wTitle, wBox
  wTitle, wBox, wEdit, resetWhisper =
    CreateTemplateEditor(content, S.whisperEditor, "whisperTemplate", updateExample)
  wTitle:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -14)
  wBox:SetPoint("TOPLEFT", wTitle, "BOTTOMLEFT", 0, -6)
  wBox:SetPoint("RIGHT", content, "RIGHT", -4, 0)

  local pTitle, pBox
  pTitle, pBox, pEdit, resetParty =
    CreateTemplateEditor(content, S.partyEditor, "partyTemplate", updateExample)
  pTitle:SetPoint("TOPLEFT", wBox, "BOTTOMLEFT", 0, -14)
  pBox:SetPoint("TOPLEFT", pTitle, "BOTTOMLEFT", 0, -6)
  pBox:SetPoint("RIGHT", content, "RIGHT", -4, 0)

  example = content:CreateFontString(nil, "OVERLAY")
  example:SetFont(FONT, 11, "")
  example:SetTextColor(Theme.textDim[1], Theme.textDim[2], Theme.textDim[3])
  example:SetPoint("TOPLEFT", pBox, "BOTTOMLEFT", 0, -12)
  example:SetPoint("RIGHT", content, "RIGHT", -4, 0)
  example:SetJustifyH("LEFT")
  example:SetSpacing(3)
  updateExample()
end

local function buildPanel(p)
  -- Debug mode and the minimap button live in the title bar, so the first group
  -- is free to host the What's New list.
  local whatsNew = p:Group(S.whatsNew)
  whatsNew:BottomSection(S.versionInfo)
  whatsNew:BottomLabel({
    label = LootWishlist.Strings.addon.title,
    value = "v" .. (C_AddOns.GetAddOnMetadata(ADDON_FOLDER, "Version") or "?"),
  })
  whatsNew:BottomLabel({
    label = S.utilsLabel,
    value = "v" .. (C_AddOns.GetAddOnMetadata("Luckys_Utils", "Version")
      or ("1.0 r" .. LibStub.minors["LuckysUtils-1.0"])),
  })
  LuckyPromo:AddToRichGroup(whatsNew, ADDON_FOLDER)

  p:Group(S.groupWishlist, buildWishlist)
  p:Group(S.groupSummary, buildSummary)
  p:Group(S.groupAlerts, buildAlerts)
  p:Group(S.groupMinimap, buildMinimap)
  -- The message boxes want every pixel of width, and the hint above them says
  -- what the About rail would have.
  p:Group(S.groupMessages, { showAbout = false }, buildMessages)
end

local function CreatePanel()
  if panel then return panel end

  panel = LuckySettings:NewRichPanel(LootWishlist.Strings.addon.title, {
    addonFolder   = ADDON_FOLDER,
    minVersion    = LootWishlist.WHATS_NEW_MIN_VERSION,
    devMode       = {
      label    = S.debugMode,
      desc     = S.debugModeDesc,
      checked  = function() return LootWishlist.IsDebug() end,
      onToggle = function(checked) LootWishlist.SetDebug(checked) end,
    },
    minimapButton = {
      label    = S.minimapButton,
      desc     = S.minimapButtonDesc,
      checked  = function() return not (LootWishlistDB and LootWishlistDB.minimap or {}).hide end,
      onToggle = function(checked)
        if LootWishlist.minimapButton then
          LootWishlist.minimapButton:SetShown_Persisted(checked)
        end
      end,
    },
  }, buildPanel)

  return panel
end

function Options.Open()
  CreatePanel():Open()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", CreatePanel)
