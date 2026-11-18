-- Detectors for every milestone axis. Each one calls ST.Record.Hit(key, label).
-- Also keeps the live "upcoming" helpers: recent quests, profession ranks, riding.
local ADDON_NAME, ST = ...; ST.Probe = "load:" .. (debugstack(1, 1, 0):match("[^\\/]+%.lua") or "?")
local U = ST.Util
local D = ST.Data
-- (load phase set on the ADDON_NAME line)

ST.Milestones = {}
local M = ST.Milestones

------------------------------------------------------------------------
-- Quest log snapshot (for "recently progressed" quests)
------------------------------------------------------------------------
-- QuestLog_Snapshot[questID] = { Title=, Complete=bool, Objectives="fingerprint" }
local questSnapshot = {}
-- QuestRecent[] = questIDs ordered most-recently-progressed first
M.QuestRecent = {}
local questTitleCache = {}

local function QuestTitle(questID)
  if questTitleCache[questID] then return questTitleCache[questID] end
  local title
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then title = C_QuestLog.GetTitleForQuestID(questID) end
  if not title and QuestUtils_GetQuestName then title = QuestUtils_GetQuestName(questID) end
  if title and title ~= "" then questTitleCache[questID] = title end
  return title
end
M.QuestTitle = QuestTitle

local function ObjectiveFingerprint(questID)
  if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return "" end
  local objs = C_QuestLog.GetQuestObjectives(questID)
  if not objs then return "" end
  local parts = {}
  for i, o in ipairs(objs) do parts[i] = tostring(o.numFulfilled or 0) .. "/" .. tostring(o.numRequired or 0) .. (o.finished and "!" or "") end
  return table.concat(parts, ",")
end

-- Iterate quest log entries (Mainline C_QuestLog.GetInfo or Classic GetQuestLogTitle).
local function EachQuest(fn)
  local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
  for i = 1, n do
    local questID, title, isHeader, isComplete
    if C_QuestLog and C_QuestLog.GetInfo then
      local info = C_QuestLog.GetInfo(i)
      if info then questID, title, isHeader = info.questID, info.title, info.isHeader end
      if questID and C_QuestLog.IsComplete then isComplete = C_QuestLog.IsComplete(questID) end
    elseif GetQuestLogTitle then
      local t, _, _, header, _, complete, _, id = GetQuestLogTitle(i)
      title, isHeader, isComplete, questID = t, header, (complete == 1 or complete == true), id
    end
    if questID and not isHeader then
      if title then questTitleCache[questID] = title end
      fn(questID, title, isComplete)
    end
  end
end

local function Touch(questID)
  for i, id in ipairs(M.QuestRecent) do if id == questID then table.remove(M.QuestRecent, i) break end end
  table.insert(M.QuestRecent, 1, questID)
  while #M.QuestRecent > 10 do table.remove(M.QuestRecent) end
  M.Attention().Quests[questID] = time()
  -- refresh once the recent window lapses so the row drops on time
  C_Timer.After((ST.db.Config.Attention_RecentSeconds or D.Attention_RecentSeconds) + 0.5, function() if ST.Live then ST.Live.QueueRefresh() end end)
end

-- Progressed within the attention window?
function M.QuestRecentlyProgressed(questID)
  local t = M.Attention().Quests[questID]
  return t ~= nil and (time() - t) < (ST.db.Config.Attention_RecentSeconds or D.Attention_RecentSeconds)
end

-- Persistent attention state lives on the character record (wall-clock stamps), so the
-- 180 s / 45 s windows survive /reload and relog exactly as they were.
function M.Attention()
  local rec = ST.Record.Current()
  rec.Attention = rec.Attention or {}
  rec.Attention.Quests = rec.Attention.Quests or {}   -- questID -> time() of last progress
  rec.Attention.Skills = rec.Attention.Skills or {}   -- skillName -> time() of last gain
  rec.Attention.SkillRanks = rec.Attention.SkillRanks or {}  -- skillName -> last seen rank
  return rec.Attention
end

