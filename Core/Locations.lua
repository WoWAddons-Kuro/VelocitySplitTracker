-- Location splits: "first time the player passes within <Radius> yards of a point".
-- Stored per start zone (ST.db.Plans[zone].Locations) so every character of that start zone
-- shares them and their times compare. Proximity is checked on a 1 s poll against a
-- shortlist of the nearest few unreached points on the current map (re-sorted every 10 s),
-- never against the whole list every frame.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local U = ST.Util
local D = ST.Data

ST.Locations = {}
local L = ST.Locations

L.DefaultRadiusYards = 10
L.ShowWithinYards = 200          -- upcoming row appears when this close
L.ShortlistSize = 3
L.PollSeconds = 1
L.ResortSeconds = 10

------------------------------------------------------------------------
-- Storage
------------------------------------------------------------------------
local function PlanForZone()
  local zone = ST.Record.Current().CharacterRun_StartZone or "Unknown"
  ST.db.Plans[zone] = ST.db.Plans[zone] or {}
  ST.db.Plans[zone].Locations = ST.db.Plans[zone].Locations or {}
  return ST.db.Plans[zone].Locations
end
L.List = PlanForZone

local function Slug(label)
  return (label:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

-- Add a location split at the player's current position.
function L.AddHere(label, radius)
  local where = ST.Record.WhereNow()
  if not where or not where.X then U.Print("cannot read your map position here"); return nil end
  label = label and label:match("^%s*(.-)%s*$") or ""
  if label == "" then label = string.format("%s %.1f, %.1f", where.Zone or "Location", where.X * 100, where.Y * 100) end
  local entry = {
    Key = D.Key("loc", Slug(label)),
    Label = label,
    Map = where.Map, X = where.X, Y = where.Y, Zone = where.Zone,
    Radius = radius or L.DefaultRadiusYards,
    CreatedAt = time(),
  }
  local list = PlanForZone()
  for _, e in ipairs(list) do if e.Key == entry.Key then U.Print("a location split named '%s' already exists", label); return nil end end
  list[#list + 1] = entry
  U.Print("location split added: %s (%s, %.1f %.1f, %d yd)", label, entry.Zone or "?", entry.X * 100, entry.Y * 100, entry.Radius)
  -- You are standing on it: that counts as reaching it now.
  ST.Record.Hit(entry.Key, "Reach " .. label)
  L.Resort()
  return entry
end

function L.Remove(key)
  local list = PlanForZone()
  for i, e in ipairs(list) do if e.Key == key then table.remove(list, i); U.Print("location split removed: %s", e.Label); L.Resort(); return true end end
  return false
end

------------------------------------------------------------------------
-- Geometry
------------------------------------------------------------------------
local mapSizeCache = {}
local function MapYards(mapID)
  local s = mapSizeCache[mapID]
  if s then return s.w, s.h end
  local w, h
  if C_Map and C_Map.GetMapWorldSize then
    local ok, ww, hh = pcall(C_Map.GetMapWorldSize, mapID)
    if ok and ww and ww > 0 then w, h = ww, hh end
  end
  if not w then w, h = 5000, 3333 end   -- rough zone-sized fallback when the API is absent
  mapSizeCache[mapID] = { w = w, h = h }
  return w, h
end

-- Distance in yards from the player to an entry on the same map, or nil if on another map.
local function DistanceYards(entry, mapID, px, py)
  if entry.Map ~= mapID then return nil end
  local w, h = MapYards(mapID)
  local dx, dy = (entry.X - px) * w, (entry.Y - py) * h
  return math.sqrt(dx * dx + dy * dy)
end

------------------------------------------------------------------------
-- Polling
------------------------------------------------------------------------
local shortlist = {}          -- nearest unreached entries on the current map, ascending distance
local nearest = nil           -- { Entry=, Yards= } for the upcoming row
local sinceResort = math.huge

local function PlayerPos()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return nil end
  local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return nil end
  local ok, x, y = pcall(pos.GetXY, pos)
  if not ok or not x then return nil end
  return mapID, x, y
end

-- Rebuild the shortlist: the N nearest unreached entries on the player's current map.
function L.Resort()
  sinceResort = 0
  shortlist = {}
  local mapID, px, py = PlayerPos()
  if not mapID then return end
  local rec = ST.Record.Current()
  local candidates = {}
  for _, e in ipairs(PlanForZone()) do
    if not rec.Milestones[e.Key] then
      local d = DistanceYards(e, mapID, px, py)
      if d then candidates[#candidates + 1] = { Entry = e, Yards = d } end
    end
  end
  table.sort(candidates, function(a, b) return a.Yards < b.Yards end)
  for i = 1, math.min(L.ShortlistSize, #candidates) do shortlist[i] = candidates[i] end
end

local function Poll()
  if #shortlist == 0 then nearest = nil; return end
  local mapID, px, py = PlayerPos()
  if not mapID then nearest = nil; return end
  local best
  for _, c in ipairs(shortlist) do
    local d = DistanceYards(c.Entry, mapID, px, py)
    if d then
      c.Yards = d
      if d <= (c.Entry.Radius or L.DefaultRadiusYards) then
        ST.Record.Hit(c.Entry.Key, "Reach " .. c.Entry.Label)
        L.Resort()
        return
      end
      if not best or d < best.Yards then best = c end
    end
  end
  local changed = (nearest and nearest.Entry) ~= (best and best.Entry)
  nearest = best
  if changed and ST.Live then ST.Live.QueueRefresh() end
end

-- For the live window: nearest unreached location within ShowWithinYards, or nil.
function L.Nearest()
  if nearest and nearest.Yards <= L.ShowWithinYards then return nearest.Entry, nearest.Yards end
  return nil
end

local frame = CreateFrame("Frame")
local acc = 0
function L.Init()
  pcall(frame.RegisterEvent, frame, "ZONE_CHANGED_NEW_AREA")
  pcall(frame.RegisterEvent, frame, "ZONE_CHANGED")
  pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")
  frame:SetScript("OnEvent", function() C_Timer.After(1, L.Resort) end)
  frame:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < L.PollSeconds then return end
    acc = 0
    sinceResort = sinceResort + L.PollSeconds
    if sinceResort >= L.ResortSeconds then L.Resort() end
    if #PlanForZone() > 0 then Poll() end
  end)
end
