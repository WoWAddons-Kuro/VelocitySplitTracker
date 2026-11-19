# Velocity Split Tracker — specification

LiveSplit-style milestone tracker for WoW leveling, inside the game client.
Repo: https://github.com/WoWAddons-Kuro/VelocitySplitTracker  · Folder/TOC: `VelocitySplitTracker` · Display name: Velocity (renamed from SplitTimer 2026-11-17; a legacy `SplitTimerDB` is migrated into `VelocitySplitTrackerDB` on first load) · Slash: `/split`, `/velocity` · SavedVariables: `VelocitySplitTrackerDB` (account-wide).
Target client: WoW Forever (`_forever_`, interface 16001, Mainline UI code). Lua 5.1 headless tests like BTT.Kuro.

## 1. Philosophy

**What this is for** (the author, 2026-11-17, lightly edited):

> I have 12k hours of WoW. I don't need RestedXP telling me to wipe my nose. I want to know
> the rough pacing of my best run, to *decide* whether I'm going to follow it or deviate, and
> how I'm doing against it.
>
> This is mostly **not** for world-first speedruns - that needs a do-not-leave-the-chair
> mentality, and even with Active tracking you leave the mental zone. This is a way to
> **(a)** automatically record the rough shape of a run just because you did it, without
> editing any files; **(b)** import/export good runs to share; **(c)** benchmark against
> whatever you want. A human paladin PvE death-skip run replicating Vitochie's record? A
> Skyborne mage hardcore run that you still benchmark against Vitochie's paladin because you
> are insane? *You* choose.

Design consequences, so they are not re-argued:

- **The tool informs a decision; it does not make it.** It should never silently switch what
  you are racing in a way you did not ask for. Automatic route detection (5.8) may *rank* and
  *suggest*; the reference you see is the one you chose, or `Auto select` with its rule stated.
- **Deviation is a first-class outcome**, not an error. When the player leaves the reference's
  route the window should show that plainly (missed anchors, a fork), not pretend.
- **The far horizon matters as much as the next row.** "Kharanos in 12 min, Ironforge in 22,
  Stormwind in 27 - because this is the Elwynn-transfer route" is the pacing a 12k-hour
  player actually wants; the next-level XP bar is table stakes.
- **Zero authoring.** Every run is recorded; curation (naming a pattern, importing, pinning a
  reference) is optional and after the fact.

- **Record everything, curate later.** Every character automatically records every milestone it reaches, against two clocks. Nothing is ever lost because the player forgot to "start a run".
- **Milestones are benchmarks, not a linear list.** A level-30 character may still not have done Vagash. So the UI shows the *next milestone on each axis*, not "the next row".
- **Comparison is derived from history**, keyed by `(StartZone|ANY, Class|ANY, RunPattern|personal|ANY)`. Unnamed runs are the `personal` pattern; a run becomes a named "run pattern" when the player names it in the History window. Personal Best is computed, never hand-set.
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

## 3. Data model (SavedVariables `VelocitySplitTrackerDB`)

