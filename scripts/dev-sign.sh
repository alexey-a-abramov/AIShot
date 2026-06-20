#!/usr/bin/env bash
#
# Sign a locally-built AIShot.app with a STABLE self-signed identity so macOS
# TCC permissions (Screen Recording, Accessibility) persist across rebuilds.
#
# Why: an unsigned / ad-hoc build gets a NEW code identity every time it's
# rebuilt and reinstalled, so macOS treats each copy as a different app and the
# Accessibility / Screen-Recording grant you gave the previous copy no longer
# applies — the app then correctly reports "not granted". Signing every build
# with the SAME certificate keeps the identity stable: you grant the permissions
# once and they stick.
#
# This script CREATES the "AIShot Dev" self-signed code-signing certificate in
# your login keychain on first run (no Keychain Access steps needed), then signs.
#
# Usage: scripts/dev-sign.sh [/Applications/AIShot.app]
set -euo pipefail

APP="${1:-/Applications/AIShot.app}"
IDENTITY="AIShot Dev"

create_certificate() {
  echo "==> Creating self-signed code-signing certificate '$IDENTITY'…"
  local dir; dir="$(mktemp -d)"
  cat > "$dir/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$dir/key.pem" -out "$dir/cert.pem" -config "$dir/req.cnf" >/dev/null 2>&1
  # Legacy PBE/MAC algorithms so macOS `security import` can read the PKCS12
  # (newer OpenSSL defaults fail with "MAC verification failed").
  /usr/bin/openssl pkcs12 -export -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$IDENTITY" \
    -out "$dir/id.p12" -passout pass:aishotdev >/dev/null 2>&1
  # -A lets codesign use the key without a keychain prompt on every build.
  security import "$dir/id.p12" -P aishotdev -A -T /usr/bin/codesign
  rm -rf "$dir"
}

if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
  create_certificate
fi

HELPER="$APP/Contents/Helpers/aishot-mcp-server"
if [ -f "$HELPER" ]; then
  codesign --force --sign "$IDENTITY" "$HELPER"
fi
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --verbose=2 "$APP" 2>&1 | tail -1

echo "==> Signed '$APP' with stable identity '$IDENTITY'."
echo "    Grant Accessibility / Screen Recording once; it now persists across rebuilds."
