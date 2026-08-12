# Permissions & Distribution

AIShot relies on three TCC-gated capabilities. None require Info.plist usage strings — they are granted at runtime in **System Settings → Privacy & Security**.

| Capability | Needed for | Detect (silent) | Request / prompt |
|---|---|---|---|
| **Screen Recording** | All capture | `CGPreflightScreenCaptureAccess()` | `CGRequestScreenCaptureAccess()` (one-time dialog) |
| **Accessibility** | Synthetic input, reading other apps' UI | `AXIsProcessTrusted()` | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` (opens the pane; user toggles manually) |
| **Notifications** | Capture notifications | `UNUserNotificationCenter.getNotificationSettings` | `requestAuthorization(options:)` |

## Re-prompt limitations

macOS prompts for each permission **once**. After a decision, you cannot re-trigger the dialog — the app can only deep-link the user to the relevant System Settings pane. So onboarding must:

1. Show live status per permission.
2. Offer "Open System Settings" deep links when denied/not-determined.
3. Detect the grant and update without requiring a manual relaunch (note: ScreenCaptureKit may need an app **restart** after first grant — handle gracefully).

## TCC is keyed to the code signature

TCC ties grants to the app's signing identity. An **unstable or ad-hoc signature causes repeated re-prompts** and lost grants. Use a stable Developer ID identity for all builds you test permissions with.

### Developer builds (unsigned)

A locally-built, unsigned/ad-hoc app gets a *new* identity on every rebuild, so a freshly reinstalled copy is treated as a different app and the Accessibility / Screen-Recording grant you gave the previous copy no longer applies — the Permissions pane then correctly shows "not granted". To make grants persist across rebuilds during development, sign every build with the **same** self-signed certificate via [`scripts/dev-sign.sh`](../scripts/dev-sign.sh) (create a "AIShot Dev" Code Signing certificate once in Keychain Access, then grant the permissions a single time). The in-app "Re-check" button and the on-activation refresh report the *true* status; they can't restore a grant that macOS has invalidated.

## Sandbox vs. Developer ID — the core decision

The automation/agent features (synthetic `CGEvent` input + cross-app `AXUIElement` control) are **effectively incompatible with the App Sandbox**, and that path is incompatible with the Mac App Store:

- Sandboxed processes can't post synthetic events to other apps, and `kTCCServiceAccessibility` requests don't surface properly.
- Some apps reject events flagged as synthetic from sandboxed senders.

**Decision: ship Developer ID, notarized, NON-sandboxed**, distributed outside the Mac App Store.

### Entitlements (`App/Resources/AIShot.entitlements`)

```xml
<key>com.apple.security.app-sandbox</key> <false/>
```

- **Hardened Runtime** is enabled at sign time (`ENABLE_HARDENED_RUNTIME=YES` in `project.yml`).
- **Notarization** is required for distribution (Phase 4 release pipeline).
- Add `NSCameraUsageDescription` only if a future webcam/PiP feature is introduced.

## References

- ScreenCaptureKit permissions — Apple Developer Forums [#732726](https://developer.apple.com/forums/thread/732726)
- `AXIsProcessTrustedWithOptions` — [Apple docs](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- Synthetic events & sandbox — [QA1888](https://developer.apple.com/library/archive/qa/qa1888/_index.html), Forums [#724603](https://developer.apple.com/forums/thread/724603)

## The MCP helper is a separate TCC identity

`Contents/Helpers/aishot-mcp-server` is its own executable, so macOS treats it as a
separate subject for permissions: the first time an agent captures through it, macOS
prompts for **Screen Recording for the helper**, independently of the grant you gave
AIShot.app. Likewise, agent-driven `click` / `type_text` need Accessibility for the
helper.

This is a direct consequence of the server being a spawned process rather than hosted
in the app — see [ARCHITECTURE.md](ARCHITECTURE.md#why-the-mcp-server-isnt-hosted-in-process).
