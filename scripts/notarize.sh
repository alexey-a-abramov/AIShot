#!/usr/bin/env bash
#
# Notarize and staple a built app.
# Prereq: a notarytool keychain profile, e.g.
#   xcrun notarytool store-credentials AIShotNotary --apple-id you@example.com \
#     --team-id TEAMID --password <app-specific-password>
# Env: NOTARY_PROFILE (the stored profile name)
set -euo pipefail

APP="${1:-dist/AIShot.app}"
ZIP="${APP%.app}.zip"

echo "==> Zipping $APP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to notary service"
xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:?set NOTARY_PROFILE}" --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
echo "==> Notarized + stapled: $APP"
