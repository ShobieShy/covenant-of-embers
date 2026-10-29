# Changelog: 0.3.1-prealpha (2026-10-28)

From 0.3.0-prealpha. Polish round P1 to P8 in docs/POLISH_0.3.1_PLAN.md and
docs/build_state.json. No save-format change; 0.3.0 saves load unchanged.

## Added
- Panel motion (P1): every panel fades and slides in, and fades out, through one shared
  helper (UiAnim). Instant with Reduced motion and in headless runs. Fast travel and respawn
  fade in from black.
- Labyrinth stairs (P2): hold Interact to take the stairs, with a prompt and a glow. In co-op
  a party vote banner shows who is ready.
- Dialogue (P3): typewriter text, a continue arrow, speaker colours, and an Instant text
  setting.
- HUD feedback (P4): bars pulse and shake on change, gold counts up, damage numbers merge
  per target, loot is pulled toward you, and pickups play a sound.
- Combat feel (P5): enemies flinch when hit, casting has more weight, and a death camera.
- Menus and travel (P6): the main menu title fades in, buttons nudge on hover, and save
  slots show as cards. Trash has a Keep focus, a pad hold and Undo. The skill tree gets hover
  detail, a path pulse, a respec confirm and a point counter. Loading screens show Act art,
  smooth their bar, and have new Labyrinth, brand and co-op tips. Fast travel from the world
  map has a confirm card.
- Co-op lobby (P6): join phases, a "The host is loading" overlay, and a damage chip on party
  frames. While a joiner makes its first load into the world, its loading screen reads
  "Co-op: loading the world".
- Sound (P7): new cues for UI hover, open and close, chests, rest shrines and stairs. The
  crystal-set and enemy-death sounds were replaced.

## Fixed
- After fast travel straight out of the starting interior, a second "town_square" loading
  screen no longer appears and pulls the party back to town (QA r14).
- Settings and Credits now play the open and close cues and animate like the other panels.
- Party frames sit below the HUD's level, HP and gold line instead of overlapping it.
- The co-op panel is centred and the main menu column is hidden behind it.
- Earlier QA rounds (r9 to r13): reopening a panel during its close, paused fades, centred
  vote banner and panels, damage-number age, and the Skills label.

## For testers
- `COE_DEBUG_HOST_LOAD_DELAY_S` delays the co-op host's world load (up to 10 s) in debug builds only
  (docs/TEST_TIERS.md). Release exports ignore it.

## Known issues
- Co-op: the joining game can still exit with code 134 while shutting down, after the session
  ends. Progress is already saved.
- Save-slot cards do not show playtime yet.
- The first Labyrinth floor you enter can hitch once (about 60 ms) while its shaders compile.
