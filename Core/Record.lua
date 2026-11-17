-- The per-character run record in SplitTimerDB.Characters and the single
-- entry point for recording a milestone.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local U = ST.Util
local D = ST.Data

ST.Record = {}
local R = ST.Record

-- Records are keyed by the character GUID (unique per character, account-wide); Name-Realm
-- is kept for display only. Keying by Name-Realm merged two characters that share a name into
-- one record (observed 2026-11-16: inferred levels 12-16 and a foreign /played landed in a
-- level-11 character's record, and then blocked its real Level 10/11 splits).
function R.KeyFor_Player()
  local guid = UnitGUID and UnitGUID("player")
  if guid and guid ~= "" then return guid end
  return U.CharacterKey()   -- fallback: legacy name-realm
end

-- One-time migration: adopt a legacy Name-Realm record for this GUID if no GUID record exists.
local function MigrateLegacyRecord(guidKey)
  local legacyKey = U.CharacterKey()
  local legacy = ST.db.Characters[legacyKey]
  if legacy and legacyKey ~= guidKey and not ST.db.Characters[guidKey] then
    legacy.CharacterRun_Key = guidKey
    legacy.CharacterRun_LegacyKey = legacyKey
    ST.db.Characters[guidKey] = legacy
    ST.db.Characters[legacyKey] = nil
    U.Print("migrated run record for %s to a per-character key", legacyKey)
  end
end

-- Where the player is right now: { Map = uiMapID, X = 0..1, Y = 0..1, Zone = "name" } or nil.
function R.WhereNow()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return nil end
  local where = { Map = mapID }
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  if info then where.Zone = info.name end
  local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
  if pos then
    local ok, x, y = pcall(pos.GetXY, pos)
    if ok and x then where.X, where.Y = math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000 end
  end
  return where
end

-- Returns (and creates on first sight) the record for the logged-in character.
function R.Current()
  if R._current then return R._current end
  local key = R.KeyFor_Player()
  MigrateLegacyRecord(key)
  local rec = ST.db.Characters[key]
  if not rec then
    local _, raceFile = UnitRace("player")
    local _, classFile = UnitClass("player")
    rec = {
      CharacterRun_Key = key,
      CharacterRun_Name = U.CharacterDisplayName(),
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
  -- Keep the display name current (records created before the two-name fix hold only "First").
  local display = U.CharacterDisplayName(); if display and display ~= "?" then rec.CharacterRun_Name = display end
  -- Self-heal: if the race wasn't in the table when first seen, try again each login.
  if rec.CharacterRun_StartZone == "Unknown" or not rec.CharacterRun_StartZone then
    local _, raceFile = UnitRace("player")
    rec.CharacterRun_Race = raceFile
    rec.CharacterRun_StartZone = D.RaceStartZone[raceFile] or "Unknown"
  end
  R._current = rec
  return rec
end

-- Record a milestone once. Returns true if newly recorded.
-- extra: { Label=, Inferred=bool }
function R.Hit(key, label, extra)
  local rec = R.Current()
  if rec.CharacterRun_Frozen then return false end
  -- A real hit always replaces an Inferred placeholder (back-filled at login); a real hit
  -- never replaces another real hit; an inferred hit never touches anything existing.
  local inferred = extra and extra.Inferred or false
  local existing = rec.Milestones[key]
  if existing then
    if inferred then return false end                 -- never downgrade / duplicate
    if not existing.Inferred then return false end    -- already a real split
    -- fall through: upgrade the inferred placeholder to a real split
  end
  local played, active = ST.Clock.Now()
  local m = { Played = played, Active = active, At = time(), Label = label }
  if inferred then m.Inferred = true end
  if not inferred then m.Where = R.WhereNow() end
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
  if ST.Live then ST.Live.QueueRefresh() end
  -- and again when this split should leave the done list
  C_Timer.After((ST.db.Config.Attention_DoneSeconds or D.Attention_DoneSeconds) + 0.5, function() if ST.Live then ST.Live.QueueRefresh() end end)
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

-- Discard this character's record entirely and start a fresh one (for contaminated data).
function R.WipeCurrent()
  local key = R.KeyFor_Player()
  ST.db.Characters[key] = nil
  ST.db.Characters[U.CharacterKey()] = nil   -- any legacy-keyed leftover too
  R._current = nil
  local rec = R.Current()
  ST.Compare.Invalidate()
  if ST.Clock and ST.Clock.RequestPlayed then ST.Clock.RequestPlayed() end  -- re-seeds Active from /played
  if ST.Live then ST.Live.QueueRefresh() end
  return rec
end
