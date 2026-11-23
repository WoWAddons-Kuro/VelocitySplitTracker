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
  row.trainTick = T.Texture(row, T.Colour.TrainTick, "OVERLAY")
  row.trainTick:SetSize(7, 7)
  if row.trainTick.SetRotation then row.trainTick:SetRotation(math.pi / 4) end
  if row.SetClipsChildren then row:SetClipsChildren(true) end
  row.trainTick:Hide()
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
  -- level segment delta "(+2:14)", one notch smaller, sits left of the cumulative delta
  row.segment = T.Text(row, T.FontSize - 2)
  row.segment:SetJustifyH("RIGHT")
  -- level rows: "12.3k xp/hr", smaller and dim, just right of the label text. The label is
  -- shrunk to its string width on level rows so this hugs "Level 10" instead of the column edge.
  row.xp = T.Text(row, T.FontSize - 3)
  row.xp:SetJustifyH("LEFT")
  row.xp:SetWordWrap(false)
  return row
end

-- Lay a row out for the configured side. Times block = [delta][time].
-- The icon column is always reserved so labels line up whether or not a row has an icon.
-- Rows without a delta (upcoming rows) let the label run over the empty delta column.
local function LayoutRow(row, timesLeft)
  local p = T.Padding
  local hasDelta = (row.delta:GetText() or "") ~= ""
  local hasSegment = (row.segment:GetText() or "") ~= ""
  local hasXP = (row.xp:GetText() or "") ~= ""
  row.icon:ClearAllPoints(); row.label:ClearAllPoints(); row.time:ClearAllPoints(); row.delta:ClearAllPoints(); row.segment:ClearAllPoints(); row.xp:ClearAllPoints()
  row.time:SetWidth(58)
  row.delta:SetWidth(48)
  if timesLeft then
    row.delta:SetPoint("LEFT", row, "LEFT", p, 0)
    row.time:SetPoint("LEFT", row.delta, "RIGHT", 4, 0)
    row.segment:SetPoint("LEFT", row.time, "RIGHT", 4, 0)
    row.icon:SetPoint("LEFT", hasSegment and row.segment or row.time, "RIGHT", 6, 0)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    if hasXP then row.xp:SetPoint("LEFT", row.label, "RIGHT", 6, 0); row.xp:SetPoint("RIGHT", row, "RIGHT", -p, 0)
    else row.label:SetPoint("RIGHT", row, "RIGHT", -p, 0) end
  else
    row.icon:SetPoint("LEFT", row, "LEFT", p, 0)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.time:SetPoint("RIGHT", row, "RIGHT", -p, 0)
    row.delta:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
    row.segment:SetPoint("RIGHT", row.delta, "LEFT", -4, 0)
    local rightStop = hasSegment and row.segment or (hasDelta and row.delta or row.time)
    if hasXP then row.xp:SetPoint("LEFT", row.label, "RIGHT", 6, 0); row.xp:SetPoint("RIGHT", rightStop, "LEFT", -4, 0)
    else row.label:SetPoint("RIGHT", rightStop, "LEFT", -4, 0) end
  end
  -- With an xp/hr tag the label is exactly as wide as its text so the tag sits right beside it.
  if hasXP then row.label:SetWidth(row.label:GetStringWidth() + 1) else row.label:SetWidth(0) end
end

-- "12.3k xp/hr" / "870 xp/hr"
local function FormatXPPerHour(v)
  if not v or v <= 0 then return "" end
  if v >= 10000 then return string.format("%.0fk xp/hr", v / 1000) end
  if v >= 1000 then return string.format("%.1fk xp/hr", v / 1000) end
  return string.format("%.0f xp/hr", v)
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
  -- Level rows: the (n-1 -> n) segment delta in parentheses, left of the cumulative delta.
  -- "(+2:14)  +10:30  54:11" = lost 2:14 during this level, 10:30 behind in total, at 54:11.
  if item.SegmentDelta then
    row.segment:SetText("(" .. U.FormatDelta(item.SegmentDelta) .. ")")
    T.SetColour(row.segment, T.DeltaColour(item.SegmentDelta), 0.85)
  else
    row.segment:SetText("")
  end
  -- Level rows: XP/hr over that level, small and dim beside the label.
  row.xp:SetText(item.Axis == "level" and FormatXPPerHour(item.XPPerHour) or "")
  T.SetColour(row.xp, T.Colour.TextDim, 0.8)
  row.xpLive = nil
  row.progress:Hide()
