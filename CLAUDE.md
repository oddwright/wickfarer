# Emberwake

An original pixel-art spaceship roguelike for Android and iOS phones and foldables.
Godot 4.7.2, GDScript, Compatibility renderer. Design doc and art rules live outside the
repo (links in README); this file is the rulebook for the code.

## Commands

```sh
godot --headless --path . --import                  # once after a fresh clone or new files
godot --headless --path . -s tests/run_tests.gd     # all checks; must pass before every push
gdformat -l 100 scripts tests tools                 # format (pip install "gdtoolkit==4.*")
gdlint scripts tests tools                          # lint, config in gdlintrc
godot --headless --path . -s tools/autobattle.gd -- 60   # balance report after any rules change
xvfb-run godot --path . -s tools/shot.gd -- 2400 1080 out.png   # screenshot at a screen size
```

## Architecture rules

1. **The simulation decides; the view draws.** `scripts/sim/` is plain `RefCounted` code with no
   nodes, no input and no rendering. It must run headless. `scripts/view/` only reads sim state and
   sends orders through `Combat.apply()` (or the matching entry point for other modes). Never
   change sim state from the view.
2. **Player and enemies share one code path.** Anything a ship can do goes in `Ship`; the AI sends
   the same orders a player can. No `if side == 0` rules in the sim.
3. **Fixed step.** The sim ticks at `Combat.TICK` (20 Hz). Never use frame delta or wall-clock time
   in the sim. All randomness comes from `RngStreams`, one named stream per domain; add a new
   stream rather than borrowing another domain's.
4. **Determinism survives saves.** Every continuous sim value is snapped with `Q.q()` once per
   tick (see `Ship.quantize()`). New float state must be added there and to `to_dict`/`from_dict`.
   The resume test must stay green.
5. **Content is data.** Ships, weapons, species, systems and strings live in `data/*.json`. New
   content must not need code changes. Add validation for every new field in
   `ContentDB.validate()`.
6. **Every player-facing string is a translation key** in `data/strings_en.json`, read with
   `tr()`. No literal English in the view.
7. **Saves are JSON only.** Never load Godot Resources from `user://`. Write through
   `SaveService` (temp file, swap, backup). Changing the save shape means bumping
   `SaveService.VERSION`, adding a step to `SaveService.migrate()`, and adding a fixture under
   `tests/fixtures/`. Never delete a migration step or a fixture.
8. **Read JSON numbers with `int()`/`float()`.** JSON makes every number a float.
9. **Screens go through `ScreenManager` and `HudLayout`.** Pixel art is drawn at a whole-number
   scale only. Nothing interactive sits on the fold line in the Square layout. Add new buttons to
   `HudLayout` so `test_layouts_on_every_screen` checks them on every device size.
10. **Touch first.** Hit targets are at least 48 dp (about 10 native pixels at 5x). No hover-only
    information. Long press is the secondary action; right click stands in for it on desktop.
11. **Text is pixel text.** Use `TextLayer._text()` with the 3x5 font; no hi-res fonts.
12. **Mobile lifecycle.** Save on `NOTIFICATION_APPLICATION_PAUSED` and focus loss, never rely on
    a quit event.

## Code style

- Static typing everywhere (`var x: int`, `:=`, typed arrays, return types).
- `class_name` for shared types; private members start with `_`.
- Format with `gdformat -l 100`; CI rejects unformatted code and lint errors.
- Comments explain why, not what. Keep functions short; split a tick into `_tick_*` helpers.

## Tests

- Every rules change gets a test in `tests/run_tests.gd` (add the name to the list in `_init`).
- Every bug fix gets a test that failed before the fix.
- Run the auto-battle report after balance or AI changes and put the numbers in the PR.

## Art

- Sprites in `art/` are placeholders exported by `tools/art_export.py` from the concept-art
  generators. Final art follows the Pixel Art Bible: locked palette, 5x scale, only the Ember glows.
- Never hand-edit exported PNGs; change the generator or replace the asset through the art pipeline.

## Workflow

- Branch from `main`, open a PR, keep it to one change. CI (tests, lint, Android build, layout
  screenshots) and the automatic review must pass before merging.
- Commit messages: imperative summary line, then why.
