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
  return key
end

-- Recently hit milestones, oldest first. Inferred ones are skipped (no real time).
-- Exception: the previous level is always present so "last level -> current level" reads.
function V.Done(limit)
  local rec = ST.Record.Current()
  local field = ClockField()
  -- Done rows: the previous level (always, added below), plus every real split completed within
  -- Attention_DoneSeconds. Inferred milestones (back-filled at login) never appear.
  local now = time()
  local doneWindow = ST.db.Config.Attention_DoneSeconds or D.Attention_DoneSeconds
  local list = {}
  for key, m in pairs(rec.Milestones) do
    if not m.Inferred and m.At and (now - m.At) <= doneWindow then
      local axis = D.ParseKey(key)
      if axis ~= "questaccept" and axis ~= "zone" then
        list[#list + 1] = { Key = key, Axis = axis, Label = MilestoneLabel(key, m), Time = m[field], At = m.At }
      end
    end
  end
  table.sort(list, function(a, b) if a.Time == b.Time then return (a.At or 0) < (b.At or 0) end return a.Time < b.Time end)
  local out = {}
  for i = math.max(1, #list - limit + 1), #list do
    local item = list[i]
    item.Best = ST.Compare.Best(item.Key)
    item.Gold = item.Best ~= nil and item.Time < item.Best
    out[#out + 1] = item
  end
  -- Guarantee the previous level row. It is exempt from the done-window: use the recorded
  -- milestone (real time) whenever one exists; only fall back to a timeless placeholder when
  -- the level was inferred / reached before the addon was installed.
  local level = UnitLevel("player")
  local prevKey = D.Key("level", level)
  local present = false
  for _, it in ipairs(out) do if it.Key == prevKey then present = true break end end
  if not present and level >= 1 then
    local m = rec.Milestones[prevKey]
    local row = { Key = prevKey, Axis = "level", Label = "Level " .. level, Best = ST.Compare.Best(prevKey) }
    if m and not m.Inferred then
      row.Time = m[field]
      row.Gold = row.Best ~= nil and row.Time < row.Best
    else
      row.Inferred = true
    end
    table.insert(out, 1, row)
    while #out > limit do table.remove(out, 2) end   -- keep the level row, drop the oldest other
  end
  return out
end

function V.Upcoming(limit)
  local rec = ST.Record.Current()
  local cfg = ST.db.Config
  local level = UnitLevel("player")
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
    local near = nearStep or nearCap
    local active = ST.Milestones.SkillIsActive(s.Name)
    -- Not gated on the current trainer cap (s.Max): the cap rises with training, the
    -- milestone is still "next 50". Only the absolute skill ceiling applies.
    if nextStep <= D.SkillCeiling and (near or active) then
      local key = D.Key("skill", s.Name, nextStep)
      -- Part of the goal above the current trainer cap is not reachable until trained.
      local capFraction = (s.Max and s.Max < nextStep) and (s.Max / nextStep) or nil
      out[#out + 1] = { Key = key, Axis = "skill", Icon = D.SkillIcon[s.Name], Label = s.Name .. " " .. nextStep, Best = ST.Compare.Best(key),
        Progress = s.Rank / nextStep, ProgressText = s.Rank .. "/" .. nextStep, Active = active,
        CapFraction = capFraction, CapText = capFraction and tostring(s.Max) or nil,
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

  -- Priority: the level row stays first; everything else is ordered by most recent progress
  -- (sticky rows count as current), so what you just did is never cut off by the row cap.
  local levelRow = out[1] and out[1].Current and table.remove(out, 1) or nil
  local nowWall = time()
  for _, it in ipairs(out) do
    if it.Sticky then it.SortKey = nowWall + 1 else it.SortKey = it.LastProgress or 0 end
  end
  table.sort(out, function(a, b) if a.SortKey ~= b.SortKey then return a.SortKey > b.SortKey end return a.Key < b.Key end)
  if levelRow then table.insert(out, 1, levelRow) end
  while #out > limit do table.remove(out) end
  -- Pinned money row: always last, outside the cap.
  if moneyRow then out[#out + 1] = moneyRow end
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
function V.PreviousSegmentDelta()
  local rec = ST.Record.Current()
  local field = ClockField()
  local level = UnitLevel("player")
  local b = rec.Milestones[D.Key("level", level)]
  local a = level > 2 and rec.Milestones[D.Key("level", level - 1)] or { [field] = 0 }
  if not b or b.Inferred or not a or a.Inferred then return nil end
  local best = ST.Compare.BestLevelSegment(level)
  if not best then return nil end
  return (b[field] - a[field]) - best
end

function V.Build()
  local cfg = ST.db.Config
  local rec = ST.Record.Current()
  local key = ST.Compare.Key()
  local played, active = ST.Clock.Now()
  return {
    CompareKey = { StartZone = key.StartZone, Class = ST.Compare.ClassLabel(key.Class), Pattern = key.Pattern },
    Level = UnitLevel("player"),
    Done = V.Done(cfg.RowsDone or 4),
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