```lua
VelocitySplitTrackerDB = {
  Version = 1,
  Config = { ... },                      -- global UI/behaviour options (section 7)
  Characters = {                         -- keyed by "Name-Realm"
    ["Player-1234-00ABCDEF"] = {         -- a CharacterRun record, keyed by UnitGUID("player") (Name-Realm collided: Forever characters share first names)
      CharacterRun_Key        = "Kuro-Forever",
      CharacterRun_Name       = "Kuro", CharacterRun_Realm = "Forever",
      CharacterRun_ClassFile  = "HUNTER",     -- select(2, UnitClass)
      CharacterRun_Race       = "NightElf",
      CharacterRun_Mode       = "pve",        -- pve | pvp | hardcore-pve | hardcore-pvp | unknown; travels with exports so others can align categories. /split mode overrides.
      CharacterRun_ClientFlavour   = "forever", -- forever | era | classic | mists | mainline | unknown. Forever (realmless) and Era (realms) are different categories; stamped at creation, refreshed each login (Util.ClientInfo: WOW_PROJECT_ID + interface band; Forever = MAINLINE/CAMELOT with 16000 <= interface < 20000).
      CharacterRun_ClientVersion_First   = "1.60.1",  -- GetBuildInfo() version at run start (write-once; THE category version). Legacy records seed it on first login after upgrade.
      CharacterRun_ClientInterface_First = 16001,
      CharacterRun_ClientVersion   = "1.60.3",  -- version LAST played on, refreshed each login
      CharacterRun_ClientInterface = 16003,
      CharacterRun_ClientVersions  = { ["1.60.1"] = 1763300000, ["1.60.3"] = 1763900000 },  -- every version the run touched -> time() first seen on it. History shows "Forever 1.60.1 -> 1.60.3 (1.60.1, 1.60.3)".
      CharacterRun_StartZone  = "Teldrassil",  -- StartZone_Key, resolved once from race (table), fallback first zone seen
      CharacterRun_Pattern    = nil,          -- RunPattern_Name set by the player in History (nil = "personal", the unnamed bucket)
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
| NPC kill | `kill:<creatureID>` (or `kill:name:<slug>` if the ID was never seen) | `CHAT_MSG_COMBAT_XP_GAIN` "<Name> dies, you gain N experience." — the credit signal itself. Creature IDs are learned from `PLAYER_TARGET_CHANGED`. **`COMBAT_LOG_EVENT_UNFILTERED` cannot be registered by addons on this client** (`ADDON_ACTION_FORBIDDEN`, confirmed 2026-11-16). | name from the chat line |
| Zone entered | `zone:<uiMapID>` | `ZONE_CHANGED_NEW_AREA` → `C_Map.GetBestMapForUnit("player")` | `C_Map.GetMapInfo(id).name` |
| Riding | `riding:<rank>` 1..4 | `SPELLS_CHANGED` / `LEARNED_SPELL_IN_SKILL_LINE` (`LEARNED_SPELL_IN_TAB` does not exist here) + `IsSpellKnown` for riding spell IDs (33388, 33391, 34090, 34091 — verify) | `Apprentice Riding` |
| Mounted | `mounted:1` | first time `IsMounted()` is true (poll 1 s / `UNIT_AURA` player). Mount *purchase* is not reliably observable in Classic-style bags, so "first mounted" is the milestone | `First Mount` |
| Profession | `skill:<skillName>:<n>` n ∈ 50,100,150,…,300 (configurable step) | `SKILL_LINES_CHANGED` / `CHAT_MSG_SKILL` → `GetProfessions/GetProfessionInfo` (works here) merged with `GetSkillLineInfo` if present, plus the chat line `SKILL_RANK_UP` parsed directly. Steps already passed at login are back-filled as `Inferred`. | `Skinning 150` |
| Profession learned | `learn:<skillName>` | first time a tracked profession appears in the skill list after a skill event (baseline scan → `Inferred`). Upcoming row "Learn X" shows once the clock reaches `Attention_TimeNearPct` (0.80) of the comparison run's time. | `Learned Skinning` |
| Money acquired | `gold:<copper>` at 100 / 1 000 / 10 000 / 100 000 / 1 000 000 / 10 000 000 (1s 10s 1g 10g 100g 1000g) | `PLAYER_MONEY` positive deltas summed into `GoldAcquired_Copper` (skipped while mail/trade window open). Existing characters seed from purse, passed steps `Inferred`. | `Money Acquired - 10s` |
| Bag slots | `bags:<n>` n ∈ 22, 28, 34, … 96 (every 6 above the 16-slot backpack, up to 4 x 20) | `BAG_UPDATE_DELAYED` / `BAG_CONTAINER_UPDATE` / `PLAYER_EQUIPMENT_CHANGED` → sum of `GetContainerNumSlots(0..4)`; high-water mark in `BagSlots_Max` (a downgrade never un-hits). Login baseline `Inferred`; a swap that crosses several steps fires them all. Upcoming row within `Attention_NearPct` of the next step or 180 s after a bag change; fixed axis; shares the Money auto-hide toggle. | `Bag Slots - 28` |
| Area entered | `area:<Zone>/<Subzone>` | `ZONE_CHANGED` / `_INDOORS` / `_NEW_AREA` → `GetRealZoneText()` + `GetSubZoneText()`; first time per character. Login area is `Inferred`. Upcoming: comparison run's next unentered areas at 80 % of their time. Automatic, no setup. | `Enter Coldridge Pass` |
| Location reached | `loc:<slug>` | user-defined per start zone (`Plans[zone].Locations`: Map, X, Y, Radius=10 yd) via hamburger → *Add location split here…*. Polled 1 s against the 3 nearest unreached points on the current map (shortlist re-sorted every 10 s). Upcoming within 200 yd. | `Reach <name>` |
| Manual | `manual:<slug>` | `/split hit <name>` or click **Split** button | user text |

- A milestone is recorded **once** (first time). Re-triggering is ignored.
- A real hit **replaces** an `Inferred` placeholder; real never overwrites real; inferred never overwrites anything.
- Times recorded = both clocks at the moment of the event, plus `Where = { Map, X, Y, Zone }` for real hits.

## 5. Comparison

**Decision (2026-11-17):** the primary comparison is against **one reference run**, not a
composite of best splits. Most splits are *route-dependent*: "first Hogger kill" at 0:42 in a
run that started in Elwynn means nothing to a run that started in Dun Morogh and met Hogger at
level 14; a composite built across both is nonsense. One run is internally consistent, so every
delta against it is meaningful. Best-splits-across-runs remains a secondary mode for the one
case it is honest about: *your own* runs of the *same* route.

### 5.1 Comparison target
`Config.Compare_Target = { Mode = "Auto" | "Run" | "BestSplits" | "None", RunKey = <CharacterRun_Key> }`

| Mode | Meaning | Title line 2 |
|---|---|---|
| `Auto` (**default**) | a *continuously re-evaluated* pick: the candidate run that is **fastest to its own end, among runs whose end lies ahead of you** (5.1.1). Runs are judged as units by their extent. | `vs auto: Vitochie Dwarf Hunter 1:09 v` |
| `Run` | one specific `CharacterRun`, pinned (another character or an imported reference) | `vs Vitochie Dwarf Hunter 1:09 v` |
| `BestSplits` | best time per milestone across the candidate set (the previous behaviour) | `vs Best splits v` |
| `None` | no comparison; the window only records | `no comparison v` |

- Stored **per context** `Config.Compare_ByContext[startZone .. "|" .. classFile]`, so each (zone, class) keeps its own setting and a rerolled Dwarf Hunter inherits the last Dwarf Hunter's choice.
- A pinned run that is deleted falls back to `Auto` and says so once in chat.

#### 5.1.1 `Auto` selection rule
Each candidate run has an **extent** `E(r)` = the highest *real* level milestone it reached, and an **end time** `T_end(r)` = its clock at `E(r)`. Given the player's current level `L`:

1. Eligible = candidates with `E(r) > L` (their run still has something ahead of you). If none, eligible = all candidates (you have out-levelled every run; keep the best one for the done rows). **Title exhaustion is one level stricter:** only when `L > E(r)` - your last completed level is *past* the run's end - does the title switch to `vs auto: no run data...` (`Target().Exhausted`). At `L == E(r)` (you just dinged the reference's final level) the comparison stays named: that ding row still has its full delta and is exactly what the run was for.
2. Pick the eligible run with the **lowest `T_end(r)`**. Ties → higher `E(r)`, then lower clock at level `L+1`, then name.
3. Re-evaluate on every level ding (and when the candidate set changes). The pick therefore *hands off*: with run A (10:00 to level 5, extent 5) and run B (12:00 to level 5, 30:00 to level 10, extent 10), `Auto` compares against **A until you ding 5**, then **B** — because at level 5 A no longer has anything ahead of you.

Why "fastest to its own end" rather than "fastest to the next level": a run is a unit — its early splits only make sense inside the route that produced its end time. Judging each run by its own extent is what keeps the comparison honest while still letting the shortest-extent-but-fastest run be the reference for as long as it applies.

- The hand-off is announced once in chat (`comparison: now vs Kuro Ciderkeg (run A ended at level 5)`) and the `vs auto:` line updates.
- Deltas on **done rows** always use the run that was the reference *when that split was hit* (stored on the milestone as `Milestone.CompareRunKey`), so a hand-off never recolours history.
- History's ★ marks, per `(zone, class, pattern)`, the run with the highest extent, ties by lower `T_end` — a *different* question ("best run overall") from `Auto` ("best run for where I am now"); both are documented so the two badges are not confused.

```lua
-- pseudo
function Compare.AutoPick(candidates, playerLevel)
  local eligible = filter(candidates, function(r) return Extent(r) > playerLevel end)
  if #eligible == 0 then eligible = candidates end
  sort(eligible, by: EndTime asc, Extent desc, TimeAt(playerLevel+1) asc, Name)
  return eligible[1]
