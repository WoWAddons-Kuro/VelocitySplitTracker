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

-- Game mode of this character: "pve" | "pvp" | "hardcore-pve" | "hardcore-pvp" | "unknown".
-- Sources, in order: Config.ModeOverride (wins); hardcore flag from the client when it has one;
-- realm-name tokens as Forever writes them ("... Realm 1 PvE"); IsPVPServer if present.
function R.DetectMode()
  local override = ST.db.Config.ModeOverride
  if override and override ~= "" then return override end
  local hardcore = false
  if C_GameRules and C_GameRules.IsHardcoreActive then
    local ok, v = pcall(C_GameRules.IsHardcoreActive); hardcore = ok and v == true
  elseif C_GameModeManager and C_GameModeManager.IsFeatureEnabled and Enum and Enum.GameModeFeatureSetting and Enum.GameModeFeatureSetting.Hardcore then
    local ok, v = pcall(C_GameModeManager.IsFeatureEnabled, Enum.GameModeFeatureSetting.Hardcore); hardcore = ok and v == true
  end
  local realm = (GetRealmName() or ""):lower()
  if realm:find("hardcore", 1, true) then hardcore = true end
  local base
  if realm:find("pvp", 1, true) then base = "pvp"
  elseif realm:find("pve", 1, true) or realm:find("normal", 1, true) then base = "pve" end
  if not base and IsPVPServer then
    local ok, v = pcall(IsPVPServer); if ok and v ~= nil then base = v and "pvp" or "pve" end
  end
  if not base then return hardcore and "hardcore-unknown" or "unknown" end
  return hardcore and ("hardcore-" .. base) or base
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

-- Realm / mode are read from GetRealmName(), which on Forever is still "" at PLAYER_LOGIN
-- (Record.Current runs there). DetectMode then finds no "pve"/"pvp" token and stamps "unknown",
-- and the mode filter in Compare hides every other run. Re-run from PLAYER_ENTERING_WORLD.
-- Realm is stored once it is non-empty; mode is re-detected while it is still unknown.
function R.RefreshIdentity(rec)
  rec = rec or R.Current()
  local realm = GetRealmName()
  if realm and realm ~= "" and (not rec.CharacterRun_Realm or rec.CharacterRun_Realm == "") then rec.CharacterRun_Realm = realm end
  if not rec.CharacterRun_Mode or rec.CharacterRun_Mode:find("unknown", 1, true) then
    local mode = R.DetectMode()
    if mode ~= rec.CharacterRun_Mode then
      rec.CharacterRun_Mode = mode
      if ST.Compare then ST.Compare.Invalidate() end
      if ST.Live and not mode:find("unknown", 1, true) then ST.Live.QueueRefresh() end
    end
  end
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
      CharacterRun_Mode = R.DetectMode(),
      CharacterRun_StartZone = D.RaceStartZone[raceFile] or "Unknown",
      CharacterRun_Pattern = nil,
      CharacterRun_ClientFlavour = U.ClientInfo().Flavour,           -- "forever" | "era" | ...
      CharacterRun_ClientVersion_First = U.ClientInfo().Version,     -- "1.60.1" at run start (write-once)
      CharacterRun_ClientInterface_First = U.ClientInfo().Interface, -- 16001 at run start
      CharacterRun_ClientVersion = U.ClientInfo().Version,           -- last played (refreshed each login below)
      CharacterRun_ClientInterface = U.ClientInfo().Interface,
      CharacterRun_ClientVersions = { [U.ClientInfo().Version] = time() },  -- every version touched -> first seen
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
  -- Mode: fill in for records that pre-date this field; re-detect when it was unknown.
  -- NOTE: at PLAYER_LOGIN GetRealmName() can still be "" on Forever (observed 2026-11-21: four
  -- characters stamped mode "unknown" with Realm ""), so R.RefreshIdentity() runs this again
  -- from PLAYER_ENTERING_WORLD when the realm is known.
  R.RefreshIdentity(rec)
  -- Client flavour / version: a Forever (realmless) run and an Era run are different categories,
  -- and a run that spans a client patch is a different run than one inside a single version.
  --   CharacterRun_ClientFlavour       flavour (never changes for a character)
  --   CharacterRun_ClientVersion_First first version this run was recorded on (write-once; the speedrun category)
  --   CharacterRun_ClientVersion       version LAST played on (refreshed each login)
  --   CharacterRun_ClientVersions      { ["1.60.1"] = firstSeenEpoch, ... } every version the run touched
  -- Legacy records (pre-field) are seeded with the current client on first login after upgrade.
  do
    local ci = U.ClientInfo()
    rec.CharacterRun_ClientFlavour, rec.CharacterRun_ClientVersion, rec.CharacterRun_ClientInterface = ci.Flavour, ci.Version, ci.Interface
    if not rec.CharacterRun_ClientVersion_First then
      rec.CharacterRun_ClientVersion_First = ci.Version
      rec.CharacterRun_ClientInterface_First = ci.Interface
    end
    rec.CharacterRun_ClientVersions = rec.CharacterRun_ClientVersions or {}
    if not rec.CharacterRun_ClientVersions[ci.Version] then
      rec.CharacterRun_ClientVersions[ci.Version] = time()
      if next(rec.CharacterRun_ClientVersions, next(rec.CharacterRun_ClientVersions)) then U.Print("client version %s (run started on %s)", ci.Version, tostring(rec.CharacterRun_ClientVersion_First)) end
    end
  end
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
  if not m.Inferred and ST.AutoHide then ST.AutoHide.OnHit(key) end
  if ST.Live then ST.Live.QueueRefresh() end
  -- and again when this split should leave the done list
  C_Timer.After((ST.db.Config.Attention_DoneSeconds or D.Attention_DoneSeconds) + 0.5, function() if ST.Live then ST.Live.QueueRefresh() end end)
  return true
end

function R.Has(key)
  return R.Current().Milestones[key] ~= nil
end

-- The player's level as the addon knows it. PLAYER_LEVEL_UP carries the new level as its
-- argument and we store it on the record immediately; UnitLevel("player") can still report
-- the OLD level during the refresh that follows the ding (observed 2026-11-17 on Forever and
-- Era: title/rows stayed one level behind until an unrelated refresh). Take the higher of the two.
function R.Level()
  local unit = UnitLevel and UnitLevel("player") or 0
  return math.max(unit, R.Current().CharacterRun_Level or 0)
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
