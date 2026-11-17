-- History window: every recorded character/run, with a milestone detail panel and the
-- actions that curate runs (name a route pattern, clear it, delete, copy as text).
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local T = ST.Theme
local U = ST.Util
local D = ST.Data

ST.History = {}
local H = ST.History

local frame
local selectedKey

-- Column layout for the run list: { title, width, justify }
local COLUMNS = {
  { "",          14, "LEFT"  },   -- PB star
  { "Character", 200, "LEFT"  },
  { "Start zone",100, "LEFT"  },
  { "Class",     64, "LEFT"  },
  { "Lvl",       28, "RIGHT" },
  { "Active",    62, "RIGHT" },
  { "Played",    62, "RIGHT" },
  { "Pattern",  120, "LEFT"  },
}
local LIST_WIDTH = 0
for _, c in ipairs(COLUMNS) do LIST_WIDTH = LIST_WIDTH + c[2] + 4 end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
local function ClockField() return ST.db.Config.Clock == "PLAYED" and "Played" or "Active" end

-- Personal best per (start zone, class, pattern): the run that reached the highest level;
-- ties broken by the lower clock at that level.
local function ComputePBs()
  local field = ClockField()
  local best = {}   -- groupKey -> { key=, level=, t= }
  for key, rec in pairs(ST.db.Characters) do
    local group = (rec.CharacterRun_StartZone or "?") .. "|" .. (rec.CharacterRun_ClassFile or "?") .. "|" .. (rec.CharacterRun_Pattern or "default")
    local lvl, t = 1, nil
    for n = D.MaxLevel, 2, -1 do
      local m = rec.Milestones[D.Key("level", n)]
      if m and not m.Inferred then lvl, t = n, m[field] break end
    end
    local cur = best[group]
    if not cur or lvl > cur.level or (lvl == cur.level and t and cur.t and t < cur.t) then
      best[group] = { key = key, level = lvl, t = t }
    end
  end
  local isPB = {}
  for _, b in pairs(best) do isPB[b.key] = true end
  return isPB
end

