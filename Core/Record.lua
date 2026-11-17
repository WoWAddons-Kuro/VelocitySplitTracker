-- The per-character run record in SplitTimerDB.Characters and the single
-- entry point for recording a milestone.
local ADDON_NAME, ST = ...
local U = ST.Util
local D = ST.Data

ST.Record = {}
local R = ST.Record

-- Returns (and creates on first sight) the record for the logged-in character.
function R.Current()
  if R._current then return R._current end
  local key = U.CharacterKey()
  local rec = ST.db.Characters[key]
  if not rec then
    local _, raceFile = UnitRace("player")
    local _, classFile = UnitClass("player")
    rec = {
      CharacterRun_Key = key,
      CharacterRun_Name = UnitName("player"),
      CharacterRun_Realm = GetRealmName(),
      CharacterRun_ClassFile = classFile,
      CharacterRun_Race = raceFile,
      CharacterRun_StartZone = D.RaceStartZone[raceFile] or "Unknown",
      CharacterRun_Pattern = nil,
      CharacterRun_CreatedAt = time(),
      CharacterRun_Frozen = false,
      CharacterRun_Level = UnitLevel("player"),
      PlayedSeconds_Total = 0,
      PlayedSeconds_SyncedAt = nil,
      ActiveSeconds_Total = nil,   -- nil until Clock initialises it from /played
      Milestones = {},
    }
    ST.db.Characters[key] = rec
  end
  rec.CharacterRun_Level = UnitLevel("player")
  R._current = rec
  return rec
end

-- Record a milestone once. Returns true if newly recorded.
-- extra: { Label=, Inferred=bool }
function R.Hit(key, label, extra)
  local rec = R.Current()
  if rec.CharacterRun_Frozen then return false end
  if rec.Milestones[key] then return false end
  local played, active = ST.Clock.Now()
  local m = { Played = played, Active = active, At = time(), Label = label }
  if extra and extra.Inferred then m.Inferred = true end
  rec.Milestones[key] = m
  local axis, id = D.ParseKey(key)
  if axis == "level" and tonumber(id) >= D.MaxLevel then
    rec.CharacterRun_Frozen = true
  end
  if not m.Inferred then
    local best = ST.Compare.Best(key)
    local deltaText = ""
    if best then
      local delta = active - best
      deltaText = string.format("  (%s%s vs best)", delta < 0 and "|cff4ccf4c" or "|cffe64c4c", U.FormatDelta(delta) .. "|r")
    end
    U.Print("%s  %s%s", label or key, U.FormatTime(active), deltaText)
  end
  ST.Clock.Activity()
  if ST.Live then ST.Live.Refresh() end
  return true
end

function R.Has(key)
  return R.Current().Milestones[key] ~= nil
end

-- Mark levels below the current one that were never recorded (addon installed
-- mid-run, or missed events). They carry the current clocks and Inferred=true.
function R.ReconcileLevels()
  local rec = R.Current()
  local level = UnitLevel("player")
  for n = 2, level do
    local key = D.Key("level", n)
    if not rec.Milestones[key] then R.Hit(key, "Level " .. n, { Inferred = true }) end
  end
end
