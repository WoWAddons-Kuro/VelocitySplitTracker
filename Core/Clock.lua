-- Two clocks per character:
--   Played : server /played total, kept current by local accumulation.
--   Active : /played accumulated only while the character is doing something.
-- See SPEC.md section 2 for the rules.
local ADDON_NAME, ST = ...
local U = ST.Util

ST.Clock = {}
local C = ST.Clock

local IDLE_SECONDS_DEFAULT = 30
local FLUSH_INTERVAL = 15
local TICK = 0.5

-- Played
local playedBase = nil          -- seconds from last TIME_PLAYED_MSG
local playedBaseAt = nil        -- GetTime() when it arrived
local suppressPlayedChat = false

-- Active
local activeRunning = false     -- accumulating right now
local lastActivityAt = nil      -- GetTime() of the latest activity signal
local lastTickAt = nil
local inCombat = false
local userPaused = false
local sinceFlush = 0
local pollAcc = 0

local function Rec() return ST.Record.Current() end
local function IdleSeconds() return (ST.db.Config.IdleSeconds or IDLE_SECONDS_DEFAULT) end

------------------------------------------------------------------------
-- Played
------------------------------------------------------------------------
function C.PlayedNow()
  local rec = Rec()
  if playedBase then return playedBase + (GetTime() - playedBaseAt) end
  -- Not synced yet this session: best effort from the persisted total.
  return rec.PlayedSeconds_Total or 0
end

local function OnTimePlayed(totalSeconds)
  playedBase, playedBaseAt = totalSeconds, GetTime()
  local rec = Rec()
  rec.PlayedSeconds_Total = totalSeconds
  rec.PlayedSeconds_SyncedAt = time()
  if rec.ActiveSeconds_Total == nil then
    -- First time this character is seen by the addon: pre-addon time counts as active.
    rec.ActiveSeconds_Total = totalSeconds
  end
  ST.Record.ReconcileLevels()
  if ST.Live then ST.Live.QueueRefresh() end
end

-- Ask the server without spamming chat with "Total time played".
function C.RequestPlayed()
  suppressPlayedChat = true
  RequestTimePlayed()
end

if ChatFrame_DisplayTimePlayed then
  hooksecurefunc("ChatFrame_DisplayTimePlayed", function() end)
  local orig = ChatFrame_DisplayTimePlayed
  ChatFrame_DisplayTimePlayed = function(...)
    if suppressPlayedChat then suppressPlayedChat = false return end
    return orig(...)
  end
end

------------------------------------------------------------------------
-- Active
------------------------------------------------------------------------
function C.ActiveNow()
  local rec = Rec()
  return rec.ActiveSeconds_Total or C.PlayedNow()
end

-- Both clocks as of now: played, active
function C.Now() return C.PlayedNow(), C.ActiveNow() end

function C.IsRunning() return activeRunning end
function C.IsPaused() return userPaused end

function C.ForcedStop()
  if userPaused then return "paused" end
  if ST.ConfigPanelOpen then return "settings open" end
  if ST.History and ST.History.IsShown and ST.History.IsShown() then return "history open" end
  if UnitIsAFK and UnitIsAFK("player") then return "afk" end
  if Rec().CharacterRun_Frozen then return "frozen" end
  return nil
end

-- Any activity signal lands here.
function C.Activity()
  local now = GetTime()
  lastActivityAt = now
  if not activeRunning and not C.ForcedStop() then
    activeRunning = true
    lastTickAt = now
    if ST.Live then ST.Live.UpdateTimer() end
  end
end

local function StopActive(reason)
  if not activeRunning then return end
  activeRunning = false
  if ST.Live then ST.Live.UpdateTimer() end
end

local function Tick(elapsed)
  local now = GetTime()
  local rec = Rec()
  if rec.ActiveSeconds_Total == nil then return end   -- waiting for /played

  -- combat and movement keep us active without discrete events
  pollAcc = pollAcc + elapsed
  if pollAcc >= 1 then
    pollAcc = 0
    if inCombat or (GetUnitSpeed and GetUnitSpeed("player") > 0) then C.Activity() end
  end

  if activeRunning then
    if C.ForcedStop() then
      StopActive()
    elseif lastActivityAt and (now - lastActivityAt) >= IdleSeconds() then
      -- Went idle: drop the idle window we already counted, then stop.
      rec.ActiveSeconds_Total = rec.ActiveSeconds_Total - (now - lastActivityAt)
      StopActive()
    else
      rec.ActiveSeconds_Total = rec.ActiveSeconds_Total + (now - (lastTickAt or now))
    end
  end
  lastTickAt = now

  sinceFlush = sinceFlush + elapsed
  if sinceFlush >= FLUSH_INTERVAL then
    sinceFlush = 0
    rec.PlayedSeconds_Total = C.PlayedNow()
  end
end

function C.SetPaused(paused)
  userPaused = paused and true or false
  if userPaused then StopActive() else C.Activity() end
  U.Print(userPaused and "active clock paused" or "active clock resumed")
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ACTIVITY_EVENTS = {
  "PLAYER_STARTED_MOVING", "PLAYER_STARTED_TURNING",
  "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
  "MERCHANT_SHOW", "TRAINER_SHOW", "TAXIMAP_OPENED", "LOOT_OPENED", "BANKFRAME_OPENED", "MAIL_SHOW", "TRADE_SHOW",
  "BAG_UPDATE", "PLAYER_TARGET_CHANGED", "AUCTION_HOUSE_SHOW",
}

local frame = CreateFrame("Frame")
function C.Init()
  for _, e in ipairs(ACTIVITY_EVENTS) do pcall(frame.RegisterEvent, frame, e) end
  frame:RegisterEvent("TIME_PLAYED_MSG")
  frame:RegisterEvent("PLAYER_REGEN_DISABLED")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:RegisterEvent("PLAYER_LOGOUT")
  pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
  pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_CHANNEL_START", "player")
  pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SENT", "player")
  frame:SetScript("OnEvent", function(_, event, ...)
    if event == "TIME_PLAYED_MSG" then OnTimePlayed((...))
    elseif event == "PLAYER_REGEN_DISABLED" then inCombat = true; C.Activity()
    elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false; C.Activity()
    elseif event == "PLAYER_LOGOUT" then Rec().PlayedSeconds_Total = C.PlayedNow()
    else C.Activity() end
  end)
  frame:SetScript("OnUpdate", function(_, elapsed) Tick(elapsed) end)
  -- Active starts stopped; the first real activity after login starts it.
  C_Timer.After(2, C.RequestPlayed)
  -- Re-sync /played every 10 minutes to correct any drift.
  C_Timer.NewTicker(600, C.RequestPlayed)
end
