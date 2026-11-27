#!/bin/zsh
# Construit mDOWN, la signe (certificat local stable) puis l'installe dans ~/Applications/Applications Personnelles.
#   ./build_app.sh            : version installée « mDOWN.app » (identifiant fr.stephan.mdown)
#   DEV=1 ./build_app.sh      : version de développement « mDOWN Dev.app » (identifiant …​.dev, données séparées, jamais installée)
# NO_INSTALL=1 : ne pas installer ; NO_OPEN=1 : ne pas lancer.
set -euo pipefail
cd "$(dirname "$0")"
if [ -n "${DEV:-}" ]; then APP="mDOWN Dev.app"; NO_INSTALL=1; else APP="mDOWN.app"; fi
DEST="$HOME/Applications/Applications Personnelles"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos15 -o "$APP/Contents/MacOS/mDOWN" Sources/*.swift
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${DEV:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier fr.stephan.mdown.dev" -c "Set :CFBundleDisplayName mDOWN Dev" -c "Set :CFBundleName mDOWN Dev" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 mdown-dev" "$APP/Contents/Info.plist"
fi
cp -R Extension "$APP/Contents/Resources/Extension"
SIGN="/Volumes/SKYRIM/TOOLS/MAC/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then "$SIGN" "$APP"; else codesign --force --deep -s - "$APP"; fi
if [ -z "${NO_INSTALL:-}" ]; then
  mkdir -p "$DEST"
  if [ -z "${FORCE:-}" ] && pgrep -f "$DEST/mDOWN.app/Contents/Resources/.*yt-dlp" >/dev/null; then echo "Téléchargement en cours : installation annulée (FORCE=1 pour forcer)." >&2; exit 2; fi
  pkill -x mDOWN 2>/dev/null || true
  rm -rf "$DEST/$APP"; cp -R "$APP" "$DEST/$APP"
  echo "Installée : $DEST/$APP"
fi
echo "OK : $APP"