end
```

### 5.2 Candidate set (filters)
The title dropdowns are **filters that narrow the list of runs offered** as a reference (and the `BestSplits` pool); they no longer *are* the comparison.
- **Start zone**: specific or `Any zone`; default = the character's own.
- **Class**: specific or `Any`; default = the character's own.
- **Pattern**: `default` or a named pattern; unnamed runs match `default`; named runs also appear under `default` when `Config.Compare_IncludeNamedInDefault` (default **true**).
- **Mode** (pve / pvp / hardcore-*): must match unless `Config.Compare_AnyMode`; references with unknown mode pass.
- The current character is never its own candidate.
- **Reference runs** (`Core/Reference.lua`): imported split tables stored as ordinary records flagged `CharacterRun_Reference = true`, key `ref:<slug>`, one time for both clocks; shown `(ref)`; never the player's PB. `/split import` opens the paste box.

### 5.3 Title bar
```
☰ vs auto: Vitochie Dwarf Hunter 1:09 [2026.11.17 03:55] v ◆        9 🔒      ← collapsed (default)
   Start zone   Dun Morogh v                                              ← twiddle ◆ expands these
   Class        Hunter v
   Pattern      personal v
   Clock        Active v
```
- **Collapsed** (one line, `T.TitleHeightCollapsed` 24): hamburger, the comparison target as a dropdown (the one thing changed mid-run), the twiddle, the level, the lock. Everything on this line is TOP-anchored so it stays put when the frame grows.
- **Expanded** (`Config.TitleExpanded`): four labelled filter rows under it (`T.TitleRowHeight` 17 each), each value a dropdown clamped to the window edge. The comparison target is *not* repeated as a row - the collapsed line is that dropdown. Renderer draws only from `V.Title` (`VsLabel`, `Level`, `Locked`, `Expanded`, `Rows[]`).
- The dropdown has a **selected-mark column** (check for the active choice, blank gap otherwise) and lists: `Auto select` first, then the candidate runs **ranked in `Auto` order** (5.1.1: eligible first, by `T_end` asc) — so the row directly under `Auto select` is the run Auto is using *right now* — capped at **5** runs, then the two fixed modes:

```
 [✓]  Auto select
 [ ]  Vitochie Dwarf Hunter 1:09 [2026.11.17 03:55]        ← rank 1 = what Auto is using now
 [ ]  Kuro Ciderkeg [2026.11.17 01:10]                      ← rank 2 …
 [ ]  Human Pally 55m [2026.11.17 03:56] (ref)
 ──────────────
 [ ]  Best splits
 [ ]  No comparison
