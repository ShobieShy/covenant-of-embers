# Test tiers (0.3.1+)

Ember QA runs the same three tiers as development. Run each from the repo root, with a private
user dir so QA saves are never touched:

    export XDG_DATA_HOME=$(mktemp -d -t coe-user.XXXXXX)

| Tier | Command | When | Roughly runs |
|---|---|---|---|
| Fast | `TEST_ONLY=test_hud.gd,test_dialogue.gd tools/run_tests.sh --fast` | every change / step | Python checks, import, the TEST_ONLY files plus the core list (`CORE_TESTS` in tools/run_tests.sh), one `--start` smoke run, the 4x solo playtest |
| Full | `tools/run_tests.sh` | milestones | Python checks, import, every unit test (the closed-level flow tests included), both smoke runs, the 1x solo playtest, one 1x solo Labyrinth playtest (`PLAYTEST_LABYRINTH=1`), the co-op playtest, asset/credit/path lints |
| Release | `tools/run_tests.sh --classic` | before a release tag | the full tier (`--classic` is the same set; the old release-only group moved into full) |

`TEST_ONLY` is optional in the fast tier; leave it empty to run just the core list.

## Closed-level flow tests

0.4.0 runs the old classic level-flow tests in the full tier, and the fast tier's core
list includes `test_flow.gd` and `test_level.gd`. `test_linear_flow.gd`,
`test_linear_migration.gd` and `test_gate_vote.gd` cover the new gates, save migration and
the co-op gate vote. `CLASSIC` in tests/run_tests.gd is empty.

To run just those flow tests:

    TEST_ONLY=test_flow.gd,test_level.gd,test_linear_flow.gd,test_linear_migration.gd,test_gate_vote.gd godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd

## Notes

- 0.6.0 saw four co-op slices (three standalone, one inside the full tier) exit 0 after
  `CoopWorld.prepare_shutdown` disables physics before freeing puppets and proxies. The
  abort was intermittent and the official binary has no symbols, so `coop_playtest.sh` still
  warns on rc 134 after PASS and does not treat that warning as the fix. A session that only
  follows the host through doors exits 0, and a short session (`COE_PLAYTEST_MAX_S`) exits 0.
- The Labyrinth playtest's default timeout is 2400 s. Set `PLAYTEST_TIMEOUT` to change it.
- The Act II leg is `PLAYTEST_ACT2=1 tools/playtest.sh` (King already dead, Sump pad, then the root-bridge ramps, then the Matriarch). It loads the cached cavern navmesh and does not rebake. `PLAYTEST_ACT2=1 tools/coop_playtest.sh` puts the host on the Crown pad and checks the joiner's height. The crater walk past z 86 stays skipped.
- The Act III leg is `PLAYTEST_ACT3=1 tools/playtest.sh`. The King and the Matriarch are already dead. The bot takes the Railhead and crosses checkpoints 9–13. If a gantry walk stalls, it logs the position and the next stair, then unsticks. Forgemaw's death and a waystone trip home leave `current` at 13. The full tier runs this leg after Act II.
- A run fails on any `ERROR`/`SCRIPT ERROR` log line, except the known Terrain3D res:// pair and the headless exit leaks below.
- Headless Godot prints these at process exit after a green unit suite (counts vary). They are classified, not fixed: `Pages in use exist at exit in PagedAllocator` for `GeometryInstanceDummy`, `NavAgent3D`, `JoltShape3D`, `JoltBody3D`, dummy-renderer material/shader/mesh/instance RIDs, and `resources still in use at exit`. A `SCRIPT ERROR` still fails the run.
- Headless runs skip UI animations (UiAnim is instant when DisplayServer is headless).

## QA debug hooks

- `COE_DEBUG_HOST_LOAD_DELAY_S=<seconds>` (0 to 10; larger values are capped at 10 because
  the joiner's ENet peer times out at about 20 s and reports "host left"): the co-op host waits this long after
  Start before loading the world, so a joiner's "The host is loading ..." overlay (party
  frames, 0.3.1 L2) can be captured. Set it on the host process only. Debug builds only:
  `Coop.host_load_delay()` returns 0 when `OS.is_debug_build()` is false, so release exports
  ignore it. The host logs a `[coop] COE_DEBUG_HOST_LOAD_DELAY_S` warning when it applies.
