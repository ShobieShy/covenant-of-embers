#!/usr/bin/env bash
# Step 93: two-bot co-op run of the slice over localhost ENet. The host bot plays the slice
# (tools/playtest.sh route); the joiner bot follows it, fights its enemies (hits go to the
# host), follows its level travel and saves its own character. PASS when both bots pass.
# Optional: COOP_LAG=150 COOP_LOSS=0.02 for the step 92 link conditioner on both ends.
set -uo pipefail
cd "$(dirname "$0")/.."
G="${GODOT:-godot}"
PORT="${COOP_PORT:-$((27800 + RANDOM % 200))}"
EXTRA=()
[ -n "${COOP_LAG:-}" ] && EXTRA+=("--net-lag=${COOP_LAG}")
[ -n "${COOP_LOSS:-}" ] && EXTRA+=("--net-loss=${COOP_LOSS}")
dir="$(mktemp -d)"
timeout 600 "$G" --headless --fixed-fps 60 --path . -- --autoplay --host "$PORT" --name HostBot "${EXTRA[@]}" >"$dir/host.log" 2>&1 &
hp=$!
sleep 2
timeout 600 "$G" --headless --fixed-fps 60 --path . -- --autoplay --join "127.0.0.1:$PORT" --name JoinBot "${EXTRA[@]}" >"$dir/join.log" 2>&1 &
jp=$!
wait "$hp"; hrc=$?
wait "$jp"; jrc=$?
grep -E '^\[(playtest|coop)\]' "$dir/host.log" | sed 's/^/host   /' | tail -12
grep -E '^\[(playtest|coop|character)\]' "$dir/join.log" | sed 's/^/joiner /' | tail -12
bad=0
for f in host join; do
	# Terrain3D 1.0.2 logs a harmless load("res://") pair per terrain init (as in run_tests.sh).
	if grep -vE "^ERROR: (Resource file not found: res:// \(expected type: unknown\)|Error loading resource: ''\.)$" "$dir/$f.log" | grep -qE '^(SCRIPT ERROR|ERROR):'; then echo "[coop_playtest] errors in $f log:"; grep -E -A3 '^(SCRIPT ERROR|ERROR):' "$dir/$f.log" | head -20; bad=1; fi
done
if [ $hrc -eq 0 ] && [ $jrc -eq 0 ] && [ $bad -eq 0 ] && grep -q '^\[playtest\] PASS' "$dir/host.log" && grep -q '^\[playtest\] PASS' "$dir/join.log"; then
	echo "[coop_playtest] PASS (logs $dir)"
	exit 0
fi
echo "[coop_playtest] FAIL host rc $hrc, joiner rc $jrc (logs $dir)"
exit 1