end

local function FillUpcomingRow(row, item, width)
  SetRowIcon(row, item.Axis, item.Icon)
  local label = item.Label
  if item.ProgressText then label = label .. "  |cff999999" .. item.ProgressText .. "|r" end
  row.label:SetText(label)
  T.SetColour(row.label, item.Current and T.Colour.Text or T.Colour.TextDim)
  -- Current-level row: running XP/hr for this level; UpdateTimer refreshes it every second.
  row.xpLive = (item.Current and item.Axis == "level") or nil
  row.xp:SetText(row.xpLive and FormatXPPerHour(ST.View.CurrentXPPerHour()) or "")
  T.SetColour(row.xp, T.Colour.TextDim, 0.8)
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
  -- Train marker: small up-pointing triangle on the bottom margin where the next tier becomes
  -- trainable. Stays visible after you pass it (faint) as a reminder that training is available.
  if item.TrainFraction and item.TrainFraction < 1 then
    local tx = width * item.TrainFraction
    row.trainTick:SetAlpha(item.Progress and item.Progress >= item.TrainFraction and 0.45 or 0.9)
    row.trainTick:ClearAllPoints()
    -- a 7x7 square rotated 45 degrees, centred on the bottom edge; the row clips the lower half
    row.trainTick:SetPoint("CENTER", row, "BOTTOMLEFT", tx, 0)
    row.trainTick:Show()
  else
    row.trainTick:Hide()
  end
end

