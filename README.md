# Emberwake: Phase 0 combat prototype

One fight between the Tallow Wren and an Ashmarket Cutter, touch only.
Godot 4.7.2, GDScript, Compatibility renderer.

## Run it
- Open this folder in Godot 4.7.2 and press Play. On desktop, a left click is a tap,
  holding the click (or a right click) is a long press, and Space pauses.
- On an Android phone: install the latest build from GitHub Releases, or let Obtainium keep it
  up to date. See [docs/INSTALL.md](docs/INSTALL.md). Every green build of `main` is published.
- iOS needs a Mac with Xcode for now; docs/INSTALL.md lists what an iOS pipeline would need.

## Controls
- Tap a weapon, then an enemy room, to aim it. Long-press a weapon to stop firing.
- Tap a crew member, then a room on your ship, to send them there.
- Tap a system to add power; long-press to take power away.
- Tap the ward button to move your ward to the other deck (it loses half its layers).
- Red corner marks show where the enemy is aiming.

## Checks
- `godot --headless --path . -s tests/run_tests.gd`: rules, saves, determinism, layouts on 10 screens.
- `godot --headless --path . -s tools/autobattle.gd -- 200`: balance numbers from seeded auto-fights.
- `xvfb-run godot --path . -s tools/shot.gd -- 2400 1080 out.png`: a screenshot at any screen size.
- `python3 tools/art_export.py <concept-art/pixel-src> art/`: re-export the placeholder sprites.

## Layout
- `scripts/sim/`: the rules. Plain code, 20 ticks a second, no nodes, no screen.
- `scripts/core/`: content loading and checks, saves, screen and pixel-scale logic.
- `scripts/view/`: drawing, text and touch input. Reads the sim, sends it orders.
- `data/`: ships, weapons, species, systems and English strings as JSON.
- `art/`: placeholder pixel sprites exported from the concept-art generators.

## Working on the game
- Read `CLAUDE.md` first: it has the architecture rules every change follows.
- Every PR runs format and lint, the headless tests, a balance report, layout screenshots on
  five phone and foldable sizes, and an Android debug APK build. Claude reviews every PR in the
  project session at high effort before it is merged.
- Bugs: use the issue template and include the fight's seed and your device.
