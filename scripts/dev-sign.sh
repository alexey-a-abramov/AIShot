#!/usr/bin/env bash
#
# Sign a locally-built AIShot.app with a STABLE identity so macOS TCC
# permissions (Screen Recording, Accessibility) persist across rebuilds.
#
# Why: an unsigned / ad-hoc build gets a new code identity every time it's
# rebuilt and reinstalled, so macOS treats each copy as a different app and the
# Accessibility / Screen-Recording grant you gave the previous copy no longer
# applies — the app then correctly reports "not granted". Signing every build
# with the SAME self-signed certificate keeps the identity stable, so you grant
# the permissions once and they stick.
#
# One-time setup (creates the persistent certificate):
#   Keychain Access → Certificate Assistant → Create a Certificate…
#     Name: "AIShot Dev"
#     Identity Type: Self-Signed Root
#     Certificate Type: Code Signing
#   Create, then run this script. Grant permissions once in System Settings.
#
# Usage: scripts/dev-sign.sh [/Applications/AIShot.app]
set -euo pipefail

APP="${1:-/Applications/AIShot.app}"
IDENTITY="AIShot Dev"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  SIGN="$IDENTITY"
  echo "==> Signing with persistent identity: $IDENTITY (TCC grants will persist)"
else
  SIGN="-"
  echo "==> '$IDENTITY' certificate not found — using ad-hoc signing."
  echo "    Note: ad-hoc grants do NOT persist across rebuilds. Create the"
  echo "    'AIShot Dev' code-signing certificate (see header) to fix that."
fi

HELPER="$APP/Contents/Helpers/aishot-mcp-server"
if [ -f "$HELPER" ]; then
  codesign --force --sign "$SIGN" "$HELPER"
fi
codesign --force --deep --sign "$SIGN" "$APP"
codesign --verify --verbose=2 "$APP"
echo "==> Signed $APP"
