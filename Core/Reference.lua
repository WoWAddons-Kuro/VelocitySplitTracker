-- Reference runs: imported split tables (a VOD, another player's export) stored as ordinary
-- character records flagged CharacterRun_Reference = true, so History, the pivots and the
-- comparison engine treat them like any other run. Key = "ref:<slug>".
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local U = ST.Util
local D = ST.Data

ST.Reference = {}
local R = ST.Reference

local function Slug(s) return (s:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")) end

-- "1:32" / "41:53" / "1:02:05" / "95" -> seconds, or nil
function R.ParseTime(s)
  if not s then return nil end
  s = s:match("^%s*(.-)%s*$")
  local h, m, sec = s:match("^(%d+):(%d+):(%d+)$")
  if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec) end
  m, sec = s:match("^(%d+):(%d+)$")
  if m then return tonumber(m) * 60 + tonumber(sec) end
  local n = tonumber(s)
  return n
end

-- Parse the import text. Grammar (whitespace / newlines / ; / , separated tokens):
--   name="Human Pally 55m"   zone="Elwynn Forest"   class=PALADIN   mode=pve   pattern="no-ah"
--   level:4=7:58   (any milestone key = time)   or shorthand   4=7:58  /  L4 7:58  /  "level 4 - 7:58"
-- Returns spec { Name, Zone, Class, Mode, Pattern, Splits = { [key] = seconds } }, or nil + error.
function R.ParseText(text)
  local spec = { Splits = {} }
  -- key="quoted value" / key=value
  for k, v in text:gmatch('(%a+)%s*=%s*"([^"]*)"') do spec[k:lower()] = v end
  local stripped = text:gsub('(%a+)%s*=%s*"[^"]*"', " ")
  for k, v in stripped:gmatch("(%a+)%s*=%s*([^%s;,]+)") do
    local lk = k:lower()
    if lk == "name" or lk == "zone" or lk == "class" or lk == "mode" or lk == "pattern" then spec[lk] = v end
  end
  -- explicit milestone keys: axis:id[:value]=time
  for key, t in stripped:gmatch("([%a]+:[%w_%.%-/]+)%s*=%s*([%d:%.]+)") do
    local secs = R.ParseTime(t)
    if secs then spec.Splits[key] = secs end
  end
  -- shorthand level lines: "level 4 - 7:58", "L4 7:58", "4=7:58", "4: 7:58"
  for line in (stripped .. "\n"):gmatch("([^\n;]+)") do
    local lvl, t = line:match("^%s*[Ll]?[Ee]?[Vv]?[Ee]?[Ll]?%s*(%d%d?)%s*[-=:%s]%s*([%d:]+)%s*$")
    if lvl and t and tonumber(lvl) >= 2 and tonumber(lvl) <= D.MaxLevel then
      local secs = R.ParseTime(t)
      if secs then spec.Splits[D.Key("level", tonumber(lvl))] = secs end
    end
  end
  local n = 0; for _ in pairs(spec.Splits) do n = n + 1 end
  if n == 0 then return nil, "no splits found (expected lines like 'level 4 - 7:58' or 'level:4=7:58')" end
  if not spec.name or spec.name == "" then return nil, 'missing name="..."' end
  spec.Name, spec.Zone, spec.Class, spec.Mode, spec.Pattern = spec.name, spec.zone or "Unknown", (spec.class or "ANY"):upper(), spec.mode or "unknown", spec.pattern
  return spec
end

-- Create (or replace) the reference record from a parsed spec. Returns the record key.
function R.Import(spec)
  local key = "ref:" .. Slug(spec.Name)
  local rec = {
    CharacterRun_Key = key,
    CharacterRun_Reference = true,
    CharacterRun_Name = spec.Name,
    CharacterRun_Realm = "reference",
    CharacterRun_ClassFile = spec.Class ~= "ANY" and spec.Class or "UNKNOWN",
    CharacterRun_Race = nil,
    CharacterRun_Mode = spec.Mode,
    CharacterRun_StartZone = spec.Zone,
    CharacterRun_Pattern = spec.Pattern,
    CharacterRun_CreatedAt = time(),
    CharacterRun_Frozen = false,
    CharacterRun_Level = 1,
    PlayedSeconds_Total = 0, ActiveSeconds_Total = 0,
    Milestones = {},
  }
  local maxTime, maxLevel = 0, 1
  for mkey, secs in pairs(spec.Splits) do
    -- a reference time is one number; it stands for both clocks
    rec.Milestones[mkey] = { Played = secs, Active = secs, At = time(), Label = nil }
    local axis, id, value = D.ParseKey(mkey)
    if axis == "level" then
      rec.Milestones[mkey].Label = "Level " .. id
      if tonumber(id) > maxLevel then maxLevel = tonumber(id) end
    elseif axis == "area" then
      -- "Dun_Morogh/Coldridge_Pass" -> "Enter Coldridge Pass"; "Dun_Morogh/" -> "Enter Dun Morogh"
      local zone, sub = tostring(id):match("^(.-)/(.*)$")
      local name = (sub and sub ~= "") and sub or (zone or tostring(id))
      rec.Milestones[mkey].Label = "Enter " .. name:gsub("_", " ")
    elseif axis == "skill" then rec.Milestones[mkey].Label = tostring(id):gsub("_", " ") .. " " .. tostring(value)
    elseif axis == "learn" then rec.Milestones[mkey].Label = "Learned " .. tostring(id):gsub("_", " ")
    elseif axis == "kill" then rec.Milestones[mkey].Label = tostring(value or id):gsub("_", " ")
    elseif axis == "gold" then rec.Milestones[mkey].Label = "Money Acquired - " .. D.FormatCopper(tonumber(id) or 0, true)
    end
    if secs > maxTime then maxTime = secs end
  end
  rec.CharacterRun_Level = maxLevel
  rec.PlayedSeconds_Total, rec.ActiveSeconds_Total = maxTime, maxTime
  if maxLevel >= D.MaxLevel then rec.CharacterRun_Frozen = true end
  ST.db.Characters[key] = rec
  ST.Compare.Invalidate()
  if ST.Live then ST.Live.Refresh() end
  if ST.History then ST.History.Refresh() end
  return key
end

function R.IsReference(rec) return rec and rec.CharacterRun_Reference == true end

------------------------------------------------------------------------
-- Import window: a multi-line edit box + Import button
------------------------------------------------------------------------
local frame
function R.ShowImport(prefill)
  if not frame then
    local T = ST.Theme
    frame = CreateFrame("Frame", "SplitTimerImportWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(520, 360)
    frame:SetPoint("CENTER")
    -- Above the data window (DIALOG) so it is neither interleaved with it nor loses clicks to it.
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
      frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      frame:SetBackdropColor(0.06, 0.06, 0.06, 0.97); frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
    -- explicit background too, in case the backdrop mixin is absent on this client
    frame.bg = frame:CreateTexture(nil, "BACKGROUND"); frame.bg:SetAllPoints(); frame.bg:SetColorTexture(0.06, 0.06, 0.06, 0.97)
    tinsert(UISpecialFrames, "SplitTimerImportWindow")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
    local title = T.Text(frame, 16); title:SetPoint("TOPLEFT", 12, -10); title:SetText("Import reference run")
    local hint = T.Text(frame, T.FontSize - 1); hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4); hint:SetPoint("RIGHT", -12, 0)
    hint:SetJustifyH("LEFT"); T.SetColour(hint, T.Colour.TextDim)
    hint:SetText('One header line, then one split per line.  name="..." zone="..." class=PALADIN mode=pve   |   level 4 - 7:58   or   level:4=7:58')
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -52); scroll:SetPoint("BOTTOMRIGHT", -30, 44)
    -- visible text-field background behind the scroll area
    local fieldBg = frame:CreateTexture(nil, "BORDER"); fieldBg:SetPoint("TOPLEFT", scroll, -4, 4); fieldBg:SetPoint("BOTTOMRIGHT", scroll, 4, -4); fieldBg:SetColorTexture(0, 0, 0, 0.5)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(470); edit:SetHeight(260)
    edit:SetTextInsets(4, 4, 4, 4)
    edit:EnableMouse(true)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- clicking anywhere in the field focuses the box (a multi-line EditBox only takes focus on its text)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    scroll:SetScrollChild(edit)
    frame.edit = edit
    local status = T.Text(frame, T.FontSize - 1); status:SetPoint("BOTTOMLEFT", 12, 14); status:SetPoint("RIGHT", -130, 0); status:SetJustifyH("LEFT")
    frame.status = status
    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetSize(100, 22); btn:SetPoint("BOTTOMRIGHT", -12, 10); btn:SetText("Import")
    btn:SetScript("OnClick", function()
      local spec, err = R.ParseText(edit:GetText() or "")
      if not spec then status:SetText("|cffff4040" .. err .. "|r"); return end
      local key = R.Import(spec)
      local n = 0; for _ in pairs(spec.Splits) do n = n + 1 end
      status:SetText(string.format("|cff5ad65aImported '%s' (%d splits) as %s|r", spec.Name, n, key))
    end)
  end
  if prefill then frame.edit:SetText(prefill) end
  frame:Show(); frame.edit:SetFocus()
end
