-- Bootstrap: saved variables, slash commands, minimap button, event wiring.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local U = ST.Util
-- (load phase set on the ADDON_NAME line)

_G.Velocity = ST

local DB_VERSION = 1

local DEFAULT_CONFIG = {
  Shown = true,
  Locked = false,
  TimesSide = "RIGHT",   -- "LEFT" | "RIGHT"
  Clock = "ACTIVE",      -- "ACTIVE" | "PLAYED"
  BigTimer = false,      -- large LiveSplit-style timer with tenths; off = compact row
  AlwaysShowMoney = true, -- pin the next money milestone as the last upcoming row
  RowsDone = 4,
  RowsUpcoming = 6,
  Scale = 1,
  BgAlpha = 0.85,
  Position = nil,
  Minimap = { hide = false },
}

local function InitDB()
  -- One-time migration from the addon's previous name (SplitTimer): adopt the old DB if the
  -- new one is empty. The old global is left untouched so nothing is lost if this is rolled back.
  if type(VelocitySplitTrackerDB) ~= "table" or next(VelocitySplitTrackerDB) == nil then
    if type(SplitTimerDB) == "table" and next(SplitTimerDB) ~= nil then
      VelocitySplitTrackerDB = CopyTable and CopyTable(SplitTimerDB) or SplitTimerDB
      print("|cff5ad65aVelocity|r: migrated saved data from SplitTimer")
    else
      VelocitySplitTrackerDB = {}
    end
  end
  local db = VelocitySplitTrackerDB
  db.Version = db.Version or DB_VERSION
  db.Config = db.Config or {}
  for k, v in pairs(DEFAULT_CONFIG) do
    if db.Config[k] == nil then
      if type(v) == "table" then
        local copy = {}
        for kk, vv in pairs(v) do copy[kk] = vv end
        db.Config[k] = copy
      else
        db.Config[k] = v
      end
    end
  end
  db.Characters = db.Characters or {}
  db.Plans = db.Plans or {}
  ST.db = db
end

local function SetupMinimap()
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  local Icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (LDB and Icon) then return end
  local obj = LDB:NewDataObject("Velocity", {
    type = "launcher",
    icon = "Interface\\AddOns\\VelocitySplitTracker\\Assets\\VelocitySplitTracker_Icon.tga",
    OnClick = function(_, button)
      if button == "RightButton" then ST.DataWindow.Toggle()
      elseif button == "MiddleButton" then ST.Config.Open()
      else ST.Live.Toggle() end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("Velocity")
      tt:AddLine("|cffffffffLeft-click|r toggle split window", 0.8, 0.8, 0.8)
      tt:AddLine("|cffffffffRight-click|r data window (pivots / history)", 0.8, 0.8, 0.8)
      tt:AddLine("|cffffffffMiddle-click|r settings", 0.8, 0.8, 0.8)
    end,
  })
  Icon:Register("Velocity", obj, ST.db.Config.Minimap)
end

