-- Loot Wishlist - settings panel, built on LuckyRichSettings.

LootWishlist = LootWishlist or {}
LootWishlist.Options = LootWishlist.Options or {}

local Options = LootWishlist.Options
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
    label    = "Also track higher difficulties",
    desc     = "Adding a dungeon item on Normal also tracks it on Heroic, Mythic and Mythic+. Turn this off to track only the difficulty you picked.",
    checked  = function() return isOn("addHigherDifficulties") end,
    onToggle = function(checked) write("addHigherDifficulties", checked) end,
  })

  g:Toggle({
    label    = "Star wishlist items in the Great Vault",
    desc     = "Puts a pulsing star on any Great Vault reward you track. Hover the star to see which wishlist entries it matches.",
    checked  = function() return isOn("enableVaultOverlay") end,
    onToggle = function(checked) write("enableVaultOverlay", checked) end,
  })

  g:Toggle({
    label    = "Hide the Wardrobe model preview",
    desc     = "Stops Lucky's Wardrobe showing your character wearing an item when you hover a row in the wishlist or the Loot Browser. The preview still works everywhere else in the game.",
    requires = { addon = "Luckys_Wardrobe" },
    checked  = function() return isOff("hideWardrobePreview") end,
    onToggle = function(checked) write("hideWardrobePreview", checked) end,
  })
end

