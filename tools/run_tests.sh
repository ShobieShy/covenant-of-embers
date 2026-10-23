#!/usr/bin/env bash
# Headless checks: import, unit tests, 2 s main-scene smoke run, asset license lint.
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . -s res://tests/run_tests.gd
godot --headless --path . -- --seconds 2
python3 tools/check_assets.py
echo "[run_tests] all green"
