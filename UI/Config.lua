-- Settings panel registered with the Blizzard options UI.
-- Layout follows the GotJunk options panel: a scrolling canvas, a title + intro, then bordered
-- Section boxes with a header; widgets hang off a running `last` anchor inside each box so
-- checkboxes, sliders and grids share one left edge. Every widget exposes Update() and the
-- panel re-reads ST.db.Config on every OnShow.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local T = ST.Theme

ST.Config = {}
local C = ST.Config

local panel, categoryID
local widgets = {}   -- everything with an Update(); refreshed on OnShow

local BOX_W, PAD = 580, 10

local function Cfg() return ST.db.Config end
local function Refresh() if ST.Live then ST.Live.Refresh() end end

function C.Create()
  if panel then return panel end
  panel = CreateFrame("Frame", "VelocityConfigPanel")
  panel.name = "Velocity Split Tracker"

  -- Scrolling container: the registered canvas holds a ScrollFrame whose child `content`
  -- carries every widget. Mouse wheel scrolls; a standard scrollbar sits on the right.
  local scroll = CreateFrame("ScrollFrame", "VelocityConfigScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(620, 1200)   -- height corrected after layout
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(math.max(620, w)) end)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
  end)

  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16); title:SetText("Velocity Split Tracker")
  local sub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6); sub:SetWidth(560); sub:SetJustifyH("LEFT")
  sub:SetText("LiveSplit-style split tracker for leveling. Every character is recorded automatically; these options only change what the split window shows. While this panel is open the Active clock is paused.")

  -- Layout: every top-level widget hangs off `last` at a fixed left column.
  local last, lastDy = sub, -14
  local function Place(w, dy, dx) w:SetPoint("TOPLEFT", last, "BOTTOMLEFT", dx or 0, dy or lastDy); last = w; lastDy = -6 end

  ------------------------------------------------------------------------
  -- Widget factories (all return a frame with :Update())
  ------------------------------------------------------------------------
  local function Check(parent, label, tip, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb.Text:SetText(label)
    cb.tooltipText = tip
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); Refresh() end)
    cb.Update = function(self) self:SetChecked(get() and true or false) end
    widgets[#widgets + 1] = cb
    return cb
  end

  -- Slider with its label above-left (not centred over the track) so it aligns with checkboxes.
  local function Slider(parent, name, minV, maxV, get, set, labelFn)
    local holder = CreateFrame("Frame", nil, parent); holder:SetSize(BOX_W - 2 * PAD, 44)
    local label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); label:SetPoint("TOPLEFT", 4, 0)
    local s = CreateFrame("Slider", name, holder, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 2, -6); s:SetWidth(220)
    s:SetMinMaxValues(minV, maxV); s:SetValueStep(1); s:SetObeyStepOnDrag(true)
    _G[name .. "Low"]:SetText(tostring(minV)); _G[name .. "High"]:SetText(tostring(maxV)); _G[name .. "Text"]:SetText("")
    s:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      label:SetText(labelFn(v))
      if v ~= get() then set(v) end
    end)
    holder.Update = function() s:SetValue(get()); label:SetText(labelFn(get())) end
    widgets[#widgets + 1] = holder
    return holder
  end

  -- Grid of small checkboxes, `perRow` per line, for a set of named flags stored in
  -- ST.db.Config[tableKey][group]. Returns a holder sized to the grid.
  local function FlagGrid(parent, tableKey, groups, labels, perRow, onChange)
    perRow = perRow or 3
    local colW, rowH = 150, 24
    local rows = math.ceil(#groups / perRow)
    local holder = CreateFrame("Frame", nil, parent); holder:SetSize(BOX_W - 2 * PAD, rows * rowH)
    holder.boxes = {}
    for i, group in ipairs(groups) do
      local cb = CreateFrame("CheckButton", nil, holder, "InterfaceOptionsCheckButtonTemplate")
      local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
      cb:SetSize(22, 22)
      cb:SetPoint("TOPLEFT", holder, "TOPLEFT", col * colW, -row * rowH)
      cb.Text:SetText(labels[group] or group)
      cb:SetScript("OnClick", function(self)
        Cfg()[tableKey] = Cfg()[tableKey] or {}
        Cfg()[tableKey][group] = self:GetChecked() and true or false
        if onChange then onChange() end
      end)
      holder.boxes[group] = cb
    end
    holder.Update = function()
      local t = Cfg()[tableKey] or {}
      for group, cb in pairs(holder.boxes) do cb:SetChecked(t[group] == true) end
    end
    -- enable/disable the whole grid (used under a master checkbox)
    holder.SetEnabledAll = function(_, on)
      for _, cb in pairs(holder.boxes) do cb:SetEnabled(on); cb.Text:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5) end
    end
    widgets[#widgets + 1] = holder
    return holder
  end

  -- Plain text line inside a section (sub-heading for a grid).
  local function Label(parent, text)
    local holder = CreateFrame("Frame", nil, parent); holder:SetSize(BOX_W - 2 * PAD, 16)
    local fs = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); fs:SetPoint("TOPLEFT", 4, 0); fs:SetText(text)
    return holder
  end

  -- Bordered section. Children are laid out inside with their own `last` chain; the box is
  -- sized from the running height after the children are added.
  local function Section(header)
    local box = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
    box:SetWidth(BOX_W)
    if box.SetBackdrop then
      box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      box:SetBackdropColor(0, 0, 0, 0.25); box:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.6)
    end
    local h = box:CreateFontString(nil, "ARTWORK", "GameFontNormal"); h:SetPoint("TOPLEFT", PAD, -PAD); h:SetText(header)
    box.inner_last, box.inner_h = h, PAD + 14
    function box:Add(w, height, dy, dx)
      dy = dy or -6
      w:SetPoint("TOPLEFT", self.inner_last, "BOTTOMLEFT", dx or 0, dy)
      self.inner_last, self.inner_h = w, self.inner_h - dy + height
      return w
    end
    function box:Finish() self:SetHeight(self.inner_h + PAD) end
    Place(box, -14)
    return box
  end

  ------------------------------------------------------------------------
  -- Lock: outside any section, directly under the intro (quick to reach).
  ------------------------------------------------------------------------
  Place(Check(content, "Lock window position", "Stops the split window being dragged. Same as the lock icon in its title bar.",
    function() return Cfg().Locked == true end, function(v) ST.Live.SetLocked(v) end), -14)

  ------------------------------------------------------------------------
  -- Section: Display Options
  ------------------------------------------------------------------------
  local win = Section("Display Options")
  win:Add(Check(win, "Large timer (LiveSplit style)",
    "Show the big two-line timer. Off = a compact single row with both clocks.",
    function() return Cfg().BigTimer == true end, function(v) Cfg().BigTimer = v end), 26)
  win:Add(Check(win, "Always show the next money milestone",
    "Pin the next 'Money Acquired' step as the last upcoming row. Off = only within 20% of the step.",
    function() return Cfg().AlwaysShowMoney == true end, function(v) Cfg().AlwaysShowMoney = v end), 26)
  win:Add(Check(win, "Always show deaths (softcore)",
    "Show the death counter in the footer even when it is 0. Off = only once you have died. Hardcore runs always show 'Hardcore' instead.",
    function() return Cfg().ShowDeathsSoftcore ~= false end, function(v) Cfg().ShowDeathsSoftcore = v end), 26)
  -- RowsDoneLevels: how many past level splits stay pinned above the current level.
  win:Add(Slider(win, "VelocityConfigRowsDoneLevels", 1, 4,
    function() return math.max(1, math.min(4, Cfg().RowsDoneLevels or 1)) end,
    function(v) Cfg().RowsDoneLevels = v; Refresh() end,
    function(v) return "Past Level Splits to Show: " .. v end), 44, -10)
  -- Attention_RecentSeconds: how long a profession / money row stays up after its last gain
  -- (unless it is sticky for another reason: near the next step, trainable, or pinned).
  local D = ST.Data
  win:Add(Slider(win, "VelocityConfigRecentSeconds", 1, 60,
    function() return math.floor((Cfg().Attention_RecentSeconds or D.Attention_RecentSeconds) + 0.5) end,
    function(v) Cfg().Attention_RecentSeconds = v end,
    function(v) return "Auto-Hide Profession and Money Progress After: " .. v .. " seconds" end), 44, -10)
  win:Finish()

  ------------------------------------------------------------------------
  -- Section: Auto Hide Settings
  ------------------------------------------------------------------------
  local AH = ST.AutoHide
  local ah = Section("Auto Hide Settings")
  ah:Add(Slider(ah, "VelocityConfigAutoHideSeconds", 0, 60,
    function() return AH.Seconds() end,
    function(v) Cfg().AutoHide_Seconds = v; AH.Apply() end,
    function(v) return "Auto-Hide Panel After: " .. (v == 0 and "never" or (v .. " seconds")) end), 44)

  ah:Add(Label(ah, "Show on Splits Reached:"), 16, -10)
  ah:Add(FlagGrid(ah, "AutoHide_ShowOnReached", AH.Groups, AH.GroupLabel, 3), 2 * 24, -4, 8)

  local nearGrid
  local nearMaster = ah:Add(Check(ah, "Show when near Upcoming Splits",
    "Bring the window back when an upcoming split on a ticked axis becomes near: quest complete in log, profession within reach of its next step or trainable, money near the next step, level XP at/over the near threshold, zone by time vs the reference.",
    function() return Cfg().AutoHide_ShowNearUpcoming == true end,
    function(v) Cfg().AutoHide_ShowNearUpcoming = v; if nearGrid then nearGrid:SetEnabledAll(v) end end), 26, -10, -8)
  nearGrid = ah:Add(FlagGrid(ah, "AutoHide_ShowNearAxes", AH.Groups, AH.GroupLabel, 3), 2 * 24, -2, 24)
  -- the near grid is greyed out while its master is off; keep that in sync on show
  local baseUpdate = nearGrid.Update
  nearGrid.Update = function() baseUpdate(); nearGrid:SetEnabledAll(Cfg().AutoHide_ShowNearUpcoming == true) end
  ah:Finish()

  ------------------------------------------------------------------------
  -- Buttons
  ------------------------------------------------------------------------
  local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  btn:SetSize(160, 22); btn:SetText("Toggle split window")
  btn:SetScript("OnClick", function() ST.Live.Toggle() end)
  Place(btn, -16)
  local btn2 = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  btn2:SetSize(160, 22); btn2:SetPoint("LEFT", btn, "RIGHT", 8, 0); btn2:SetText("Open data window")
  btn2:SetScript("OnClick", function() ST.DataWindow.Toggle() end)

  -- content height = everything above + the buttons + a margin
  content:SetHeight(math.abs(select(5, btn:GetPoint(1)) or 0) + 60)
  C_Timer.After(0, function()
    local top, bottom = content:GetTop(), btn:GetBottom()
    if top and bottom then content:SetHeight(top - bottom + 40) end
  end)

  panel:SetScript("OnShow", function()
    ST.ConfigPanelOpen = true
    for _, w in ipairs(widgets) do w:Update() end
  end)
  panel:SetScript("OnHide", function() ST.ConfigPanelOpen = false end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    -- Do NOT override category.ID with the name: newer clients pass the ID straight to
    -- C_SettingsUtil.OpenSettingsPanel, which requires the numeric ID.
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