-- On login: rebuild the in-memory recent-quest order from the persisted stamps and schedule
-- refreshes for every window that is still open, so the display comes back as it was.
function M.RestoreAttention()
  local A = M.Attention()
  local window = ST.db.Config.Attention_RecentSeconds or D.Attention_RecentSeconds
  local now = time()
  local list = {}
  for questID, t in pairs(A.Quests) do
    if now - t < window then list[#list + 1] = { questID, t } else A.Quests[questID] = nil end
  end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  M.QuestRecent = {}
  for i = 1, math.min(10, #list) do M.QuestRecent[i] = list[i][1] end
  for name, t in pairs(A.Skills) do if now - t >= window then A.Skills[name] = nil end end
  -- one refresh when the soonest still-open window closes
  local soonest
  for _, t in pairs(A.Quests) do if not soonest or t < soonest then soonest = t end end
  for _, t in pairs(A.Skills) do if not soonest or t < soonest then soonest = t end end
  if soonest then C_Timer.After(math.max(0.5, soonest + window - now + 0.5), function() if ST.Live then ST.Live.QueueRefresh() end end) end
end

local firstScan = true
function M.ScanQuestLog()
  if firstScan then M.RestoreAttention() end
  local seen = {}
  EachQuest(function(questID, title, isComplete)
    seen[questID] = true
    local fp = ObjectiveFingerprint(questID)
    local prev = questSnapshot[questID]
    if not prev then
      questSnapshot[questID] = { Title = title, Complete = isComplete, Objectives = fp }
      if not firstScan then Touch(questID) end
    elseif prev.Objectives ~= fp or prev.Complete ~= isComplete then
      prev.Objectives, prev.Complete = fp, isComplete
      Touch(questID)
    end
  end)
  for questID in pairs(questSnapshot) do if not seen[questID] then questSnapshot[questID] = nil end end
  -- Drop recent entries that left the log without being turned in (abandoned).
  for i = #M.QuestRecent, 1, -1 do if not seen[M.QuestRecent[i]] then table.remove(M.QuestRecent, i) end end
  firstScan = false
end

function M.QuestIsComplete(questID)
  local s = questSnapshot[questID]
  return s and s.Complete or false
end

------------------------------------------------------------------------
-- Professions
------------------------------------------------------------------------
-- Returns { { Name=, Rank=, Max= }, ... } for tracked skills.
local chatRank = {}              -- SkillName -> rank learned from CHAT_MSG_SKILL (API-independent)
M.LastSkillAPI = "none"
function M.Skills()
  local out = {}
  local seen = {}
  local function Add(name, rank, max)
    if name and D.TrackedSkills[name] and not seen[name] then
      seen[name] = true
      out[#out + 1] = { Name = name, Rank = rank or chatRank[name] or 0, Max = max or 300 }
    end
  end
  -- Try every API this client exposes; they do not all report Classic-data skill lines.
  if GetNumSkillLines and GetSkillLineInfo then
    M.LastSkillAPI = "GetSkillLineInfo"
    local outer = ST.Probe; ST.Probe = (outer or "") .. ">GetSkillLineInfo"
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
      if not isHeader then Add(name, rank, max) end
    end
    ST.Probe = outer
  end
  if GetProfessions and GetProfessionInfo then
    if #out == 0 then M.LastSkillAPI = "GetProfessions" end
    local outer = ST.Probe; ST.Probe = (outer or "") .. ">GetProfessions"
    local idx = { GetProfessions() }
    for _, i in pairs(idx) do
      if type(i) == "number" then
        local name, _, rank, max = GetProfessionInfo(i)
        Add(name, rank, max)
      end
    end
    ST.Probe = outer
  end
  -- Last resort: skills we have only ever seen via the chat line.
  for name, rank in pairs(chatRank) do if not seen[name] then M.LastSkillAPI = M.LastSkillAPI .. "+chat"; Add(name, rank, nil) end end
  return out
end

-- "Your skill in Fishing has increased to 12." -> name, rank. Works without any skill API.
local skillPattern
function M.ParseSkillChat(msg)
  if not skillPattern then
    local fmt = SKILL_RANK_UP or "Your skill in %s has increased to %d."
    skillPattern = "^" .. fmt:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)"):gsub("%.$", "%%.?") .. "$"
  end
  local name, rank = msg:match(skillPattern)
  if name then chatRank[name] = tonumber(rank) end
  return name, tonumber(rank)
end

function M.CheckSkills()
  local step = ST.db.Config.SkillStep or D.SkillStep
  local now = time()
  local A = M.Attention()
  -- Baseline scan (login / no skill-up event pending): steps already passed are back-filled as
  -- Inferred, exactly like levels - they are not splits achieved now.
  local baseline = not M._skillEventPending
  for _, s in ipairs(M.Skills()) do
    -- Any rank gain marks the skill "active" for a while so its next step shows in the window.
    -- A missing baseline counts as a gain too: if we are here because of a skill-up event,
    -- the very first observation IS the gain, and we must not silently swallow it.
    local prev = A.SkillRanks[s.Name]
    if (prev ~= nil and s.Rank > prev) or (prev == nil and M._skillEventPending) then
      A.Skills[s.Name] = now
    end
    -- First time this profession shows up in the skill list = it was just learned
    -- (or, on the baseline scan, learned before the addon saw it -> inferred).
    if prev == nil then
      ST.Record.Hit(D.Key("learn", s.Name), "Learned " .. s.Name, { Inferred = baseline })
    end
    A.SkillRanks[s.Name] = s.Rank
    for n = step, s.Rank - (s.Rank % step), step do
      -- Only the step reached by THIS gain is a real split; anything older is inferred.
      local inferred = baseline or (prev ~= nil and n <= prev)
      ST.Record.Hit(D.Key("skill", s.Name, n), s.Name .. " " .. n, { Inferred = inferred })
    end
  end
  M._skillEventPending = false
end

function M.SkillIsActive(name)
  local t = M.Attention().Skills[name]
  return t ~= nil and (time() - t) < (ST.db.Config.Attention_RecentSeconds or D.Attention_RecentSeconds)
end

-- Earliest expiry among active skills (so the window can drop the row on time), or nil.
function M.NextSkillExpiry()
  local soonest
  local window = ST.db.Config.Attention_RecentSeconds or D.Attention_RecentSeconds
  for _, t in pairs(M.Attention().Skills) do
    local untilTime = t + window
    if untilTime > time() and (not soonest or untilTime < soonest) then soonest = untilTime end
  end
  return soonest  -- wall-clock time()
end

------------------------------------------------------------------------
-- Riding / mounted
------------------------------------------------------------------------
function M.RidingRank()
  local best = 0
  for _, r in ipairs(D.RidingSpells) do
    for _, spell in ipairs(r.Spells) do
      if IsSpellKnown and IsSpellKnown(spell) then best = math.max(best, r.Rank) end
    end
  end
  return best
end

function M.CheckRiding()
  local rank = M.RidingRank()
  for _, r in ipairs(D.RidingSpells) do
    if r.Rank <= rank then ST.Record.Hit(D.Key("riding", r.Rank), r.Label) end
  end
  if IsMounted and IsMounted() then ST.Record.Hit("mounted:1", "First Mount") end
end

------------------------------------------------------------------------
-- Kills (credit required: PARTY_KILL from us/our pet, or the XP-gain death line)
------------------------------------------------------------------------
local function CreatureIDFromGUID(guid)
  if not guid then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
local nameByCreatureID = {}
local creatureIDByName = {}      -- learned from the player's target as they fight

-- Remember the creature ID behind a name whenever we look at one (PLAYER_TARGET_CHANGED).
function M.NoteTarget()
  if not UnitExists("target") or UnitIsPlayer("target") then return end
  local id = CreatureIDFromGUID(UnitGUID("target"))
  local name = UnitName("target")
  if id and name then creatureIDByName[name] = id; nameByCreatureID[id] = name end
end

-- Credit signal: "<Name> dies, you gain N experience." Pattern is built from the client's
-- own format string so it works in any locale. (COMBAT_LOG_EVENT_UNFILTERED is forbidden here.)
local xpPattern
local function OnXPGainLine(msg)
  if not xpPattern then
    local fmt = COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
    xpPattern = "^" .. fmt:gsub("%%s", "(.-)"):gsub("%%d", "%%d+"):gsub("%.$", "%%.?")
  end
  local name = msg:match(xpPattern)
  if not name or name == "" then return end
  -- Prefer a stable creature ID (seen via target); fall back to a name-keyed milestone.
  local id = creatureIDByName[name]
  if not id and UnitExists("target") and UnitName("target") == name then
    id = CreatureIDFromGUID(UnitGUID("target"))
    if id then creatureIDByName[name] = id; nameByCreatureID[id] = name end
  end
  local key = id and D.Key("kill", id) or D.Key("kill", "name", (name:gsub("%s+", "_")))
  ST.Record.Hit(key, name)
end

function M.CreatureName(id) return nameByCreatureID[id] end

------------------------------------------------------------------------
-- Areas: first entry into a zone/subzone pair ("Enter Coldridge Pass"). Automatic, no setup.
------------------------------------------------------------------------
local lastAreaKey
local function OnArea()
  local zone = GetRealZoneText and GetRealZoneText() or nil
  local sub = GetSubZoneText and GetSubZoneText() or nil
  if not zone or zone == "" then return end
  if sub == "" then sub = nil end
  local name = sub or zone
  local key = D.Key("area", (zone .. "/" .. (sub or "")):gsub("%s+", "_"))
  if key == lastAreaKey then return end
  lastAreaKey = key
  -- The very first area seen after login is where you logged in, not somewhere you entered.
  if M._areaBaselinePending then
    M._areaBaselinePending = false
    ST.Record.Hit(key, "Enter " .. name, { Inferred = true })
    return
  end
  ST.Record.Hit(key, "Enter " .. name)
end
M._areaBaselinePending = true
function M.CurrentAreaKey() return lastAreaKey end

------------------------------------------------------------------------
-- Deaths. death:<n> split on PLAYER_DEAD; the rez type is written back onto that milestone:
-- CONFIRM_XP_LOSS fires when the player talks to a spirit healer, so a PLAYER_UNGHOST within
-- 30 s of it is a spirit rez, otherwise a corpse run. (Deliberate deaths are a route tool.)
------------------------------------------------------------------------
local lastDeathKey, lastDeathAt, lastSpiritPromptAt

function M.DeathCount()
  return ST.Record.Current().Deaths_Count or 0
end

local function OnDeath()
  local rec = ST.Record.Current()
  rec.Deaths_Count = (rec.Deaths_Count or 0) + 1
  local n = rec.Deaths_Count
  lastDeathKey = D.Key("death", n)
  lastDeathAt = GetTime()
  ST.Record.Hit(lastDeathKey, "Death #" .. n)
  if ST.Live then ST.Live.QueueRefresh() end
end

local function OnSpiritPrompt() lastSpiritPromptAt = GetTime() end

local function OnUnghost()
  if not lastDeathKey then return end
  local rec = ST.Record.Current()
  local m = rec.Milestones[lastDeathKey]
  if m and not m.Rez then
    local spirit = lastSpiritPromptAt and (GetTime() - lastSpiritPromptAt) < 30
    m.Rez = spirit and "spirit" or "corpse"
    m.RezAfter = lastDeathAt and math.floor(GetTime() - lastDeathAt + 0.5) or nil
    m.Label = string.format("Death #%s (%s, %s)", lastDeathKey:match(":(%d+)$") or "?", m.Rez, m.RezAfter and U.FormatTime(m.RezAfter) or "?")
    U.Print("%s", m.Label)
  end
  lastDeathKey, lastDeathAt, lastSpiritPromptAt = nil, nil, nil
  if ST.Live then ST.Live.QueueRefresh() end
end

-- Login baseline: a dead/ghost character at login must not count as a new death.
function M.SeedDeathState()
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then lastDeathKey = nil end
end

------------------------------------------------------------------------
-- Gold acquired: cumulative positive money deltas (loot, vendor, quest rewards).
-- Deltas while the mail or trade window is open are not "acquired" and are skipped.
------------------------------------------------------------------------
local lastMoney = nil

local function GoldStepLabel(copper) return "Money Acquired - " .. D.FormatCopper(copper, true) end

-- Current cumulative total; seeds from the purse on first sight of an existing character.
function M.GoldAcquired()
  local rec = ST.Record.Current()
  if rec.GoldAcquired_Copper == nil then
    rec.GoldAcquired_Copper = GetMoney() or 0
    -- steps already passed at seeding are back-fills, not splits
    for _, step in ipairs(D.GoldSteps_Copper) do
      if rec.GoldAcquired_Copper >= step then ST.Record.Hit(D.Key("gold", step), GoldStepLabel(step), { Inferred = true }) end
    end
  end
  return rec.GoldAcquired_Copper
end

function M.NextGoldStep()
  local total = M.GoldAcquired()
  for _, step in ipairs(D.GoldSteps_Copper) do if total < step then return step end end
  return nil
end

-- Take the purse baseline now (login), so the first PLAYER_MONEY of the session is measured as
-- a delta and can fire a split - instead of becoming the seed and swallowing the step.
function M.SeedMoney()
  lastMoney = GetMoney() or 0
  M.GoldAcquired()
end

local function OnMoney()
  local now = GetMoney() or 0
  if lastMoney == nil then M.SeedMoney(); return end
  local delta = now - lastMoney
  lastMoney = now
  if delta <= 0 then return end
  local mailOpen = MailFrame and MailFrame:IsShown()
  local tradeOpen = TradeFrame and TradeFrame:IsShown()
  if mailOpen or tradeOpen then return end
  local rec = ST.Record.Current()
  rec.GoldAcquired_Copper = M.GoldAcquired() + delta
  M.Attention().Gold = time()
  for _, step in ipairs(D.GoldSteps_Copper) do
    if rec.GoldAcquired_Copper >= step then ST.Record.Hit(D.Key("gold", step), GoldStepLabel(step)) end
  end
  if ST.Live then ST.Live.QueueRefresh() end
end

function M.GoldRecentlyProgressed()
  local t = M.Attention().Gold
  return t ~= nil and (time() - t) < (ST.db.Config.Attention_RecentSeconds or D.Attention_RecentSeconds)
end

------------------------------------------------------------------------
-- Zone
------------------------------------------------------------------------
local function OnZone()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return end
  local info = C_Map.GetMapInfo(mapID)
  if info and info.mapType == 3 then  -- Enum.UIMapType.Zone
    ST.Record.Hit(D.Key("zone", mapID), info.name)
  end
end

------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local questScanQueued = false
local function QueueQuestScan()
  if questScanQueued then return end
  questScanQueued = true
  C_Timer.After(1.0, function() questScanQueued = false; U.InPhase("Milestones.timer:ScanQuestLog", M.ScanQuestLog); if ST.Live then ST.Live.QueueRefresh() end end)
end

function M.Init()
  -- Event names differ between client flavours; an unknown one must never abort Init
  -- (it would leave the OnEvent handler unset and silently kill all tracking).
  local function Reg(event)
    local outer = U.Phase("Reg:" .. event)
    local ok = pcall(frame.RegisterEvent, frame, event)
    U.PhaseEnd(outer)
    if not ok then U.Print("|cffaaaaaa(event %s not on this client; skipped)|r", event) end
  end
  Reg("PLAYER_LEVEL_UP")
  Reg("QUEST_TURNED_IN")
  Reg("QUEST_ACCEPTED")
  Reg("QUEST_LOG_UPDATE")
  Reg("UNIT_QUEST_LOG_CHANGED")
  Reg("SKILL_LINES_CHANGED")
  Reg("CHAT_MSG_SKILL")
  Reg("SPELLS_CHANGED")
  Reg("LEARNED_SPELL_IN_TAB")       -- Classic-era clients only
  Reg("LEARNED_SPELL_IN_SKILL_LINE") -- its Mainline successor
  -- COMBAT_LOG_EVENT_UNFILTERED is a FORBIDDEN registration on this client (confirmed with the
  -- ADDON_ACTION_FORBIDDEN probe). Kill credit comes from the XP-gain chat line instead.
  Reg("CHAT_MSG_COMBAT_XP_GAIN")
  Reg("ZONE_CHANGED_NEW_AREA")
  Reg("PLAYER_ENTERING_WORLD")
  Reg("PLAYER_XP_UPDATE")
  Reg("PLAYER_TARGET_CHANGED")
  Reg("PLAYER_MONEY")
  Reg("ZONE_CHANGED")
  Reg("ZONE_CHANGED_INDOORS")
  Reg("PLAYER_DEAD")
  Reg("PLAYER_UNGHOST")
  Reg("CONFIRM_XP_LOSS")
  -- First-mount detection: a slow poll instead of UNIT_AURA (which fires constantly in combat).
  local o = U.Phase("NewTicker")
  C_Timer.NewTicker(3, function()
    if IsMounted and IsMounted() and not ST.Record.Has("mounted:1") then ST.Record.Hit("mounted:1", "First Mount") end
  end)
  U.PhaseEnd(o); o = U.Phase("SetScript")
  -- Every event runs under pcall: an error in one detector must not be swallowed by a hidden
  -- script-error setting (the symptom is "the split silently didn't record"). It is printed
  -- once per distinct message so a per-tick failure cannot flood chat.
  local reported = {}
  local function OnEvent(_, event, ...)
    local outer = U.Phase("Milestones.event:" .. event)
    if event == "PLAYER_LEVEL_UP" then
      local level = ...
      ST.Record.Current().CharacterRun_Level = level
      -- Auto comparison re-evaluates on every ding (the pick can hand off to a longer run)
      ST.Compare.Invalidate()
      local key = D.Key("level", level)
      ST.Record.Hit(key, "Level " .. level)
      -- XP the level just completed required (UnitXPMax of the level we were on), for XP/min.
      local m = ST.Record.Current().Milestones[key]
      if m and not m.Inferred and M._lastXPMax and M._lastXPMax > 0 then m.XPRequired = M._lastXPMax end
      M._lastXPMax = nil
    elseif event == "QUEST_TURNED_IN" then
      local questID = ...
      ST.Record.Hit(D.Key("quest", questID), QuestTitle(questID) or ("Quest " .. questID))
      QueueQuestScan()
    elseif event == "QUEST_ACCEPTED" then
      local a, b = ...
      local questID = type(b) == "number" and b or a   -- classic passes (logIndex, questID)
      ST.Record.Hit(D.Key("questaccept", questID), "Accept: " .. (QuestTitle(questID) or questID))
      QueueQuestScan()
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
      QueueQuestScan()
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
      if event == "CHAT_MSG_SKILL" then
        local name = M.ParseSkillChat((...))
        if name then M.Attention().Skills[name] = time() end
        M._skillEventPending = true
      end
      M.CheckSkills(); if ST.Live then ST.Live.QueueRefresh() end
      -- drop the row again once the active window lapses
      local expiry = M.NextSkillExpiry()
      if expiry then C_Timer.After(math.max(0.5, expiry - time() + 0.5), function() if ST.Live then ST.Live.QueueRefresh() end end) end
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
      M.CheckRiding()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
      OnXPGainLine((...))
    elseif event == "ZONE_CHANGED_NEW_AREA" then
      OnZone(); OnArea()
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
      OnArea()
    elseif event == "PLAYER_DEAD" then
      OnDeath()
    elseif event == "CONFIRM_XP_LOSS" then
      OnSpiritPrompt()
    elseif event == "PLAYER_UNGHOST" then
      OnUnghost()
    elseif event == "PLAYER_XP_UPDATE" then
      -- remember the current level's XP cap; consumed by the next PLAYER_LEVEL_UP
      M._lastXPMax = UnitXPMax("player")
      if ST.Live then ST.Live.QueueRefresh() end
    elseif event == "PLAYER_TARGET_CHANGED" then
      M.NoteTarget()
    elseif event == "PLAYER_MONEY" then
      OnMoney()
    elseif event == "PLAYER_ENTERING_WORLD" then
      C_Timer.After(3, function()
        local o = U.Phase("Milestones.enterworld+3s")
        U.InPhase("ScanQuestLog", M.ScanQuestLog)
        U.InPhase("CheckSkills", M.CheckSkills)
        U.InPhase("CheckRiding", M.CheckRiding)
        U.InPhase("SeedMoney", M.SeedMoney)
        U.InPhase("OnZone", OnZone)
        U.InPhase("OnArea", OnArea)   -- baseline: the login area is inferred, not entered
        U.PhaseEnd(o)
        if ST.Live then ST.Live.QueueRefresh() end
      end)
    end
    U.PhaseEnd(outer)
  end
  frame:SetScript("OnEvent", function(self, event, ...)
    local ok, err = pcall(OnEvent, self, event, ...)
    if not ok then
      err = tostring(err)
      if not reported[err] then reported[err] = true; U.Print("|cffff4040%s handler failed:|r %s", event, err) end
      ST.Probe = nil
    end
  end)
  U.PhaseEnd(o)
end