local function buildSummary(g)
  g:Toggle({
    label    = "Hide the summary window",
    desc     = "The summary window is the small note listing what you track, grouped by dungeon and boss. Ticking this keeps it off the screen without changing your wishlist.",
    checked  = function() return isOff("hideSummaryWindow") end,
    onToggle = function(checked)
      write("hideSummaryWindow", checked)
      refreshSummary()
    end,
  })

  g:Toggle({
    label    = "Hide the summary in combat and Mythic+",
    desc     = "The summary window disappears while you are in combat or inside a Mythic+ run, then comes back when you leave.",
    checked  = function() return isOn("hideSummaryInCombatAndMythicPlus") end,
    onToggle = function(checked)
      write("hideSummaryInCombatAndMythicPlus", checked)
      refreshSummary()
    end,
  })

  g:Slider({
    label     = "Summary opacity when not hovered",
    desc      = "How solid the summary window looks while your mouse is away from it. At 0% it vanishes, and reappears when you hover where it sits.",
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
  g:Section("When a wishlist item drops")

  g:Toggle({
    label    = "Play a sound on a drop",
    desc     = "A sound plays when a tracked item drops, a bigger one when you looted it yourself. The on-screen alert shows either way.",
    since    = "1.12.0",
    checked  = function() return isOn("enableDropSound") end,
    onToggle = function(checked) write("enableDropSound", checked) end,
  })

  g:Toggle({
    label    = "Alert on a raid group roll",
    desc     = "A banner across the top of the screen when a tracked item goes up for a group roll. Raid groups only.",
    checked  = function() return isOn("enableRaidRollAlert") end,
    onToggle = function(checked) write("enableRaidRollAlert", checked) end,
  })

  g:Section("Bonus rolls")

  g:Toggle({
    label    = "Remind me after an eligible run",
    desc     = "A popup after a Mythic+ 10 or a Heroic or Mythic raid boss, listing the wishlist items you flagged for a bonus roll there. Only when you hold enough Nebulous Voidcore.",
    checked  = function() return isOn("enableBonusRollReminders") end,
    onToggle = function(checked) write("enableBonusRollReminders", checked) end,
  })

  g:Toggle({
    label    = "Play a sound with the reminder",
    desc     = "A raid warning sound plays alongside the bonus roll popup.",
    parent   = "Remind me after an eligible run",
    checked  = function() return isOn("bonusRollSound") end,
    onToggle = function(checked) write("bonusRollSound", checked) end,
  })

  g:Section("Spec reminders")

  g:Slider({
    label     = "Delay after a boss kill",
    desc      = "A spec reminder warns you when something you track on an upcoming boss needs a different loot spec. This is how long after a kill the check runs.",
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
      options  = LootWishlist.Const.MINIMAP_CLICK_ACTIONS,
      value    = function() return read(key) end,
      onSelect = function(action) write(key, action) end,
    })
  end

  clickRow("Left-click",
    "Which windows a plain left-click on the minimap button toggles. Click again to close them.",
    "minimapClick",
    "An empty wishlist stays shut, so \"Wishlist and Loot Browser\" opens the browser alone until you track something.")
  clickRow("Ctrl-click",
    "Which windows a left-click with Ctrl held toggles.",
    "minimapCtrlClick")
  clickRow("Shift-click",
    "Which windows a left-click with Shift held toggles.",
    "minimapShiftClick")

  g:Section("Other clicks")
  g:Label({ label = "Right-click", value = "Settings" })
  g:Label({ label = "Middle-click", value = "Toggle debug mode" })
  g:Label({ label = "Drag", value = "Move the button" })
end

local function buildMessages(g)
  local resetWhisper, resetParty

  g:Button({
    label   = "Reset both messages",
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
  hint:SetText("When someone else loots an item you track, the alert offers a Whisper and a Party button. These are what they send. %item% becomes the item link, %looter% the person who looted it. A box saves when you click away from it.")

  local wEdit, pEdit, example

  local function updateExample()
    if not (wEdit and pEdit and example) then return end
    local whisper = wEdit:GetText()
    local party = pEdit:GetText()
    if whisper == "" then whisper = defaultTemplate("whisperTemplate") end
    if party == "" then party = defaultTemplate("partyTemplate") end
    example:SetText("Whisper: " .. applyPlaceholders(whisper, "[Example Item]", "Teammate")
      .. "\nParty: " .. applyPlaceholders(party, "[Example Item]"))
  end

  local wTitle, wBox
  wTitle, wBox, wEdit, resetWhisper =
    CreateTemplateEditor(content, "Whisper to the looter", "whisperTemplate", updateExample)
  wTitle:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -14)
  wBox:SetPoint("TOPLEFT", wTitle, "BOTTOMLEFT", 0, -6)
  wBox:SetPoint("RIGHT", content, "RIGHT", -4, 0)

  local pTitle, pBox
  pTitle, pBox, pEdit, resetParty =
    CreateTemplateEditor(content, "Message to your group", "partyTemplate", updateExample)
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
  local whatsNew = p:Group("What's New")
  whatsNew:BottomSection("Version info")
  whatsNew:BottomLabel({
    label = "Lucky's Loot Wishlist",
    value = "v" .. (C_AddOns.GetAddOnMetadata(ADDON_FOLDER, "Version") or "?"),
  })
  whatsNew:BottomLabel({
    label = "Lucky's Utils",
    value = "v" .. (C_AddOns.GetAddOnMetadata("Luckys_Utils", "Version")
      or ("1.0 r" .. LibStub.minors["LuckysUtils-1.0"])),
  })
  LuckyPromo:AddToRichGroup(whatsNew, ADDON_FOLDER)

  p:Group("Wishlist", buildWishlist)
  p:Group("Summary", buildSummary)
  p:Group("Alerts", buildAlerts)
  p:Group("Minimap", buildMinimap)
  -- The message boxes want every pixel of width, and the hint above them says
  -- what the About rail would have.
  p:Group("Messages", { showAbout = false }, buildMessages)
end

local function CreatePanel()
  if panel then return panel end

  panel = LuckySettings:NewRichPanel("Lucky's Loot Wishlist", {
    addonFolder   = ADDON_FOLDER,
    minVersion    = LootWishlist.WHATS_NEW_MIN_VERSION,
    devMode       = {
      label    = "Debug mode",
      desc     = "Prints what the addon is doing to chat. Useful when reporting a problem.",
      checked  = function() return LootWishlist.IsDebug() end,
      onToggle = function(checked) LootWishlist.SetDebug(checked) end,
    },
    minimapButton = {
      label    = "Minimap button",
      desc     = "Show the Loot Wishlist button on the minimap. The Minimap group sets what each click opens.",
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
