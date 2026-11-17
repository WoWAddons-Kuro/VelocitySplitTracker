-- The LiveSplit-style main window. Currently rendered from ST.Mock so the look
-- can be designed first; the data accessors at the top are the seam the real
-- engine will plug into.
local ADDON_NAME, ST = ...
local T = ST.Theme
local U = ST.Util

ST.Live = {}
local L = ST.Live

------------------------------------------------------------------------
-- Data seam (mock for now)
------------------------------------------------------------------------
local function GetView()
  local M = ST.Mock
  return {
    CompareKey = M.CompareKey,
    Level = M.CharacterLevel,
    Done = M.Done,
    Upcoming = M.Upcoming,
    Final = M.Final,
    ActiveSeconds = M.ActiveSeconds,
    PlayedSeconds = M.PlayedSeconds,
    Running = M.ActiveRunning,
    PreviousSegmentDelta = M.PreviousSegmentDelta,
  }
end

local function Cfg() return ST.db.Config end

------------------------------------------------------------------------
-- Row widget
------------------------------------------------------------------------
local function CreateRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(T.RowHeight)
  row.bg = T.Texture(row, T.Colour.RowAlt)
  row.bg:SetAllPoints()
  row.progress = T.Texture(row, T.Colour.Progress, "BORDER")
  row.progress:SetPoint("TOPLEFT")
  row.progress:SetPoint("BOTTOMLEFT")
  row.progress:SetWidth(1)
  row.progress:Hide()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(T.RowHeight - 6, T.RowHeight - 6)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.label = T.Text(row, T.FontSize)
  row.label:SetJustifyH("LEFT")
  row.label:SetWordWrap(false)
  row.time = T.Text(row, T.FontSize)
  row.time:SetJustifyH("RIGHT")
  row.delta = T.Text(row, T.FontSize)
  row.delta:SetJustifyH("RIGHT")
  return row
end

-- Lay a row out for the configured side. Times block = [delta][time].
local function LayoutRow(row, timesLeft)
  local p = T.Padding
  row.icon:ClearAllPoints(); row.label:ClearAllPoints(); row.time:ClearAllPoints(); row.delta:ClearAllPoints()
  row.time:SetWidth(58)
  row.delta:SetWidth(48)
  if timesLeft then
    row.delta:SetPoint("LEFT", row, "LEFT", p, 0)
    row.time:SetPoint("LEFT", row.delta, "RIGHT", 4, 0)
    row.icon:SetPoint("LEFT", row.time, "RIGHT", 6, 0)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -p, 0)
  else
    row.icon:SetPoint("LEFT", row, "LEFT", p, 0)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.time:SetPoint("RIGHT", row, "RIGHT", -p, 0)
    row.delta:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
    row.label:SetPoint("RIGHT", row.delta, "LEFT", -4, 0)
  end
end

local function FillDoneRow(row, item)
  local delta = item.Best and (item.Time - item.Best) or nil
  row.icon:SetTexture(ST.Mock.AxisIcon[item.Axis])
  row.label:SetText(item.Label)
  T.SetColour(row.label, T.Colour.Text)
  row.time:SetText(U.FormatTime(item.Time))
  T.SetColour(row.time, T.Colour.Text)
  row.delta:SetText(U.FormatDelta(delta))
  T.SetColour(row.delta, T.DeltaColour(delta, item.Gold))
  row.progress:Hide()
end

local function FillUpcomingRow(row, item, width)
  row.icon:SetTexture(ST.Mock.AxisIcon[item.Axis])
  local label = item.Label
  if item.ProgressText then label = label .. "  |cff999999" .. item.ProgressText .. "|r" end
  row.label:SetText(label)
  T.SetColour(row.label, item.Current and T.Colour.Text or T.Colour.TextDim)
  row.time:SetText(U.FormatTime(item.Best))
  T.SetColour(row.time, T.Colour.TextDim)
  row.delta:SetText("")
  if item.Progress then
    row.progress:SetWidth(math.max(1, width * math.min(1, item.Progress)))
    row.progress:Show()
  else
    row.progress:Hide()
  end
