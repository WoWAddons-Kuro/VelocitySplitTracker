-- Comparison: which runs are candidates for the current compare key, and the
-- best time per milestone across them. Pure logic over SplitTimerDB.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")

ST.Compare = {}
local C = ST.Compare

-- The key we compare against. Class/Pattern are user-selectable in the title;
-- StartZone is fixed by the character.
function C.Key()
  local rec = ST.Record.Current()
  local cfg = ST.db.Config
  -- StartZone is user-selectable too: a specific zone, or "ANY" (e.g. a Skyborne racing a
  -- Dun Morogh reference). Defaults to the character's own; legacy CompareAnyZone = "ANY".
  local zone = cfg.CompareZone or (cfg.CompareAnyZone and "ANY") or rec.CharacterRun_StartZone
  return {
    StartZone = zone,
    Class = cfg.CompareClass or rec.CharacterRun_ClassFile,   -- "ANY" or a class file
    Pattern = cfg.ComparePattern or ST.Data.DefaultPattern,
  }
end

local function ClockField() return ST.db.Config.Clock == "PLAYED" and "Played" or "Active" end

-- Other characters that match the compare key.
function C.Candidates()
  local key = C.Key()
  local meRec = ST.Record.Current()
  local me = meRec.CharacterRun_Key
  -- Filters are strict: "personal" is a value like any named pattern, so a run filed under
  -- "vitochie" does NOT match a "personal" filter. The old leak (named runs counted under the
  -- unnamed bucket) is now opt-in only.
  local includeNamedInDefault = ST.db.Config.Compare_IncludeNamedInDefault == true
  local sameModeOnly = ST.db.Config.Compare_AnyMode ~= true   -- a PvP run is not a benchmark for a PvE run
  local out = {}
  for k, rec in pairs(ST.db.Characters) do
    local zoneOK = key.StartZone == "ANY" or rec.CharacterRun_StartZone == key.StartZone
    -- reference runs with unknown mode are allowed through the mode filter (their mode is often not stated)
    local modeOK = not sameModeOnly or (rec.CharacterRun_Mode or "unknown") == (meRec.CharacterRun_Mode or "unknown") or (rec.CharacterRun_Reference and (rec.CharacterRun_Mode or "unknown") == "unknown")
    if k ~= me and zoneOK and modeOK then
      local classOK = key.Class == "ANY" or rec.CharacterRun_ClassFile == key.Class
      local pat = ST.Data.PatternOf(rec)
      local patOK = key.Pattern == "ANY" or (pat == key.Pattern) or (key.Pattern == ST.Data.DefaultPattern and includeNamedInDefault)
      if classOK and patOK then out[#out + 1] = rec end
    end
  end
  return out
end

local cache, cacheStamp = {}, 0
function C.Invalidate() cache = {}; cacheStamp = cacheStamp + 1 end


------------------------------------------------------------------------
-- Comparison target (SPEC 5.1): Auto | Run | BestSplits | None, stored per (zone|class) context.
------------------------------------------------------------------------
local function ContextKey()
  local rec = ST.Record.Current()
  return (rec.CharacterRun_StartZone or "?") .. "|" .. (rec.CharacterRun_ClassFile or "?")
end

local function StoredTarget()
  local cfg = ST.db.Config
  cfg.Compare_ByContext = cfg.Compare_ByContext or {}
  return cfg.Compare_ByContext[ContextKey()]
end

function C.SetTarget(mode, runKey)
  local cfg = ST.db.Config
  cfg.Compare_ByContext = cfg.Compare_ByContext or {}
  cfg.Compare_ByContext[ContextKey()] = { Mode = mode, RunKey = runKey }
  C.Invalidate()
end

-- Extent of a run = highest real level milestone; second return = its clock there.
function C.Extent(rec)
  local D = ST.Data
  local field = ClockField()
  for n = D.MaxLevel, 2, -1 do
    local m = rec.Milestones[D.Key("level", n)]
    if m and not m.Inferred and m[field] then return n, m[field] end
  end
  return 1, 0
end

local function TimeAtLevel(rec, n)
  local m = rec.Milestones[ST.Data.Key("level", n)]
  return (m and not m.Inferred) and m[ClockField()] or nil
end

-- Candidates ranked in Auto order (SPEC 5.1.1): eligible (extent > player level) first, by
-- end time asc; ties by extent desc, then time at level+1 asc, then name.
function C.RankedCandidates()
  local level = ST.Record.Level()
  local list = {}
  for _, rec in ipairs(C.Candidates()) do
    local ext, endT = C.Extent(rec)
    list[#list + 1] = { Rec = rec, Key = rec.CharacterRun_Key, Extent = ext, EndTime = endT, Eligible = ext > level, NextT = TimeAtLevel(rec, level + 1) }
  end
  table.sort(list, function(a, b)
    if a.Eligible ~= b.Eligible then return a.Eligible end
    if a.EndTime ~= b.EndTime then return a.EndTime < b.EndTime end
    if a.Extent ~= b.Extent then return a.Extent > b.Extent end
    local an, bn = a.NextT or math.huge, b.NextT or math.huge
    if an ~= bn then return an < bn end
    return (a.Rec.CharacterRun_Name or "") < (b.Rec.CharacterRun_Name or "")
  end)
  return list
end

function C.AutoPick()
  local ranked = C.RankedCandidates()
  return ranked[1] and ranked[1].Rec or nil
end

-- Resolve the active target: { Mode, Run (rec or nil), RunKey }
local lastAutoKey
function C.Target()
  local stored = StoredTarget()
  local mode = stored and stored.Mode or "Auto"
  if mode == "Run" then
    local run = stored.RunKey and ST.db.Characters[stored.RunKey]
    if run then return { Mode = "Run", Run = run, RunKey = stored.RunKey } end
    C.SetTarget("Auto")
    ST.Util.Print("the pinned comparison run no longer exists; back to auto select")
    mode = "Auto"
  end
  if mode == "Auto" then
    local run = C.AutoPick()
    local key = run and run.CharacterRun_Key
    if key ~= lastAutoKey then
      if lastAutoKey ~= nil and run then ST.Util.Print("comparison: now vs %s", ST.Util.RunDisplayName(run)) end
      lastAutoKey = key
    end
    return { Mode = "Auto", Run = run, RunKey = key }
  end
  return { Mode = mode }   -- BestSplits | None
end

function C.TargetLabel()
  local t = C.Target()
  if t.Mode == "None" then return "no comparison" end
  if t.Mode == "BestSplits" then return "vs Best splits" end
  if not t.Run then return "vs auto: (no runs yet)" end
  return (t.Mode == "Auto" and "vs auto: " or "vs ") .. ST.Util.RunDisplayName(t.Run)
end

-- Lowest time for a milestone key across ALL candidates (the record), or nil.
function C.BestAcrossCandidates(key)
  local field = ClockField()
  local ck = "all|" .. field .. "|" .. key
  if cache[ck] ~= nil then return cache[ck] or nil end
  local best
  for _, rec in ipairs(C.Candidates()) do
    local m = rec.Milestones[key]
    if m and not m.Inferred and m[field] and (not best or m[field] < best) then best = m[field] end
  end
  cache[ck] = best or false
  return best
end

-- The comparison time for a milestone under the active mode, or nil.
function C.Best(key)
  local t = C.Target()
  if t.Mode == "None" then return nil end
  if t.Mode == "BestSplits" then return C.BestAcrossCandidates(key) end
  if not t.Run then return nil end
  local m = t.Run.Milestones[key]
  if m and not m.Inferred then return m[ClockField()] end
  return nil
end

-- True if `time` beats every candidate for this milestone (gold in Run/Auto mode).
function C.IsRecord(key, time)
  local best = C.BestAcrossCandidates(key)
  return best ~= nil and time < best
end

-- Milestones of one axis that candidate runs reached, with best time <= maxTime, that the
-- current character has NOT reached, soonest first. Used for time-based upcoming rows
-- (areas, first-learn) where there is no progress metric of our own.
function C.UpcomingByTime(axis, maxTime, limit)
  local field = ClockField()
  local me = ST.Record.Current()
  -- Run/Auto: the reference run only. BestSplits: the candidate pool. None: nothing.
  local t = C.Target()
  local pool
  if t.Mode == "BestSplits" then pool = C.Candidates()
  elseif (t.Mode == "Run" or t.Mode == "Auto") and t.Run then pool = { t.Run }
  else return {} end
  local bestByKey, labelByKey = {}, {}
  local prefix = axis .. ":"
  for _, rec in ipairs(pool) do
    for key, m in pairs(rec.Milestones) do
      if key:sub(1, #prefix) == prefix and not m.Inferred and m[field] and m[field] <= maxTime and not me.Milestones[key] then
        if not bestByKey[key] or m[field] < bestByKey[key] then bestByKey[key] = m[field]; labelByKey[key] = m.Label end
      end
    end
  end
  local list = {}
  for key, t in pairs(bestByKey) do list[#list + 1] = { Key = key, Best = t, Label = labelByKey[key] or key } end
  table.sort(list, function(a, b) return a.Best < b.Best end)
  while #list > (limit or 3) do table.remove(list) end
  return list
end

-- Best level segment (level n-1 -> n) across candidates.
function C.BestLevelSegment(n)
  local field = ClockField()
  local D = ST.Data
  -- Comparison level segment (level n-1 -> n) under the active mode.
  local t = C.Target()
  local pool
  if t.Mode == "BestSplits" then pool = C.Candidates()
  elseif (t.Mode == "Run" or t.Mode == "Auto") and t.Run then pool = { t.Run }
  else return nil end
  local best
  for _, rec in ipairs(pool) do
    local a, b = rec.Milestones[D.Key("level", n - 1)], rec.Milestones[D.Key("level", n)]
    if n == 2 then a = { [field] = 0 } end
    if a and b and not b.Inferred and not a.Inferred then
      local seg = b[field] - a[field]
      if not best or seg < best then best = seg end
    end
  end
  return best
end

-- Options for the title dropdowns.
function C.ZoneOptions()
  local set = { [ST.Record.Current().CharacterRun_StartZone or "Unknown"] = true }
  for _, rec in pairs(ST.db.Characters) do if rec.CharacterRun_StartZone then set[rec.CharacterRun_StartZone] = true end end
  local list = { "ANY" }
  for z in pairs(set) do list[#list + 1] = z end
  table.sort(list, function(a, b) if a == "ANY" then return true elseif b == "ANY" then return false end return a < b end)
  return list
end

function C.ZoneLabel(zone) return zone == "ANY" and "Any zone" or zone end

function C.ClassOptions()
  local zone = C.Key().StartZone
  local set = { [ST.Record.Current().CharacterRun_ClassFile] = true }
  for _, rec in pairs(ST.db.Characters) do
    if zone == "ANY" or rec.CharacterRun_StartZone == zone then set[rec.CharacterRun_ClassFile] = true end
  end
  local list = { "ANY" }
  for c in pairs(set) do list[#list + 1] = c end
  table.sort(list, function(a, b) if a == "ANY" then return true elseif b == "ANY" then return false end return a < b end)
  return list
end

function C.PatternOptions()
  local zone = C.Key().StartZone
  local set = {}
  for _, rec in pairs(ST.db.Characters) do
    if (zone == "ANY" or rec.CharacterRun_StartZone == zone) and rec.CharacterRun_Pattern then set[rec.CharacterRun_Pattern] = true end
  end
  local def = ST.Data.DefaultPattern
  -- "ANY" first (every pattern), then "personal" (unnamed runs only), then the named patterns.
  local list = { "ANY", def }
  for p in pairs(set) do list[#list + 1] = p end
  local rank = { ANY = 0, [def] = 1 }
  table.sort(list, function(a, b) local ra, rb = rank[a] or 2, rank[b] or 2; if ra ~= rb then return ra < rb end return a < b end)
  return list
end

function C.PatternLabel(p) return p == "ANY" and "Any pattern" or p end

-- Pretty class name from file name.
function C.ClassLabel(classFile)
  if classFile == "ANY" then return "Any" end
  local t = LOCALIZED_CLASS_NAMES_MALE
  return (t and t[classFile]) or classFile
end
