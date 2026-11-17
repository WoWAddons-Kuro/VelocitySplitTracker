-- The LiveSplit-style main window. Currently rendered from ST.Mock so the look
-- can be designed first; the data accessors at the top are the seam the real
-- engine will plug into.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local T = ST.Theme
local U = ST.Util
-- (load phase set on the ADDON_NAME line)

ST.Live = {}
local L = ST.Live

------------------------------------------------------------------------
-- Data seam (mock for now)
------------------------------------------------------------------------
local function GetView()
  return ST.View.Build()
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
  -- cap overlay (profession rows): muted red band + bright tick where the trainer cap sits
  row.capBand = T.Texture(row, T.Colour.CapLocked, "BORDER")
  row.capBand:Hide()
  row.capTick = T.Texture(row, T.Colour.CapTick, "ARTWORK")
  row.capTick:SetWidth(2)
  row.capTick:Hide()
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
-- The icon column is always reserved so labels line up whether or not a row has an icon.
-- Rows without a delta (upcoming rows) let the label run over the empty delta column.
local function LayoutRow(row, timesLeft)
  local p = T.Padding
  local hasDelta = (row.delta:GetText() or "") ~= ""
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
    row.label:SetPoint("RIGHT", hasDelta and row.delta or row.time, "LEFT", -4, 0)
  end
end

-- Per-row icon: explicit item.Icon (e.g. the profession's own icon) beats the axis default.
local function SetRowIcon(row, axis, icon)
  local tex = icon or ST.Data.AxisIcon[axis]
  if tex then
    row.icon:SetTexture(tex)
    row.icon:Show()
  else
    row.icon:Hide()
  end
end

local function FillDoneRow(row, item)
  local delta = (item.Best and item.Time) and (item.Time - item.Best) or nil
  SetRowIcon(row, item.Axis, item.Icon)
  row.label:SetText(item.Label)
  T.SetColour(row.label, item.Inferred and T.Colour.TextDim or T.Colour.Text)
  row.time:SetText(U.FormatTime(item.Time))
  T.SetColour(row.time, item.Inferred and T.Colour.TextDim or T.Colour.Text)
  row.delta:SetText(U.FormatDelta(delta))
  T.SetColour(row.delta, T.DeltaColour(delta, item.Gold))
  row.progress:Hide()
end

local function FillUpcomingRow(row, item, width)
  SetRowIcon(row, item.Axis, item.Icon)
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
  -- Locked band: the stretch between the trainer cap and the goal, with a tick at the cap.
  if item.CapFraction and item.CapFraction < 1 then
    local capX = width * item.CapFraction
    row.capBand:ClearAllPoints()
    row.capBand:SetPoint("TOPLEFT", row, "TOPLEFT", capX, 0)
    row.capBand:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.capBand:Show()
    row.capTick:ClearAllPoints()
    row.capTick:SetPoint("TOPLEFT", row, "TOPLEFT", capX - 1, 0)
    row.capTick:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", capX - 1, 0)
    row.capTick:Show()
  else
    row.capBand:Hide(); row.capTick:Hide()
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

  -- Subtle lock toggle in the corner
  local lock = CreateFrame("Button", nil, title)
  lock:SetSize(14, 14)
  lock:SetPoint("TOPRIGHT", -3, -4)
  lock:SetFrameLevel(title:GetFrameLevel() + 5)
  lock:RegisterForClicks("LeftButtonUp")
  lock.tex = lock:CreateTexture(nil, "ARTWORK")
  lock.tex:SetAllPoints()
  lock:SetScript("OnEnter", function()
    lock:SetAlpha(1)
    GameTooltip:SetOwner(lock, "ANCHOR_LEFT")
    GameTooltip:SetText(lock.locked and "Locked - click to unlock" or "Unlocked - click to lock", 1, 1, 1)
    GameTooltip:Show()
  end)
  lock:SetScript("OnLeave", function() GameTooltip:Hide(); L.UpdateLock() end)
  lock:SetScript("OnClick", function()
    L.SetLocked(not Cfg().Locked)
    GameTooltip:SetText(Cfg().Locked and "Locked - click to unlock" or "Unlocked - click to lock", 1, 1, 1)
  end)
  title.lock = lock

  title.level = T.Text(title, T.TitleSize + 1)
  title.level:SetPoint("RIGHT", lock, "LEFT", -4, 0)
  title.level:SetJustifyH("RIGHT")

  title.zone = T.Text(title, T.TitleSize)
  title.zone:SetPoint("LEFT", T.Padding, 0)

  -- Clickable class / pattern pieces: "Zone - Class v - Pattern v"
  local function Clickable(onClick)
    local b = CreateFrame("Button", nil, title)
    b:SetHeight(16)
    b.text = T.Text(b, T.TitleSize)
    b.text:SetPoint("LEFT")
    T.SetColour(b.text, T.Colour.TextDim)
    b:SetScript("OnEnter", function() T.SetColour(b.text, T.Colour.Text) end)
    b:SetScript("OnLeave", function() T.SetColour(b.text, T.Colour.TextDim) end)
    b:SetScript("OnClick", function() onClick(b) end)
    b.SetLabel = function(self, s) self.text:SetText(s .. " |cff777777v|r"); self:SetWidth(self.text:GetStringWidth() + 2) end
    return b
  end
  local function Dash()
    local d = T.Text(title, T.TitleSize)
    T.SetColour(d, T.Colour.TextDim)
    d:SetText("-")
    return d
  end
  title.dash0 = Dash()
  title.dash0:SetPoint("LEFT", title.zone, "RIGHT", 4, 0)
  title.class = Clickable(function(b) L.ShowClassMenu(b) end)
  title.class:SetPoint("LEFT", title.dash0, "RIGHT", 4, 0)
  title.dash = Dash()
  title.dash:SetPoint("LEFT", title.class, "RIGHT", 4, 0)
  title.pattern = Clickable(function(b) L.ShowPatternMenu(b) end)
  title.pattern:SetPoint("LEFT", title.dash, "RIGHT", 4, 0)
  title.dash2 = Dash()
  title.dash2:SetPoint("LEFT", title.pattern, "RIGHT", 4, 0)
  title.clock = Clickable(function(b) L.ShowClockMenu(b) end)
  title.clock:SetPoint("LEFT", title.dash2, "RIGHT", 4, 0)

  title.sep = T.Separator(f)
  title.sep:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, 0)
  title.sep:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, 0)
  return title
