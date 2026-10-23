#!/usr/bin/env bash
# Headless checks: generated levels in sync, import, unit tests, 2 s main-scene smoke run,
# asset license lint. Every Godot run is --headless with a timeout so nothing hangs or opens a window.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
python3 tools/toml_to_scene.py --self-test
python3 tools/toml_to_scene.py --check
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1
timeout 120 "$GODOT" --headless --path . -s res://tests/run_tests.gd
timeout 60 "$GODOT" --headless --path . -- --seconds 2
python3 tools/check_assets.py
echo "[run_tests] all green"
