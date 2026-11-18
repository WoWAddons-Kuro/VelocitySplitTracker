-- Auto-hide: the split window hides itself Config.AutoHide_Seconds after the last trigger and
-- reappears on the triggers the player opted into (a split reached on a chosen axis, or an
-- upcoming split on a chosen axis becoming "near"). 0 seconds = never hide (the default).
--
-- Auto-hide is a TRANSIENT state: Config.Shown stays true. A manual toggle (/split, minimap,
-- menu) shows the window and restarts the timer like any other trigger.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local D = ST.Data

ST.AutoHide = {}
local A = ST.AutoHide

-- Milestone axis -> settings axis. Axes not listed never trigger the window.
A.AxisGroup = {
  level = "level",
  quest = "quest", questaccept = "quest",
  skill = "skill", learn = "skill",
  gold  = "gold",
  zone  = "zone", area = "zone",
}
A.Groups = { "level", "quest", "skill", "gold", "zone" }
A.GroupLabel = { level = "Level", quest = "Quest", skill = "Professions", gold = "Money", zone = "Zone" }

local function Cfg() return ST.db.Config end

function A.Seconds() return tonumber(Cfg().AutoHide_Seconds) or 0 end
function A.Enabled() return A.Seconds() > 0 end

local function ReachedOn(group)  local t = Cfg().AutoHide_ShowOnReached; return t and t[group] == true end
local function NearOn(group)     local t = Cfg().AutoHide_ShowNearAxes; return Cfg().AutoHide_ShowNearUpcoming == true and t and t[group] == true end

------------------------------------------------------------------------
-- Timer
------------------------------------------------------------------------
local hideTimer
A.Hidden = false   -- true while hidden BY auto-hide (not by the user)

local function CancelTimer() if hideTimer then hideTimer:Cancel(); hideTimer = nil end end

-- Show the window (if the user has it enabled) and (re)start the hide countdown.
function A.Trigger(reason)
  if not A.Enabled() then return end
  if Cfg().Shown == false then return end   -- user hid it on purpose; never override
  if ST.Live then ST.Live.ShowTransient() end
  A.Hidden = false
  CancelTimer()
  hideTimer = C_Timer.NewTimer(A.Seconds(), function()
    hideTimer = nil
    if not A.Enabled() or Cfg().Shown == false then return end
    A.Hidden = true
    if ST.Live then ST.Live.HideTransient() end
  end)
end

-- Settings changed: 0 seconds -> make sure the window is back; >0 -> arm the countdown.
function A.Apply()
  if not A.Enabled() then
    CancelTimer(); A.Hidden = false
    if ST.Live and Cfg().Shown ~= false then ST.Live.ShowTransient() end
  else
    A.Trigger("apply")
  end
end

------------------------------------------------------------------------
-- Triggers
------------------------------------------------------------------------
-- A real (non-inferred) split was recorded.
function A.OnHit(key)
  if not A.Enabled() then return end
  local axis = D.ParseKey(key)
  local group = axis and A.AxisGroup[axis]
  if group and ReachedOn(group) then A.Trigger("reached:" .. key) end
end

-- Called from the view refresh with the upcoming rows. A row is "near" when the view marks it
-- Sticky (quest complete-in-log, profession within NearPct / trainable, money near, area/learn by
-- time) or, for the level row, when XP is at/over Attention_NearPct. Each key triggers once.
local nearSeen = {}
function A.CheckNear(upcoming)
  if not A.Enabled() or Cfg().AutoHide_ShowNearUpcoming ~= true then return end
  local nearPct = Cfg().Attention_NearPct or D.Attention_NearPct
  local present = {}
  for _, it in ipairs(upcoming or {}) do
    local group = A.AxisGroup[it.Axis]
    local near = it.Sticky or (it.Axis == "level" and (it.Progress or 0) >= nearPct)
    if group and near then
      present[it.Key] = true
      if not nearSeen[it.Key] and NearOn(group) then
        nearSeen[it.Key] = true
        A.Trigger("near:" .. it.Key)
      end
    end
  end
  -- forget keys that are no longer near so they can trigger again later (e.g. profession cap lifted)
  for k in pairs(nearSeen) do if not present[k] then nearSeen[k] = nil end end
end