```
- `Auto select` → `Mode = Auto` (the pick may hand off later). Any run row → `Mode = Run`, pinned. The title line shows `vs auto: <name>` in Auto and `vs <name>` when pinned.
- `Config.Compare_DropdownRuns` = 5 (how many ranked runs to list).
- History and the pivot cells gain **"Compare against this run"** (button / cell right-click) which sets the target for the current context.

### 5.4 Deltas under each mode
- `Run`: `delta = mine(M) − ref(M)`; blank when the reference never reached `M`. **Green** = ahead of the reference; **red** = behind; **gold** = ahead of the reference *and* faster than every candidate (a true record for that split).
- `BestSplits`: `delta = mine(M) − min over candidates(M)`; gold = new best.
- `None`: no deltas, no colours, best column blank.
- **Segment delta** on level done-rows, `(+2:14)` left of the cumulative delta: our `t(n) − t(n−1)` minus the comparison segment, which follows the mode (the reference's segment, or the best segment across candidates). Blank when either end of our segment is inferred. Replaced the LiveSplit "Previous Segment" footer (2026-11-17): it sat far from the row it described and its label meant nothing.
- Level segment = `t(level:n) − t(level:n−1)` as before.

### 5.5 Rows derived from the comparison
- Time-based upcoming rows (`Enter X`, `Learn X` via `Compare.UpcomingByTime`) come from the **reference run only** in `Run` mode (its next unentered areas / unlearned professions beyond your current clock); from the candidate pool in `BestSplits`; off in `None`.
- Level / profession / money rows have their own progress metrics and are unaffected.

### 5.6 Implementation map
- `Core/Compare.lua`: `C.Target() → { Mode, RunKey, Run }` (config → `AutoPick` when `Auto`, re-run on `PLAYER_LEVEL_UP`); `C.Extent(rec)`, `C.EndTime(rec)`; `C.Best(key)`, `C.BestLevelSegment(n)`, `C.UpcomingByTime(...)` mode-aware; `C.IsRecord(key, time)`; `C.CandidateRuns()` (dropdown order: Auto, then by `T_end` asc); `C.SetTarget(mode, runKey)` writes `Compare_ByContext`. `Record.Hit` stores `CompareRunKey` on each real milestone.
- `Core/View.lua`: `Gold` = `C.IsRecord` in `Run` mode.
- `UI/LiveWindow.lua`: second title line + `vs` dropdown; `TitleHeight` 40.
- `UI/History.lua`, `UI/DataWindow.lua`: "Compare against this run" action.
- Migration: `CompareZone / CompareClass / ComparePattern` keep their meaning as filters; `Compare_Target` is new and auto-picks until set. `Config.CompareAnyZone` already maps to zone `ANY`.

### 5.7 Open questions
- Should choosing a reference also snap the filters to that run's zone/class? Proposed **no**: filters narrow the list, the `vs` line names the pick; keeping them independent lets you pick a Dun Morogh reference while browsing `Any zone`.
- Context key `zone|class` vs per-character GUID: proposed `zone|class` so rerolls inherit.

### 5.8 Route horizon and route-aware Auto (roadmap)

Today's `Auto` (5.1.1) is **route-blind**: it picks by extent and end time and never notices
that the player walked east to Loch Modan while the reference went to the Tram. Fixing that
is staged so each step is useful on its own and tunable against real data; the full scorer
comes last because with a handful of runs its weights cannot be tuned honestly.

**Stage 0 - `Milestone.CompareRunKey`.** `Record.Hit` stores which run was the reference when
a split was hit; done-row deltas are computed against *that* run forever. Prerequisite for any
hand-off or hot-swap: history must never recolour.

**Stage 1 - Route horizon row(s).** A `Horizon` block under the upcoming rows: the reference
run's next **N anchors** (zone/subzone entries, named kills, first-learns) with their times,
not just the nearest one:
```
   > Kharanos 12:40   > Ironforge 22:00   > Stormwind 27:30     (Elwynn-transfer route)
