#!/usr/bin/env bash
#
# Package a built app into a distributable .dmg with an /Applications symlink.
set -euo pipefail

APP="${1:-dist/AIShot.app}"
DMG="${2:-dist/AIShot.dmg}"
STAGE="$(mktemp -d)"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AIShot" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "==> Created $DMG"
