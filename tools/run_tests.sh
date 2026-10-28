#!/usr/bin/env bash
# Headless checks: generated levels in sync, import, unit tests, 2 s main-scene smoke run,
# asset license lint. Every Godot run is --headless with a timeout so nothing hangs or opens a window.
# Tiers (0.3.1, docs/TEST_TIERS.md):
#   tools/run_tests.sh --fast     Python checks, import, TEST_ONLY area tests + CORE_TESTS,
#                                 one smoke run, the 4x solo playtest (per step)
#   tools/run_tests.sh            full: every unit test (not classic), both smoke runs, 1x solo,
#                                 1x solo Labyrinth, co-op, lints (milestones)
#   tools/run_tests.sh --classic  full + the classic level-flow tests (releases)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MODE=full
for a in "$@"; do
	case "$a" in
	--fast) MODE=fast ;;
	--classic) export TEST_CLASSIC=1 ;;
	*) echo "usage: tools/run_tests.sh [--fast] [--classic]"; exit 2 ;;
	esac
done
if [ "$MODE" = fast ] && [ "${TEST_CLASSIC:-}" = 1 ]; then echo "--classic is a full-tier option"; exit 2; fi
# The fast tier's always-run list: save/load, player, casting, loot, UI basics, Labyrinth.
CORE_TESTS="test_smoke.gd,test_branding.gd,test_save.gd,test_save_migration.gd,test_world_save_migration.gd,test_player.gd,test_casting.gd,test_damage.gd,test_inventory.gd,test_hud.gd,test_settings.gd,test_labyrinth_state.gd,test_labyrinth_floor.gd,test_labyrinth_sync.gd,test_world_session.gd,test_audio.gd"
python3 tools/toml_to_scene.py --self-test
python3 tools/expand_maps.py --check
python3 tools/toml_to_scene.py --check
python3 tools/import_magewar_parts.py --check
python3 tools/labyrinth_gen.py --self-test  # L1
python3 tools/labyrinth_gen.py --check
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1
# Unit tests and the smoke run must also log no SCRIPT ERROR / ERROR lines: a GDScript
# runtime error inside a test doesn't fail it by itself (step 8 fix).
log="$(mktemp)"
# QA: every run (unit suite, smoke, solo + co-op playtests) gets a private user:// so two runs
# (or a run and a play session) never read/delete each other's saves, character files, .bak
# leftovers, keybinds or user://patches. Override with RUN_TESTS_SHARED_USER=1.
if [ "${RUN_TESTS_SHARED_USER:-0}" != 1 ]; then
	XDG_DATA_HOME="$(mktemp -d -t coe-user.XXXXXX)"
	export XDG_DATA_HOME
fi
trap 'rm -f "$log"; [ "${RUN_TESTS_SHARED_USER:-0}" = 1 ] || rm -rf "${XDG_DATA_HOME:?}"' EXIT
run_clean() {
	local rc=0
	"$@" 2>&1 | tee "$log" || rc=$?
	if [ "$rc" -ne 0 ]; then echo "[run_tests] failed (exit $rc): $*"; exit "$rc"; fi
	# Terrain3D 1.0.2 logs a harmless load("res://") pair when a terrain initialises.
	if grep -vE "^ERROR: (Resource file not found: res:// \(expected type: unknown\)|Error loading resource: ''\.)$" "$log" | grep -qE '^(SCRIPT ERROR|ERROR):'; then
		echo "[run_tests] errors logged by: $*"; exit 1
	fi
}
# --fixed-fps 60: tests that await physics frames (step 12) step exactly 1/60 s each, fast.
if [ "$MODE" = fast ]; then
	TEST_ONLY="${TEST_ONLY:+$TEST_ONLY,}$CORE_TESTS" run_clean timeout 1500 "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
	run_clean timeout 60 "$GODOT" --headless --path . -- --start --seconds 2
	PLAYTEST_SPEED=4 run_clean tools/playtest.sh  # step 96: the bot also clears the slice at 4x
	grep -q "^\[playtest\] PASS" "$log" || { echo "[run_tests] 4x playtest did not pass"; exit 1; }
else
	TEST_ONLY="" run_clean timeout 1500 "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
	run_clean timeout 60 "$GODOT" --headless --path . -- --seconds 2
	run_clean timeout 60 "$GODOT" --headless --path . -- --start --seconds 2
	run_clean tools/playtest.sh
	grep -q "^\[playtest\] PASS" "$log" || { echo "[run_tests] playtest did not pass"; exit 1; }
	PLAYTEST_LABYRINTH=1 PLAYTEST_TIMEOUT="${PLAYTEST_TIMEOUT:-2400}" run_clean tools/playtest.sh  # 0.3.1: Act I at 1x
	grep -q "^\[playtest\] PASS" "$log" || { echo "[run_tests] labyrinth playtest did not pass"; exit 1; }
	tools/coop_playtest.sh || { echo "[run_tests] co-op playtest did not pass"; exit 1; }  # step 93
fi
python3 tools/check_assets.py
python3 tools/gen_credits.py --check
python3 tools/gen_element_trees.py --check
if [ ! -f build/world/world.json ]; then  # build/ is not in git: regenerate the world sources
	run_clean timeout 300 "$GODOT" --headless --path . -s res://tools/export_zone_heights.gd
	python3 tools/build_world.py
fi
python3 tools/gen_world_map.py --check  # OW7
python3 tools/check_paths.py --self-test
python3 tools/check_paths.py
echo "[run_tests] all green ($MODE${TEST_CLASSIC:+ + classic})"
