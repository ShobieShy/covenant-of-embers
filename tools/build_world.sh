#!/usr/bin/env bash
# OW2: regenerate the world terrain (res://world/terrain/) from the level TOMLs' scenes.
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . -s res://tools/export_zone_heights.gd
python3 tools/build_world.py
godot --headless --path . -s res://tools/save_world_terrain.gd
godot --headless --path . -s res://tools/build_cells.gd
godot --headless --path . -s res://tools/bake_world_nav.gd
godot --headless --path . -s res://tools/bake_interior_nav.gd
godot --headless --path . -s res://tools/bake_world_markers.gd
