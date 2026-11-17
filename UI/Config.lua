-- Settings panel registered with the Blizzard options UI. Empty shell for now.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local T = ST.Theme

ST.Config = {}
local C = ST.Config

local panel, categoryID

function C.Create()
  if panel then return panel end
  panel = CreateFrame("Frame", "VelocityConfigPanel")
  panel.name = "Velocity"

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Velocity")

  local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetWidth(560); sub:SetJustifyH("LEFT")
  sub:SetText("Options and the milestone plan editor will live here. While this panel is open the Active clock is paused.")

  -- Checkbox helper: label + getter/setter against ST.db.Config
  local lastWidget = sub
  local function AddCheck(label, tooltip, get, set)
    local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", 0, -10)
    cb.Text:SetText(label)
    cb.tooltipText = tooltip
    cb:SetScript("OnShow", function() cb:SetChecked(get()) end)
    cb:SetScript("OnClick", function() set(cb:GetChecked() and true or false); if ST.Live then ST.Live.Refresh() end end)
    lastWidget = cb
    return cb
  end

  AddCheck("Large timer (LiveSplit style, with tenths)",
    "Show the big two-line timer with tenths of a second. Off = a compact single row.",
    function() return ST.db.Config.BigTimer == true end,
    function(v) ST.db.Config.BigTimer = v end)

  AddCheck("Always show the next money milestone",
    "Pin the next 'Money Acquired' step as the last upcoming row. Off = only within 20% of the step.",
    function() return ST.db.Config.AlwaysShowMoney == true end,
    function(v) ST.db.Config.AlwaysShowMoney = v end)

  AddCheck("Always show deaths (softcore)",
    "Show the death counter in the footer even when it is 0. Off = only once you have died. Hardcore runs always show 'Hardcore' instead.",
    function() return ST.db.Config.ShowDeathsSoftcore ~= false end,
    function(v) ST.db.Config.ShowDeathsSoftcore = v end)

  local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  btn:SetSize(160, 22)
  btn:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", 0, -16)
  btn:SetText("Toggle split window")
  btn:SetScript("OnClick", function() ST.Live.Toggle() end)

  local btn2 = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  btn2:SetSize(160, 22)
  btn2:SetPoint("LEFT", btn, "RIGHT", 8, 0)
  btn2:SetText("Open history")
  btn2:SetScript("OnClick", function() ST.History.Toggle() end)

  panel:SetScript("OnShow", function() ST.ConfigPanelOpen = true end)
  panel:SetScript("OnHide", function() ST.ConfigPanelOpen = false end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    category.ID = panel.name
    Settings.RegisterAddOnCategory(category)
    categoryID = category:GetID()
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
  return panel
end

function C.Open()
  C.Create()
  if Settings and Settings.OpenToCategory and categoryID then
    Settings.OpenToCategory(categoryID)
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end
