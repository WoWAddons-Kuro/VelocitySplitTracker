-- Detectors for every milestone axis. Each one calls ST.Record.Hit(key, label).
-- Also keeps the live "upcoming" helpers: recent quests, profession ranks, riding.
local ADDON_NAME, ST = ...
local U = ST.Util
local D = ST.Data

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
end

local firstScan = true
function M.ScanQuestLog()
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
local skillRankSnapshot = {}     -- SkillName -> last seen rank
M.SkillActiveUntil = {}          -- SkillName -> GetTime() until which it is shown as "active"
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
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
      if not isHeader then Add(name, rank, max) end
    end
  end
  if GetProfessions and GetProfessionInfo then
    if #out == 0 then M.LastSkillAPI = "GetProfessions" end
    local idx = { GetProfessions() }
    for _, i in pairs(idx) do
      if type(i) == "number" then
        local name, _, rank, max = GetProfessionInfo(i)
        Add(name, rank, max)
      end
    end
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
  local now = GetTime()
  for _, s in ipairs(M.Skills()) do
    -- Any rank gain marks the skill "active" for a while so its next step shows in the window.
    -- A missing baseline counts as a gain too: if we are here because of a skill-up event,
    -- the very first observation IS the gain, and we must not silently swallow it.
    local prev = skillRankSnapshot[s.Name]
    if (prev ~= nil and s.Rank > prev) or (prev == nil and M._skillEventPending) then
      M.SkillActiveUntil[s.Name] = now + (ST.db.Config.SkillActiveSeconds or D.SkillActiveSeconds)
    end
    skillRankSnapshot[s.Name] = s.Rank
    for n = step, s.Rank - (s.Rank % step), step do
      ST.Record.Hit(D.Key("skill", s.Name, n), s.Name .. " " .. n)
    end
  end
  M._skillEventPending = false
end

function M.SkillIsActive(name)
  local untilTime = M.SkillActiveUntil[name]
  if untilTime and untilTime > GetTime() then return true end
  if untilTime then M.SkillActiveUntil[name] = nil end
  return false
end

-- Earliest expiry among active skills (so the window can drop the row on time), or nil.
function M.NextSkillExpiry()
  local soonest
  for _, t in pairs(M.SkillActiveUntil) do if not soonest or t < soonest then soonest = t end end
  return soonest
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

local function OnCombatLog()
  local _, sub, _, sourceGUID, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
  if sub ~= "PARTY_KILL" then return end
  local playerGUID = UnitGUID("player")
  local petGUID = UnitGUID("pet")
  if sourceGUID ~= playerGUID and sourceGUID ~= petGUID then return end
  local id = CreatureIDFromGUID(destGUID)
  if id then
    nameByCreatureID[id] = destName
    ST.Record.Hit(D.Key("kill", id), destName)
  end
end

function M.CreatureName(id) return nameByCreatureID[id] end

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
  C_Timer.After(1.0, function() questScanQueued = false; M.ScanQuestLog(); if ST.Live then ST.Live.QueueRefresh() end end)
end

function M.Init()
  frame:RegisterEvent("PLAYER_LEVEL_UP")
  frame:RegisterEvent("QUEST_TURNED_IN")
  frame:RegisterEvent("QUEST_ACCEPTED")
  frame:RegisterEvent("QUEST_LOG_UPDATE")
  frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
  frame:RegisterEvent("SKILL_LINES_CHANGED")
  frame:RegisterEvent("CHAT_MSG_SKILL")
  frame:RegisterEvent("SPELLS_CHANGED")
  frame:RegisterEvent("LEARNED_SPELL_IN_TAB")
  frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("PLAYER_XP_UPDATE")
  -- First-mount detection: a slow poll instead of UNIT_AURA (which fires constantly in combat).
  C_Timer.NewTicker(3, function()
    if IsMounted and IsMounted() and not ST.Record.Has("mounted:1") then ST.Record.Hit("mounted:1", "First Mount") end
  end)
  frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LEVEL_UP" then
      local level = ...
      ST.Record.Current().CharacterRun_Level = level
      ST.Record.Hit(D.Key("level", level), "Level " .. level)
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
        if name then M.SkillActiveUntil[name] = GetTime() + (ST.db.Config.SkillActiveSeconds or D.SkillActiveSeconds) end
        M._skillEventPending = true
      end
      M.CheckSkills(); if ST.Live then ST.Live.QueueRefresh() end
      -- drop the row again once the active window lapses
      local expiry = M.NextSkillExpiry()
      if expiry then C_Timer.After(expiry - GetTime() + 0.5, function() if ST.Live then ST.Live.QueueRefresh() end end) end
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
      M.CheckRiding()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
      OnCombatLog()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
      OnZone()
    elseif event == "PLAYER_XP_UPDATE" then
      if ST.Live then ST.Live.QueueRefresh() end
    elseif event == "PLAYER_ENTERING_WORLD" then
      C_Timer.After(3, function()
        M.ScanQuestLog(); M.CheckSkills(); M.CheckRiding(); OnZone()
        if ST.Live then ST.Live.QueueRefresh() end
      end)
    end
  end)
end
