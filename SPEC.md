# SplitTimer — specification

LiveSplit-style milestone tracker for WoW leveling, inside the game client.
Repo: https://github.com/WoWAddons-Kuro/SplitTimer  · Folder/TOC: `SplitTimer` · Slash: `/split` · SavedVariables: `SplitTimerDB` (account-wide).
Target client: WoW Forever (`_forever_`, interface 16001, Mainline UI code). Lua 5.1 headless tests like BTT.Kuro.

## 1. Philosophy

- **Record everything, curate later.** Every character automatically records every milestone it reaches, against two clocks. Nothing is ever lost because the player forgot to "start a run".
- **Milestones are benchmarks, not a linear list.** A level-30 character may still not have done Vagash. So the UI shows the *next milestone on each axis*, not "the next row".
- **Comparison is derived from history**, keyed by `(StartZone, Class|ANY, RunPattern|default)`. A run becomes a named "run pattern" when the player names it in the History window. Personal Best is computed, never hand-set.
- Level 60 freezes the run (read-only forever after).

## 2. Clocks

| Clock | Definition | Source | Survives logout |
|---|---|---|---|
| **Played** | Total `/played` for the character | `RequestTimePlayed()` → `TIME_PLAYED_MSG` on login, then `GetTime()` delta accumulation; re-synced on every `TIME_PLAYED_MSG` | yes (server authoritative) |
| **Active** | Played time accumulated only while the character is *doing something* | Our own accumulator, persisted | yes (we store `ActiveSeconds_Total` + flush every 15 s and on logout) |

### 2.1 Active clock rules
- On login, if the character record has no `ActiveSeconds_Total`, initialise it to the current Played total (treat pre-addon time as active).
- Active clock starts **stopped** on every login/reload. It only starts on the first activity signal (movement/cast/combat/interaction) *after* `PLAYER_ENTERING_WORLD`.
- Active clock **stops** when `Config.Active_IdleSeconds` (default **30 s**) pass with no activity signal. The idle window itself is **not** counted: when activity resumes after an idle stop, the accumulator rolls back to `LastActivity_Timestamp` (i.e. idle seconds are subtracted). Implementation: accumulate on each tick only while `now - LastActivity_Timestamp < IdleSeconds`.
- Active clock is **forced stopped** while: the Split Config panel is shown; the History window is shown; player is explicitly paused (`/split pause` / pause button); `UnitIsAFK("player")`.
- Activity signals (any resets `LastActivity_Timestamp`):
  - `PLAYER_STARTED_MOVING`, `PLAYER_STARTED_TURNING`, plus a 1 s poll of `GetUnitSpeed("player") > 0` (covers taxi/vehicle/mounted where events may not fire)
  - `UNIT_SPELLCAST_SENT` / `_SUCCEEDED` / `_CHANNEL_START` for `player`
  - `PLAYER_REGEN_DISABLED`, `COMBAT_LOG_EVENT_UNFILTERED` where source is player (in combat = active continuously)
  - UI interaction: `GOSSIP_SHOW`, `QUEST_DETAIL`, `QUEST_PROGRESS`, `QUEST_COMPLETE`, `MERCHANT_SHOW`, `TRAINER_SHOW`, `TAXIMAP_OPENED`, `LOOT_OPENED`, `BANKFRAME_OPENED`, `MAIL_SHOW`, `TRADE_SHOW`, `BAG_UPDATE`
  - `CHAT_MSG_SAY/PARTY/WHISPER_INFORM` sent by player (typing counts; configurable, default on)
  - Any milestone hit
- Both clocks are stored per milestone; display defaults to **Active** with Played shown small/secondary (option to swap or hide one).

## 3. Data model (SavedVariables `SplitTimerDB`)

