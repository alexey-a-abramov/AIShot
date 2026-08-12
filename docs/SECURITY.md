# Security & Privacy

AIShot can see the screen and, when permitted, drive input. That power is matched with a
conservative, local-first posture — and with an honest account of what is and isn't
implemented yet.

## Principles

- **Local-only.** No network egress except an explicit, user-initiated update check.
  Screenshots, recognized text, notes, and history never leave the machine.
- **No telemetry, no analytics, no account.**
- **Least privilege.** Capture needs Screen Recording alone. Accessibility (synthetic
  input) is only relevant if you opt into letting agents click and type.

## MCP exposure — threat model

The MCP server is the largest attack surface. It is a **separate, short-lived process**
(`Contents/Helpers/aishot-mcp-server`) that an agent spawns and speaks to over **stdio**.

| Risk | Status |
|---|---|
| Remote or other-host access | **Mitigated by construction** — stdio only; no socket is opened, no port is bound. |
| Another local process connecting | **Not applicable** — there is no endpoint to connect to. A process that can spawn the helper could already run any command as you. |
| Server running when unwanted | **Mitigated** — the *Enable MCP server* setting is a master switch, re-read per tool call; with it off every tool, including plain capture, is refused. |
| Agent performs destructive input | **Partly mitigated** — `click` / `type_text` / `switch_app` are refused while *Confirm before clicks/typing* is on (the default). Turning it off is a **standing** grant, not per-action: see the gap below. |
| Capturing secrets | Auto-redact for emails, card numbers, and IPs; manual blur/pixelate in the editor. Both are opt-in per image, not automatic. |
| Silent activity | **Not mitigated** — see the gap below. |

### Known gaps

Stated plainly rather than implied away:

1. **No per-action confirmation UI.** The helper is headless, so it cannot prompt. The
   confirmation setting is therefore binary: keep input tools refused, or allow them for
   the whole session. A confirmation prompt hosted by the GUI app would fix this and is
   the main reason to move MCP hosting in-process.
2. **No audit log.** Tool calls aren't recorded or surfaced in the Dashboard, so an
   agent's activity is not reviewable after the fact.
3. **No menu-bar indicator** while an agent is connected.
4. **The helper has its own TCC identity**, so it needs its own Screen Recording grant —
   granting it is separate from granting the app.

Contributions in these areas are welcome; they're the highest-value security work
outstanding.

## Data at rest

| What | Where |
|---|---|
| Screenshots & recordings | Your chosen folder, default `~/Pictures/AIShot` |
| Notes & project tags | `.aishot-metadata.json` beside the captures (hidden by default), or a folder you pick |
| Capture history | `~/Library/Application Support/AIShot/history.json` |
| OCR search index | `~/Library/Application Support/AIShot/text-index.json` |
| Settings | `UserDefaults`, domain `com.aishot.app` |

All are plain files you can inspect, back up, or delete. The OCR index is derived data —
deleting it is safe and it rebuilds in the background. Note it **does contain the text of
your screenshots**, so treat it with the same care as the images themselves.

No secrets are stored.

## Distribution integrity

- **Developer ID signed + notarized**, Hardened Runtime enabled — see [PERMISSIONS.md](PERMISSIONS.md).
- The update checker fetches a signed appcast over HTTPS and never installs silently.
- Development builds are signed with a locally-generated self-signed identity
  (`scripts/dev-sign.sh`) purely so TCC grants survive rebuilds; that identity is not
  trusted for distribution.

## Reporting a vulnerability

Please report privately rather than opening a public issue: open a
[GitHub security advisory](https://github.com/alexey-a-abramov/AIShot/security/advisories/new)
on the repository. Include reproduction steps and the affected version
(**Settings → About** shows it). You'll get an acknowledgement within a few days.
