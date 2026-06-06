# Security & Privacy

AIShot can see the screen and (when permitted) drive input. That power is matched with a conservative, local-first posture.

## Principles

- **Local-only.** No network egress except an optional, explicit auto-update check (Phase 4). Screenshots, OCR text, and history never leave the machine.
- **No telemetry / analytics.**
- **Least privilege.** Accessibility (synthetic input) is only requested when the user opts into automation features; capture works with Screen Recording alone.

## MCP exposure — threat model

The embedded MCP server is the largest new attack surface.

| Risk | Mitigation |
|---|---|
| Remote/other-host access | Bind **loopback only**; optional **Unix domain socket** (no TCP port). |
| Local non-agent process connecting | **Per-launch bearer token** + `Origin` check on the HTTP transport. |
| Agent performs destructive input | `click`/`type_text`/`switch_app` are **confirmation-gated by default** (`mcpRequireConfirmationForInput`); session-approve / allowlist are explicit opt-ins. |
| Silent activity | **Audit log** of every tool call in the Dashboard; menu-bar indicator when MCP is active. |
| Capturing secrets | Auto-redact (Phase 3) for sensitive patterns; manual blur/pixelate in the editor (P1c). |
| Runaway agent | One-click **kill switch** disables the server immediately. |

## Data at rest

- Screenshots are ordinary files in the user-chosen folder (default `~/Pictures/AIShot`) — managed by the user.
- Settings live in `UserDefaults` under `com.aishot.app`; history in a small local store under Application Support. No secrets are stored beyond the ephemeral per-launch MCP token.

## Distribution integrity

- **Developer ID signed + notarized**, Hardened Runtime enabled (see [PERMISSIONS.md](PERMISSIONS.md)).
- Auto-update (Sparkle, Phase 4) uses **EdDSA-signed** appcasts over HTTPS.

## Reporting

Until a formal policy exists, report suspected vulnerabilities privately to the maintainer rather than opening a public issue.
