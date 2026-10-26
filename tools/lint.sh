#!/usr/bin/env bash
# GDScript lint + format check (BUILD_PLAN step 42), gdtoolkit 4 (pipx install "gdtoolkit==4.*").
# gdlint uses ./gdlintrc; gdformat enforces 120 columns. FORMAT_SKIP: files gdformat 4.5
# mis-wraps (inline lambdas inside long calls come out with an unindent Godot rejects);
# they are still linted.
set -euo pipefail
cd "$(dirname "$0")/.."
FORMAT_SKIP=(scripts/core/main.gd tests/unit/test_enemy.gd tests/unit/test_item_codes.gd)
mapfile -t ALL < <(git ls-files '*.gd' | grep -v -e '^archive/' -e '^addons/')
FMT=()
for f in "${ALL[@]}"; do
	skip=0
	for s in "${FORMAT_SKIP[@]}"; do [[ "$f" == "$s" ]] && skip=1; done
	((skip)) || FMT+=("$f")
done
gdlint "${ALL[@]}"
gdformat -l 120 --check "${FMT[@]}"
echo "[lint] ${#ALL[@]} files linted, ${#FMT[@]} format-checked: green"
