-- Static game data: start zones per race, riding spells, icons per axis.
local ADDON_NAME, ST = ...

ST.Data = {}
local D = ST.Data

-- Race file name (select(2, UnitRace("player"))) -> start zone key.
-- The start zone is always derived from race, never from where we first see the
-- character, so characters that pre-date the addon still land in the right bucket.
D.RaceStartZone = {
  Human = "Elwynn Forest",
  Dwarf = "Dun Morogh", Gnome = "Dun Morogh",
  NightElf = "Teldrassil",
  Draenei = "Azuremyst Isle",
  Orc = "Durotar", Troll = "Durotar",
  Scourge = "Tirisfal Glades",
  Tauren = "Mulgore",
  BloodElf = "Eversong Woods",
  Worgen = "Gilneas", Goblin = "Kezan", Pandaren = "Wandering Isle",
}

-- Riding skill spell IDs by rank (classic + later clients; IsSpellKnown picks what exists).
D.RidingSpells = {
  { Rank = 1, Label = "Apprentice Riding",  Spells = { 33388 } },
  { Rank = 2, Label = "Journeyman Riding",  Spells = { 33391 } },
  { Rank = 3, Label = "Expert Riding",      Spells = { 34090, 34092 } },
  { Rank = 4, Label = "Artisan Riding",     Spells = { 34091, 34093 } },
}

D.MaxLevel = 60
D.RidingShowFromLevel = 38
D.SkillStep = 50
D.SkillNearPct = 0.80

-- Primary + the secondaries worth tracking. Keyed by English skill line name.
D.TrackedSkills = {
  ["Alchemy"] = true, ["Blacksmithing"] = true, ["Enchanting"] = true, ["Engineering"] = true,
  ["Herbalism"] = true, ["Leatherworking"] = true, ["Mining"] = true, ["Skinning"] = true,
  ["Tailoring"] = true, ["Jewelcrafting"] = true, ["Inscription"] = true,
  ["First Aid"] = true, ["Cooking"] = true, ["Fishing"] = true,
}

D.SkillIcon = {
  Alchemy = "Interface\\Icons\\Trade_Alchemy", Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
  Enchanting = "Interface\\Icons\\Trade_Engraving", Engineering = "Interface\\Icons\\Trade_Engineering",
  Herbalism = "Interface\\Icons\\Trade_Herbalism", Leatherworking = "Interface\\Icons\\Trade_LeatherWorking",
  Mining = "Interface\\Icons\\Trade_Mining", Skinning = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
  Tailoring = "Interface\\Icons\\Trade_Tailoring", Jewelcrafting = "Interface\\Icons\\INV_Misc_Gem_01",
  Inscription = "Interface\\Icons\\INV_Inscription_Tradeskill01", ["First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
  Cooking = "Interface\\Icons\\INV_Misc_Food_15", Fishing = "Interface\\Icons\\Trade_Fishing",
}

-- Icon per axis; nil = reserved blank column.
D.AxisIcon = {
  level = nil,
  quest = "Interface\\GossipFrame\\ActiveQuestIcon",
  kill  = "Interface\\Icons\\Ability_DualWield",
  skill = nil,          -- resolved per skill via SkillIcon
  riding = nil, mounted = nil, zone = nil, manual = nil,
}

-- Milestone key helpers. Key = "<axis>:<id>[:<value>]".
function D.Key(axis, id, value)
  if value ~= nil then return axis .. ":" .. tostring(id) .. ":" .. tostring(value) end
  return axis .. ":" .. tostring(id)
end

function D.ParseKey(key)
  local axis, rest = key:match("^(%w+):(.*)$")
  if not axis then return nil end
  local id, value = rest:match("^(.-):([^:]*)$")
  if not id then id = rest end
  return axis, id, value
end

function D.IconForKey(key)
  local axis, id = D.ParseKey(key)
  if axis == "skill" then return D.SkillIcon[id] end
  return D.AxisIcon[axis]
end