end

local function BuildTimer(f)
  local area = CreateFrame("Frame", nil, f)
  area:SetHeight(T.TimerHeight)
  area.big = T.Text(area, T.TimerSize)
  area.big:SetJustifyH("RIGHT")
  area.secondary = T.Text(area, T.FontSize - 2)
  T.SetColour(area.secondary, T.Colour.TextDim)
  area.sepTop = T.Separator(f)
  area.sepTop:SetPoint("TOPLEFT", area, "TOPLEFT"); area.sepTop:SetPoint("TOPRIGHT", area, "TOPRIGHT")
  return area
end

-- Large LiveSplit-style block (tenths, two lines) or a compact single row.
function L.LayoutTimer(big)
  local area = frame.timer
  if area.isBig == big then return end
  area.isBig = big
  area.lastPrimaryTenths = nil   -- force text rebuild in the new format
  area.big:ClearAllPoints(); area.secondary:ClearAllPoints()
  if big then
    area:SetHeight(T.TimerHeight)
    area.big:SetFont(T.Font, T.TimerSize, "")
    area.big:SetPoint("RIGHT", -T.Padding, 2)
    area.secondary:SetPoint("BOTTOMRIGHT", -T.Padding, 1)
    area.secondary:SetJustifyH("RIGHT")
  else
    area:SetHeight(T.RowHeight)
    area.big:SetFont(T.Font, T.FontSize + 1, "")
    area.big:SetPoint("RIGHT", -T.Padding, 0)
    area.secondary:SetPoint("LEFT", T.Padding, 0)
    area.secondary:SetJustifyH("LEFT")
  end
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
  -- Apply the saved visibility before anything else can fail; a refresh error must not leave it shown.
  frame:SetShown(Cfg().Shown ~= false)
  L.RestorePosition()
  local ok, err = pcall(L.Refresh)
  if not ok then U.Print("refresh error: %s", tostring(err)) end
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
  local outer = U.Phase("Live.Refresh")
  local V = GetView()
  lastDone = V.Done
  local cfg = Cfg()
  local timesLeft = cfg.TimesSide == "LEFT"
  frame:SetScale(cfg.Scale or 1)
  frame.bg:SetAlpha(cfg.BgAlpha or 0.85)

  -- title
  local tt = frame.title
  tt.zone:SetText(V.CompareKey.StartZone)
  tt.class:SetLabel(V.CompareKey.Class)
  tt.pattern:SetLabel(V.CompareKey.Pattern)
  tt.clock:SetLabel(cfg.Clock == "PLAYED" and "Played" or "Active")
  tt.level:SetText(tostring(V.Level))
  L.UpdateLock()

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
  local big = cfg.BigTimer == true
  L.LayoutTimer(big)
  frame.timer:ClearAllPoints()
  frame.timer:SetPoint("TOPLEFT", 0, y); frame.timer:SetPoint("TOPRIGHT", 0, y)
  y = y - (big and T.TimerHeight or T.RowHeight)
  frame.footer:ClearAllPoints()
  frame.footer:SetPoint("TOPLEFT", 0, y); frame.footer:SetPoint("TOPRIGHT", 0, y)
  y = y - T.FooterHeight
  frame.footer.value:SetText(U.FormatDelta(V.PreviousSegmentDelta))
  T.SetColour(frame.footer.value, T.DeltaColour(V.PreviousSegmentDelta))

  frame:SetHeight(-y)
  L.UpdateTimer(V)
  U.PhaseEnd(outer)
