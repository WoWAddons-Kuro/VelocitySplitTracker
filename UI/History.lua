-- History window: list of recorded characters/runs and their milestone detail.
-- Placeholder layout for now; real data comes with Core/Compare.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local T = ST.Theme
local U = ST.Util

ST.History = {}
local H = ST.History

local frame

local MOCK_RUNS = {
  { Name = "Kuro",     Class = "Hunter",  Zone = "Teldrassil", Level = 23, Pattern = "default",             Active = 4376,  Played = 6012,  PB = true  },
  { Name = "Kurodru",  Class = "Druid",   Zone = "Teldrassil", Level = 60, Pattern = "darkshore+ashenvale", Active = 17494, Played = 23011, PB = true, Frozen = true },
  { Name = "Kurowar",  Class = "Warrior", Zone = "Elwynn Forest", Level = 12, Pattern = "default",          Active = 1900,  Played = 2400,  PB = false },
}

function H.Create()
  if frame then return frame end
  frame = CreateFrame("Frame", "SplitTimerHistoryWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(640, 400)
  frame:SetPoint("CENTER")
  frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
  frame:SetFrameStrata("DIALOG")
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnShow", function() H.Refresh() end)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
  end
  tinsert(UISpecialFrames, "SplitTimerHistoryWindow")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  frame.title = T.Text(frame, 16)
  frame.title:SetPoint("TOPLEFT", 12, -10)
  frame.title:SetText("SplitTimer - History")

  frame.hint = T.Text(frame, T.FontSize - 1)
  frame.hint:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
  T.SetColour(frame.hint, T.Colour.TextDim)
  frame.hint:SetText("Every character is recorded automatically. Select a run to see its milestones; name a run to make it a route pattern.")

  -- left: run list
  local list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", 12, -52)
  list:SetPoint("BOTTOMLEFT", 12, 12)
  list:SetWidth(330)
  frame.list = list
  list.header = T.Text(list, T.FontSize - 1)
  list.header:SetPoint("TOPLEFT")
  T.SetColour(list.header, T.Colour.TextDim)
  list.header:SetText("Character        Zone / Class             Lvl   Active   Pattern")
  list.rows = {}

  -- right: detail
  local detail = CreateFrame("Frame", nil, frame)
  detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)
  detail:SetPoint("BOTTOMRIGHT", -12, 12)
  detail.bg = T.Texture(detail, T.Colour.RowAlt); detail.bg:SetAllPoints()
  frame.detail = detail
  detail.text = T.Text(detail, T.FontSize)
  detail.text:SetPoint("TOPLEFT", 8, -8)
  detail.text:SetPoint("BOTTOMRIGHT", -8, 8)
  detail.text:SetJustifyH("LEFT"); detail.text:SetJustifyV("TOP")
  detail.text:SetText("|cff999999Select a run.|r")

  return frame
end

local function RowText(r)
  local pb = r.PB and "|cfff2cc40*|r " or "  "
  local frozen = r.Frozen and " |cff8888aa(60)|r" or ""
  return string.format("%s%-14s %-12s %-9s %3d  %8s  %s%s", pb, r.Name, r.Zone, r.Class, r.Level, U.FormatTime(r.Active), r.Pattern, frozen)
end

function H.Refresh()
  if not frame then return end
  local list = frame.list
  for i, r in ipairs(MOCK_RUNS) do
    local row = list.rows[i]
    if not row then
      row = CreateFrame("Button", nil, list)
      row:SetHeight(T.RowHeight)
      row:SetPoint("TOPLEFT", 0, -16 - (i - 1) * T.RowHeight)
      row:SetPoint("TOPRIGHT", 0, -16 - (i - 1) * T.RowHeight)
      row.bg = T.Texture(row, T.Colour.RowAlt); row.bg:SetAllPoints(); row.bg:SetShown(i % 2 == 0)
      row.hl = T.Texture(row, T.Colour.RowCurrent, "HIGHLIGHT"); row.hl:SetAllPoints()
      row.text = T.Text(row, T.FontSize)
      row.text:SetPoint("LEFT", 4, 0)
      row.text:SetFont("Fonts\\ARIALN.TTF", T.FontSize, "")
      list.rows[i] = row
    end
    row.text:SetText(RowText(r))
    row:SetScript("OnClick", function() H.ShowDetail(r) end)
    row:Show()
  end
end

function H.ShowDetail(r)
  local lines = {
    string.format("|cffffffff%s|r  %s %s  -  %s", r.Name, r.Zone, r.Class, r.Pattern),
    string.format("Level %d   Active %s   Played %s", r.Level, U.FormatTime(r.Active), U.FormatTime(r.Played)),
    "",
    "|cff999999Milestone table goes here:|r",
    "Level 10        1:02:53   seg 9:41    -0:31",
    "Vagash          1:04:01             +1:10",
    "Skinning 100    1:09:33             -0:04",
    "",
    "|cff999999[Name pattern...]  [Clear pattern]  [Delete run]  [Copy as text]|r",
  }
  frame.detail.text:SetText(table.concat(lines, "\n"))
end

function H.Toggle()
  H.Create()
  frame:SetShown(not frame:IsShown())
end
