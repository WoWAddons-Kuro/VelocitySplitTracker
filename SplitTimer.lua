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
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
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
  elseif cmd == "status" then
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version")
    U.Print("version %s | character %s | clock %s | times %s", tostring(version), U.CharacterKey(), ST.db.Config.Clock, ST.db.Config.TimesSide)
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
  elseif event == "PLAYER_LOGIN" then
    ST.Live.Create()
    ST.Live.Toggle(ST.db.Config.Shown ~= false)
  end
end)
