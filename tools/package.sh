#!/usr/bin/env bash
# Release packaging (BUILD_PLAN step 85, Q13/Q14): runs tools/export.sh (Windows smoke-run
# under wine in build/wineprefix), then makes
#   build/release/CovenantOfEmbers-<ver>-x86_64.AppImage   (Linux, appimagetool)
#   build/release/CovenantOfEmbers-<ver>-windows.zip       (exe + GodotSteam dlls + README + CREDITS)
#   build/steam/content/{linux,windows}                    (staged for packaging/steam/*.vdf)
# Nothing is uploaded. SKIP_EXPORT=1 reuses the existing build/linux + build/windows.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
if [[ "${SKIP_EXPORT:-0}" != 1 ]]; then WINE_SMOKE="${WINE_SMOKE:-1}" bash tools/export.sh; fi
REL=build/release
rm -rf "$REL" build/appdir build/steam/content
mkdir -p "$REL" build/steam/content/linux build/steam/content/windows

# Linux AppImage
APPDIR="$PWD/build/appdir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/doc/covenant-of-embers"
cp build/linux/covenant_of_embers.x86_64 build/linux/*.so "$APPDIR/usr/bin/"  # + GodotSteam libs
cp packaging/linux/covenant-of-embers.desktop "$APPDIR/"
cp assets/branding/icon.png "$APPDIR/covenant-of-embers.png"
cp CREDITS.md "$APPDIR/usr/share/doc/covenant-of-embers/"
cat >"$APPDIR/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/covenant_of_embers.x86_64" "$@"
RUN
chmod +x "$APPDIR/AppRun"
IMG="$PWD/$REL/CovenantOfEmbers-$VERSION-x86_64.AppImage"
ARCH=x86_64 appimagetool --appimage-extract-and-run --no-appstream "$APPDIR" "$IMG" >/dev/null
chmod +x "$IMG"

# Windows zip
ZIPDIR=build/zipdir/CovenantOfEmbers
rm -rf build/zipdir && mkdir -p "$ZIPDIR"
cp build/windows/covenant_of_embers.exe build/windows/*.dll packaging/windows/README.txt CREDITS.md "$ZIPDIR/"
ZIP="$PWD/$REL/CovenantOfEmbers-$VERSION-windows.zip"
(cd build/zipdir && zip -qr "$ZIP" CovenantOfEmbers)

# Steam staging (app 480 placeholder; no upload)
cp build/linux/covenant_of_embers.x86_64 build/linux/*.so build/linux/covenant-of-embers.desktop build/linux/covenant-of-embers.png CREDITS.md build/steam/content/linux/
cp "$ZIPDIR"/* build/steam/content/windows/

# Smoke: the AppImage itself runs headless without errors; the zip lists the exe.
log=$(mktemp)
timeout 60 "$IMG" --appimage-extract-and-run --headless -- --seconds 2 >"$log" 2>&1 </dev/null || true
cat "$log"
if grep -vE "^ERROR: (Resource file not found: res:// \(expected type: unknown\)|Error loading resource: ''\.)$" "$log" | grep -qE "SCRIPT ERROR|^ERROR" || ! grep -qE "\[(main|menu)\]" "$log"; then echo "[package] AppImage smoke failed"; exit 1; fi
unzip -l "$ZIP" | grep -q "CovenantOfEmbers/covenant_of_embers.exe"
ls -la "$REL"
echo "[package] AppImage + Windows zip + Steam staging: green"
