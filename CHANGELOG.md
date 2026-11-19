# Changelog

## Unreleased

- Renamed to **Velocity** (folder `VelocitySplitTracker`). Saved data from the SplitTimer name is migrated on first load.
- Comparison model: Auto select (fastest run to its own end among runs still ahead of you, hands off at dings), pinned run, Best splits, or none. Zone / class / pattern dropdowns filter the candidate list.
- Reference-run import (`/split import`, History button, hamburger): paste level times from a VOD or another player.
- Milestone axes: levels, quest turn-ins, kills (XP-gain credit), professions with train-threshold and cap markers, first-learn, money acquired, area entries, manual location splits, deaths with rez type.
- Two clocks: Active (idle-aware) and Played; both shown, seconds in lockstep.
- Data window: By Level / By Class / By Start Zone pivots and History with Kills/min, XP/min and Where per split.
- Records keyed by character GUID; game mode (pve / pvp / hardcore-*) stored per run.
- Client flavour and version (Forever 1.60.x vs Classic Era 1.15.x) stored per run - first-played version (write-once, the category), last-played version, and every version touched - and shown in History (Client column, detail line, pattern dialog, copy-as-text `client=`); reference imports accept `client=forever/1.60.1`. `/split status` reports the client. Realmless Forever runs and Era runs are different categories.
- New milestone axis: bag slots (`bags:<n>`), a split every 6 total container slots from 22 to 96. Login baseline is inferred; equipping a bigger bag fires the steps it crosses. Upcoming row "Bag Slots - 20 of 22" appears near a step or after a bag change.
- Fixed: `View.lua:252 attempt to compare number with nil` spam after a ding - the done-row level delta parsed the milestone key's axis instead of its level number (`tonumber("level")`); `SegmentDelta` now also returns nil instead of a bogus full-elapsed segment when the previous level's ding is missing.