local function Slash(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  if cmd == "" then ST.Live.Toggle()
  elseif cmd == "history" then ST.DataWindow.Toggle(rest ~= "" and rest or nil)
  elseif cmd == "config" or cmd == "settings" or cmd == "options" then ST.Config.Open()
  elseif cmd == "lock" then ST.db.Config.Locked = not ST.db.Config.Locked; U.Print("window %s", ST.db.Config.Locked and "locked" or "unlocked")
  elseif cmd == "reset" then ST.db.Config.Position = nil; ST.Live.Create(); ST.Live.RestorePosition(); U.Print("position reset")
  elseif cmd == "pause" then ST.Clock.SetPaused(true)
  elseif cmd == "resume" then ST.Clock.SetPaused(false)
  elseif cmd == "clock" then
    if rest == "played" or rest == "active" then ST.db.Config.Clock = rest:upper(); ST.Compare.Invalidate(); ST.Live.Refresh() end
    U.Print("clock: %s", ST.db.Config.Clock)
  elseif cmd == "hit" then
    if rest == "" then U.Print("usage: /split hit <name>") else
      local slug = rest:gsub("%s+", "_")
      ST.Record.Hit("manual:" .. slug, rest)
    end
  elseif cmd == "pattern" then StaticPopup_Show("VELOCITY_NAME_PATTERN")
  elseif cmd == "played" then ST.Clock.RequestPlayed()
  elseif cmd == "wipe" then StaticPopup_Show("VELOCITY_WIPE_RUN")
  elseif cmd == "key" then U.Print("record key: %s  (name-realm: %s)", tostring(ST.Record.KeyFor_Player()), U.CharacterKey())
  elseif cmd == "import" or cmd == "ref" then ST.Reference.ShowImport()
  elseif cmd == "anyzone" then ST.db.Config.CompareAnyZone = not ST.db.Config.CompareAnyZone; ST.Compare.Invalidate(); ST.Live.Refresh(); U.Print("compare across start zones: %s", ST.db.Config.CompareAnyZone and "on" or "off")
  elseif cmd == "mode" then
    -- game mode carried by the run record (travels with exports so others can align categories)
    local valid = { pve = true, pvp = true, ["hardcore-pve"] = true, ["hardcore-pvp"] = true }
    if rest == "auto" or rest == "clear" then ST.db.Config.ModeOverride = nil
    elseif valid[rest] then ST.db.Config.ModeOverride = rest
    elseif rest ~= "" then U.Print("usage: /split mode pve | pvp | hardcore-pve | hardcore-pvp | auto") return end
    local rec = ST.Record.Current()
    rec.CharacterRun_Mode = ST.Record.DetectMode()
    ST.Compare.Invalidate(); if ST.Live then ST.Live.Refresh() end
    U.Print("game mode: %s%s  (realm '%s')", rec.CharacterRun_Mode, ST.db.Config.ModeOverride and "  [override]" or "  [detected]", GetRealmName() or "?")
  elseif cmd == "rows" then
    -- diagnostic: what the view is producing right now
    local V = ST.View.Build()
    U.Print("upcoming rows (%d):", #V.Upcoming)
    for i, it in ipairs(V.Upcoming) do print(string.format("  %d. [%s] %s%s%s", i, it.Axis, it.Label, it.Sticky and "  sticky" or "", it.LastProgress and ("  progressed " .. (time() - it.LastProgress) .. "s ago") or "")) end
    print(string.format("  cap=%s  AlwaysShowMoney=%s", tostring(ST.db.Config.RowsUpcoming), tostring(ST.db.Config.AlwaysShowMoney)))
  elseif cmd == "skills" then
    -- diagnostic: which profession API path is in use and what it returns
    local api = string.format("GetSkillLineInfo=%s GetProfessions=%s", tostring(GetSkillLineInfo ~= nil), tostring(GetProfessions ~= nil))
    local list = ST.Milestones.Skills()
    U.Print("skill API: %s, tracked skills found: %d", api, #list)
    for _, s in ipairs(list) do
      print(string.format("  %s %d/%d%s", s.Name, s.Rank or -1, s.Max or -1, ST.Milestones.SkillIsActive(s.Name) and "  (active)" or ""))
    end
  elseif cmd == "ms" then
    -- diagnostic: every recorded milestone for this character (key, clocks, inferred flag)
    local rec = ST.Record.Current()
    local keys = {}
    for k in pairs(rec.Milestones) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return (rec.Milestones[a].Active or 0) < (rec.Milestones[b].Active or 0) end)
    U.Print("%d milestones for %s (level %d):", #keys, rec.CharacterRun_Key, UnitLevel("player"))
    for _, k in ipairs(keys) do
      local m = rec.Milestones[k]
      if rest == "" or k:find(rest, 1, true) then
        print(string.format("  %-22s active %-9s played %-9s %s %s", k, U.FormatTime(m.Active), U.FormatTime(m.Played), m.Inferred and "|cff888888INFERRED|r" or "", m.Label or ""))
      end
    end
  elseif cmd == "cpu" then
    -- Top addons by CPU since last /reload. Needs: /console scriptProfile 1 + /reload.
    if GetCVar("scriptProfile") ~= "1" then
      U.Print("profiling is off. Run: /console scriptProfile 1  then /reload, play a bit, then /split cpu again. Turn off afterwards with scriptProfile 0.")
      return
    end
    UpdateAddOnCPUUsage()
    local numAddons = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)
    local rows = {}
    for i = 1, numAddons do
      local name = getInfo(i)
      local ms = GetAddOnCPUUsage(i)
      if ms and ms > 0 then rows[#rows + 1] = { name, ms } end
    end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    U.Print("CPU ms since reload (top %d):", math.min(12, #rows))
    for i = 1, math.min(12, #rows) do print(string.format("  %8.0f ms  %s", rows[i][2], rows[i][1])) end
    local mine = GetAddOnCPUUsage("SplitTimer")
    if mine then print(string.format("  SplitTimer frame OnUpdate share: %.0f ms", mine)) end
  elseif cmd == "icon" then
    -- dev helper: try an icon name on the minimap button, e.g. /split icon INV_Misc_Orb_05
    local Icon = LibStub and LibStub("LibDBIcon-1.0", true)
    local path = "Interface\\Icons\\" .. rest
    if Icon and Icon:GetMinimapButton("SplitTimer") then Icon:GetMinimapButton("SplitTimer").icon:SetTexture(path) end
    U.Print("minimap icon set to %s", path)
  elseif cmd == "status" then
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version")
    U.Print("version %s | character %s | race %s -> %s | clock %s | times %s", tostring(version), U.CharacterKey(), tostring(ST.Record.Current().CharacterRun_Race), tostring(ST.Record.Current().CharacterRun_StartZone), ST.db.Config.Clock, ST.db.Config.TimesSide)
  else
    U.Print("/split - toggle window | history | config | lock | reset | status")
  end
end

local f = CreateFrame("Frame")
ST.Probe = "load:SplitTimer.lua:frame"
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
-- Diagnostic: name the protected function when the client blocks us (taint hunting).
pcall(f.RegisterEvent, f, "ADDON_ACTION_BLOCKED")
pcall(f.RegisterEvent, f, "ADDON_ACTION_FORBIDDEN")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    local addonName, func = arg1, arg2
    if addonName == ADDON_NAME then U.Print("|cffff4040%s|r blocked call: %s  during stage: %s", event, tostring(func), tostring(ST.Probe)) end
    return
  end
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    local function Stage(name, fn)
      local ok, err = pcall(U.InPhase, "ADDON_LOADED:" .. name, fn)
      if not ok then U.Print("|cffff4040%s failed:|r %s", name, tostring(err)) end
    end
    Stage("InitDB", InitDB)
    Stage("Slash", function()
      SLASH_SPLITTIMER1 = "/split"
      SLASH_SPLITTIMER2 = "/velocity"
      SlashCmdList.SPLITTIMER = Slash
    end)
    Stage("ConfigPanel", ST.Config.Create)
    Stage("Minimap", SetupMinimap)
    Stage("Popup", function()
      StaticPopupDialogs["VELOCITY_NAME_PATTERN"] = {
        text = "Name this run's route pattern (blank = default):",
        button1 = OKAY, button2 = CANCEL,
        hasEditBox = true, maxLetters = 40,
        OnShow = function(self) self.editBox:SetText(ST.Record.Current().CharacterRun_Pattern or "") end,
        OnAccept = function(self)
          local name = self.editBox:GetText():match("^%s*(.-)%s*$")
          ST.Record.Current().CharacterRun_Pattern = (name ~= "" and name ~= "default") and name or nil
          ST.Compare.Invalidate(); ST.Live.Refresh()
        end,
        EditBoxOnEnterPressed = function(self) local p = self:GetParent(); p.button1:Click() end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
      }
      StaticPopupDialogs["VELOCITY_WIPE_RUN"] = {
        text = "Discard ALL recorded splits and clocks for this character and start a fresh record?",
        button1 = "Wipe", button2 = CANCEL,
        OnAccept = function() ST.Record.WipeCurrent(); U.Print("record wiped; fresh record started") end,
        timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
      }
      StaticPopupDialogs["VELOCITY_ADD_LOCATION"] = {
        text = "Name this location split (blank = zone + coordinates). It triggers the first time a character of this start zone comes within 10 yards.",
        button1 = "Add", button2 = CANCEL,
        hasEditBox = true, maxLetters = 40,
        OnShow = function(self)
          local w = ST.Record.WhereNow()
          self.editBox:SetText(w and w.Zone and (GetSubZoneText() ~= "" and GetSubZoneText() or w.Zone) or "")
          self.editBox:HighlightText()
        end,
        OnAccept = function(self) ST.Locations.AddHere(self.editBox:GetText()); if ST.Live then ST.Live.Refresh() end end,
        EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
      }
    end)
  elseif event == "PLAYER_LOGIN" then
    -- Each stage is isolated: a failure in one must not stop the window from being created,
    -- and must be visible in chat rather than silently swallowed.
    local function Stage(name, fn)
      local ok, err = pcall(U.InPhase, "PLAYER_LOGIN:" .. name, fn)
      if not ok then U.Print("|cffff4040%s failed:|r %s", name, tostring(err)) end
    end
    Stage("Record", ST.Record.Current)
    Stage("Clock", ST.Clock.Init)
    Stage("Milestones", ST.Milestones.Init)
    Stage("Locations", ST.Locations.Init)
    Stage("Window", ST.Live.Create)   -- applies Config.Shown itself
  end
end)
ST.Probe = nil  -- end of file-load phase for SplitTimer.lua
