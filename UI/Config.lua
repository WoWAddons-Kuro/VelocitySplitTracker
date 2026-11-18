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

  ------------------------------------------------------------------------
  -- Auto Hide Settings
  ------------------------------------------------------------------------
  local function AddHeader(text)
    local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", 0, -18)
    h:SetText(text)
    lastWidget = h
    return h
  end

  -- Slider: label "<text>: N seconds" above, min/max under the ends; 0 is shown as "never".
  local function AddSlider(label, minV, maxV, step, get, set, zeroLabel)
    local s = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", 4, -24)
    s:SetWidth(220)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    s.Low:SetText(tostring(minV)); s.High:SetText(tostring(maxV))
    local function Caption(v)
      v = math.floor(v + 0.5)
      s.Text:SetText(label .. ": " .. ((v == 0 and zeroLabel) and zeroLabel or (v .. " seconds")))
    end
    s:SetScript("OnShow", function() s:SetValue(get()); Caption(get()) end)
    s:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      Caption(v)
      if v ~= get() then set(v) end
    end)
    lastWidget = s
    return s
  end

  -- Grid of checkboxes, 3 per row, each bound to table[key] under ST.db.Config[tableKey].
  -- Returns the last widget so the caller can continue the vertical flow.
  local function AddAxisGrid(tableKey, onChange)
    local AH = ST.AutoHide
    local anchor = lastWidget
    local perRow, colW, rowH = 3, 150, 26
    local first
    local boxes = {}
    for i, group in ipairs(AH.Groups) do
      local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
      local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
      cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 16 + col * colW, -6 - row * rowH)
      cb.Text:SetText(AH.GroupLabel[group])
      cb:SetScript("OnShow", function()
        local t = ST.db.Config[tableKey] or {}
        cb:SetChecked(t[group] == true)
      end)
      cb:SetScript("OnClick", function()
        ST.db.Config[tableKey] = ST.db.Config[tableKey] or {}
        ST.db.Config[tableKey][group] = cb:GetChecked() and true or false
        if onChange then onChange() end
      end)
      boxes[#boxes + 1] = cb
      if not first then first = cb end
    end
    -- the flow continues under the last row; use an invisible spacer anchored to the final row
    local rows = math.ceil(#AH.Groups / perRow)
    local spacer = CreateFrame("Frame", nil, panel)
    spacer:SetSize(1, 1)
    spacer:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6 - rows * rowH)
    lastWidget = spacer
    return boxes
  end

  AddHeader("Auto Hide Settings")

  AddSlider("Auto-Hide Panel After", 0, 60, 1,
    function() return ST.AutoHide.Seconds() end,
    function(v) ST.db.Config.AutoHide_Seconds = v; ST.AutoHide.Apply() end,
    "never")

  local reachedLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  reachedLabel:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", -4, -22)
  reachedLabel:SetText("Show on Splits Reached:")
  lastWidget = reachedLabel
  AddAxisGrid("AutoHide_ShowOnReached")

  AddCheck("Show when near Upcoming Splits",
    "Bring the window back when an upcoming split on a ticked axis becomes 'near' (quest complete in log, profession within reach of its next step or trainable, money near the next step, level XP at/over the near threshold, zone/area by time vs the reference).",
    function() return ST.db.Config.AutoHide_ShowNearUpcoming == true end,
    function(v) ST.db.Config.AutoHide_ShowNearUpcoming = v end)
  AddAxisGrid("AutoHide_ShowNearAxes")

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
