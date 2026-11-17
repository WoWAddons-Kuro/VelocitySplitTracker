-- Bootstrap: saved variables, slash commands, minimap button, event wiring.
local ADDON_NAME, ST = ...
local U = ST.Util

_G.SplitTimer = ST

local DB_VERSION = 1

local DEFAULT_CONFIG = {
  Shown = true,
  Locked = false,
  TimesSide = "RIGHT",   -- "LEFT" | "RIGHT"
  Clock = "ACTIVE",      -- "ACTIVE" | "PLAYED"
  BigTimer = false,      -- large LiveSplit-style timer with tenths; off = compact row
  RowsDone = 4,
  RowsUpcoming = 4,
  Scale = 1,
  BgAlpha = 0.85,
  Position = nil,
  Minimap = { hide = false },
}

local function InitDB()
  if type(SplitTimerDB) ~= "table" then SplitTimerDB = {} end
  local db = SplitTimerDB
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
  local obj = LDB:NewDataObject("SplitTimer", {
    type = "launcher",
    icon = "Interface\\Icons\\Inv_helm_armor_pirateeyepatch_b_01_green",
    OnClick = function(_, button)
      if button == "RightButton" then ST.History.Toggle()
      elseif button == "MiddleButton" then ST.Config.Open()
      else ST.Live.Toggle() end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("SplitTimer")
      tt:AddLine("|cffffffffLeft-click|r toggle split window", 0.8, 0.8, 0.8)
      tt:AddLine("|cffffffffRight-click|r history", 0.8, 0.8, 0.8)
      tt:AddLine("|cffffffffMiddle-click|r settings", 0.8, 0.8, 0.8)
    end,
  })
  Icon:Register("SplitTimer", obj, ST.db.Config.Minimap)
end

local function Slash(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  if cmd == "" then ST.Live.Toggle()
  elseif cmd == "history" then ST.History.Toggle()
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
  elseif cmd == "pattern" then StaticPopup_Show("SPLITTIMER_NAME_PATTERN")
  elseif cmd == "played" then ST.Clock.RequestPlayed()
  elseif cmd == "skills" then
    -- diagnostic: which profession API path is in use and what it returns
    local api = (GetProfessions and GetProfessionInfo) and "GetProfessions" or ((GetNumSkillLines and GetSkillLineInfo) and "GetSkillLineInfo" or "none")
    local list = ST.Milestones.Skills()
    U.Print("skill API: %s, tracked skills found: %d", api, #list)
    for _, s in ipairs(list) do
      print(string.format("  %s %d/%d%s", s.Name, s.Rank or -1, s.Max or -1, ST.Milestones.SkillIsActive(s.Name) and "  (active)" or ""))
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
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    InitDB()
    SLASH_SPLITTIMER1 = "/split"
    SLASH_SPLITTIMER2 = "/splittimer"
    SlashCmdList.SPLITTIMER = Slash
    ST.Config.Create()
    SetupMinimap()
    StaticPopupDialogs["SPLITTIMER_NAME_PATTERN"] = {
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
  elseif event == "PLAYER_LOGIN" then
    -- Each stage is isolated: a failure in one must not stop the window from being created,
    -- and must be visible in chat rather than silently swallowed.
    local function Stage(name, fn)
      local ok, err = pcall(fn)
      if not ok then U.Print("|cffff4040%s failed:|r %s", name, tostring(err)) end
    end
    Stage("Record", ST.Record.Current)
    Stage("Clock", ST.Clock.Init)
    Stage("Milestones", ST.Milestones.Init)
    Stage("Window", ST.Live.Create)   -- applies Config.Shown itself
  end
end)
