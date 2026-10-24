#!/usr/bin/env bash
# Step 40: the scripted bot plays the slice headless (menu -> Midden -> craft/save -> Breach
# -> Warden -> vault). Exit 0 on "[playtest] PASS". Uses user://playtest_save.json only.
set -euo pipefail
cd "$(dirname "$0")/.."
exec timeout 300 "${GODOT:-godot}" --headless --fixed-fps 60 --path . -- --autoplay
