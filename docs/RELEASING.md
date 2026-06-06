# Releasing AIShot

AIShot ships as a **Developer ID-signed, notarized, non-sandboxed** app
distributed outside the Mac App Store.

## Update mechanism

The app includes a built-in, dependency-free **update checker** (`UpdateChecker`):
"Check for Updates…" fetches the `SUFeedURL` appcast, compares versions, and
offers a download. For full **silent in-place installs**, add **Sparkle** back as
a Swift package (`project.yml`) and wire `SPUStandardUpdaterController`; the
appcast you publish below works for both.

## Prerequisites

- Apple Developer account + a **Developer ID Application** certificate in your keychain.
- `xcodegen` (`brew install xcodegen`).
- Sparkle's tools (`generate_keys`, `generate_appcast`) from the Sparkle release or `brew install --cask sparkle`.

## One-time Sparkle key

```bash
generate_keys                       # prints the public EdDSA key
```

Add the printed key to `App/Resources/Info.plist`:

```xml
<key>SUPublicEDKey</key>
<string>...your base64 public key...</string>
```

Set `SUFeedURL` to your hosted appcast (already stubbed to `https://aishot.app/appcast.xml`).

## Build, sign, notarize, package

```bash
export SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export DEVELOPMENT_TEAM="TEAMID"
export NOTARY_PROFILE="AIShotNotary"   # from `xcrun notarytool store-credentials`

scripts/build-release.sh     # builds app + bundles aishot-mcp-server into Contents/Helpers, signs
scripts/notarize.sh          # notarizes + staples dist/AIShot.app
scripts/make-dmg.sh          # produces dist/AIShot.dmg
```

## Appcast (Sparkle)

```bash
generate_appcast dist/        # signs the DMG and writes/updates appcast.xml
# upload dist/AIShot.dmg and appcast.xml to your SUFeedURL host
```

## Entitlements / sandbox

The app is **non-sandboxed** (`com.apple.security.app-sandbox = false`) because
synthetic input + cross-app Accessibility control are incompatible with the
sandbox (see [PERMISSIONS.md](PERMISSIONS.md)). Hardened Runtime is enabled.

## MCP server binary

`aishot-mcp-server` is built in release and copied to
`AIShot.app/Contents/Helpers/aishot-mcp-server`. Register it with an agent:

```bash
claude mcp add aishot -- /Applications/AIShot.app/Contents/Helpers/aishot-mcp-server
```

## CI

`.github/workflows/release.yml` runs on `v*` tags and produces an **unsigned**
build (signing/notarization require Developer ID secrets configured as repo
secrets; wire them in when ready).
