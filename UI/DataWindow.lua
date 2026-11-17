-- The data window: [ By Level ] [ By Class ] [ By Start Zone ] [ History ].
-- The three pivot tabs are one GridPanel widget configured three ways over ST.Pivot;
-- the History tab hosts UI/History.lua's content.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local T = ST.Theme
local U = ST.Util
local P = ST.Pivot

ST.DataWindow = {}
local W = ST.DataWindow

local WIDTH, HEIGHT = 780, 480
local PICKER_WIDTH = 120
local ROW_LABEL_WIDTH = 96
local CELL_WIDTH = 72
local MAX_COLS = 8

local frame
local tabs = {}            -- id -> { button=, panel=, refresh=fn }
local TAB_ORDER = { "level", "class", "zone", "history" }
local TAB_TITLES = { level = "By Level", class = "By Class", zone = "By Start Zone", history = "History" }

------------------------------------------------------------------------
-- GridPanel: picker on the left, header row + scrollable cell rows on the right
------------------------------------------------------------------------
local function NewGridPanel(parent, spec)
  -- spec = { PickerItems=fn(facts)->list, PickerLabel=fn(v)->string, DefaultPick=fn()->v, Grid=fn(facts, pick)->grid }
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetAllPoints()
  panel.spec = spec

  -- picker
  local picker = CreateFrame("Frame", nil, panel)
  picker:SetPoint("TOPLEFT", 8, -8); picker:SetPoint("BOTTOMLEFT", 8, 8); picker:SetWidth(PICKER_WIDTH)
  picker.bg = T.Texture(picker, T.Colour.RowAlt); picker.bg:SetAllPoints()
  picker.scroll = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
  picker.scroll:SetPoint("TOPLEFT", 2, -2); picker.scroll:SetPoint("BOTTOMRIGHT", -22, 2)
  picker.content = CreateFrame("Frame", nil, picker.scroll)
  picker.content:SetSize(PICKER_WIDTH - 26, 10)
  picker.scroll:SetScrollChild(picker.content)
  picker.buttons = {}
  panel.picker = picker

  -- grid area
  local grid = CreateFrame("Frame", nil, panel)
  grid:SetPoint("TOPLEFT", picker, "TOPRIGHT", 10, 0); grid:SetPoint("BOTTOMRIGHT", -8, 8)
  grid.info = T.Text(grid, T.FontSize - 1)
  grid.info:SetPoint("TOPLEFT", 0, 0); T.SetColour(grid.info, T.Colour.TextDim)
  grid.header = CreateFrame("Frame", nil, grid)
  grid.header:SetPoint("TOPLEFT", 0, -18); grid.header:SetPoint("TOPRIGHT", 0, -18); grid.header:SetHeight(T.RowHeight)
  grid.headerCells = {}
  local sep = T.Separator(grid); sep:SetPoint("TOPLEFT", grid.header, "BOTTOMLEFT"); sep:SetPoint("TOPRIGHT", grid.header, "BOTTOMRIGHT")
  grid.scroll = CreateFrame("ScrollFrame", nil, grid, "UIPanelScrollFrameTemplate")
  grid.scroll:SetPoint("TOPLEFT", grid.header, "BOTTOMLEFT", 0, -2); grid.scroll:SetPoint("BOTTOMRIGHT", -22, 0)
  grid.content = CreateFrame("Frame", nil, grid.scroll)
  grid.content:SetSize(WIDTH - PICKER_WIDTH - 60, 10)
  grid.scroll:SetScrollChild(grid.content)
  grid.rows = {}
  panel.grid = grid

  function panel:HeaderCell(i)
    local fs = grid.headerCells[i]
    if not fs then
      fs = T.Text(grid.header, T.FontSize - 1); fs:SetJustifyH(i == 1 and "LEFT" or "RIGHT"); fs:SetWordWrap(false)
      fs:SetWidth(i == 1 and ROW_LABEL_WIDTH or CELL_WIDTH)
      fs:SetPoint("LEFT", i == 1 and 0 or (ROW_LABEL_WIDTH + 4 + (i - 2) * (CELL_WIDTH + 4)), 0)
      T.SetColour(fs, T.Colour.TextDim)
      grid.headerCells[i] = fs
    end
    return fs
  end

  function panel:Row(i)
    local row = grid.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, grid.content)
    row:SetHeight(T.RowHeight)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * T.RowHeight); row:SetPoint("TOPRIGHT", 0, -(i - 1) * T.RowHeight)
    row.bg = T.Texture(row, T.Colour.RowAlt); row.bg:SetAllPoints(); row.bg:SetShown(i % 2 == 0)
    row.label = T.Text(row, T.FontSize); row.label:SetPoint("LEFT", 0, 0); row.label:SetWidth(ROW_LABEL_WIDTH); row.label:SetJustifyH("LEFT"); row.label:SetWordWrap(false)
    row.cells = {}
    grid.rows[i] = row
    return row
  end

  function panel:Cell(row, j)
    local b = row.cells[j]
    if b then return b end
    b = CreateFrame("Button", nil, row)
    b:SetSize(CELL_WIDTH, T.RowHeight)
    b:SetPoint("LEFT", ROW_LABEL_WIDTH + 4 + (j - 1) * (CELL_WIDTH + 4), 0)
    b.text = T.Text(b, T.FontSize); b.text:SetAllPoints(); b.text:SetJustifyH("RIGHT")
    b.hl = T.Texture(b, T.Colour.RowCurrent, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetAlpha(0.5)
    b:SetScript("OnEnter", function()
      if not b.cell then return end
      GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
      GameTooltip:SetText(b.cell.CharName .. (ST.db.Characters[b.cell.CharKey] and (" " .. U.FormatFirstSeen(ST.db.Characters[b.cell.CharKey].CharacterRun_CreatedAt)) or ""), 1, 1, 1)
      GameTooltip:AddLine("pattern: " .. (b.cell.Pattern or "default"), 0.7, 0.7, 0.7)
      if b.cell.Count > 1 then GameTooltip:AddLine(string.format("best of %d characters", b.cell.Count), 0.7, 0.7, 0.7) end
      GameTooltip:AddLine("click: open in History", 0.5, 0.8, 0.5)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() if b.cell then W.ShowTab("history"); ST.History.Select(b.cell.CharKey) end end)
    row.cells[j] = b
    return b
  end

  function panel:Refresh()
    local facts = P.Facts()
    local items = spec.PickerItems(facts)
    -- keep the current pick if still valid, else default
    local valid = false
    for _, v in ipairs(items) do if v == self.pick then valid = true break end end
    if not valid then self.pick = spec.DefaultPick(items) end
    -- picker buttons
    for _, b in ipairs(picker.buttons) do b:Hide() end
    for i, v in ipairs(items) do
      local b = picker.buttons[i]
      if not b then
        b = CreateFrame("Button", nil, picker.content)
        b:SetHeight(T.RowHeight)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * T.RowHeight); b:SetPoint("TOPRIGHT", 0, -(i - 1) * T.RowHeight)
        b.sel = T.Texture(b, T.Colour.RowCurrent, "BORDER"); b.sel:SetAllPoints()
        b.hl = T.Texture(b, T.Colour.RowCurrent, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetAlpha(0.5)
        b.text = T.Text(b, T.FontSize); b.text:SetPoint("LEFT", 6, 0); b.text:SetPoint("RIGHT", -2, 0); b.text:SetJustifyH("LEFT")
        picker.buttons[i] = b
      end
      b.text:SetText(spec.PickerLabel(v))
      b.sel:SetShown(v == self.pick)
      b:SetScript("OnClick", function() self.pick = v; self:Refresh() end)
      b:Show()
    end
    picker.content:SetHeight(math.max(10, #items * T.RowHeight))
    T.AutoHideScrollBar(picker.scroll)

    -- grid
    for _, r in ipairs(grid.rows) do r:Hide() end
    for _, h in ipairs(grid.headerCells) do h:Hide() end
    if self.pick == nil then grid.info:SetText("No data yet - splits appear here as characters level."); return end
    local g = spec.Grid(facts, self.pick)
    local me = ST.Record.Current()
    local cols = g.Cols
    local more = 0
    if #cols > MAX_COLS then more = #cols - MAX_COLS; local t = {}; for i = 1, MAX_COLS do t[i] = cols[i] end; cols = t end
    grid.info:SetText(string.format("%s   |cff999999%d character%s%s|r", spec.Title(self.pick), g.Characters, g.Characters == 1 and "" or "s", more > 0 and ("  (+" .. more .. " more columns hidden)") or ""))
    local h1 = self:HeaderCell(1); h1:SetText(spec.RowHeader); h1:Show()
    for j, c in ipairs(cols) do
      local h = self:HeaderCell(j + 1); h:SetText(g.ColLabel(c)); h:Show()
      local mine = (c == me.CharacterRun_StartZone) or (c == me.CharacterRun_ClassFile)
      T.SetColour(h, mine and T.Colour.Ahead or T.Colour.TextDim)
    end
    for i, r in ipairs(g.Rows) do
      local row = self:Row(i)
      row.label:SetText(g.RowLabel(r))
      local mineRow = (r == me.CharacterRun_ClassFile) or (r == UnitLevel("player"))
      T.SetColour(row.label, mineRow and T.Colour.Ahead or T.Colour.Text)
      -- best in row
      local best
      for _, c in ipairs(cols) do local cell = g.Cell[r] and g.Cell[r][c]; if cell and (not best or cell.Time < best) then best = cell.Time end end
      for j, c in ipairs(cols) do
        local b = self:Cell(row, j)
        local cell = g.Cell[r] and g.Cell[r][c]
        b.cell = cell
        if cell then
          b.text:SetText(U.FormatTime(cell.Time))
          T.SetColour(b.text, (cell.Time == best and #cols > 1) and T.Colour.Gold or (cell.CharKey == me.CharacterRun_Key and T.Colour.Ahead or T.Colour.Text))
        else
          b.text:SetText("|cff555555-|r")
        end
        b:Show()
      end
      for j = #cols + 1, #row.cells do row.cells[j]:Hide() end
      row:Show()
    end
    grid.content:SetHeight(math.max(10, #g.Rows * T.RowHeight))
    T.AutoHideScrollBar(grid.scroll)
  end

  return panel
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
function W.Create()
  if frame then return frame end
  frame = CreateFrame("Frame", "VelocityDataWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER")
  -- Frames are visible by default; a freshly created window must start hidden or the first
  -- Toggle() sees IsShown()==true and hides it (the "click twice" bug).
  frame:Hide()
  frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
  frame:SetFrameStrata("DIALOG")
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
  end
  tinsert(UISpecialFrames, "VelocityDataWindow")
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)

  frame.title = T.Text(frame, 16); frame.title:SetPoint("TOPLEFT", 12, -10); frame.title:SetText("Velocity")

  -- tab strip
  local strip = CreateFrame("Frame", nil, frame)
  strip:SetPoint("TOPLEFT", 12, -34); strip:SetPoint("TOPRIGHT", -12, -34); strip:SetHeight(22)
  local sep = T.Separator(frame); sep:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -1); sep:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, -1)
  local x = 0
  for _, id in ipairs(TAB_ORDER) do
    local b = CreateFrame("Button", nil, strip)
    b:SetHeight(22)
    b.text = T.Text(b, T.FontSize); b.text:SetPoint("CENTER"); b.text:SetText(TAB_TITLES[id])
    b:SetWidth(b.text:GetStringWidth() + 24)
    b:SetPoint("LEFT", x, 0)
    b.sel = T.Texture(b, T.Colour.RowCurrent, "BORDER"); b.sel:SetAllPoints()
    b.hl = T.Texture(b, T.Colour.RowCurrent, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetAlpha(0.4)
    b:SetScript("OnClick", function() W.ShowTab(id) end)
    x = x + b:GetWidth() + 2
    local panelHost = CreateFrame("Frame", nil, frame)
    panelHost:SetPoint("TOPLEFT", 0, -60); panelHost:SetPoint("BOTTOMRIGHT", 0, 0)
    panelHost:Hide()
    tabs[id] = { button = b, host = panelHost }
  end

  -- pivot tabs
  local function Pick(items, want) for _, v in ipairs(items) do if v == want then return v end end return items[1] end
  tabs.level.panel = NewGridPanel(tabs.level.host, {
    Title = function(v) return "Best time to Level " .. v end, RowHeader = "Class",
    PickerItems = P.LevelsPresent, PickerLabel = function(v) return "Level " .. v end,
    DefaultPick = function(items) return Pick(items, UnitLevel("player")) end,
    Grid = P.ByLevel,
  })
  tabs.class.panel = NewGridPanel(tabs.class.host, {
    Title = function(v) return ST.Compare.ClassLabel(v) .. " - best time per level" end, RowHeader = "Level",
    PickerItems = P.ClassesPresent, PickerLabel = ST.Compare.ClassLabel,
    DefaultPick = function(items) return Pick(items, ST.Record.Current().CharacterRun_ClassFile) end,
    Grid = P.ByClass,
  })
  tabs.zone.panel = NewGridPanel(tabs.zone.host, {
    Title = function(v) return v .. " - best time per level" end, RowHeader = "Level",
    PickerItems = P.ZonesPresent, PickerLabel = function(v) return v end,
    DefaultPick = function(items) return Pick(items, ST.Record.Current().CharacterRun_StartZone) end,
    Grid = P.ByZone,
  })
  -- history tab hosts the existing History content
  ST.History.CreateIn(tabs.history.host)
  tabs.history.refresh = ST.History.Refresh

  frame:SetScript("OnShow", function() W.ShowTab(ST.db.Config.DataWindow_Tab or "level") end)
  return frame
end

function W.ShowTab(id)
  W.Create()
  if not tabs[id] then id = "level" end
  ST.db.Config.DataWindow_Tab = id
  for tid, t in pairs(tabs) do
    local on = tid == id
    t.host:SetShown(on)
    t.button.sel:SetShown(on)
    T.SetColour(t.button.text, on and T.Colour.Text or T.Colour.TextDim)
  end
  local t = tabs[id]
  if t.panel then t.panel:Refresh() elseif t.refresh then t.refresh() end
end

function W.IsShown() return frame ~= nil and frame:IsShown() end

function W.Toggle(tab)
  W.Create()
  if frame:IsShown() and (tab == nil or tab == ST.db.Config.DataWindow_Tab) then frame:Hide(); return end
  if tab then ST.db.Config.DataWindow_Tab = tab end
  frame:Show()
  W.ShowTab(ST.db.Config.DataWindow_Tab or "level")
end
