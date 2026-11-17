-- Placeholder data so the UI can be designed before the recording engine exists.
-- Everything here is replaced by Core/Clock, Core/Milestones and Core/Compare later.
local ADDON_NAME, ST = ...

ST.Mock = {}
local M = ST.Mock

-- What the title bar shows: the comparison key.
M.CompareKey = { StartZone = "Teldrassil", Class = "Hunter", Pattern = "default" }
M.CharacterLevel = 23

-- Clocks (seconds). The live window animates ActiveSeconds forward while "running".
M.ActiveSeconds = 4376.4
M.PlayedSeconds = 6012
M.ActiveRunning = true

-- Icons per axis (reused by the real UI).
M.AxisIcon = {
  level   = nil,
  quest   = "Interface\\GossipFrame\\ActiveQuestIcon",
  kill    = "Interface\\Icons\\Ability_DualWield",
  skill   = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
  riding  = nil,
  zone    = nil,
  manual  = nil,
}

-- Recently hit milestones (newest last). Delta vs best; Best is the comparison time.
M.Done = {
  { Axis = "level", Label = "Level 20",       Time = 3290, Best = 3350, Gold = false },
  { Axis = "kill",  Label = "Vagash",         Time = 3545, Best = 3475, Gold = false },
  { Axis = "level", Label = "Level 21",       Time = 3620, Best = 3701, Gold = true  },
  { Axis = "skill", Label = "Skinning 100",   Time = 3961, Best = 3965, Gold = false },
  { Axis = "level", Label = "Level 22",       Time = 4173, Best = 4204, Gold = false },
}

-- Upcoming milestones: next level always first, others only when "near".
-- Progress is 0..1 or nil.
-- Quests: for now the 3 most recently progressed quests (later: curated "major" quests).
M.Upcoming = {
  { Axis = "level", Label = "Level 23",                      Best = 4633, Progress = 0.61, Current = true },
  { Axis = "quest", Label = "Cave of Ferocity",              Best = 4893, Progress = nil },
  { Axis = "quest", Label = "The Blackwood Corrupted",       Best = 5010, Progress = nil },
  { Axis = "quest", Label = "Buzzbox 323",                   Best = nil,  Progress = nil },
  { Axis = "skill", Label = "Skinning 150",                  Best = 5400, Progress = 134 / 150, ProgressText = "134/150" },
}

-- Pinned final milestone.
M.Final = { Axis = "level", Label = "Level 60", Best = 17494 }

-- Footer
M.PreviousSegmentDelta = -31

-- Mock options for the dropdowns.
M.ClassOptions   = { "Any", "Hunter", "Druid", "Warrior" }
M.PatternOptions = { "default", "darkshore+ashenvale", "darkshore+wetlands" }
