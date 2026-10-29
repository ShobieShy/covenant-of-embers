# 0.3.3 — two fixes

Branched from master (`0.3.1-prealpha`). Does not include 0.3.2 (PR #1) and does not start 0.3.4, Acts II–V, or other features. Game version is `0.3.3-prealpha`. Co-op protocol stays 3.

## 1. Dialogue advance

Looking at the NPC who is talking consumed Interact. That NPC is added after the dialogue box, so its `_unhandled_input` ran first, called `talk()` (a no-op while a line is already up) and marked the key handled. The line never advanced.

- `DialogueUI` takes Interact and left click in `_input`, before world interactables. The first press or click finishes a line that is still typing; the next one advances or closes, as before. Choice buttons still receive the click.
- `Npc` does not swallow Interact while a line is up.
- Instant text is unchanged: the line is already complete, so the first press or click advances.
- The same press is released from `action_primary` / `interact` so it does not also cast or pick up loot.
- `tests/unit/test_dialogue.gd` feeds a real click and an Interact press while the camera is on the speaker.

## 2. Joiner exit (rc 134)

Reproduced on Godot 4.7.2 headless. After the bot logs PASS, `quit()` aborts with `corrupted size vs. prev_size in fastbins`. A gdb break on `abort` is in engine shutdown (`malloc_consolidate` during `free`), not in the playtest script.

What changed:

- Following the host through a door used to instantiate a whole level scene just to read `world_offset` or an Exits marker, then `free()` that tree while the open world was live (`SaveMigration`, `Interiors.marker_world` / `leave`). Those reads use `PackedScene.get_state()` and never build the level. A session that only follows the host through doors used to abort and now exits 0.
- The joiner no longer spawns a second breach population (`BreachEnemies`). The host's puppets are the fight, as with the Labyrinth. Local enemy frees, puppet frees, and puppet / remote motion run on the idle frame, and a body stops physics processing before it is freed.

What is still open:

A full slice that reaches the breach fight still aborts at exit after PASS (joiner rc 134). The same abort did not show up before the joiner entered `breach_rooms`. Entering the interior alone, or killing and freeing dozens of enemies on a live terrain without the co-op slice, exits 0. Turning navigation async iterations off, and freeing the game scene on the main thread before `quit()`, did not clear it. `coop_playtest.sh` still warns and accepts 134 after PASS. A clean exit did not print the ObjectDB "1 instance leaked" line; that line was only seen when shutdown aborted first.
