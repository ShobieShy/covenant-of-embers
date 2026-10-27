#!/usr/bin/env bash
# OW11e: cold-cache world perf walk: fresh user data (Godot shader/pipeline caches), fresh
# XDG cache and Mesa's disk shader cache off, so every shader and pipeline compiles in-run.
set -euo pipefail
cd "$(dirname "$0")/.."
out=${1:-build/perf_cold}; res=${2:-1280x800}
XDG_DATA_HOME=$(mktemp -d -t coe-user.XXXXXX) XDG_CACHE_HOME=$(mktemp -d -t coe-cache.XXXXXX) \
MESA_SHADER_CACHE_DISABLE=true timeout 400 godot --display-driver wayland --path . \
	-s tools/perf_capture.gd -- "$out" --world --res "$res" ${3:-}
