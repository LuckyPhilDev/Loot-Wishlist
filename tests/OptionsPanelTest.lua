-- luacheck: ignore 111 112 113 121 122 131
-- Builds the settings panel against stub frames. The panel is WoW frames all
-- the way down, so the frame API is stubbed just far enough for the rows to be
-- built and clicked: what this covers is that every group builds, and that the
-- rows read and write the same settings keys.

local function noop() end

local stubMeta = { __index = function() return noop end }

local function stub(fields)
  return setmetatable(fields or {}, stubMeta)
end

local function newText()
  return stub({
    text = "",
    SetText = function(self, t) self.text = t end,
    GetText = function(self) return self.text end,
    GetStringWidth = function() return 40 end,
    GetStringHeight = function() return 12 end,
  })
end

local editBoxes = {}

local function newFrame(kind, parent)
  local frame = stub({
    kind = kind,
    parent = parent,
    points = {},
    scripts = {},
    height = 0,
    width = 400,
    SetPoint = function(self, point, rel, relPoint, x, y)
      self.points[point] = { rel = rel, relPoint = relPoint, x = x, y = y }
    end,
    ClearAllPoints = function(self) self.points = {} end,
    SetHeight = function(self, h) self.height = h end,
    GetHeight = function(self) return self.height end,
    SetWidth = function(self, w) self.width = w end,
    GetWidth = function(self) return self.width end,
    SetSize = function(self, w, h) self.width, self.height = w, h end,
    CreateTexture = function() return stub() end,
    CreateFontString = function() return newText() end,
    SetScript = function(self, event, fn) self.scripts[event] = fn end,
    HookScript = function(self, event, fn) self.scripts[event] = fn end,
    GetScript = function(self, event) return self.scripts[event] or noop end,
  })

  if kind == "ScrollFrame" then
    frame.ScrollBar = stub({ SetShown = function(self, shown) self.shown = shown end })
  elseif kind == "CheckButton" then
    frame.checked = false
    frame.SetChecked = function(self, v) self.checked = v and true or false end
    frame.GetChecked = function(self) return self.checked end
  elseif kind == "Slider" then
    frame.value = 0
    frame.Low, frame.High, frame.Text = newText(), newText(), newText()
    frame.GetValue = function(self) return self.value end
    -- Like the real slider, a value that has not moved fires nothing.
    frame.SetValue = function(self, v)
      if self.value == v then return end
      self.value = v
      local fn = self.scripts.OnValueChanged
      if fn then fn(self, v) end
    end
  elseif kind == "EditBox" then
    frame.text = ""
    frame.focus = false
    frame.GetText = function(self) return self.text end
    frame.HasFocus = function(self) return self.focus end
    frame.SetText = function(self, t)
      self.text = t or ""
      local fn = self.scripts.OnTextChanged
      if fn then fn(self) end
    end
    frame.SetFocus = function(self)
      self.focus = true
      local fn = self.scripts.OnEditFocusGained
      if fn then fn(self) end
    end
    frame.ClearFocus = function(self)
      if not self.focus then return end
      self.focus = false
      local fn = self.scripts.OnEditFocusLost
      if fn then fn(self) end
    end
    editBoxes[#editBoxes + 1] = frame
  end

  return frame
end

CreateFrame = function(kind, _, parent) return newFrame(kind, parent) end

LuckyUI = stub({
  Backdrop = {},
  C = { goldIcon = { 1, 1, 1 } },
  CreateIconButton = function(parent) return newFrame("Button", parent) end,
  CreateButton = function(parent) return newFrame("Button", parent) end,
})
LuckySettings = stub({ Register = function() return "category" end })
LuckyMedia = function(file) return file end
LuckyPromo = stub()
LuckyDeps = stub({ Check = function() return false end })
C_AddOns = stub({ GetAddOnMetadata = function() return "1.12.3" end })

local menuButtons = {}
UIDropDownMenu_SetWidth = noop
UIDropDownMenu_SetText = function(dd, text) dd.text = text end
UIDropDownMenu_CreateInfo = function() return {} end
UIDropDownMenu_Initialize = function(dd, fn) dd.initialize = fn end
UIDropDownMenu_AddButton = function(info) menuButtons[#menuButtons + 1] = info end
UIDropDownMenu_EnableDropDown = noop
UIDropDownMenu_DisableDropDown = noop

local ns = {}
dofile("src/Luckys_Utils/LibStub.lua")
loadfile("src/Luckys_Utils/VersionGate.lua")("Luckys_Utils")
loadfile("src/Luckys_Utils/LuckyRichSettings/Core.lua")("Luckys_Utils", ns)
loadfile("src/Luckys_Utils/LuckyRichSettings/About.lua")("Luckys_Utils", ns)
loadfile("src/Luckys_Utils/LuckyRichSettings/Rows.lua")("Luckys_Utils", ns)
loadfile("src/Luckys_Utils/LuckyRichSettings/Panel.lua")("Luckys_Utils", ns)

-- Hand the built panel back so its rows can be read and clicked.
local builder
local newRichPanel = LuckySettings.NewRichPanel
LuckySettings.NewRichPanel = function(self, name, opts, contents)
  builder = newRichPanel(self, name, opts, contents)
  return builder
end

local debugMode = false
LootWishlistDB = { settings = {}, minimap = { hide = true } }
LootWishlistCharDB = { settings = {} }

dofile("src/LootWishlist_Constants.lua")

LootWishlist.IsDebug = function() return debugMode end
LootWishlist.SetDebug = function(v) debugMode = v end

-- The defaults Core applies at load, which every row reads through.
local defaults = {
  addHigherDifficulties = true,
  enableVaultOverlay = true,
  hideWardrobePreview = false,
  hideSummaryWindow = false,
  hideSummaryInCombatAndMythicPlus = true,
  summaryUnhoveredAlpha = 1.0,
  enableDropSound = true,
  enableRaidRollAlert = true,
  enableBonusRollReminders = true,
  bonusRollSound = true,
  bossKillReminderDelay = 10,
  minimapClick = "both",
  minimapCtrlClick = "wishlist",
  minimapShiftClick = "browser",
  whisperTemplate = LootWishlist.Const.DEFAULT_WHISPER_TEMPLATE,
  partyTemplate = LootWishlist.Const.DEFAULT_PARTY_TEMPLATE,
}
for k, v in pairs(defaults) do LootWishlistDB.settings[k] = v end

dofile("src/LootWishlist_Options.lua")

local settings = LootWishlistDB.settings
local checks = 0

local function check(condition, why)
  assert(condition, why)
  checks = checks + 1
end

LootWishlist.Options.Open()
builder.canvas.scripts.OnShow(builder.canvas)

local function findRow(label)
  for _, group in ipairs(builder.groups) do
    if group.byLabel[label] then return group.byLabel[label] end
  end
end

local function clickToggle(label, checked)
  local row = findRow(label)
  assert(row and row.checkbox, label .. " has no toggle")
  row.checkbox:SetChecked(checked)
  row.checkbox.scripts.OnClick(row.checkbox)
end

local function pickOption(label, index)
  local row = findRow(label)
  assert(row and row.dropdown, label .. " has no dropdown")
  menuButtons = {}
  row.dropdown.initialize(row.dropdown, 1)
  menuButtons[index].func()
end

-------------------------------------------------------------------------------
-- Every group builds, and What's New leads so it can host the list.
-------------------------------------------------------------------------------
local names = {}
for i, group in ipairs(builder.groups) do names[i] = group.name end
check(table.concat(names, "|") == "What's New|Wishlist|Summary|Alerts|Minimap|Messages",
  "the panel has its six groups in order, got " .. table.concat(names, "|"))

-------------------------------------------------------------------------------
-- Toggles read the value they write.
-------------------------------------------------------------------------------
check(findRow("Track higher difficulties").checkbox:GetChecked() == true,
  "a default-on toggle opens checked")

clickToggle("Track higher difficulties", false)
check(settings.addHigherDifficulties == false, "unchecking writes false")
clickToggle("Track higher difficulties", true)
check(settings.addHigherDifficulties == true, "checking writes true")

clickToggle("Hide the summary window", true)
check(settings.hideSummaryWindow == true, "a default-off toggle writes true when checked")

check(findRow("Play a sound with the reminder").parentSetting == findRow("Bonus roll reminders"),
  "the bonus roll sound hangs off the reminder toggle")

-------------------------------------------------------------------------------
-- A row whose addon is missing locks rather than lying about what it does.
-------------------------------------------------------------------------------
check(findRow("Hide the Wardrobe preview").disabled == true,
  "the Wardrobe row is disabled while Lucky's Wardrobe is absent")

-------------------------------------------------------------------------------
-- Sliders, including the percentage the summary stores as a fraction.
-------------------------------------------------------------------------------
findRow("Delay after a boss kill").slider:SetValue(20)
check(settings.bossKillReminderDelay == 20, "the delay slider writes seconds")

findRow("Opacity when not hovered").slider:SetValue(50)
check(settings.summaryUnhoveredAlpha == 0.5, "the opacity slider writes a fraction")

-------------------------------------------------------------------------------
-- The minimap click rows pick from the shared action list.
-------------------------------------------------------------------------------
check(findRow("Left-click opens").dropdown.text == "Wishlist and loot browser",
  "the row shows the label of the saved action")

pickOption("Left-click opens", 2)
check(settings.minimapClick == LootWishlist.Const.MINIMAP_CLICK_ACTIONS[2].key,
  "picking an option writes its key")

-------------------------------------------------------------------------------
-- Hovering a row renders it in the About rail. The rail is the library's work;
-- this only proves no row type the panel uses trips it up.
-------------------------------------------------------------------------------
for _, label in ipairs({ "Left-click opens", "Delay after a boss kill", "Play a sound", "Open the wishlist" }) do
  builder:UpdateAbout(findRow(label))
end
check(true, "every row type renders in the About rail")

-------------------------------------------------------------------------------
-- Message templates save when the box loses focus, and an empty box falls back
-- to the wording the addon ships with.
-------------------------------------------------------------------------------
local whisper = editBoxes[1]
check(whisper:GetText() == LootWishlist.Const.DEFAULT_WHISPER_TEMPLATE,
  "the whisper box opens on the saved template")

whisper:SetFocus()
whisper:SetText("Can I have %item%?")
whisper:ClearFocus()
check(settings.whisperTemplate == "Can I have %item%?", "clicking away saves the message")

whisper:SetFocus()
whisper:SetText("")
whisper:ClearFocus()
check(settings.whisperTemplate == LootWishlist.Const.DEFAULT_WHISPER_TEMPLATE,
  "an emptied box falls back to the default")
check(whisper:GetText() == LootWishlist.Const.DEFAULT_WHISPER_TEMPLATE,
  "and the box shows what was saved")

print(string.format("OptionsPanelTest: %d checks passed", checks))