------------------------------------------------------------------------
-- Window construction
------------------------------------------------------------------------
local frame
local lastDone   -- V.Done from the most recent Refresh; UpdateTimer colours the clock from it between refreshes

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
  lock:SetPoint("TOPRIGHT", -3, -(T.TitleHeightCollapsed - 14) / 2)   -- vertically centred on line 1
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
  title.level:SetPoint("RIGHT", lock, "LEFT", -4, 0)   -- lock is TOP-anchored, so this stays on line 1
  title.level:SetJustifyH("RIGHT")

  -- Hamburger: three drawn lines (ARIALN has no glyph for it). Opens the same menu as right-click.
  -- Everything on the collapsed line is anchored to the TOP of the title frame (not its vertical
  -- centre) so it stays on line 1 when the expanded rows grow the frame downwards.
  local line1Y = -(T.TitleHeightCollapsed / 2)   -- centre of the first line
  local menuBtn = CreateFrame("Button", nil, title)
  menuBtn:SetSize(14, 14)
  menuBtn:SetPoint("TOPLEFT", T.Padding - 1, line1Y + 7)
  menuBtn:SetFrameLevel(title:GetFrameLevel() + 5)
  menuBtn.lines = {}
  for i = 1, 3 do
    local ln = menuBtn:CreateTexture(nil, "ARTWORK")
    ln:SetColorTexture(0.75, 0.75, 0.75, 1)
    ln:SetSize(12, 2)
    ln:SetPoint("TOP", 0, -(1 + (i - 1) * 4))
    menuBtn.lines[i] = ln
  end
  menuBtn:SetAlpha(0.6)
  menuBtn:SetScript("OnEnter", function() menuBtn:SetAlpha(1) end)
  menuBtn:SetScript("OnLeave", function() menuBtn:SetAlpha(0.6) end)
  menuBtn:SetScript("OnClick", function() L.ShowContextMenu(menuBtn) end)
  title.menu = menuBtn

  -- Clickable label with a dim "v" dropdown marker.
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

  -- Collapsed line: [=] vs <target> v  [>]            level [lock]
  -- The vs label is the one setting changed mid-run, so it stays a dropdown when collapsed.
  title.vs = Clickable(function(b) L.ShowTargetMenu(b) end)
  title.vs:SetPoint("LEFT", menuBtn, "RIGHT", 5, 0)
  title.vs.text:SetWordWrap(false)
  T.SetColour(title.vs.text, T.Colour.Text)
  title.vs:SetScript("OnLeave", function() T.SetColour(title.vs.text, T.Colour.Text) end)
  -- Twiddle: a small right/down triangle (drawn, ARIALN has no glyphs) that expands the filter rows.
  local tw = CreateFrame("Button", nil, title)
  tw:SetSize(14, 14)
  tw:SetPoint("LEFT", title.vs, "RIGHT", 2, 0)
  tw.tex = tw:CreateTexture(nil, "ARTWORK")
  tw.tex:SetSize(8, 8); tw.tex:SetPoint("CENTER")
  tw.tex:SetColorTexture(0.75, 0.75, 0.75, 1)
  if tw.tex.SetRotation then tw.tex:SetRotation(math.pi / 4) end
  tw:SetAlpha(0.55)
  tw:SetScript("OnEnter", function() tw:SetAlpha(1) end)
  tw:SetScript("OnLeave", function() tw:SetAlpha(0.55) end)
  tw:SetScript("OnClick", function() Cfg().TitleExpanded = not Cfg().TitleExpanded; L.Refresh() end)
  title.twiddle = tw
  -- vs label is clamped so it never pushes the twiddle/level off the row; long names ellipsize.
  title.vs.SetLabel = function(self, s)
    self.text:SetText(s .. " |cff777777v|r")
    local maxW = (frame and frame:GetWidth() or T.Width) - 14 - 5 - 16 - 30 - 20 - T.Padding
    local w = self.text:GetStringWidth() + 2
    self:SetWidth(math.min(w, maxW)); self.text:SetWidth(math.min(w, maxW))
  end

  -- Expanded block (under the collapsed line): one row per FILTER setting, dim heading on the
  -- left, dropdown value on the right. The comparison target is NOT repeated here - the vs line
  -- above is that dropdown - so the values get the full width.
  title.rows = {}
  local menuFor = { zone = L.ShowZoneMenu, class = L.ShowClassMenu, pattern = L.ShowPatternMenu, clock = L.ShowClockMenu }
  for i = 1, 4 do
    local r = {}
    r.label = T.Text(title, T.FontSize - 1)
    r.label:SetPoint("TOPLEFT", T.Padding + 14, -(T.TitleHeightCollapsed + (i - 1) * T.TitleRowHeight) - 3)
    r.label:SetWidth(70); r.label:SetJustifyH("LEFT")
    T.SetColour(r.label, T.Colour.TextDim)
    r.value = Clickable(function(b) local fn = menuFor[b.rowId]; if fn then fn(b) end end)
    r.value:SetPoint("LEFT", r.label, "RIGHT", 6, 0)
    r.value.text:SetWordWrap(false)
    -- Size from the text but clamp to the space left of the window edge so a long value
    -- ellipsizes instead of running past the lock. (The button keeps a single LEFT anchor.)
    r.value.SetLabel = function(self, s)
      self.text:SetText(s .. " |cff777777v|r")
      local maxW = (frame and frame:GetWidth() or T.Width) - (T.Padding + 14 + 70 + 6) - T.Padding
      local w = math.min(self.text:GetStringWidth() + 2, maxW)
      self:SetWidth(w); self.text:SetWidth(w)
    end
    r.value:Hide(); r.label:Hide()
    title.rows[i] = r
  end

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
  -- compact: the whole "Active x | Played y" line. big: the OTHER clock, at the left edge.
  area.secondary = T.Text(area, T.FontSize - 2)
  T.SetColour(area.secondary, T.Colour.TextDim)
  -- big only: the name of the clock the big number is showing, small, under the number.
  area.modeLabel = T.Text(area, T.FontSize - 3)
  T.SetColour(area.modeLabel, T.Colour.TextDim)
  area.modeLabel:Hide()
  area.sepTop = T.Separator(f)
  area.sepTop:SetPoint("TOPLEFT", area, "TOPLEFT"); area.sepTop:SetPoint("TOPRIGHT", area, "TOPRIGHT")
  return area
end