```
Pure display over `Where`/area milestones already recorded. `Config.Horizon_Anchors` (3).

**Stage 2 - Missed-anchor eligibility.** An `anchor` of run R = an area entry / named kill R
hit at level `L_a`. If the player is past `L_a + 0.5` levels and has not hit it, it is
*missed*. A run with `>= Config.Auto_MaxMissedAnchors` (2) missed anchors is **ineligible** for
`Auto` (it stays pinnable). This alone fixes the Loch-Modan-vs-Tram case with one threshold
instead of six weights. Hand-off is announced in chat as today; hysteresis = the threshold
itself (anchors are discrete, so there is no flicker).

**Stage 3 - Fork ahead.** When the top two eligible runs agree on anchors hit so far but their
next anchors differ, show the alternate's horizon as a dimmed second line:
```
   > Ironforge 22:00   > Stormwind 27:30
   alt: > Vagash 26:00   > Loch Modan 31:00
```
This surfaces the decision *before* the fork (e.g. standing in Kharanos at level 6) instead
of guessing after it. Display only; nothing switches until Stage 2's rule fires.

**Stage 4 - Affinity scorer (only with enough runs).** Per candidate, on each milestone or a
15 s tick: `S = w_pace·PaceRank + w_match·Σ γ^k·Match(recent_k) - w_miss·Σ Age(missed) -
w_dist·Dist(pos, interp(R, level+xp%))`, with a two-check hysteresis margin before the HUD
swaps. Spatial interpolation uses `Where` on level milestones (~1 fix per level - coarse; a
tiebreaker, not a primary). Weights are tuned against logged divergences from Stages 1-3,
not guessed. **Not before the candidate pool for a zone is in the tens of runs.**

Invariant across all stages (from §1): the user can always see *which* run is the reference
and *why* (`vs auto: X` / `vs X`), and any automatic change is announced, never silent.

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
│              ☠ 2                 v2026… │  ← footer: centred status (softcore: deaths; hardcore: "Hardcore"), build at right
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
**Attention model** (decided 2026-11-16, replaces the earlier "near" rule):
- Level: previous level (always, dim/no time if inferred) and `level:<cur+1>` with XP progress — always. No pinned Level 60 unless `Config.ShowFinalRow`.
- Any **progress** on a quest objective or profession rank → that row is shown for `Attention_RecentSeconds` (**180 s**) from the last progress.
- At/over `Attention_NearPct` (**0.90**) of the goal (quest complete-in-log counts as 100 %); for professions the goal is **either** the next 50-step **or** the trainer cap, so a capped profession stays up until trained → the row is **sticky** until completed.
- A **completed** split (quest, profession step, kill) appears in the done list for `Attention_DoneSeconds` (**45 s**) and then disappears. The done list is *not* "the last N milestones".
- Profession rows draw a red band + tick for the part of the goal above the current trainer cap (`CapFraction = trainerMax / nextStep`). The next 50-step is shown even above the cap.
- Riding/Mounted: show `riding:1` from level 38 (configurable) until obtained, `mounted:1` after riding obtained.
- Cap `Config.RowsUpcoming` (default 4); order: level, quests, professions, riding.

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

### 7.1 Data window (tabs)

One window (`/split history`, minimap right-click), four tabs along the top. Three of them are
**fixed pivots** — the same grid widget with its axes pre-chosen, plus a picker on the left for
the dimension being filtered. A generic "choose any axes" pivot was considered and rejected as
more UI than it is worth; these three cover the questions actually asked.

```
[ By Level ] [ By Class ] [ By Start Zone ] [ History ]
```

**Fact table** (all three pivots read the same thing): every *real* milestone of every character,
`(Character, StartZone, Class, Pattern, MilestoneKey) → time` on the selected clock
(Active/Played, title-bar setting). Inferred milestones are excluded. A cell that aggregates
several characters shows the **best** (lowest) time; cells with no fact are blank.

| Tab | Left picker (filter) | Columns | Rows | Cell |
|---|---|---|---|---|
| **By Level** | a level split `2 … 60` (only levels present in data; default = current character's level) | Start zone | Class | best time to that level for (zone, class) |
| **By Class** | a class (only classes present; default = current character's) | Start zone | Level split (present in data) | best time to that level for (zone, class) |
| **By Start Zone** | a start zone (only zones present; default = current character's) | Class | Level split (present in data) | best time to that level for (zone, class) |

- Picker = scrollable list of buttons on the left (`DataWindow_PickerWidth` 120 px); selected item highlighted.
- The current character's column/row is tinted green; the best cell in each row is tinted gold.
- Cell tooltip: which character set the time, its pattern, how many characters contributed.
- Clicking a cell → **History** tab with that character selected.
- Column cap 8 (start zones / classes present are naturally few); rows scroll.
- Grid header shows "N characters" covered by the current filter, so an empty grid is explainable.

**Implementation**
- `Core/Pivot.lua` (pure Lua, headless-testable):
  - `Pivot.Facts(clockField) → { Pivot_Fact… }`, `Pivot_Fact = { CharKey, CharName, Zone, Class, Pattern, Key, Axis, Level, Time }`
  - `Pivot.BestGrid(facts, filterFn, colOf, rowOf) → { Cols, Rows, Cell[row][col] = { Time, CharKey, CharName, Count } }`
  - `Pivot.LevelsPresent / ZonesPresent / ClassesPresent(facts)` for the pickers.
- `UI/DataWindow.lua`: window shell, tab strip, one reusable `GridPanel` (picker + header + scrollable rows). The three pivot tabs are three configurations of `GridPanel`; the History tab hosts the existing `UI/History.lua` content re-parented into the window.

#### Tab 4 — History

The existing run list + detail panel (`UI/History.lua` as built): run list with fixed columns
(PB ★, character, start zone, class, level, Active, Played, pattern), detail with the milestone
table (Active / Played / level segment), actions **Name pattern…**, **Clear pattern**,
**Copy as text**, **Delete run**.

#### Shared
- Tab strip at the top of the window; the last selected tab is remembered (`Config.DataWindow_Tab`).
- The Active clock is force-stopped while the window is open (already true).
- Fixed 780×480 for now; resizable later.

**Open questions**
- Pivot rows are `level:*` only in v1. Quests / professions / money as rows is a later chip on By Class / By Start Zone if wanted.
- Pattern is not a picker in v1; cells aggregate across patterns. A pattern filter in the grid header is the natural extension.

### 7.2 Split Config panel
- Plan editor for `(StartZone, Plan_Name)`: ordered list of milestone entries with `Label`, optional `Zone`, remove/reorder; add via: *Add level(s)*, *Add quest from log* (dropdown of current quest log), *Add current target as kill*, *Add zone (current)*, *Add profession step*, *Add manual*.
- Options: clock, times side, rows done/upcoming, idle seconds, skill step (50), near-percent, fonts/scale/alpha, hide in combat, lock.
- Plans ship with a built-in default per StartZone = all levels + riding + mounted + zone-entry for the standard progression zones; built-in defaults live in `Data/DefaultPlans.lua` and are copied into `SplitTimerDB.Plans` on first edit (so updates to defaults still flow for untouched plans).

## 8. File layout

```
VelocitySplitTracker/
  VelocitySplitTracker.toc
  Libs/LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0   (minimap button; copied from BTT.Kuro)
  Core/Util.lua          time/delta formatting, Print, load-phase probes (taint diagnostics)
  Core/Data.lua          race → start zone, riding spells, skill steps/caps, gold steps, icons, Milestone_Key helpers
  Core/Record.lua        per-character run record (keyed by GUID), Record.Hit = the single milestone entry point
  Core/Clock.lua         Played + Active clocks, activity signals, persistence
  Core/Compare.lua       filters → candidates, comparison target (Auto/Run/BestSplits/None), best-per-milestone, segments
  Core/Milestones.lua    axis detectors → Record.Hit(Milestone_Key); attention state
  Core/Locations.lua     user-placed location splits (per start zone), proximity poll
  Core/View.lua          view-model for the live window (title block, done rows, upcoming rows)
  Core/Pivot.lua         fact table + best-grid for the data-window pivots
  Core/Reference.lua     imported reference runs (ref:<slug>)
  UI/Theme.lua           fonts, colours, textures, menu abstraction
  UI/LiveWindow.lua      the split window
  UI/History.lua         run list + detail (hosted in the data window)
  UI/DataWindow.lua      tabbed window: By Level / By Class / By Start Zone / History
  UI/Config.lua          settings panel
  VelocitySplitTracker.lua   addon bootstrap, DB init/migration, slash commands, minimap, popups
  Assets/                icons, screenshots
  tests/                 (planned) lua5.1 headless harness; covers Clock accumulation, Compare, View
  README.md, CHANGELOG.md, LICENSE, .gitignore, .pkgmeta