```lua
SplitTimerDB = {
  Version = 1,
  Config = { ... },                      -- global UI/behaviour options (section 7)
  Characters = {                         -- keyed by "Name-Realm"
    ["Kuro-Forever"] = {                 -- a CharacterRun record
      CharacterRun_Key        = "Kuro-Forever",
      CharacterRun_Name       = "Kuro", CharacterRun_Realm = "Forever",
      CharacterRun_ClassFile  = "HUNTER",     -- select(2, UnitClass)
      CharacterRun_Race       = "NightElf",
      CharacterRun_StartZone  = "Teldrassil",  -- StartZone_Key, resolved once from race (table), fallback first zone seen
      CharacterRun_Pattern    = nil,          -- RunPattern_Name set by the player in History (nil = "default")
      CharacterRun_CreatedAt  = 1763300000,   -- time() at first sight
      CharacterRun_Frozen     = false,        -- true once level 60 recorded
      CharacterRun_Level      = 23,           -- last known level (cheap display without login)
      PlayedSeconds_Total     = 61234,        -- last synced /played + accumulation
      PlayedSeconds_SyncedAt  = 1763300000,   -- time() of last TIME_PLAYED_MSG
      ActiveSeconds_Total     = 40210,
      Milestones = {                          -- keyed by Milestone_Key (section 4)
        ["level:10"]   = { Played = 9100, Active = 7200, At = 1763301000 },
        ["quest:1126"] = { Played = ..., Active = ..., At = ... },   -- e.g. turned in
        ["kill:1130"]  = { ... },                                      -- Vagash
        ["skill:Skinning:150"] = { ... },
      },
      ActivityLog = { ... },                  -- optional ring buffer of pause/resume stamps for debugging (cap 200)
    },
  },
  Plans = {                                -- user-edited milestone plans, keyed by StartZone_Key then Plan_Name
    ["Teldrassil"] = { ["default"] = { Plan_Milestones = { "level:*", "quest:1126", ... } } },
  },
}
```

- Characters record **all** milestones of all built-in axes whether or not they are in a plan. A plan only decides what the live window **shows**; History and comparison use the full record.
- Deleted/rerolled characters: records remain until the player deletes them in History (there is a *Delete* with confirm).

## 4. Milestone axes

`Milestone_Key` is `"<axis>:<id>[:<value>]"`. Keys are stable strings so comparison is a table lookup.

| Axis | Key | Detected by | Display name |
|---|---|---|---|
| Level | `level:<n>` 2..60 | `PLAYER_LEVEL_UP` (arg1 = new level); on login reconcile any missing lower levels **not** recorded (mark them with current times + `Inferred=true`, shown greyed) | `Level 10` |
| Quest turn-in | `quest:<questID>` | `QUEST_TURNED_IN` (questID) | quest title via `C_QuestLog.GetTitleForQuestID` / `QuestUtils_GetQuestName`; cached in `Plan` entry as `Label` |
| Quest accepted | `questaccept:<questID>` | `QUEST_ACCEPTED` | `Accept: <title>` |
| NPC kill | `kill:<creatureID>` | `COMBAT_LOG_EVENT_UNFILTERED` `UNIT_DIED`/`PARTY_KILL` where destGUID creature id matches **and** player or party tagged it (we accept: `PARTY_KILL` with source player/pet, or `UNIT_DIED` while player had that GUID targeted/in combat with it in last 10 s) | creature name from GUID cache (`UNIT_TARGET` name capture) or plan `Label` |
| Zone entered | `zone:<uiMapID>` | `ZONE_CHANGED_NEW_AREA` → `C_Map.GetBestMapForUnit("player")` | `C_Map.GetMapInfo(id).name` |
| Riding | `riding:<rank>` 1..4 | `LEARNED_SPELL_IN_TAB` / `SPELLS_CHANGED` + `IsSpellKnown` for riding spell IDs (33388, 33391, 34090, 34091, 90265 etc. — verify list for this client) | `Apprentice Riding` |
| Mounted | `mounted:1` | first time `IsMounted()` is true (poll 1 s / `UNIT_AURA` player). Mount *purchase* is not reliably observable in Classic-style bags, so "first mounted" is the milestone | `First Mount` |
| Profession | `skill:<skillName>:<n>` n ∈ 50,100,150,…,300 (configurable step) | `SKILL_LINES_CHANGED` / `CHAT_MSG_SKILL` → scan `GetNumSkillLines/GetSkillLineInfo` (Classic API) with fallback `GetProfessions/GetProfessionInfo` (Mainline). Records when `rank >= n` | `Skinning 150` |
| Manual | `manual:<slug>` | `/split hit <name>` or click **Split** button | user text |

- A milestone is recorded **once** (first time). Re-triggering is ignored.
- Times recorded = both clocks at the moment of the event.

## 5. Comparison

### 5.1 Comparison key
`CompareKey = (StartZone_Key, ClassFile | "ANY", RunPattern_Name | "default")`.
The live window's title shows this as `{Start Zone} - {Class|Any} - {default|Pattern}`; Class and Pattern are dropdowns (section 6.1).

