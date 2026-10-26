#!/usr/bin/env bash
# Headless checks: generated levels in sync, import, unit tests, 2 s main-scene smoke run,
# asset license lint. Every Godot run is --headless with a timeout so nothing hangs or opens a window.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
python3 tools/toml_to_scene.py --self-test
python3 tools/expand_maps.py --check
python3 tools/toml_to_scene.py --check
python3 tools/import_magewar_parts.py --check
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1
# Unit tests and the smoke run must also log no SCRIPT ERROR / ERROR lines: a GDScript
# runtime error inside a test doesn't fail it by itself (step 8 fix).
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
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
run_clean timeout 1500 "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
run_clean timeout 60 "$GODOT" --headless --path . -- --seconds 2
run_clean timeout 60 "$GODOT" --headless --path . -- --start --seconds 2
run_clean tools/playtest.sh
grep -q "^\[playtest\] PASS" "$log" || { echo "[run_tests] playtest did not pass"; exit 1; }
PLAYTEST_SPEED=4 run_clean tools/playtest.sh  # step 96: the bot also clears the slice at 4x
grep -q "^\[playtest\] PASS" "$log" || { echo "[run_tests] 4x playtest did not pass"; exit 1; }
tools/coop_playtest.sh || { echo "[run_tests] co-op playtest did not pass"; exit 1; }  # step 93
python3 tools/check_assets.py
python3 tools/gen_credits.py --check
python3 tools/gen_element_trees.py --check
python3 tools/check_paths.py --self-test
python3 tools/check_paths.py
echo "[run_tests] all green"