-- Large LiveSplit-style block (two lines, whole seconds) or a compact single row.
function L.LayoutTimer(big)
  local area = frame.timer
  if area.isBig == big then return end
  area.isBig = big
  area.lastTick, area.lastBigTick = nil, nil   -- force text rebuild in the new format
  area.big:ClearAllPoints(); area.secondary:ClearAllPoints(); area.modeLabel:ClearAllPoints()
  if big then
    -- [ other clock, small, left ]           1:12:56   <- big number, top right
    --                                          Active   <- mode caption, small, under it
    area:SetHeight(T.TimerHeight)
    area.big:SetFont(T.Font, T.TimerSize, "")
    area.big:SetPoint("TOPRIGHT", -T.Padding, -2)
    area.modeLabel:SetPoint("TOPRIGHT", area.big, "BOTTOMRIGHT", -2, 2)
    area.modeLabel:SetJustifyH("RIGHT")
    area.modeLabel:Show()
    area.secondary:SetFont(T.Font, T.FontSize - 2, "")
    -- lower-left, on the same baseline as the mode caption under the big number
    area.secondary:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", T.Padding, 0)
    area.secondary:SetPoint("BOTTOM", area.modeLabel, "BOTTOM", 0, 0)
    area.secondary:SetJustifyH("LEFT")
  else
    area:SetHeight(T.RowHeight)
    area.modeLabel:Hide()
    area.big:SetPoint("RIGHT", -T.Padding, 0)   -- unused in compact mode (text cleared)
    area.secondary:SetFont(T.Font, T.FontSize, "")
    area.secondary:SetPoint("LEFT", T.Padding, 0); area.secondary:SetPoint("RIGHT", -T.Padding, 0)
    area.secondary:SetJustifyH("CENTER")
  end
end

local function BuildFooter(f)
  local footer = CreateFrame("Frame", nil, f)
  footer:SetHeight(T.FooterHeight)
  footer.bg = T.Texture(footer, T.Colour.RowAlt); footer.bg:SetAllPoints()
  -- build number, small and subtle, right-aligned
  footer.build = T.Text(footer, 9)
  footer.build:SetPoint("RIGHT", -T.Padding, 0)
  footer.build:SetJustifyH("RIGHT")
  T.SetColour(footer.build, T.Colour.TextDim, 0.6)
  footer.build:SetText(U.BuildLabel())
  -- left-justified status: hardcore runs say "Hardcore"; softcore runs show skull + death count
  -- (always when Config.ShowDeathsSoftcore, otherwise only once > 0). Icon leads, text follows,
  -- so the pair never overlaps the right-aligned build label at narrow widths.
  footer.status = T.Text(footer, T.FontSize)
  footer.status:SetJustifyH("LEFT")
  footer.status:Hide()
  footer.deathIcon = footer:CreateTexture(nil, "ARTWORK")
  footer.deathIcon:SetSize(12, 12)
  footer.deathIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")   -- skull raid marker
  footer.deathIcon:SetPoint("LEFT", footer, "LEFT", T.Padding, 0)
  footer.status:SetPoint("LEFT", footer.deathIcon, "RIGHT", 3, 0)
  footer.deathIcon:Hide()
  return footer
end