end

------------------------------------------------------------------------
-- Window construction
------------------------------------------------------------------------
local frame

local function BuildTitle(f)
  local title = CreateFrame("Frame", nil, f)
  title:SetHeight(T.TitleHeight)
  title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT")
  title:EnableMouse(true)
  title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() if not Cfg().Locked then f:StartMoving() end end)
  title:SetScript("OnDragStop", function() f:StopMovingOrSizing(); L.SavePosition() end)
  title:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then L.ShowContextMenu(title) end end)

  title.icon = title:CreateTexture(nil, "ARTWORK")
  title.icon:SetSize(24, 24)
  title.icon:SetPoint("LEFT", T.Padding, 0)
  title.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
  title.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  title.level = T.Text(title, T.TitleSize + 1)
  title.level:SetPoint("RIGHT", -T.Padding, 0)
  title.level:SetJustifyH("RIGHT")

  title.zone = T.Text(title, T.TitleSize)
  title.zone:SetPoint("TOPLEFT", title.icon, "TOPRIGHT", 6, -1)

  -- Clickable class / pattern pieces on the second line
  local function Clickable(onClick)
    local b = CreateFrame("Button", nil, title)
    b:SetHeight(14)
    b.text = T.Text(b, T.TitleSize - 1)
    b.text:SetPoint("LEFT")
    T.SetColour(b.text, T.Colour.TextDim)
    b:SetScript("OnEnter", function() T.SetColour(b.text, T.Colour.Text) end)
    b:SetScript("OnLeave", function() T.SetColour(b.text, T.Colour.TextDim) end)
    b:SetScript("OnClick", function() onClick(b) end)
    b.SetLabel = function(self, s) self.text:SetText(s .. " |cff777777\226\150\190|r"); self:SetWidth(self.text:GetStringWidth() + 2) end
    return b
  end
  title.class = Clickable(function(b) L.ShowClassMenu(b) end)
  title.class:SetPoint("BOTTOMLEFT", title.icon, "BOTTOMRIGHT", 6, 1)
  title.dash = T.Text(title, T.TitleSize - 1)
  T.SetColour(title.dash, T.Colour.TextDim)
  title.dash:SetText("-")
  title.dash:SetPoint("LEFT", title.class, "RIGHT", 4, 0)
  title.pattern = Clickable(function(b) L.ShowPatternMenu(b) end)
  title.pattern:SetPoint("LEFT", title.dash, "RIGHT", 4, 0)

  title.sep = T.Separator(f)
  title.sep:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, 0)
  title.sep:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, 0)
  return title
end

local function BuildTimer(f)
  local area = CreateFrame("Frame", nil, f)
  area:SetHeight(T.TimerHeight)
  area.big = T.Text(area, T.TimerSize)
  area.big:SetPoint("RIGHT", -T.Padding, 2)
  area.big:SetJustifyH("RIGHT")
  area.tenths = T.Text(area, math.floor(T.TimerSize * 0.6))
  area.secondary = T.Text(area, T.FontSize - 2)
  area.secondary:SetPoint("BOTTOMRIGHT", -T.Padding, 1)
  area.secondary:SetJustifyH("RIGHT")
  T.SetColour(area.secondary, T.Colour.TextDim)
  area.sepTop = T.Separator(f)
  area.sepTop:SetPoint("TOPLEFT", area, "TOPLEFT"); area.sepTop:SetPoint("TOPRIGHT", area, "TOPRIGHT")
  return area
end

local function BuildFooter(f)
  local footer = CreateFrame("Frame", nil, f)
  footer:SetHeight(T.FooterHeight)
  footer.bg = T.Texture(footer, T.Colour.RowAlt); footer.bg:SetAllPoints()
  footer.label = T.Text(footer, T.FontSize)
  footer.label:SetPoint("LEFT", T.Padding, 0)
  footer.label:SetText("Previous Segment")
  footer.value = T.Text(footer, T.FontSize)
  footer.value:SetPoint("RIGHT", -T.Padding, 0)
  return footer