local function SortedRuns()
  local list = {}
  for _, rec in pairs(ST.db.Characters) do list[#list + 1] = rec end
  table.sort(list, function(a, b)
    if a.CharacterRun_StartZone ~= b.CharacterRun_StartZone then return (a.CharacterRun_StartZone or "") < (b.CharacterRun_StartZone or "") end
    if (a.CharacterRun_Level or 0) ~= (b.CharacterRun_Level or 0) then return (a.CharacterRun_Level or 0) > (b.CharacterRun_Level or 0) end
    return (a.CharacterRun_Name or "") < (b.CharacterRun_Name or "")
  end)
  return list
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------
local function MakeButton(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- Build the History content into a host frame (a tab of the data window).
function H.CreateIn(host)
  if frame then return frame end
  frame = CreateFrame("Frame", nil, host)
  frame:SetAllPoints()
  frame:SetScript("OnShow", function() H.Refresh() end)

  frame.hint = T.Text(frame, T.FontSize - 1)
  frame.hint:SetPoint("TOPLEFT", 12, -6)
  T.SetColour(frame.hint, T.Colour.TextDim)
  frame.hint:SetText("Every character is recorded automatically. Select a run to see its milestones. * = personal best for its start zone / class / pattern.")

  ----------------------------------------------------------------------
  -- Run list (left): header row + fixed-width columns, scrollable
  ----------------------------------------------------------------------
  local list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", 12, -26)
  list:SetPoint("BOTTOMLEFT", 12, 12)
  list:SetWidth(LIST_WIDTH)
  frame.list = list

  list.header = CreateFrame("Frame", nil, list)
  list.header:SetPoint("TOPLEFT"); list.header:SetPoint("TOPRIGHT"); list.header:SetHeight(T.RowHeight)
  local x = 0
  for i, c in ipairs(COLUMNS) do
    local fs = T.Text(list.header, T.FontSize - 1)
    fs:SetPoint("LEFT", x, 0); fs:SetWidth(c[2]); fs:SetJustifyH(c[3])
    T.SetColour(fs, T.Colour.TextDim)
    fs:SetText(c[1])
    x = x + c[2] + 4
  end
  local sep = T.Separator(list); sep:SetPoint("TOPLEFT", list.header, "BOTTOMLEFT"); sep:SetPoint("TOPRIGHT", list.header, "BOTTOMRIGHT")

  list.scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
  list.scroll:SetPoint("TOPLEFT", list.header, "BOTTOMLEFT", 0, -2)
  list.scroll:SetPoint("BOTTOMRIGHT", -22, 0)
  list.content = CreateFrame("Frame", nil, list.scroll)
  list.content:SetSize(LIST_WIDTH - 22, 10)
  list.scroll:SetScrollChild(list.content)
  list.rows = {}

  ----------------------------------------------------------------------
  -- Detail (right)
  ----------------------------------------------------------------------
  local detail = CreateFrame("Frame", nil, frame)
  detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)
  detail:SetPoint("BOTTOMRIGHT", -12, 12)
  detail.bg = T.Texture(detail, T.Colour.RowAlt); detail.bg:SetAllPoints()
  frame.detail = detail

  detail.heading = T.Text(detail, T.FontSize + 1)
  detail.heading:SetPoint("TOPLEFT", 8, -8); detail.heading:SetPoint("TOPRIGHT", -8, -8)
  detail.heading:SetJustifyH("LEFT")
  detail.sub = T.Text(detail, T.FontSize - 1)
  detail.sub:SetPoint("TOPLEFT", detail.heading, "BOTTOMLEFT", 0, -3); detail.sub:SetPoint("RIGHT", -8, 0)
  detail.sub:SetJustifyH("LEFT")
  T.SetColour(detail.sub, T.Colour.TextDim)

  -- action buttons along the bottom
  detail.btnName = MakeButton(detail, "Name pattern...", 110, function() if selectedKey then H.NamePattern(selectedKey) end end)
  detail.btnName:SetPoint("BOTTOMLEFT", 8, 8)
  detail.btnClear = MakeButton(detail, "Clear pattern", 100, function() if selectedKey then H.SetPattern(selectedKey, nil) end end)
  detail.btnClear:SetPoint("LEFT", detail.btnName, "RIGHT", 4, 0)
  detail.btnCopy = MakeButton(detail, "Copy as text", 100, function() if selectedKey then H.CopyAsText(selectedKey) end end)
  detail.btnCopy:SetPoint("LEFT", detail.btnClear, "RIGHT", 4, 0)
  detail.btnDelete = MakeButton(detail, "Delete run", 90, function() if selectedKey then StaticPopup_Show("SPLITTIMER_DELETE_RUN", selectedKey, nil, selectedKey) end end)
  detail.btnDelete:SetPoint("BOTTOMRIGHT", -8, 8)

  -- milestone table: scrollable, fixed columns
  detail.tableHeader = CreateFrame("Frame", nil, detail)
  detail.tableHeader:SetPoint("TOPLEFT", detail.sub, "BOTTOMLEFT", 0, -8); detail.tableHeader:SetPoint("RIGHT", -8, 0)
  detail.tableHeader:SetHeight(T.RowHeight)
  detail.cols = { { "Milestone", 150, "LEFT" }, { "Active", 64, "RIGHT" }, { "Played", 64, "RIGHT" }, { "Segment", 56, "RIGHT" } }
  local hx = 0
  for _, c in ipairs(detail.cols) do
    local fs = T.Text(detail.tableHeader, T.FontSize - 1)
    fs:SetPoint("LEFT", hx, 0); fs:SetWidth(c[2]); fs:SetJustifyH(c[3]); T.SetColour(fs, T.Colour.TextDim); fs:SetText(c[1])
    hx = hx + c[2] + 4
  end
  local sep2 = T.Separator(detail); sep2:SetPoint("TOPLEFT", detail.tableHeader, "BOTTOMLEFT"); sep2:SetPoint("TOPRIGHT", detail.tableHeader, "BOTTOMRIGHT")
  detail.scroll = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
  detail.scroll:SetPoint("TOPLEFT", detail.tableHeader, "BOTTOMLEFT", 0, -2)
  detail.scroll:SetPoint("BOTTOMRIGHT", -30, 38)
  detail.content = CreateFrame("Frame", nil, detail.scroll)
  detail.content:SetSize(340, 10)
  detail.scroll:SetScrollChild(detail.content)
  detail.rows = {}

  -- copy-as-text box (hidden until used)
  detail.copyBox = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
  detail.copyBox:SetPoint("BOTTOMLEFT", detail.btnName, "TOPLEFT", 4, 6); detail.copyBox:SetPoint("RIGHT", -8, 0)
  detail.copyBox:SetHeight(20); detail.copyBox:SetAutoFocus(false); detail.copyBox:Hide()
  detail.copyBox:SetScript("OnEscapePressed", function(self) self:Hide() end)

  StaticPopupDialogs["SPLITTIMER_DELETE_RUN"] = {
    text = "Delete the recorded run for %s? This cannot be undone.",
    button1 = DELETE, button2 = CANCEL,
    OnAccept = function(_, key) H.DeleteRun(key) end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
  }
  StaticPopupDialogs["SPLITTIMER_NAME_RUN"] = {
    text = "Route pattern name for %s (blank = default):",
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true, maxLetters = 40,
    OnShow = function(self, key) local rec = ST.db.Characters[key]; self.editBox:SetText(rec and rec.CharacterRun_Pattern or "") end,
    OnAccept = function(self, key) H.SetPattern(key, self.editBox:GetText()) end,
    EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
  }
  return frame
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------
local function RowCell(row, i, c)
  local fs = T.Text(row, T.FontSize)
  fs:SetWidth(c[2]); fs:SetJustifyH(c[3]); fs:SetWordWrap(false)
  return fs
end

local function AcquireListRow(i)
  local list = frame.list
  local row = list.rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, list.content)
  row:SetHeight(T.RowHeight)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * T.RowHeight); row:SetPoint("TOPRIGHT", 0, -(i - 1) * T.RowHeight)
  row.bg = T.Texture(row, T.Colour.RowAlt); row.bg:SetAllPoints(); row.bg:SetShown(i % 2 == 0)
  row.sel = T.Texture(row, T.Colour.RowCurrent, "BORDER"); row.sel:SetAllPoints(); row.sel:Hide()
  row.hl = T.Texture(row, T.Colour.RowCurrent, "HIGHLIGHT"); row.hl:SetAllPoints(); row.hl:SetAlpha(0.5)
  row.cells = {}
  local x = 0
  for ci, c in ipairs(COLUMNS) do
    local fs = RowCell(row, ci, c)
    fs:SetPoint("LEFT", x, 0)
    row.cells[ci] = fs
    x = x + c[2] + 4
  end
  list.rows[i] = row
  return row