### 5.2 What counts
- Candidate runs = all `Characters` matching StartZone, matching Class (or all classes for ANY), matching Pattern (unnamed runs match `default`; a named run matches only its pattern **and** is also eligible in `default` — configurable `Config.Compare_IncludeNamedInDefault`, default **true**).
- The current character is excluded from its own comparison.
- **Per-milestone best** (LiveSplit "best segments" spirit, adapted to benchmarks): for each `Milestone_Key`, the minimum `Active` (or Played, per selected clock) across candidate runs *that reached it*. Runs do not have to be complete.
- **PB run** (LiveSplit "personal best"): the candidate run with the lowest time at the **highest common level milestone**, i.e. the run that was fastest to the furthest level. Shown in History with a ★.
- Comparison mode option: `BestPerMilestone` (default) or `PBRun`.

### 5.3 Deltas
- Reaching milestone M: `delta = mine - best(M)`. Green `-0:42` ahead, red `+1:10` behind, gold if it is a new best across all candidates. White/none if no comparison data.
- Levels additionally track **segment** time: `level:n` segment = `t(level:n) - t(level:n-1)`. Footer "Previous Segment" uses the level segment delta; the level row tooltip shows cumulative and segment.

## 6. Live window (LiveSplit clone)

No border, dark translucent background (`Config.Bg_Alpha`), alternating row shading, movable (drag on title unless locked), scale option, hide-in-combat option. All fonts from `Config.Font_*`.

```
┌──────────────────────────────────────────┐
│ [icon] Teldrassil - Hunter ▾ - default ▾   23 │  ← title: compare key; right = character level
│──────────────────────────────────────────│
│ ★ Level 22            -0:31     1:02:53 │  ← recently hit milestones (last N=Config.Rows_Done, default 4)
│   Vagash               +1:10    1:04:01 │
│   Skinning 100         -0:04    1:09:33 │
│──────────────────────────────────────────│
│ ▶ Level 24  ▓▓▓▓▓░░░ 61%        1:17:13 │  ← always: next level, xp bar, best time for it
│   Cave of Ferocity (turn-in)    1:21:33 │  ← upcoming on other axes, when "near" (6.2)
│   Skinning 150  (134/150)       1:30:00 │
│──────────────────────────────────────────│
│                       1:12:56.4          │  ← big timer: Active (selected clock), colour per 6.3
│                       played 1:40:12     │  ← secondary clock, small
│ Previous Segment              -0:31     │
└──────────────────────────────────────────┘
```

- **Times-left option** (`Config.Times_Side = "RIGHT"|"LEFT"`): puts the `[delta] [time]` block left of the name.
- Rows show an icon per axis (level: `Interface\Icons\Achievement_Level_10`-style; quest: `!`/`?` atlas; kill: skull; skill: profession icon; riding: horse).
- Final `level:60` row is pinned at the bottom of the upcoming section like LiveSplit pins the last split, with its best time.

### 6.1 Title dropdowns
- **Class**: `Any` + classes that have ≥1 run for this StartZone (current class always present). Uses `UIDropDownMenu` / `MenuUtil` (whichever exists; abstract behind `ST_Menu`).
- **Pattern**: `default` + every `RunPattern_Name` existing for this StartZone (any class). Plus `New pattern…` which opens a text popup and names the **current character** with it.
- Start zone is fixed by the character (not a dropdown). Right-click on title → context menu: Lock, Clock (Active/Played), Times side, Open History, Open Config, Pause.

### 6.2 "Upcoming" selection rules
- Level: always show `level:<cur+1>` with XP progress `UnitXP/UnitXPMax`.
- Quest turn-in: show if the quest is in the quest log **and** complete (`C_QuestLog.IsComplete`) or in log at all when `Config.Upcoming_ShowQuestInLog` (default: only when complete).
- Kill: show if the creature's plan zone == current zone (plan entries carry optional `Zone`), or the creature's name has been seen as a nameplate/target in the last 5 min.
- Profession: show next step when `rank/next >= Config.Upcoming_SkillNearPct` (default **0.80**).
- Riding/Mounted: show `riding:1` from level 38 (configurable) until obtained, `mounted:1` after riding obtained.
- Zone: show the next zone milestone of the plan that is not yet reached (plan order).
- Cap `Config.Rows_Upcoming` (default 4); priority: level, then quests complete, then skill, then rest, by plan order.

### 6.3 Big timer colour
white = Active clock stopped (idle/paused) · green = last milestone ahead of best · red = behind · gold = last milestone was a new best · grey = run frozen (level 60).

## 7. Windows & commands

| Command | Action |
|---|---|
| `/split` | toggle live window |
| `/split history` | History window |
| `/split config` | Split Config panel (plans + options). **Active clock paused while open.** |
| `/split pause` / `resume` | explicit Active clock pause |
| `/split hit <name>` | record a manual milestone |
| `/split lock` | toggle drag lock |
| `/split clock active|played` | select displayed/compared clock |
| `/split status` | print version, clocks, compare key, candidate run count |

