-- Shared helpers: time formatting, colour constants, small table utils.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")

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

-- Display name including Forever's second name. UnitPVPName returns "First Last" here
-- (the surname occupies the PvP-title slot); UnitName returns only "First".
function U.CharacterDisplayName()
  local first = UnitName("player") or "?"
  local full = UnitPVPName and UnitPVPName("player") or nil
  if full and full ~= "" and full ~= first then return full end
  return first
end

-- "[2026.10.02 11:42]" from a time() stamp (local time); "" if unknown.
function U.FormatFirstSeen(epoch)
  if not epoch or epoch <= 0 then return "" end
  return date("[%Y.%m.%d %H:%M]", epoch)
end

-- "Kuro Lightfoot [2026.10.02 11:42]" for a character record.
function U.RunDisplayName(rec)
  return (rec.CharacterRun_Name or "?") .. " " .. U.FormatFirstSeen(rec.CharacterRun_CreatedAt)
end

function U.Print(msg, ...)
  if select("#", ...) > 0 then msg = string.format(msg, ...) end
  print("|cff5ad65aSplitTimer|r: " .. msg)
end

-- Startup/load phase probes. ST.Probe is read by the ADDON_ACTION_FORBIDDEN handler,
-- which fires synchronously inside the offending call, so the current phase names it.
-- Usage: local p = U.Phase("name") ... U.PhaseEnd(p)
function U.Phase(name)
  local outer = ST.Probe
  ST.Probe = outer and (outer .. ">" .. name) or name
  return outer
end
function U.PhaseEnd(outer) ST.Probe = outer end
-- Run fn under a named phase (errors still propagate, phase is restored).
function U.InPhase(name, fn, ...)
  local outer = U.Phase(name)
  local ok, err = pcall(fn, ...)
  U.PhaseEnd(outer)
  if not ok then error(err, 0) end
end
