#!/usr/bin/env bash
# Headless checks: generated levels in sync, import, unit tests, 2 s main-scene smoke run,
# asset license lint. Every Godot run is --headless with a timeout so nothing hangs or opens a window.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
python3 tools/toml_to_scene.py --self-test
python3 tools/toml_to_scene.py --check
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1
# Unit tests and the smoke run must also log no SCRIPT ERROR / ERROR lines: a GDScript
# runtime error inside a test doesn't fail it by itself (step 8 fix).
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
run_clean() {
	local rc=0
	"$@" 2>&1 | tee "$log" || rc=$?
	if [ "$rc" -ne 0 ]; then echo "[run_tests] failed (exit $rc): $*"; exit "$rc"; fi
	if grep -qE '^(SCRIPT ERROR|ERROR):' "$log"; then
		echo "[run_tests] errors logged by: $*"; exit 1
	fi
}
run_clean timeout 120 "$GODOT" --headless --path . -s res://tests/run_tests.gd
run_clean timeout 60 "$GODOT" --headless --path . -- --seconds 2
python3 tools/check_assets.py
echo "[run_tests] all green"
