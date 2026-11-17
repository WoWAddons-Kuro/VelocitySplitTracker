-- Comparison: which runs are candidates for the current compare key, and the
-- best time per milestone across them. Pure logic over SplitTimerDB.
local ADDON_NAME, ST = ...

ST.Compare = {}
local C = ST.Compare

-- The key we compare against. Class/Pattern are user-selectable in the title;
-- StartZone is fixed by the character.
function C.Key()
  local rec = ST.Record.Current()
  local cfg = ST.db.Config
  return {
    StartZone = rec.CharacterRun_StartZone,
    Class = cfg.CompareClass or rec.CharacterRun_ClassFile,   -- "ANY" or a class file
    Pattern = cfg.ComparePattern or "default",
  }
end

local function ClockField() return ST.db.Config.Clock == "PLAYED" and "Played" or "Active" end

-- Other characters that match the compare key.
function C.Candidates()
  local key = C.Key()
  local me = ST.Record.Current().CharacterRun_Key
  local includeNamedInDefault = ST.db.Config.Compare_IncludeNamedInDefault ~= false
  local out = {}
  for k, rec in pairs(ST.db.Characters) do
    if k ~= me and rec.CharacterRun_StartZone == key.StartZone then
      local classOK = key.Class == "ANY" or rec.CharacterRun_ClassFile == key.Class
      local pat = rec.CharacterRun_Pattern or "default"
      local patOK = (pat == key.Pattern) or (key.Pattern == "default" and includeNamedInDefault)
      if classOK and patOK then out[#out + 1] = rec end
    end
  end
  return out
end

local cache, cacheStamp = {}, 0
function C.Invalidate() cache = {}; cacheStamp = cacheStamp + 1 end

-- Best (lowest) time for a milestone key across candidates, or nil.
function C.Best(key)
  local field = ClockField()
  local ck = field .. "|" .. key
  if cache[ck] ~= nil then return cache[ck] or nil end
  local best
  for _, rec in ipairs(C.Candidates()) do
    local m = rec.Milestones[key]
    if m and not m.Inferred and m[field] and (not best or m[field] < best) then best = m[field] end
  end
  cache[ck] = best or false
  return best
end

-- Best level segment (level n-1 -> n) across candidates.
function C.BestLevelSegment(n)
  local field = ClockField()
  local D = ST.Data
  local best
  for _, rec in ipairs(C.Candidates()) do
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
function C.ClassOptions()
  local zone = ST.Record.Current().CharacterRun_StartZone
  local set = { [ST.Record.Current().CharacterRun_ClassFile] = true }
  for _, rec in pairs(ST.db.Characters) do
    if rec.CharacterRun_StartZone == zone then set[rec.CharacterRun_ClassFile] = true end
  end
  local list = { "ANY" }
  for c in pairs(set) do list[#list + 1] = c end
  table.sort(list, function(a, b) if a == "ANY" then return true elseif b == "ANY" then return false end return a < b end)
  return list
end

function C.PatternOptions()
  local zone = ST.Record.Current().CharacterRun_StartZone
  local set = {}
  for _, rec in pairs(ST.db.Characters) do
    if rec.CharacterRun_StartZone == zone and rec.CharacterRun_Pattern then set[rec.CharacterRun_Pattern] = true end
  end
  local list = { "default" }
  for p in pairs(set) do list[#list + 1] = p end
  table.sort(list, function(a, b) if a == "default" then return true elseif b == "default" then return false end return a < b end)
  return list
end

-- Pretty class name from file name.
function C.ClassLabel(classFile)
  if classFile == "ANY" then return "Any" end
  local t = LOCALIZED_CLASS_NAMES_MALE
  return (t and t[classFile]) or classFile
end
