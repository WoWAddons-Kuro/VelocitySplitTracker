# SplitTimer

LiveSplit-style milestone timer for World of Warcraft leveling. Records when each
character hits levels, key quest turn-ins, kills, profession steps and riding, on
two clocks (`/played` and an *Active* clock that stops when you go idle), and
compares the current character against your best runs for the same start zone,
class and route pattern.

Target client: WoW Forever (`_forever_`, interface 16001, Mainline UI code).

**Status: early scaffold.** The split window is a mockup driven by placeholder data.
See `SPEC.md` for the design.

| Command | Action |
|---|---|
| `/split` | Toggle the split window |
| `/split history` | History window |
| `/split config` | Settings |
| `/split lock` | Lock / unlock dragging |
| `/split reset` | Reset window position |
| `/split status` | Version and state |

Minimap button: left-click window, right-click history, middle-click settings.
Right-click the split window title for a context menu (lock, times left/right, clock).