end

function H.Refresh()
  if not frame or not frame:IsVisible() then return end
  local runs = SortedRuns()
  local isPB = ComputePBs()
  local me = ST.Record.Current().CharacterRun_Key
  for _, r in ipairs(frame.list.rows) do r:Hide() end
  for i, rec in ipairs(runs) do
    local row = AcquireListRow(i)
    local c = row.cells
    c[1]:SetText(isPB[rec.CharacterRun_Key] and "|cfff2cc40*|r" or "")
    c[2]:SetText((rec.CharacterRun_Key == me and "|cff5ad65a" or "") .. (rec.CharacterRun_Name or "?") .. " |cff777777" .. U.FormatFirstSeen(rec.CharacterRun_CreatedAt) .. "|r" .. (rec.CharacterRun_Frozen and " |cff8888aa(60)|r" or ""))
    c[3]:SetText(rec.CharacterRun_StartZone or "?")
    c[4]:SetText(ST.Compare.ClassLabel(rec.CharacterRun_ClassFile))
    c[5]:SetText(tostring(rec.CharacterRun_Level or "?"))
    c[6]:SetText(U.FormatTime(rec.ActiveSeconds_Total))
    c[7]:SetText(U.FormatTime(rec.PlayedSeconds_Total))
    c[8]:SetText(rec.CharacterRun_Pattern or "|cff777777default|r")
    row.sel:SetShown(rec.CharacterRun_Key == selectedKey)
    row:SetScript("OnClick", function() selectedKey = rec.CharacterRun_Key; H.Refresh() end)
    row:Show()
  end
  frame.list.content:SetHeight(math.max(10, #runs * T.RowHeight))
  if not selectedKey or not ST.db.Characters[selectedKey] then selectedKey = me end
  H.ShowDetail(selectedKey)
end

local function AcquireDetailRow(i)
  local d = frame.detail
  local row = d.rows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, d.content)
  row:SetHeight(T.RowHeight)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * T.RowHeight); row:SetPoint("TOPRIGHT", 0, -(i - 1) * T.RowHeight)
  row.bg = T.Texture(row, T.Colour.RowAlt); row.bg:SetAllPoints(); row.bg:SetShown(i % 2 == 0)
  row.cells = {}
  local x = 0
  for ci, c in ipairs(d.cols) do
    local fs = RowCell(row, ci, c)
    fs:SetPoint("LEFT", x, 0)
    row.cells[ci] = fs
    x = x + c[2] + 4
  end
  d.rows[i] = row
  return row
end

