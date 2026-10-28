# Test tiers (0.3.1+)

Ember QA runs the same three tiers as development. Run each from the repo root, with a private
user dir so QA saves are never touched:

    export XDG_DATA_HOME=$(mktemp -d -t coe-user.XXXXXX)

| Tier | Command | When | Roughly runs |
|---|---|---|---|
| Fast | `TEST_ONLY=test_hud.gd,test_dialogue.gd tools/run_tests.sh --fast` | every change / step | Python checks, import, the TEST_ONLY files plus the core list (`CORE_TESTS` in tools/run_tests.sh), one `--start` smoke run, the 4x solo playtest |
| Full | `tools/run_tests.sh` | milestones | Python checks, import, every unit test except the classic group, both smoke runs, the 1x solo playtest, one 1x solo Labyrinth playtest (`PLAYTEST_LABYRINTH=1`), the co-op playtest, asset/credit/path lints |
| Release | `tools/run_tests.sh --classic` | before a release tag | the full tier plus the classic level-flow tests |

`TEST_ONLY` is optional in the fast tier; leave it empty to run just the core list.

## The classic group

Classic (non-open-world) mode is still in the game, but its level-flow tests run only at
releases. These are `test_level.gd`, `test_flow.gd`, `test_hub.gd`, and two methods:
`test_town.gd::test_all_exits_link` and `test_vault.gd::test_chest_opens_after_boss`. The list
is `CLASSIC` in tests/run_tests.gd.

To run only the classic group:

    TEST_CLASSIC=only godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd

## Notes

- The co-op joiner can exit with rc 134 at teardown. That's a known issue and the run still
  counts as a pass.
- The Labyrinth playtest's default timeout is 2400 s. Set `PLAYTEST_TIMEOUT` to change it.
- A run fails on any `ERROR`/`SCRIPT ERROR` log line, except the known Terrain3D res:// pair.
- Headless runs skip UI animations (UiAnim is instant when DisplayServer is headless).