```

## 9. Phases

- [x] **P0 Scaffold**: git init, TOC, bootstrap, SavedVariables schema, `/split status`. (test harness: pending)
- [x] **P1 Clocks**: Played sync, Active accumulator with idle/forced-stop rules, persistence. (unit tests: pending)
- [x] **P2 Milestones**: level (+login reconcile), quest turn-in/accept, kill (XP-gain chat credit), area, profession, first-learn, money, death, riding, mounted, location, manual.
- [~] **P3 Compare**: filters, Auto / Run / BestSplits / None target, level segments, upcoming selection, reference import. Plans / plan editor (7.2) not started.
- [x] **P4 Live window**: theme, rows, collapsible title with dropdown rows, big/compact timer, footer, times-left option, lock/drag. (hide-in-combat: pending)
- [x] **P5 Data window**: By Level / By Class / By Start Zone pivots + History (list, detail, name pattern, delete, copy as text, compare against this run).
- [~] **P6 Config panel**: options exist; plan editor not started. Active clock forced stop while open.
- [~] **P7 Polish**: minimap button, README, CHANGELOG, icons done; first release tag pending.

## 10. Open questions / to verify in-game

1. ~~Profession API~~ — **resolved**: `GetProfessions/GetProfessionInfo` works; both paths merged anyway.
2. Dropdown API: `UIDropDownMenu_*` vs `MenuUtil.CreateContextMenu`. Code both behind `UI/Menu.lua`.
3. `PLAYER_STARTED_MOVING` availability on 16001 — fallback is the speed poll either way.
4. Riding spell IDs on this client (Classic set 33388/33391 vs later 34090/34091/90265).
5. ~~Kill attribution~~ — **resolved**: combat log registration is FORBIDDEN here; XP-gain chat line is the credit signal.
6. StartZone for a race: use race→zone table; if the character is first seen above level ~5 in another zone, still trust the race table (Human→Elwynn, etc.). OK?
7. Should the big timer show **Active** by default (assumed yes) with Played small underneath?
8. Rows_Done default 4 / Rows_Upcoming default 4 / idle 30 s / skill step 50 / near 80 % — tweak?
9. **Client facts learned**: `RegisterEvent` throws on unknown event names (abort the whole function) — always register through a pcall helper. `LEARNED_SPELL_IN_TAB` is absent. `ChatFrame_DisplayTimePlayed` must not be overridden (taint). Skyborne race → "Zephras Isle". `/played` chat line is accepted once at login.