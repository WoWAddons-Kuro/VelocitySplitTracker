# Changelog

## Unreleased

- Renamed to **Velocity** (folder `VelocitySplitTracker`). Saved data from the SplitTimer name is migrated on first load.
- Comparison model: Auto select (fastest run to its own end among runs still ahead of you, hands off at dings), pinned run, Best splits, or none. Zone / class / pattern dropdowns filter the candidate list.
- Reference-run import (`/split import`, History button, hamburger): paste level times from a VOD or another player.
- Milestone axes: levels, quest turn-ins, kills (XP-gain credit), professions with train-threshold and cap markers, first-learn, money acquired, area entries, manual location splits, deaths with rez type.
- Two clocks: Active (idle-aware) and Played; both shown, seconds in lockstep.
- Data window: By Level / By Class / By Start Zone pivots and History with Kills/min, XP/min and Where per split.
- Records keyed by character GUID; game mode (pve / pvp / hardcore-*) stored per run.