### 7.1 History window
- Left: list of all `Characters` — name, class icon, start zone, level, pattern, Active / Played time, ★ if PB for its compare key, ❄ if frozen. Sort by column. Filter by StartZone/Class/Pattern.
- Right: detail of selected run — milestone table (name, Active, Played, delta vs selected comparison), per-level segment column.
- Actions: **Name pattern…** (sets `CharacterRun_Pattern`), **Clear pattern**, **Delete run** (confirm), **Copy as text** (plain-text table to an edit box for sharing).

### 7.2 Split Config panel
- Plan editor for `(StartZone, Plan_Name)`: ordered list of milestone entries with `Label`, optional `Zone`, remove/reorder; add via: *Add level(s)*, *Add quest from log* (dropdown of current quest log), *Add current target as kill*, *Add zone (current)*, *Add profession step*, *Add manual*.
- Options: clock, times side, rows done/upcoming, idle seconds, skill step (50), near-percent, fonts/scale/alpha, hide in combat, lock.
- Plans ship with a built-in default per StartZone = all levels + riding + mounted + zone-entry for the standard progression zones; built-in defaults live in `Data/DefaultPlans.lua` and are copied into `SplitTimerDB.Plans` on first edit (so updates to defaults still flow for untouched plans).

## 8. File layout

```
SplitTimer/
  SplitTimer.toc
  Libs/LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0   (minimap button; copied from BTT.Kuro)
  Core/Clock.lua         Played + Active clocks, activity signals, persistence
  Core/Milestones.lua    axis detectors → ST_Record(Milestone_Key)
  Core/Compare.lua       candidate selection, best-per-milestone, PB run, deltas (pure Lua, tested)
  Core/Plans.lua         default plans, plan storage, upcoming selection (pure Lua, tested)
  Data/StartZones.lua    race → StartZone_Key; zone progression per StartZone
  Data/DefaultPlans.lua
  Data/Spells.lua        riding spell IDs, profession skill names
  UI/Theme.lua           fonts, colours, row factory (alternating shading), time formatting
  UI/LiveWindow.lua
  UI/History.lua
  UI/Config.lua
  UI/Menu.lua            dropdown abstraction (UIDropDownMenu vs MenuUtil)
  SplitTimer.lua         addon bootstrap, events, slash commands
  tests/harness.lua, tests/run.lua   (lua5.1; covers Clock accumulation, Compare, Plans)
  README.md, CHANGELOG.md, LICENSE, .gitignore, .pkgmeta
```

## 9. Phases

- [x] **P0 Scaffold**: git init, TOC, bootstrap, SavedVariables schema, `/split status`. (test harness: pending)
- [x] **P1 Clocks**: Played sync, Active accumulator with idle/forced-stop rules, persistence. (unit tests: pending; in-game verification: pending)
- [x] **P2 Milestones**: level (+login reconcile), quest turn-in/accept, kill (PARTY_KILL credit), zone, profession, riding, mounted, manual. In-game API verification pending.
- [~] **P3 Compare + Plans**: compare-key resolution, best-per-milestone, level segments, upcoming selection done. PB-run marker, default plans and plan editor not started.
- [x] **P4 Live window**: theme, rows, title dropdowns, big timer, footer, times-left option, lock/drag. (hide-in-combat: pending)
- [ ] **P5 History window**: list, detail, name pattern, delete, copy as text.
- [ ] **P6 Config panel**: plan editor + options; Active clock forced stop while open.
- [ ] **P7 Polish**: minimap button, README, CHANGELOG, first release tag.

## 10. Open questions / to verify in-game

1. Profession API on this client: `GetSkillLineInfo` (Classic) vs `GetProfessionInfo` (Mainline). Code both; verify which exists.
2. Dropdown API: `UIDropDownMenu_*` vs `MenuUtil.CreateContextMenu`. Code both behind `UI/Menu.lua`.
3. `PLAYER_STARTED_MOVING` availability on 16001 — fallback is the speed poll either way.
4. Riding spell IDs on this client (Classic set 33388/33391 vs later 34090/34091/90265).
5. Kill attribution: is `PARTY_KILL` fired on this client? Otherwise use target-GUID heuristic.
6. StartZone for a race: use race→zone table; if the character is first seen above level ~5 in another zone, still trust the race table (Human→Elwynn, etc.). OK?
7. Should the big timer show **Active** by default (assumed yes) with Played small underneath?
8. Rows_Done default 4 / Rows_Upcoming default 4 / idle 30 s / skill step 50 / near 80 % — tweak?