function L.Create()
  if frame then return frame end
  frame = CreateFrame("Frame", "VelocityLiveWindow", UIParent)
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

  -- title: drawn ONLY from V.Title (view-model seam; see the structure audit)
  local tt = frame.title
  local TT = V.Title
  tt.vs:SetLabel(TT.VsLabel)
  tt.level:SetText(tostring(TT.Level))
  local titleH = T.TitleHeightCollapsed
  if TT.Expanded then
    titleH = T.TitleHeightCollapsed + #TT.Rows * T.TitleRowHeight + 2
    for i, rowVM in ipairs(TT.Rows) do
      local r = tt.rows[i]
      if r then   -- renderer has a fixed pool; a view row beyond it is skipped, never a crash
        r.label:SetText(rowVM.Label); r.label:Show()
        r.value.rowId = rowVM.Id
        r.value:SetLabel(rowVM.Value); r.value:Show()
      end
    end
    for i = #TT.Rows + 1, #tt.rows do tt.rows[i].label:Hide(); tt.rows[i].value:Hide() end
    -- down-pointing: rotate the square so a corner points down (3/4 pi puts a vertex at the bottom)
    if tt.twiddle.tex.SetRotation then tt.twiddle.tex:SetRotation(math.pi / 4) end
    tt.twiddle.tex:SetTexCoord(0, 1, 0, 1)
  else
    for _, r in ipairs(tt.rows) do r.label:Hide(); r.value:Hide() end
    if tt.twiddle.tex.SetRotation then tt.twiddle.tex:SetRotation(math.pi / 4) end
  end
  -- the twiddle is a rotated square either way; expanded vs collapsed is told by the rows below it,
  -- and by its alpha (brighter when open)
  tt.twiddle:SetAlpha(TT.Expanded and 0.9 or 0.55)
  tt:SetHeight(titleH)
  L.UpdateLock()

  -- rows
  for _, r in ipairs(frame.rows) do r:Hide() end
  local y = -titleH - 1
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
  -- Done rows: V.Done already trimmed to RowsDone (non-level recent splits) + RowsDoneLevels (past
  -- level splits, 1-4). Both sorted oldest first; nothing more to cap here.
  for i = 1, #done do
    local row = AcquireRow(n + 1)
    FillDoneRow(row, done[i])
    Place(row)
  end

  frame.sepUpcoming:ClearAllPoints()
  frame.sepUpcoming:SetPoint("TOPLEFT", 0, y); frame.sepUpcoming:SetPoint("TOPRIGHT", 0, y)
  y = y - 1

  -- The view owns the row cap (variable rows only; professions / money are never capped).
  for i = 1, #V.Upcoming do
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
  -- footer status, left-justified so it never collides with the right-aligned build label:
  -- "Hardcore" on hardcore runs; otherwise skull + death counter
  -- (always when Config.ShowDeathsSoftcore, else only once > 0)
  local ft = frame.footer
  local mode = ST.Record.Current().CharacterRun_Mode or ""
  ft.status:ClearAllPoints()
  if mode:find("hardcore", 1, true) then
    ft.status:SetText("Hardcore")
    T.SetColour(ft.status, T.Colour.Behind)
    ft.status:SetPoint("LEFT", ft, "LEFT", T.Padding, 0)   -- text alone, no icon
    ft.status:Show(); ft.deathIcon:Hide()
  else
    local deaths = ST.Milestones.DeathCount()
    if deaths > 0 or cfg.ShowDeathsSoftcore ~= false then
      ft.status:SetText(tostring(deaths))
      T.SetColour(ft.status, deaths > 0 and T.Colour.Behind or T.Colour.TextDim)
      -- icon sits at the footer's left edge (anchored in BuildFooter); text follows it
      ft.status:SetPoint("LEFT", ft.deathIcon, "RIGHT", 3, 0)
      ft.status:Show(); ft.deathIcon:Show()
    else
      ft.status:Hide(); ft.deathIcon:Hide()
    end
  end

  frame:SetHeight(-y)
  L.UpdateTimer(V)
  if ST.AutoHide then ST.AutoHide.CheckNear(V.Upcoming) end
  U.PhaseEnd(outer)
end

