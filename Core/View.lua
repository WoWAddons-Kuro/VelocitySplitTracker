-- Builds what the live window draws from the current record + comparison.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local U = ST.Util
local D = ST.Data

ST.View = {}
local V = ST.View

local function ClockField() return ST.db.Config.Clock == "PLAYED" and "Played" or "Active" end

local function MilestoneLabel(key, m)
  if m and m.Label then return m.Label end
  local axis, id, value = D.ParseKey(key)
  if axis == "level" then return "Level " .. id end
  if axis == "skill" then return id .. " " .. value end
  if axis == "quest" then return ST.Milestones.QuestTitle(tonumber(id)) or ("Quest " .. id) end
  if axis == "kill" then return ST.Milestones.CreatureName(tonumber(id)) or ("Kill " .. id) end
  if axis == "bags" then return D.BagStepLabel(id) end
  return key
end

-- Recently hit milestones, oldest first. Inferred ones are skipped (no real time).
-- Exception: the previous level is always present so "last level -> current level" reads.
-- Recently hit milestones, oldest first, in two groups:
--   * the last `levelLimit` (Config.RowsDoneLevels, 1-4) LEVEL splits, exempt from the done window
--     so "previous level(s) -> current level" always reads. If the most recent one is inferred it is
--     still shown as a timeless placeholder.
--   * every other real split completed within Attention_DoneSeconds, capped at `limit` (RowsDone).
-- Inferred milestones never appear (except that single placeholder). Merged and sorted by time.
function V.Done(limit, levelLimit)
  levelLimit = math.max(1, math.min(4, tonumber(levelLimit) or 1))
  local rec = ST.Record.Current()
  local field = ClockField()
  local now = time()
  local doneWindow = ST.db.Config.Attention_DoneSeconds or D.Attention_DoneSeconds
  local list = {}   -- non-level splits within the done window
  for key, m in pairs(rec.Milestones) do
    if not m.Inferred and m.At and (now - m.At) <= doneWindow then
      local axis = D.ParseKey(key)
      if axis ~= "questaccept" and axis ~= "zone" and axis ~= "level" then
        list[#list + 1] = { Key = key, Axis = axis, Label = MilestoneLabel(key, m), Time = m[field], At = m.At }
      end
    end
  end
  table.sort(list, function(a, b) if a.Time == b.Time then return (a.At or 0) < (b.At or 0) end return a.Time < b.Time end)
  local out = {}
  for i = math.max(1, #list - limit + 1), #list do
    local item = list[i]
    item.Best = ST.Compare.Best(item.Key)
    -- Gold = a true record: faster than every candidate (not just the reference run).
    item.Gold = ST.Compare.IsRecord(item.Key, item.Time)
    out[#out + 1] = item
  end
  -- Level rows: walk down from the current level collecting real dings until levelLimit is met.
  -- Level rows carry the (n-1 -> n) segment delta and XP/hr so "am I bleeding time right now?"
  -- reads on the row itself. The current level, if inferred, is a timeless placeholder.
  local level = ST.Record.Level()
  local levelRows = {}
  for n = level, 2, -1 do
    if #levelRows >= levelLimit then break end
    local key = D.Key("level", n)
    local m = rec.Milestones[key]
    if m and not m.Inferred then
      levelRows[#levelRows + 1] = { Key = key, Axis = "level", Label = "Level " .. n, Best = ST.Compare.Best(key),
        Time = m[field], At = m.At, Gold = ST.Compare.IsRecord(key, m[field]),
        SegmentDelta = V.SegmentDelta(n), XPPerHour = V.LevelXPPerHour(n) }
    elseif n == level then
      levelRows[#levelRows + 1] = { Key = key, Axis = "level", Label = "Level " .. n, Best = ST.Compare.Best(key), Inferred = true }
    else
      break   -- an inferred older level: nothing real further back
    end
  end
  for _, r in ipairs(levelRows) do out[#out + 1] = r end
  -- Oldest first. A timeless placeholder sorts to the top.
  table.sort(out, function(a, b)
    local ta, tb = a.Time or -1, b.Time or -1
    if ta ~= tb then return ta < tb end
    return (a.At or 0) < (b.At or 0)
  end)
  return out
end

function V.Upcoming(limit)
  local rec = ST.Record.Current()
  local cfg = ST.db.Config
  local level = ST.Record.Level()
  local out = {}

  -- next level, always
  if level < D.MaxLevel then
    local key = D.Key("level", level + 1)
    local xp, xpMax = UnitXP("player"), UnitXPMax("player")
    out[#out + 1] = { Key = key, Axis = "level", Label = "Level " .. (level + 1), Best = ST.Compare.Best(key),
      Progress = xpMax > 0 and xp / xpMax or 0, Current = true }
  end

  -- Quests: shown while recently progressed (Attention_RecentSeconds) or complete-in-log (sticky).
  local shown = 0
  for _, questID in ipairs(ST.Milestones.QuestRecent) do
    if shown >= 3 then break end
    local key = D.Key("quest", questID)
    if not rec.Milestones[key] then
      local complete = ST.Milestones.QuestIsComplete(questID)
      local recent = ST.Milestones.QuestRecentlyProgressed(questID)
      if complete or recent then
        local title = ST.Milestones.QuestTitle(questID) or ("Quest " .. questID)
        out[#out + 1] = { Key = key, Axis = "quest", Label = title, Best = ST.Compare.Best(key), Progress = complete and 1 or nil,
          Sticky = complete, LastProgress = ST.Milestones.Attention().Quests[questID] }
        shown = shown + 1
      end
    end
  end

  -- Professions: shown while recently progressed, or at/over Attention_NearPct of the next step (sticky).
  local step = cfg.SkillStep or D.SkillStep
  for _, s in ipairs(ST.Milestones.Skills()) do
    local nextStep = (math.floor(s.Rank / step) + 1) * step
    local nearPct = cfg.Attention_NearPct or D.Attention_NearPct
    -- Sticky when within reach of EITHER goal: the next 50-step, or the trainer cap
    -- (a capped profession stays visible until the cap is lifted by training).
    local nearStep = s.Rank / nextStep >= nearPct
    local nearCap  = s.Max and s.Max > 0 and s.Rank / s.Max >= nearPct
    -- Past the train threshold (50 / 125 / 200) but the cap has not moved = not trained yet.
    -- Keep the row up as a standing reminder until training lifts the cap.
    local trainAt = D.SkillTrainAt(s.Max)
    local canTrain = trainAt ~= nil and s.Rank >= trainAt
    local near = nearStep or nearCap or canTrain
    local active = ST.Milestones.SkillIsActive(s.Name)
    -- Not gated on the current trainer cap (s.Max): the cap rises with training, the
    -- milestone is still "next 50". Only the absolute skill ceiling applies.
    if nextStep <= D.SkillCeiling and (near or active) then
      local key = D.Key("skill", s.Name, nextStep)
      -- Part of the goal above the current trainer cap is not reachable until trained.
      local capFraction = (s.Max and s.Max < nextStep) and (s.Max / nextStep) or nil
      -- Where the next tier becomes trainable (50 / 125 / 200), if still ahead and on this bar.
      local trainFraction = (trainAt and trainAt <= nextStep) and (trainAt / nextStep) or nil
      out[#out + 1] = { Key = key, Axis = "skill", Icon = D.SkillIcon[s.Name], Label = s.Name .. " " .. nextStep, Best = ST.Compare.Best(key),
        Progress = s.Rank / nextStep, ProgressText = s.Rank .. "/" .. nextStep, Active = active,
        CapFraction = capFraction, CapText = capFraction and tostring(s.Max) or nil,
        TrainFraction = trainFraction, TrainAt = trainAt,
        Sticky = near, LastProgress = ST.Milestones.Attention().Skills[s.Name] }
    end
  end

  -- Professions not yet learned: no progress metric, so the row appears once the current clock
  -- reaches Attention_TimeNearPct of the comparison run's first-learn time. Needs comparison data.
  do
    local known = {}
    for _, s in ipairs(ST.Milestones.Skills()) do known[s.Name] = true end
    local playedNow, activeNow = ST.Clock.Now()
    local nowClock = (cfg.Clock == "PLAYED") and playedNow or activeNow
    local timeNear = cfg.Attention_TimeNearPct or D.Attention_TimeNearPct
    for name in pairs(D.TrackedSkills) do
      local key = D.Key("learn", name)
      if not known[name] and not rec.Milestones[key] then
        local best = ST.Compare.Best(key)
        if best and nowClock >= best * timeNear then
          out[#out + 1] = { Key = key, Axis = "learn", Icon = D.SkillIcon[name], Label = "Learn " .. name, Best = best,
            Progress = math.min(1, nowClock / best), Sticky = true }
        end
      end
    end
  end

  -- Money acquired: special case. Money is always "progressing", so it gets no recent-progress
  -- rule. Either pinned as the last row (Config.AlwaysShowMoney) or shown only within
  -- Attention_MoneyNearPct of the next step (>= 80 %), sticky from there until the step is hit.
  local moneyRow
  do
    local nextStep = ST.Milestones.NextGoldStep()
    if nextStep then
      local total = ST.Milestones.GoldAcquired()
      local frac = total / nextStep
      local near = frac >= (cfg.Attention_MoneyNearPct or D.Attention_MoneyNearPct)
      if cfg.AlwaysShowMoney or near then
        local key = D.Key("gold", nextStep)
        -- "Money Acquired - 8s of 10s"
        moneyRow = { Key = key, Axis = "gold", Icon = D.GoldIcon, Label = "Money Acquired - " .. D.FormatCopper(total, true) .. " of " .. D.FormatCopper(nextStep, true), Best = ST.Compare.Best(key),
          Progress = frac,
          Sticky = true, LastProgress = ST.Milestones.Attention().Gold }
        -- Not pinned: compete for a slot like any other row.
        if not cfg.AlwaysShowMoney then out[#out + 1] = moneyRow; moneyRow = nil end
      end
    end
  end

  -- Extra bag slots: next 6-slot step. Shown ONLY for Attention_RecentSeconds after a bag change
  -- (never sticky by nearness: being 1 slot short of a step is not a reason to show it).
  do
    local nextStep = ST.Milestones.NextBagStep()
    if nextStep and ST.Milestones.BagsRecentlyProgressed() then
      local have = rec.BagSlots_Max or ST.Milestones.BagSlotsNow() or 0
      local key = D.Key("bags", nextStep)
      out[#out + 1] = { Key = key, Axis = "bags", Icon = D.BagIcon, Label = "Extra Bag Slots - " .. have .. " of " .. nextStep, Best = ST.Compare.Best(key),
        Progress = have / nextStep, ProgressText = have .. "/" .. nextStep, LastProgress = ST.Milestones.Attention().Bags }
    end
  end

  -- riding
  if level >= (cfg.RidingShowFromLevel or D.RidingShowFromLevel) then
    local rank = ST.Milestones.RidingRank()
    if rank < 1 then
      out[#out + 1] = { Key = "riding:1", Axis = "riding", Label = "Apprentice Riding", Best = ST.Compare.Best("riding:1") }
    elseif not rec.Milestones["mounted:1"] then
      out[#out + 1] = { Key = "mounted:1", Axis = "mounted", Label = "First Mount", Best = ST.Compare.Best("mounted:1") }
    end
  end

  -- Manual location splits: the nearest unreached one, when within ShowWithinYards.
  do
    local entry, yards = ST.Locations.Nearest()
    if entry then
      out[#out + 1] = { Key = entry.Key, Axis = "loc", Label = "Reach " .. entry.Label, Best = ST.Compare.Best(entry.Key),
        Progress = 1 - math.min(1, yards / ST.Locations.ShowWithinYards), ProgressText = string.format("%d yd", yards), Sticky = true }
    end
  end

  -- Automatic area splits: a comparison run's area you have not entered yet shows once your
  -- clock reaches Attention_TimeNearPct of their time (same rule as "Learn X").
  do
    local playedNow, activeNow = ST.Clock.Now()
    local nowClock = (cfg.Clock == "PLAYED") and playedNow or activeNow
    local timeNear = cfg.Attention_TimeNearPct or D.Attention_TimeNearPct
    for _, cand in ipairs(ST.Compare.UpcomingByTime("area", nowClock / timeNear, 2)) do
      out[#out + 1] = { Key = cand.Key, Axis = "area", Label = cand.Label, Best = cand.Best,
        Progress = math.min(1, nowClock / cand.Best), Sticky = true }
    end
  end

  -- Two groups. FIXED axes (professions, learn, riding, mounted, money) have bounded cardinality
  -- and are NEVER capped. VARIABLE axes (quests, areas, kills, locations) compete for the capped
  -- slots, ordered by most recent progress (sticky rows count as current).
  local FIXED_AXES = { skill = true, learn = true, riding = true, mounted = true, gold = true, bags = true }
  local levelRow = out[1] and out[1].Current and table.remove(out, 1) or nil
  local fixed, variable = {}, {}
  for _, it in ipairs(out) do
    if FIXED_AXES[it.Axis] then fixed[#fixed + 1] = it else variable[#variable + 1] = it end
  end
  local nowWall = time()
  for _, it in ipairs(variable) do
    if it.Sticky then it.SortKey = nowWall + 1 else it.SortKey = it.LastProgress or 0 end
  end
  table.sort(variable, function(a, b) if a.SortKey ~= b.SortKey then return a.SortKey > b.SortKey end return a.Key < b.Key end)
  while #variable > limit do table.remove(variable) end
  -- fixed rows: professions first (most recent gain first), then learn / riding
  table.sort(fixed, function(a, b)
    local pa, pb = (a.Axis == "skill") and 0 or 1, (b.Axis == "skill") and 0 or 1
    if pa ~= pb then return pa < pb end
    return (a.LastProgress or 0) > (b.LastProgress or 0)
  end)
  out = {}
  if levelRow then out[#out + 1] = levelRow end
  for _, it in ipairs(variable) do out[#out + 1] = it end
  for _, it in ipairs(fixed) do out[#out + 1] = it end
  if moneyRow then out[#out + 1] = moneyRow end   -- pinned last
  return out
end

function V.Final()
  if not ST.db.Config.ShowFinalRow then return nil end
  local key = D.Key("level", D.MaxLevel)
  local rec = ST.Record.Current()
  local m = rec.Milestones[key]
  return { Key = key, Axis = "level", Label = "Level " .. D.MaxLevel, Best = ST.Compare.Best(key), Time = m and m[ClockField()] }
end

-- Delta of the most recent level segment vs the best segment for that level.
-- Delta of the level (n-1 -> n) segment vs the comparison segment for that level, or nil when
-- either end of our segment is inferred or the comparison has no such segment.
function V.SegmentDelta(n)
  n = tonumber(n)
  if not n then return nil end
  local rec = ST.Record.Current()
  local field = ClockField()
  local b = rec.Milestones[D.Key("level", n)]
  -- Level 1 is the run start (clock 0). Above that the previous ding must be a real milestone.
  local a = (n <= 2) and { [field] = 0 } or rec.Milestones[D.Key("level", n - 1)]
  if not b or b.Inferred or not a or a.Inferred then return nil end
  local best = ST.Compare.BestLevelSegment(n)
  if not best then return nil end
  return (b[field] - a[field]) - best
end
-- Kept for callers that only want the latest one.
function V.PreviousSegmentDelta() return V.SegmentDelta(ST.Record.Level()) end

-- XP/hour over the (n-1 -> n) level segment, on the selected clock, or nil when either end is
-- inferred / missing or the XP for that level is unknown. XPRequired is the client's real
-- UnitXPMax captured at the ding; the Classic curve is the fallback for older records.
function V.LevelXPPerHour(n)
  n = tonumber(n)
  if not n or n < 2 then return nil end
  local rec = ST.Record.Current()
  local field = ClockField()
  local b = rec.Milestones[D.Key("level", n)]
  local a = (n <= 2) and { [field] = 0 } or rec.Milestones[D.Key("level", n - 1)]
  if not b or b.Inferred or not a or a.Inferred or not b[field] or not a[field] then return nil end
  local seconds = b[field] - a[field]
  if seconds <= 0 then return nil end
  local xp = b.XPRequired or D.XPToLevel_Classic[n]
  if not xp then return nil end
  return xp / seconds * 3600
end

-- XP/hour so far in the CURRENT level: XP into the level over the clock since the last ding.
-- nil until at least 60 s into the level (the first minute is noise) or when the ding is inferred.
function V.CurrentXPPerHour()
  local rec = ST.Record.Current()
  local level = ST.Record.Level()
  local field = ClockField()
  local since = (level <= 1) and { [field] = 0 } or rec.Milestones[D.Key("level", level)]
  if not since or since.Inferred or not since[field] then return nil end
  local played, active = ST.Clock.Now()
  local now = (field == "Played") and played or active
  local seconds = now - since[field]
  if seconds < 60 then return nil end
  return (UnitXP("player") or 0) / seconds * 3600
end

function V.Build()
  local cfg = ST.db.Config
  local rec = ST.Record.Current()
  local key = ST.Compare.Key()
  local played, active = ST.Clock.Now()
  -- Title block: everything the title bar draws, so the renderer reads nothing else.
  -- Collapsed: "vs <target>"  level  lock.  Expanded: one labelled row per filter/setting.
  local title = {
    VsLabel = ST.Compare.TargetLabel(),
    Level = ST.Record.Level(),
    Locked = cfg.Locked == true,
    Expanded = cfg.TitleExpanded == true,
    -- rows shown when expanded; Id is what the renderer passes back to Commands.
    -- The comparison target is not a row: the collapsed "vs ..." line IS that dropdown.
    Rows = {
      { Id = "zone",    Label = "Start zone", Value = ST.Compare.ZoneLabel(key.StartZone) },
      { Id = "class",   Label = "Class",      Value = ST.Compare.ClassLabel(key.Class) },
      { Id = "pattern", Label = "Pattern",    Value = ST.Compare.PatternLabel(key.Pattern) },
      { Id = "clock",   Label = "Clock",      Value = cfg.Clock == "PLAYED" and "Played" or "Active" },
    },
  }
  return {
    Title = title,
    CompareKey = { StartZone = key.StartZone, Class = ST.Compare.ClassLabel(key.Class), Pattern = key.Pattern },
    Level = ST.Record.Level(),
    Done = V.Done(cfg.RowsDone or 4, cfg.RowsDoneLevels or 1),
    Upcoming = V.Upcoming(cfg.RowsUpcoming or 6),
    Final = V.Final(),
    ActiveSeconds = active,
    PlayedSeconds = played,
    Running = ST.Clock.IsRunning(),
    Frozen = rec.CharacterRun_Frozen,
    StoppedReason = ST.Clock.ForcedStop(),
    PreviousSegmentDelta = V.PreviousSegmentDelta(),
  }
end
