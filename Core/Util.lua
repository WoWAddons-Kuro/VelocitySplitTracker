-- Shared helpers: time formatting, colour constants, small table utils.
local ADDON_NAME, ST = ...

ST.Util = {}
local U = ST.Util

-- Format seconds as LiveSplit does: H:MM:SS when >= 1h, otherwise M:SS.
-- withTenths adds .t (used by the big timer only).
function U.FormatTime(seconds, withTenths)
  if seconds == nil then return "-" end
  local negative = seconds < 0
  if negative then seconds = -seconds end
  local whole = math.floor(seconds)
  local tenths = math.floor((seconds - whole) * 10)
  local h = math.floor(whole / 3600)
  local m = math.floor((whole % 3600) / 60)
  local s = whole % 60
  local text
  if h > 0 then
    text = string.format("%d:%02d:%02d", h, m, s)
  else
    text = string.format("%d:%02d", m, s)
  end
  if withTenths then text = text .. "." .. tenths end
  if negative then text = "-" .. text end
  return text
end

-- Delta formatting: always signed, e.g. "+1:10" / "-0:42".
function U.FormatDelta(deltaSeconds)
  if deltaSeconds == nil then return "" end
  local sign = deltaSeconds < 0 and "-" or "+"
  return sign .. U.FormatTime(math.abs(deltaSeconds))
end

function U.Round(v) return math.floor(v + 0.5) end

function U.CharacterKey()
  local name, realm = UnitName("player"), GetRealmName()
  return name .. "-" .. realm
end

function U.Print(msg, ...)
  if select("#", ...) > 0 then msg = string.format(msg, ...) end
  print("|cff5ad65aSplitTimer|r: " .. msg)
end
