# Velocity

A split tracker and an auto-generated leveling guide in one, for World of Warcraft.

Velocity records when each character hits levels, key quests, kills, profession steps,
money thresholds, area entries and deaths, and compares the run you are on against a
reference run - one of your own, or one imported from a VOD or another player's export.

Two things set it apart from a plain `/played` timer:

- **The Active clock.** It stops when you stop. Walk away from the keyboard and the idle
  time is not counted, so a run interrupted by real life still produces a comparable number.
  `/played` is tracked alongside it for the purist case.
- **It is a guide as much as a timer.** The window shows the next milestone of the run you
  are chasing, reminds you when a profession can be trained (the untrainable stretch of the
  bar is red), and keeps the money, profession and level rows up without you having to
  author a plan. Less aggressive than a step-by-step guide addon: no giant dialogs, no
  manual route editing, just what is relevant right now.

Target client: WoW Forever (`_forever_`, interface 16001, Mainline UI code).
Folder / TOC: `VelocitySplitTracker`. SavedVariables: `VelocitySplitTrackerDB`
(data from the earlier `SplitTimer` name is migrated automatically on first load).

## Commands

| Command | Action |
|---|---|
| `/split` or `/velocity` | Toggle the split window |
| `/split history` | Data window (By Level / By Class / By Start Zone / History) |
| `/split import` | Import a reference run (paste level times) |
| `/split config` | Settings |
| `/split pause` / `resume` | Pause / resume the Active clock |
| `/split clock active|played` | Which clock the window and comparisons use |
| `/split mode <pve|pvp|hardcore-pve|hardcore-pvp|auto>` | Game mode carried on the run record |
| `/split lock` / `reset` | Lock dragging / reset window position |
| `/split wipe` | Discard this character's record and start fresh |
| `/split status`, `ms`, `rows`, `skills`, `cpu` | Diagnostics |

Minimap button: left-click window, right-click data window, middle-click settings.
The hamburger (top-left of the split window) opens the menu: add/remove location splits,
pause the clock, toggles, History, Import, Settings.

## Comparison

The title bar's second line shows who you are racing. **Auto select** picks, among runs
whose extent is still ahead of your level, the one fastest to its own end - and hands off
to a longer run when you pass the short one's end. You can pin any run instead, use
*Best splits* (fastest time per milestone across all matching runs), or no comparison.
The zone / class / pattern dropdowns filter which runs are offered.

See `SPEC.md` for the design.