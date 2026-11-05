# Saves and resume

Wickfarer must come back exactly where the player left it, even after the app is
swiped away or killed by the OS in the background. This page is the contract every
feature that adds state must follow.

## When the game saves

Phones don't promise a quit event. iOS kills a swiped-away app with no callback, and
Android may kill a backgrounded process without notice. So the game never relies on
one save at the end:

- **On leaving the screen**: `NOTIFICATION_APPLICATION_PAUSED` and
  `NOTIFICATION_APPLICATION_FOCUS_OUT` (and `WM_CLOSE_REQUEST` on desktop). Both fire
  before the app reaches the app switcher, which is the only place it can be swiped away.
- **After every run action**: a jump, a choice, a purchase, reading an outcome
  (`main._enter_screen()`).
- **After every accepted fight order** (power, aim, move, ward), and **every
  `AUTOSAVE_EVERY` seconds** while a fight runs, so even a crash loses at most a
  couple of seconds of a fight.
- **When a menu opens or closes**, so the app reopens on the same page.

A write that would store exactly the last bytes again is skipped, so a paused game
doesn't wear the flash.

Writes are atomic: temp file, then swap, keeping the last good save as `.bak`
(`SaveService.write`). A kill at any moment leaves either the new or the previous save.

## Save slots (files in `user://`)

| Slot | Owner | Shape | Versioned by |
|---|---|---|---|
| `run.json` | `main.gd` | `{"run": Run.to_dict(), "ui": {...}}` | `SaveService.VERSION` + `migrate()` |
| `settings.json` | `GameSettings` | comfort settings | `GameSettings.SETTINGS_VERSION` in `from_dict()` |
| `tutorial.json` | tutorial (in progress) | tutorial progress | its own version, like settings |
| `profile.json` | `Profile` | records, Wake Log, unlocks, Hush Depth | `Profile.PROFILE_VERSION` in `from_dict()` |

Anything that outlives a run gets its own slot. The run slot is erased when a run
ends, so state stored there dies with the run.

## The `ui` block

What the screen was showing, so a cold start goes straight back to it instead of the
title. Read with `.get()` and defaults everywhere; an empty or missing block means
"open on the title", which is how saves from before this block load.

```json
"ui": {
  "menu": "",            // "", "title", "pause", "options", "confirm", or a new page id
  "menu_base": "",       // the page Back returns to
  "confirm": "",         // what the confirm page asks about
  "paused_before_menu": false,
  "weapon": -1,          // selected weapon slot
  "crew": -1,            // selected crew uid
  "music": {"theme": false, "full": false, "start_hull": [0, 0]}
}
```

A new menu page adds its own keys here (for example the ship picker's highlighted
ship), saved in `main._ui_state()` and restored in `main._restore_ui()`, and adds
itself to `main.RESUMABLE_PAGES` under the page Back returns to. Pages over the title
(Options, the New run confirm) reopen over the title. Unknown pages, or a page over
the wrong base, fall back to the title.

A live fight always comes back paused with "tap to resume", never running.

## Rules for new state

1. **Sim state** (anything that changes what happens next) goes in the sim object's
   `to_dict`/`from_dict`: `Run`, `Ship`, `Crew`, `Room`, `Combat`. Floats are snapped in
   `quantize()` once per tick, or resume drifts. Randomness only through `RngStreams`.
2. **Read every new key with a default** (`d.get("xp", 0.0)`), with `int()`/`float()`.
3. **Changing the run save's shape** (renaming, moving or re-meaning a key, or a new key
   whose default would be wrong for old saves) bumps `SaveService.VERSION`, adds a
   `migrate()` step and a fixture `tests/fixtures/run_save_v<N>.json`. Keep each
   step self-contained so parallel branches can renumber at merge: whoever merges
   second takes the next number.
4. **View-only state** (selection, the open menu, music stage) goes in the `ui` block.
   Purely cosmetic, short-lived state (floating numbers, flashes, shake) is not saved.
5. **Meta state** that outlives a run (unlocks, currencies, tutorial flags) goes in its
   own slot. Award it idempotently: the run save is erased when a run ends, and a kill
   between "write the profile" and "erase the run" replays the run's last save on the
   next launch. Give the run a unique id when it is created (not the seed: seeds come
   from the clock and repeat), save it in `Run.to_dict()`, and record awarded ids in
   the profile so the same run is never paid twice.
6. Add a resume test: build the state, save, load into a fresh object, and check
   `J.canonical(a.to_dict()) == J.canonical(b.to_dict())`, then tick both and compare.
