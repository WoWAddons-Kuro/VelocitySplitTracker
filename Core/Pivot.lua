-- Flat fact table over every character's real level milestones, and the best-time grids
-- the data window's three fixed pivots (By Level / By Class / By Start Zone) are built from.
-- Pure Lua: no frames, no WoW API beyond ST.db / ST.Record.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local D = ST.Data

ST.Pivot = {}
local P = ST.Pivot

-- Pivot_Fact = { CharKey, CharName, Zone, Class, Pattern, Key, Axis, Level, Time }
-- One fact per (character, real level milestone). clockField = "Active" | "Played".
function P.Facts(clockField)
  clockField = clockField or (ST.db.Config.Clock == "PLAYED" and "Played" or "Active")
  local facts = {}
  for charKey, rec in pairs(ST.db.Characters) do
    for key, m in pairs(rec.Milestones or {}) do
      if not m.Inferred and m[clockField] then
        local axis, id = D.ParseKey(key)
        if axis == "level" then
          facts[#facts + 1] = {
            CharKey = charKey,
            CharName = rec.CharacterRun_Name or charKey,
            Zone = rec.CharacterRun_StartZone or "Unknown",
            Class = rec.CharacterRun_ClassFile or "?",
            Pattern = ST.Data.PatternOf(rec),
            Key = key, Axis = axis, Level = tonumber(id), Time = m[clockField],
          }
        end
      end
    end
  end
  return facts
end

local function SortedKeys(set, cmp)
  local list = {}
  for k in pairs(set) do list[#list + 1] = k end
  table.sort(list, cmp)
  return list
end

function P.LevelsPresent(facts)
  local set = {}
  for _, f in ipairs(facts) do if f.Level then set[f.Level] = true end end
  return SortedKeys(set, function(a, b) return a < b end)
end

function P.ZonesPresent(facts)
  local set = {}
  for _, f in ipairs(facts) do set[f.Zone] = true end
  return SortedKeys(set, function(a, b) return a < b end)
end

function P.ClassesPresent(facts)
  local set = {}
  for _, f in ipairs(facts) do set[f.Class] = true end
  return SortedKeys(set, function(a, b) return a < b end)
end

-- Best-time grid.
--   filterFn(fact) -> bool        which facts participate
--   colOf(fact) -> col value      e.g. fact.Zone
--   rowOf(fact) -> row value      e.g. fact.Class or fact.Level
-- Returns { Cols = {...}, Rows = {...}, Cell = { [row] = { [col] = Pivot_Cell } }, Characters = n }
--   Pivot_Cell = { Time, CharKey, CharName, Pattern, Count }  (lowest Time wins; Count = contributing characters)
function P.BestGrid(facts, filterFn, colOf, rowOf, rowCmp, colCmp)
  local cell, cols, rows, chars = {}, {}, {}, {}
  for _, f in ipairs(facts) do
    if filterFn == nil or filterFn(f) then
      local c, r = colOf(f), rowOf(f)
      cols[c] = true; rows[r] = true; chars[f.CharKey] = true
      cell[r] = cell[r] or {}
      local cur = cell[r][c]
      if not cur then
        cell[r][c] = { Time = f.Time, CharKey = f.CharKey, CharName = f.CharName, Pattern = f.Pattern, Count = 1, _seen = { [f.CharKey] = true } }
      else
        if not cur._seen[f.CharKey] then cur._seen[f.CharKey] = true; cur.Count = cur.Count + 1 end
        if f.Time < cur.Time then cur.Time, cur.CharKey, cur.CharName, cur.Pattern = f.Time, f.CharKey, f.CharName, f.Pattern end
      end
    end
  end
  for _, row in pairs(cell) do for _, c in pairs(row) do c._seen = nil end end
  local n = 0; for _ in pairs(chars) do n = n + 1 end
  return {
    Cols = SortedKeys(cols, colCmp or function(a, b) return tostring(a) < tostring(b) end),
    Rows = SortedKeys(rows, rowCmp or function(a, b) if type(a) == "number" and type(b) == "number" then return a < b end return tostring(a) < tostring(b) end),
    Cell = cell,
    Characters = n,
  }
end

-- The three fixed pivots. Each returns a grid plus display helpers for its axes.
function P.ByLevel(facts, level)
  local g = P.BestGrid(facts, function(f) return f.Level == level end, function(f) return f.Zone end, function(f) return f.Class end)
  g.ColLabel = function(v) return v end
  g.RowLabel = function(v) return ST.Compare.ClassLabel(v) end
  return g
end

function P.ByClass(facts, classFile)
  local g = P.BestGrid(facts, function(f) return f.Class == classFile end, function(f) return f.Zone end, function(f) return f.Level end)
  g.ColLabel = function(v) return v end
  g.RowLabel = function(v) return "Level " .. v end
  return g
end

function P.ByZone(facts, zone)
  local g = P.BestGrid(facts, function(f) return f.Zone == zone end, function(f) return f.Class end, function(f) return f.Level end)
  g.ColLabel = function(v) return ST.Compare.ClassLabel(v) end
  g.RowLabel = function(v) return "Level " .. v end
  return g
end