-- Milestones of a run, ordered by the selected clock. Inferred ones are listed dim at the top.
local function MilestoneRows(rec)
  local field = ClockField()
  local list = {}
  for key, m in pairs(rec.Milestones) do
    local axis = D.ParseKey(key)
    if axis ~= "questaccept" and axis ~= "zone" then
      list[#list + 1] = { Key = key, Axis = axis, Label = m.Label or key, Active = m.Active, Played = m.Played, Inferred = m.Inferred, Sort = m.Inferred and -1 or (m[field] or 0) }
    end
  end
  table.sort(list, function(a, b)
    if a.Sort ~= b.Sort then return a.Sort < b.Sort end
    return a.Key < b.Key
  end)
  -- level segments
  local prevLevelTime = 0
  for _, it in ipairs(list) do
    if it.Axis == "level" and not it.Inferred then
      it.Segment = (it[field] or 0) - prevLevelTime
      prevLevelTime = it[field] or prevLevelTime
    end
  end
  return list
end

function H.ShowDetail(key)
  local d = frame.detail
  for _, r in ipairs(d.rows) do r:Hide() end
  d.copyBox:Hide()
  local rec = key and ST.db.Characters[key]
  if not rec then
    d.heading:SetText("|cff999999No run selected.|r"); d.sub:SetText("")
    return
  end
  d.heading:SetText(string.format("%s  -  %s / %s / %s", U.RunDisplayName(rec), rec.CharacterRun_StartZone or "?", ST.Compare.ClassLabel(rec.CharacterRun_ClassFile), rec.CharacterRun_Pattern or "default"))
  d.sub:SetText(string.format("Level %s   Active %s   Played %s%s", tostring(rec.CharacterRun_Level or "?"), U.FormatTime(rec.ActiveSeconds_Total), U.FormatTime(rec.PlayedSeconds_Total), rec.CharacterRun_Frozen and "   |cff8888aafrozen at 60|r" or ""))
  local rows = MilestoneRows(rec)
  for i, it in ipairs(rows) do
    local row = AcquireDetailRow(i)
    local c = row.cells
    local dim = it.Inferred
    c[1]:SetText(it.Label); T.SetColour(c[1], dim and T.Colour.TextDim or T.Colour.Text)
    c[2]:SetText(dim and "-" or U.FormatTime(it.Active)); T.SetColour(c[2], dim and T.Colour.TextDim or T.Colour.Text)
    c[3]:SetText(dim and "-" or U.FormatTime(it.Played)); T.SetColour(c[3], dim and T.Colour.TextDim or T.Colour.Text)
    c[4]:SetText(it.Segment and U.FormatTime(it.Segment) or ""); T.SetColour(c[4], T.Colour.TextDim)
    row:Show()
  end
  d.content:SetHeight(math.max(10, #rows * T.RowHeight))
  d.btnClear:SetEnabled(rec.CharacterRun_Pattern ~= nil)
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------
function H.NamePattern(key)
  local popup = StaticPopup_Show("SPLITTIMER_NAME_RUN", ST.db.Characters[key].CharacterRun_Name or key, nil, key)
  if popup then popup.data = key end
end

function H.SetPattern(key, name)
  local rec = ST.db.Characters[key]; if not rec then return end
  name = name and name:match("^%s*(.-)%s*$") or ""
  rec.CharacterRun_Pattern = (name ~= "" and name ~= "default") and name or nil
  ST.Compare.Invalidate()
  H.Refresh()
  if ST.Live then ST.Live.Refresh() end
end

function H.DeleteRun(key)
  if key == ST.Record.Current().CharacterRun_Key then
    U.Print("the current character's run cannot be deleted while logged in to it")
    return
  end
  ST.db.Characters[key] = nil
  if selectedKey == key then selectedKey = nil end
  ST.Compare.Invalidate()
  H.Refresh()
  if ST.Live then ST.Live.Refresh() end
end

function H.CopyAsText(key)
  local rec = ST.db.Characters[key]; if not rec then return end
  local parts = { string.format("%s %s %s mode=%s %s L%s active=%s played=%s |", rec.CharacterRun_Name, rec.CharacterRun_StartZone, rec.CharacterRun_ClassFile, rec.CharacterRun_Mode or "unknown", rec.CharacterRun_Pattern or "default", tostring(rec.CharacterRun_Level), U.FormatTime(rec.ActiveSeconds_Total), U.FormatTime(rec.PlayedSeconds_Total)) }
  for _, it in ipairs(MilestoneRows(rec)) do
    if not it.Inferred then parts[#parts + 1] = string.format("%s=%s", it.Label, U.FormatTime(it.Active)) end
  end
  local box = frame.detail.copyBox
  box:SetText(table.concat(parts, "; "))
  box:Show(); box:SetFocus(); box:HighlightText()
end

------------------------------------------------------------------------
-- Visibility (the Active clock is force-stopped while this window is open)
------------------------------------------------------------------------
-- History lives inside the data window; Clock.ForcedStop consults H.IsShown.
function H.IsShown() return ST.DataWindow and ST.DataWindow.IsShown() end

function H.Toggle()
  ST.DataWindow.Toggle("history")
end

-- Select a run (e.g. from a pivot cell) and show it.
function H.Select(key)
  selectedKey = key
  H.Refresh()
end
