-- Shared helpers: time formatting, colour constants, small table utils.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")

ST.Util = {}
local U = ST.Util

-- Format seconds as LiveSplit does: H:MM:SS when >= 1h, otherwise M:SS.
-- withTenths adds .t (no longer used by the window; kept for callers/tests).
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

-- Build label for the footer. The TOC holds "@project-version@" in the repo; publish.cs stamps
-- the installed copy with `git describe` and release.cs commits the vYYYY.MM.DD.HHMM tag, so an
-- installed addon always reports which build it is. The raw placeholder means "running from source".
function U.BuildLabel()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local v = get and get(ADDON_NAME, "Version") or nil
  if not v or v == "" or v:find("@project%-version@") then return "source" end
  return v
end

-- Which game client this is. Forever (realmless, 1.60.x / interface 16001) and Classic Era
-- (realms, 1.15.x / 115xx) are fundamentally different speedrun categories, so the flavour and
-- the version travel with every run record. Forever reports WOW_PROJECT_MAINLINE (or
-- WOW_PROJECT_CAMELOT = 18 where defined) with a 1.60.x version, so the project id alone cannot
-- tell it from Retail: the interface band decides.
-- Returns { Flavour = "forever"|"era"|"classic"|"mists"|"mainline"|"unknown",
--           Version = "1.60.1", Build = "12345", Interface = 16001 }.
local clientInfo
function U.ClientInfo()
  if clientInfo then return clientInfo end
  local version, build, _, interface
  if GetBuildInfo then version, build, _, interface = GetBuildInfo() end
  interface = tonumber(interface) or 0
  local flavour = "unknown"
  local pid = WOW_PROJECT_ID
  if WOW_PROJECT_CAMELOT and pid == WOW_PROJECT_CAMELOT then flavour = "forever"
  elseif pid == WOW_PROJECT_CLASSIC then flavour = "era"
  elseif WOW_PROJECT_MISTS_CLASSIC and pid == WOW_PROJECT_MISTS_CLASSIC then flavour = "mists"
  elseif pid == WOW_PROJECT_MAINLINE and interface >= 16000 and interface < 20000 then flavour = "forever"
  elseif pid == WOW_PROJECT_MAINLINE then flavour = "mainline"
  elseif interface >= 11000 and interface < 12000 then flavour = "era"
  elseif interface >= 20000 and interface < 100000 then flavour = "classic"   -- TBC / Wrath / Cata progression clients
  end
  clientInfo = { Flavour = flavour, Version = tostring(version or "?"), Build = tostring(build or "?"), Interface = interface }
  return clientInfo
end

-- "Forever" / "Classic Era" / ... from a flavour key.
local FLAVOUR_LABEL = { forever = "Forever", era = "Classic Era", classic = "Classic", mists = "Mists", mainline = "Retail", unknown = "?" }
function U.ClientFlavourLabel(flavour)
  if flavour == nil or flavour == "" then return "?" end
  return FLAVOUR_LABEL[flavour] or flavour
end

-- "Forever 1.60.1" for a run record, using the FIRST-played version (the speedrun category);
-- "Forever 1.60.1 -> 1.60.3" (short: "Forever 1.60.1+") when later played on a newer client. "?" when
-- the record pre-dates the field (a reference may legitimately not state its client).
function U.ClientLabel(rec, short)
  if not rec then return "?" end
  local flavour = U.ClientFlavourLabel(rec.CharacterRun_ClientFlavour)
  local first = rec.CharacterRun_ClientVersion_First or rec.CharacterRun_ClientVersion   -- first-played = the category
  local last = rec.CharacterRun_ClientVersion                                           -- last-played
  if short and flavour == "Classic Era" then flavour = "Era" end
  if not first or first == "" or first == "?" then return flavour end
  local text = flavour .. " " .. first
  if last and last ~= first then text = text .. (short and "+" or (" -> " .. last)) end   -- run spans a patch
  return text
end

-- Every client version a run was played on, oldest first: "1.60.1, 1.60.2, 1.60.3".
function U.ClientVersionsLabel(rec)
  local set = rec and rec.CharacterRun_ClientVersions
  if not set then return (rec and rec.CharacterRun_ClientVersion) or "?" end
  local list = {}
  for v, at in pairs(set) do list[#list + 1] = { v = v, at = at or 0 } end
  table.sort(list, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.v < b.v end)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.v end
  return table.concat(out, ", ")
end

function U.Print(msg, ...)
  if select("#", ...) > 0 then msg = string.format(msg, ...) end
  print("|cff5ad65aVelocity|r: " .. msg)
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
