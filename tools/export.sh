#!/usr/bin/env bash
# Headless Linux + Windows exports (BUILD_PLAN step 42). Needs Godot 4.7.2 export templates in
# ~/.local/share/godot/export_templates/4.7.2.stable. Each export is smoke-run with --seconds 2
# The Windows build is only checked for existence unless WINE_SMOKE=1 (then run under wine in a
# private prefix build/wineprefix, never the user's ~/.wine; first run initialises it, slow).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build/linux build/windows
touch build/.gdignore
timeout 600 "$GODOT" --headless --path . --export-release Linux build/linux/covenant_of_embers.x86_64
timeout 600 "$GODOT" --headless --path . --export-release Windows build/windows/covenant_of_embers.exe
test -s build/linux/covenant_of_embers.x86_64 && test -s build/windows/covenant_of_embers.exe
# Step 84: Windows exe must carry the icon + version resources; Linux gets .desktop + icon.
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
# PE versions are numeric, so drop a prerelease suffix: 0.1.0-prealpha -> 0.1.0.0
python3 tools/pe_resources.py build/windows/covenant_of_embers.exe --expect-version "${VERSION%%-*}.0" --expect-product "Covenant of Embers"
cp packaging/linux/covenant-of-embers.desktop build/linux/
cp assets/branding/icon.png build/linux/covenant-of-embers.png
log=$(mktemp)
timeout 60 build/linux/covenant_of_embers.x86_64 --headless -- --seconds 2 >"$log" 2>&1 </dev/null; cat "$log"
if grep -vE "^ERROR: (Resource file not found: res:// \(expected type: unknown\)|Error loading resource: ''\.)$" "$log" | grep -qE "SCRIPT ERROR|^ERROR"; then echo "[export] linux export logged errors"; exit 1; fi
if [[ "${WINE_SMOKE:-0}" == 1 ]]; then
	WINEPREFIX="$PWD/build/wineprefix" WINEDEBUG=-all timeout 600 wine build/windows/covenant_of_embers.exe --headless -- --seconds 2 >"$log" 2>&1 </dev/null; cat "$log"
	WINEPREFIX="$PWD/build/wineprefix" wineserver -k || true
	if grep -vE "^ERROR: (Resource file not found: res:// \(expected type: unknown\)|Error loading resource: ''\.)$" "$log" | grep -qE "SCRIPT ERROR|^ERROR"; then echo "[export] windows export logged errors"; exit 1; fi
else
	echo "[export] windows export built (set WINE_SMOKE=1 to smoke-run it under wine)"
fi
echo "[export] linux + windows exports: green"