end

function L.UpdateTimer(V)
  if not frame then return end
  local cfg = Cfg()
  local played, active = ST.Clock.Now()
  local primary, secondaryLabel, secondary
  if cfg.Clock == "PLAYED" then
    primary, secondaryLabel, secondary = played, "active", active
  else
    primary, secondaryLabel, secondary = active, "played", played
  end
  -- Only rebuild strings when the displayed value actually changes (keeps per-frame garbage near zero).
  local big = cfg.BigTimer == true
  local primaryTenths = big and math.floor(primary * 10) or math.floor(primary)
  if primaryTenths ~= frame.timer.lastPrimaryTenths then
    frame.timer.lastPrimaryTenths = primaryTenths
    frame.timer.big:SetText(U.FormatTime(primary, big))
  end
  local running = ST.Clock.IsRunning()
  local reason = ST.Clock.ForcedStop() or (not running and "idle") or nil
  local secondaryWhole = math.floor(secondary)
  if secondaryWhole ~= frame.timer.lastSecondaryWhole or reason ~= frame.timer.lastReason or secondaryLabel ~= frame.timer.lastSecondaryLabel then
    frame.timer.lastSecondaryWhole, frame.timer.lastReason, frame.timer.lastSecondaryLabel = secondaryWhole, reason, secondaryLabel
    local suffix = reason and ("  |cffaaaaaa(" .. reason .. ")|r") or ""
    frame.timer.secondary:SetText(secondaryLabel .. " " .. U.FormatTime(secondary) .. suffix)
  end
  local colour
  if ST.Record.Current().CharacterRun_Frozen then colour = T.Colour.Frozen
  elseif not running then colour = T.Colour.Stopped
  else
    local done = (V and V.Done) or lastDone or {}
    local last = done[#done]
    colour = last and T.DeltaColour(last.Best and (last.Time - last.Best), last.Gold) or T.Colour.Text
  end
  if colour ~= frame.timer.lastColour then
    frame.timer.lastColour = colour
    T.SetColour(frame.timer.big, colour)
  end
end

-- Coalesce bursts of refresh requests (kill -> XP update + quest log update + ...) into one rebuild.
local refreshQueued = false
function L.QueueRefresh()
  if refreshQueued or not frame then return end
  refreshQueued = true
  C_Timer.After(0.25, function() refreshQueued = false; L.Refresh() end)
end

local acc = 0
function L.OnUpdate(elapsed)
  acc = acc + elapsed
  if acc >= 0.1 then acc = 0; L.UpdateTimer() end
end

------------------------------------------------------------------------
-- Menus
------------------------------------------------------------------------
function L.ShowClassMenu(anchor)
  local items = {}
  local current = ST.Compare.Key().Class
  for _, c in ipairs(ST.Compare.ClassOptions()) do
    items[#items + 1] = { text = ST.Compare.ClassLabel(c), checked = (current == c), func = function() Cfg().CompareClass = c; ST.Compare.Invalidate(); L.Refresh() end }
  end
  T.ShowMenu(anchor, items)
end

function L.ShowPatternMenu(anchor)
  local items = {}
  local current = ST.Compare.Key().Pattern
  for _, p in ipairs(ST.Compare.PatternOptions()) do
    items[#items + 1] = { text = p, checked = (current == p), func = function() Cfg().ComparePattern = p; ST.Compare.Invalidate(); L.Refresh() end }
  end
  items[#items + 1] = { separator = true }
  items[#items + 1] = { text = "Name this run's pattern...", func = function() StaticPopup_Show("SPLITTIMER_NAME_PATTERN") end }
  T.ShowMenu(anchor, items)
end

function L.ShowContextMenu(anchor)
  L.ShowContextMenuImpl(anchor)
end

function L.ShowClockMenu(anchor)
  local function Set(mode) Cfg().Clock = mode; ST.Compare.Invalidate(); L.Refresh() end
  T.ShowMenu(anchor, {
    { text = "Active  (played time while doing something)", checked = Cfg().Clock ~= "PLAYED", func = function() Set("ACTIVE") end },
    { text = "Played  (total /played)",                      checked = Cfg().Clock == "PLAYED", func = function() Set("PLAYED") end },
  })
end

function L.ShowContextMenuImpl(anchor)
  local cfg = Cfg()
  T.ShowMenu(anchor, {
    { title = "SplitTimer" },
    { text = "Lock window", checked = cfg.Locked, func = function() L.SetLocked(not cfg.Locked) end },
    { text = "Times on left", checked = cfg.TimesSide == "LEFT", func = function() cfg.TimesSide = cfg.TimesSide == "LEFT" and "RIGHT" or "LEFT"; L.Refresh() end },
    { text = "Large timer (LiveSplit style)", checked = cfg.BigTimer == true, func = function() cfg.BigTimer = not cfg.BigTimer; L.Refresh() end },
    { text = "Show Played clock", checked = cfg.Clock == "PLAYED", func = function() cfg.Clock = cfg.Clock == "PLAYED" and "ACTIVE" or "PLAYED"; ST.Compare.Invalidate(); L.Refresh() end },
    { text = ST.Clock.IsPaused() and "Resume active clock" or "Pause active clock", func = function() ST.Clock.SetPaused(not ST.Clock.IsPaused()) end },
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
  local existed = frame ~= nil
  L.Create()
  -- A toggle that had to create the frame means "show it" - never invert a freshly built frame.
  if show == nil then show = (not existed) or (not frame:IsShown()) end
  frame:SetShown(show)
  Cfg().Shown = show
end

function L.SetLocked(locked)
  Cfg().Locked = locked and true or false
  L.UpdateLock()
end

function L.UpdateLock()
  if not frame then return end
  local locked = Cfg().Locked
  local lock = frame.title.lock
  lock.locked = locked
  -- Blizzard lock textures have padding; zoom in a touch
  lock.tex:SetTexCoord(0.2, 0.8, 0.2, 0.8)
  if locked then
    lock.tex:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
    lock.tex:SetVertexColor(0.6, 0.6, 0.6, 1)    -- dim grey = locked (the usual state)
  else
    lock.tex:SetTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
    lock.tex:SetVertexColor(1.0, 0.82, 0.3, 1)   -- gold, open = unlocked (draws attention)
  end
  lock:SetAlpha(lock:IsMouseOver() and 1 or (locked and 0.3 or 0.85))
end