function L.UpdateTimer(V)
  if not frame then return end
  local cfg = Cfg()
  local played, active = ST.Clock.Now()
  local playedSelected = cfg.Clock == "PLAYED"
  local big = cfg.BigTimer == true
  local running = ST.Clock.IsRunning()
  local reason = ST.Clock.ForcedStop() or (not running and "idle") or nil
  local tm = frame.timer
  -- Both clocks are re-rendered together, gated on Played's whole second, so their seconds
  -- tick in lockstep instead of at two different millisecond offsets.
  local tick = math.floor(played)
  local primary = playedSelected and played or active
  if tick ~= tm.lastTick or reason ~= tm.lastReason or playedSelected ~= tm.lastPlayedSelected or big ~= tm.lastBig then
    tm.lastTick, tm.lastReason, tm.lastPlayedSelected, tm.lastBig = tick, reason, playedSelected, big
    local activeWhole = math.floor(active + 0.5)   -- rounded, so it lands on the same visual tick as Played
    -- The stop reason ("idle", "paused", ...) is a state of the ACTIVE clock, so it sits directly
    -- left of the Active label and takes the same emphasis (bright when Active is selected, dim otherwise).
    local reasonPrefix = reason and ("(" .. reason .. ") ") or ""
    if big then
      -- big: the OTHER clock small at the left; the big number's own name small under it.
      -- The stop reason stays attached to "Active" wherever that label ends up.
      if playedSelected then
        tm.secondary:SetText(reasonPrefix .. "Active " .. U.FormatTime(activeWhole))
        tm.modeLabel:SetText("Played")
      else
        tm.secondary:SetText("Played " .. U.FormatTime(tick))
        tm.modeLabel:SetText(reasonPrefix .. "Active")
      end
    else
      -- compact: "Active 1:30:51   Played 1:49:44" with the selected one bright
      local selOpen, selClose, dimOpen, dimClose = "|cffeeeeee", "|r", "|cff999999", "|r"
      local a = (playedSelected and dimOpen or selOpen) .. reasonPrefix .. "Active " .. U.FormatTime(activeWhole) .. (playedSelected and dimClose or selClose)
      local p = (playedSelected and selOpen or dimOpen) .. "Played " .. U.FormatTime(tick) .. (playedSelected and selClose or dimClose)
      tm.secondary:SetText(a .. "  |cff666666|||r  " .. p)
      tm.big:SetText("")
    end
  end
  if big and tick ~= tm.lastBigTick then
    tm.lastBigTick = tick
    tm.big:SetText(U.FormatTime(math.floor(primary + 0.5)))
  end
  -- Current-level row: its xp/hr tag ticks with the clock (once a second, same gate as the timer).
  if tick ~= frame.lastXPTick then
    frame.lastXPTick = tick
    for _, row in ipairs(frame.rows) do
      if row.xpLive and row:IsShown() then row.xp:SetText(FormatXPPerHour(ST.View.CurrentXPPerHour())) end
    end
  end
  local colour
  if ST.Record.Current().CharacterRun_Frozen then colour = T.Colour.Frozen
  elseif not running then colour = T.Colour.Stopped
  else
    local done = (V and V.Done) or lastDone or {}
    local last = done[#done]
    colour = last and T.DeltaColour(last.Best and (last.Time - last.Best), last.Gold) or T.Colour.Text
  end
  if colour ~= tm.lastColour then
    tm.lastColour = colour
    T.SetColour(tm.big, colour)
    -- compact mode: tint the whole line with the state colour only when stopped/frozen
    if not big then
      if colour == T.Colour.Stopped or colour == T.Colour.Frozen then T.SetColour(tm.secondary, colour) else T.SetColour(tm.secondary, T.Colour.Text) end
    else
      T.SetColour(tm.secondary, T.Colour.TextDim)
    end
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

function L.ShowZoneMenu(anchor)
  local items = {}
  local current = ST.Compare.Key().StartZone
  local mine = ST.Record.Current().CharacterRun_StartZone
  for _, z in ipairs(ST.Compare.ZoneOptions()) do
    items[#items + 1] = { text = ST.Compare.ZoneLabel(z) .. (z == mine and "  (this character)" or ""), checked = (current == z),
      func = function() Cfg().CompareZone = (z ~= mine) and z or nil; Cfg().CompareAnyZone = nil; ST.Compare.Invalidate(); L.Refresh() end }
  end
  T.ShowMenu(anchor, items)
end

function L.ShowPatternMenu(anchor)
  local items = {}
  local current = ST.Compare.Key().Pattern
  for _, p in ipairs(ST.Compare.PatternOptions()) do
    items[#items + 1] = { text = ST.Compare.PatternLabel(p), checked = (current == p), func = function() Cfg().ComparePattern = p; ST.Compare.Invalidate(); L.Refresh() end }
  end
  items[#items + 1] = { separator = true }
  items[#items + 1] = { text = "Name this run's pattern...", func = function() StaticPopup_Show("VELOCITY_NAME_PATTERN") end }
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

-- The "vs" dropdown (SPEC 5.3): check column, Auto select, top-N runs in Auto rank order,
-- then Best splits / No comparison.
function L.ShowTargetMenu(anchor)
  local t = ST.Compare.Target()
  local items = { { text = "Auto select", checked = t.Mode == "Auto", func = function() ST.Compare.SetTarget("Auto"); L.Refresh() end } }
  local ranked = ST.Compare.RankedCandidates()
  local maxRuns = Cfg().Compare_DropdownRuns or 5
  for i = 1, math.min(maxRuns, #ranked) do
    local r = ranked[i]
    local label = U.RunDisplayName(r.Rec) .. (r.Rec.CharacterRun_Reference and " (ref)" or "") .. (r.Eligible and "" or "  |cff777777(behind you)|r")
    items[#items + 1] = { text = label, checked = (t.Mode == "Run" and t.RunKey == r.Key), func = function() ST.Compare.SetTarget("Run", r.Key); L.Refresh() end }
  end
  items[#items + 1] = { separator = true }
  items[#items + 1] = { text = "Best splits", checked = t.Mode == "BestSplits", func = function() ST.Compare.SetTarget("BestSplits"); L.Refresh() end }
  items[#items + 1] = { text = "No comparison", checked = t.Mode == "None", func = function() ST.Compare.SetTarget("None"); L.Refresh() end }
  T.ShowMenu(anchor, items)
end

function L.ShowContextMenuImpl(anchor)
  local cfg = Cfg()
  -- Section 1: IMMEDIATE actions only (things that act on the here-and-now).
  local items = {
    { title = "Velocity" },
    { text = "Add location split here...", func = function() StaticPopup_Show("VELOCITY_ADD_LOCATION") end },
  }
  for _, e in ipairs(ST.Locations.List()) do
    local key, label = e.Key, e.Label
    items[#items + 1] = { text = "Remove location split: " .. label, func = function() ST.Locations.Remove(key); L.Refresh() end }
  end
  items[#items + 1] = { separator = true }
  items[#items + 1] = { title = "Clock" }
  items[#items + 1] = { text = ST.Clock.IsPaused() and "Resume active clock" or "Pause active clock", func = function() ST.Clock.SetPaused(not ST.Clock.IsPaused()) end }
  -- Section 2: settings / toggles.
  local settings = {
    { separator = true },
    { text = "Lock window", checked = cfg.Locked, func = function() L.SetLocked(not cfg.Locked) end },
    { text = "Times on left", checked = cfg.TimesSide == "LEFT", func = function() cfg.TimesSide = cfg.TimesSide == "LEFT" and "RIGHT" or "LEFT"; L.Refresh() end },
    { text = "Large timer (LiveSplit style)", checked = cfg.BigTimer == true, func = function() cfg.BigTimer = not cfg.BigTimer; L.Refresh() end },
    { text = "Always show next money milestone", checked = cfg.AlwaysShowMoney == true, func = function() cfg.AlwaysShowMoney = not cfg.AlwaysShowMoney; L.Refresh() end },
    { text = "Always show deaths (softcore)", checked = cfg.ShowDeathsSoftcore ~= false, func = function() cfg.ShowDeathsSoftcore = (cfg.ShowDeathsSoftcore == false); L.Refresh() end },
    { text = "Show Played clock", checked = cfg.Clock == "PLAYED", func = function() cfg.Clock = cfg.Clock == "PLAYED" and "ACTIVE" or "PLAYED"; ST.Compare.Invalidate(); L.Refresh() end },
  }
  -- Section 3: windows.
  local windows = {
    { separator = true },
    { text = "History", func = function() ST.History.Toggle() end },
    { text = "Import reference run...", func = function() ST.Reference.ShowImport() end },
    { text = "Settings", func = function() ST.Config.Open() end },
    { text = "Hide", func = function() L.HideByUser() end },
  }
  for _, it in ipairs(settings) do items[#items + 1] = it end
  for _, it in ipairs(windows) do items[#items + 1] = it end
  T.ShowMenu(anchor, items)
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
  -- A deliberate show restarts the auto-hide countdown (so the window does not vanish instantly).
  if show and ST.AutoHide then ST.AutoHide.Trigger("toggle") end
end

-- Auto-hide show/hide: transient visibility that leaves Config.Shown (the user's choice) alone.
function L.ShowTransient()
  if not frame then return end
  if Cfg().Shown ~= false and not frame:IsShown() then frame:Show(); L.Refresh() end
end
function L.HideTransient()
  if frame then frame:Hide() end
end

-- Context menu "Hide": hide and stop auto-hide from bringing it back (Config.Shown = false).
function L.HideByUser()
  L.Toggle(false)
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
