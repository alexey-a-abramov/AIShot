#!/usr/bin/env bash
#
# Build, (optionally) sign, and stage AIShot for Developer ID distribution.
# The standalone MCP server binary is bundled into Contents/Helpers so agents
# can spawn it from inside the app bundle.
#
# Requirements: xcodegen, Xcode, and (for signing) a "Developer ID Application"
# certificate in the keychain.
# Env (optional): SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)"
#                 DEVELOPMENT_TEAM="TEAMID"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Generating Xcode project (stamps the build number from git)"
"$ROOT/scripts/gen-project.sh"

echo "==> Building MCP server (release)"
swift build -c release --product aishot-mcp-server
MCP_BIN="$ROOT/.build/release/aishot-mcp-server"

echo "==> Archiving app"
xcodebuild -project AIShot.xcodeproj -scheme AIShot -configuration Release \
  -archivePath "$DIST/AIShot.xcarchive" \
  ${SIGNING_IDENTITY:+CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"} \
  ${DEVELOPMENT_TEAM:+DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"} \
  archive

APP="$DIST/AIShot.xcarchive/Products/Applications/AIShot.app"

echo "==> Bundling MCP server into app"
mkdir -p "$APP/Contents/Helpers"
cp "$MCP_BIN" "$APP/Contents/Helpers/aishot-mcp-server"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  echo "==> Re-signing helper and app"
  codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/aishot-mcp-server"
  codesign --force --options runtime --timestamp --deep \
    --sign "$SIGNING_IDENTITY" "$APP"
fi

cp -R "$APP" "$DIST/AIShot.app"
echo "==> Staged: $DIST/AIShot.app"
