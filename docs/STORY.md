# Wickfarer: story bible

The world, the people in it, and how the game talks. Every string in
`data/strings_en.json` should pass the voice rules at the bottom.

## The world

The stars are going out. Not exploding: going quiet. What they leave behind is the
**Hush**, a teal stillness that drinks heat and sound and drifts toward anything warm.
Nobody knows what it is. Everybody knows it follows light.

People live along the **lanes**, strings of beacons kept lit with **Light**: starfire
rendered down and bottled, the way tallow is rendered from fat. Ships burn it to jump.
Stations burn it to stay warm. Lamp-keepers burn their lives tending it. A ship with no
Light jumps dark and comes out cracked.

The player's crew are salvagers. In a wreck in the Tallow Reach they found an **Ember**:
a living star-core, small enough to sit in a ship's reactor bay and still alive. Planted
at the **Cradle**, a dead star at the far end of the Long Cold, an Ember can catch and
become a star again. That is the **Kindling**. Nobody chose this crew to do it. They found
it, so it's theirs to carry, and every faction on the way has an opinion about that.

A run crosses four **Reaches**, each ending at a **Gate** held by a **Warden**:

| Reach | Feel | Warden |
|---|---|---|
| The Tallow Reach | Home lanes. Trading posts, toll-runners, old lanterns. | **The Tollkeeper** (Ashmarket). Chains every ship at the Gate: no one dodges. |
| The Cinder Narrows | Tight, burnt-out lanes the Tidewardens patrol hard. | **The Breakwater** (Tidewardens). Its tide swaps which deck the wards cover. |
| The Glasswater | Choir country. Still, cold, beautiful. | **The Cantor** (Hollow Choir). Its hymn pulls the warmth out of every deck. |
| The Long Cold | Almost nothing left lit. | The Kindling at the Cradle. No ship. The Hush itself. |

## Factions

**Tidewardens.** Lamp-keepers. They keep the lanes lit and take a tithe of Light for it.
Blue coats, logbooks, ranks, inspections. Mostly honest, always tired. They talk in short
official sentences: "Lamp check. Open your Ember shutters."

**Ashmarket.** Traders, toll-runners, brokers and hunters. Everything has a price,
including you. Friendly until the money runs out. They talk in prices: "Lane fee's ten.
We take scrap." Rivals of the Tidewardens.

**The Hollow Choir.** They sing over the Hush, the way you whistle past a grave. Their
ships move in step and are the only symmetric things in the game. Their hymns can hide a
ship's wake and can also pull Light out of it. They never use contractions: "We will
listen for you."

## Peoples

- **Drifters.** Salvage clans. Sleep in the hull plating. Claims and kin rates matter.
- **Kith.** Small, always in threes, talk over each other. Forgers and tinkerers.
- **Oru.** Big, old, slow, patient. Do nothing in a hurry. Very strong.
- **Sable.** Carry their own heat. Sing. Some know the old warden oaths.

## People

**Ines Gall**, captain of the tug *Low Wick*. A rival salvager: cheerful, competitive,
swears a lot, keeps score. First meeting decides if she's a grudge or a friend. By the
third Reach her ship is dying in the Hush and you decide whether to save her.

**The Cantor** of the Hollow Choir. Speaks out of the Ember itself, never the comms. Old,
curious, polite in a way that's slightly frightening. Asks what you'll do with the fire,
offers to hide your wake, and holds the Glasswater Gate. Its last event asks you to sing
with the Choir "at the end".

Crew aboard change with the ship, so events never name crew members. They say "your
pilot", "your stoker", "somebody".

## Where text goes

- **Events and outcomes** are story. Short, concrete, no instructions.
- **The HUD and store pages** are labels and numbers, plus one line in the place's own
  voice. No "tap to" anywhere in normal play.
- **Item cards** are a name, one line of flavor, then stats.
- **How to play** lives only in the training flight (`TUT_`, the one-time `TIP_`s) and
  the Help page in the menu (`HELP_`, topics in `data/tutorial.json`). A test fails if
  "tap " or "hold to" shows up anywhere else.

## Voice rules

1. Say what happened, then stop. No closing line telling the player how to feel.
2. Concrete over vague: a soup pot, a stamped pass, FRAGILE in four languages. Never
   "something in the dark", "somehow", "as if", "a reminder of", "ancient", "whispers".
3. People talk like people: contractions, wants, interruptions. Each faction sounds
   different (see above).
4. Short. Intro two sentences, outcome one or two. A choice is what the captain says.
5. No groups of three, no mirrored sentence pairs, no dashes, no colons for drama.
6. Don't restate numbers the screen already shows. Don't explain a rule in a story line.
7. Dry humor, sparingly. The buoy that flashes CHICKEN is the ceiling.
8. Every character must be in the pixel font (a test checks).