end

function L.Create()
  if frame then return frame end
  frame = CreateFrame("Frame", "SplitTimerLiveWindow", UIParent)
  frame:SetSize(T.Width, 200)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("MEDIUM")
  frame.bg = T.Texture(frame, T.Colour.Bg)
  frame.bg:SetAllPoints()

  frame.title = BuildTitle(frame)
  frame.rows = {}
  frame.timer = BuildTimer(frame)
  frame.footer = BuildFooter(frame)
  frame.sepUpcoming = T.Separator(frame)
  frame.sepFinal = T.Separator(frame)

  frame:SetScript("OnUpdate", function(_, elapsed) L.OnUpdate(elapsed) end)
  L.RestorePosition()
  L.Refresh()
  return frame
end

local function AcquireRow(i)
  local row = frame.rows[i]
  if not row then
    row = CreateRow(frame)
    frame.rows[i] = row
  end
  row:Show()
  return row
end

------------------------------------------------------------------------
-- Layout / refresh
------------------------------------------------------------------------
function L.Refresh()
  if not frame then return end
  local V = GetView()
  local cfg = Cfg()
  local timesLeft = cfg.TimesSide == "LEFT"
  frame:SetScale(cfg.Scale or 1)
  frame.bg:SetAlpha(cfg.BgAlpha or 0.85)

  -- title
  local tt = frame.title
  tt.zone:SetText(V.CompareKey.StartZone)
  tt.class:SetLabel(V.CompareKey.Class)
  tt.pattern:SetLabel(V.CompareKey.Pattern)
  tt.level:SetText(tostring(V.Level))

  -- rows
  for _, r in ipairs(frame.rows) do r:Hide() end
  local y = -T.TitleHeight - 1
  local n = 0
  local width = T.Width
  local function Place(row)
    n = n + 1
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row.bg:SetShown(n % 2 == 0)
    LayoutRow(row, timesLeft)
    y = y - T.RowHeight
  end

  local done = V.Done
  local maxDone = cfg.RowsDone or 4
  for i = math.max(1, #done - maxDone + 1), #done do
    local row = AcquireRow(n + 1)
    FillDoneRow(row, done[i])
    Place(row)
  end

  frame.sepUpcoming:ClearAllPoints()
  frame.sepUpcoming:SetPoint("TOPLEFT", 0, y); frame.sepUpcoming:SetPoint("TOPRIGHT", 0, y)
  y = y - 1

  local maxUp = cfg.RowsUpcoming or 4
  for i = 1, math.min(maxUp, #V.Upcoming) do
    local row = AcquireRow(n + 1)
    FillUpcomingRow(row, V.Upcoming[i], width)
    Place(row)
    if V.Upcoming[i].Current then row.bg:Show(); T.SetColour(row.bg, T.Colour.RowCurrent) else T.SetColour(row.bg, T.Colour.RowAlt) end
  end

  frame.sepFinal:ClearAllPoints()
  frame.sepFinal:SetPoint("TOPLEFT", 0, y); frame.sepFinal:SetPoint("TOPRIGHT", 0, y)
  y = y - 1
  if V.Final then
    local row = AcquireRow(n + 1)
    FillUpcomingRow(row, V.Final, width)
    Place(row)
  end

  -- timer + footer
  frame.timer:ClearAllPoints()
  frame.timer:SetPoint("TOPLEFT", 0, y); frame.timer:SetPoint("TOPRIGHT", 0, y)
  y = y - T.TimerHeight
  frame.footer:ClearAllPoints()
  frame.footer:SetPoint("TOPLEFT", 0, y); frame.footer:SetPoint("TOPRIGHT", 0, y)
  y = y - T.FooterHeight
  frame.footer.value:SetText(U.FormatDelta(V.PreviousSegmentDelta))
  T.SetColour(frame.footer.value, T.DeltaColour(V.PreviousSegmentDelta))

  frame:SetHeight(-y)
  L.UpdateTimer(V)
end

function L.UpdateTimer(V)
  V = V or GetView()
  local cfg = Cfg()
  local primary, secondaryLabel, secondary
  if cfg.Clock == "PLAYED" then
    primary, secondaryLabel, secondary = V.PlayedSeconds, "active", V.ActiveSeconds
  else
    primary, secondaryLabel, secondary = V.ActiveSeconds, "played", V.PlayedSeconds
  end
  frame.timer.big:SetText(U.FormatTime(primary, true))
  frame.timer.secondary:SetText(secondaryLabel .. " " .. U.FormatTime(secondary))
  local colour
  if not V.Running then colour = T.Colour.Stopped
  else
    local last = V.Done[#V.Done]
    colour = last and T.DeltaColour(last.Best and (last.Time - last.Best), last.Gold) or T.Colour.Text
  end
  T.SetColour(frame.timer.big, colour)
end

local acc = 0
function L.OnUpdate(elapsed)
  -- mock: advance the active clock
  if ST.Mock.ActiveRunning then
    ST.Mock.ActiveSeconds = ST.Mock.ActiveSeconds + elapsed
    ST.Mock.PlayedSeconds = ST.Mock.PlayedSeconds + elapsed
  end
  acc = acc + elapsed
  if acc >= 0.1 then acc = 0; L.UpdateTimer() end
end

------------------------------------------------------------------------
-- Menus
------------------------------------------------------------------------
function L.ShowClassMenu(anchor)
  local items = {}
  for _, c in ipairs(ST.Mock.ClassOptions) do
    items[#items + 1] = { text = c, checked = (ST.Mock.CompareKey.Class == c), func = function() ST.Mock.CompareKey.Class = c; L.Refresh() end }
  end
  T.ShowMenu(anchor, items)
end

function L.ShowPatternMenu(anchor)
  local items = {}
  for _, p in ipairs(ST.Mock.PatternOptions) do
    items[#items + 1] = { text = p, checked = (ST.Mock.CompareKey.Pattern == p), func = function() ST.Mock.CompareKey.Pattern = p; L.Refresh() end }
  end
  items[#items + 1] = { separator = true }
  items[#items + 1] = { text = "New pattern...", func = function() U.Print("TODO: name this run") end }
  T.ShowMenu(anchor, items)
end

function L.ShowContextMenu(anchor)
  local cfg = Cfg()
  T.ShowMenu(anchor, {
    { title = "SplitTimer" },
    { text = "Lock window", checked = cfg.Locked, func = function() cfg.Locked = not cfg.Locked end },
    { text = "Times on left", checked = cfg.TimesSide == "LEFT", func = function() cfg.TimesSide = cfg.TimesSide == "LEFT" and "RIGHT" or "LEFT"; L.Refresh() end },
    { text = "Show Played clock", checked = cfg.Clock == "PLAYED", func = function() cfg.Clock = cfg.Clock == "PLAYED" and "ACTIVE" or "PLAYED"; L.Refresh() end },
    { text = (ST.Mock.ActiveRunning and "Pause" or "Resume") .. " (mock)", func = function() ST.Mock.ActiveRunning = not ST.Mock.ActiveRunning; L.UpdateTimer() end },
    { separator = true },
    { text = "History", func = function() ST.History.Toggle() end },
    { text = "Settings", func = function() ST.Config.Open() end },
    { text = "Hide", func = function() L.Toggle() end },
  })
end

------------------------------------------------------------------------
-- Position / visibility
------------------------------------------------------------------------
function L.SavePosition()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  Cfg().Position = { point, relPoint, x, y }
end

function L.RestorePosition()
  local p = Cfg().Position
  frame:ClearAllPoints()
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 80) end
end

function L.Toggle(show)
  L.Create()
  if show == nil then show = not frame:IsShown() end
  frame:SetShown(show)
  Cfg().Shown = show
end
