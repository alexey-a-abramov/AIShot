# MCP Surface

AIShot ships a [Model Context Protocol](https://modelcontextprotocol.io) server so local
agents can capture, enumerate, read, search, annotate, and — if you opt in — drive the
screen. Everything runs **on-device**.

## Transport & process model

The server is a **standalone executable** bundled inside the app at
`Contents/Helpers/aishot-mcp-server`. The agent spawns it and talks to it over **stdio**.
It opens **no network socket at all**.

```
agent  ──stdio──►  aishot-mcp-server  ──reads──►  ~/Library/Application Support/AIShot/
(Claude Code)      (spawned per session)          ├── history.json      (capture history)
                                                  └── text-index.json   (OCR search index)
                                          ──reads──►  com.aishot.app preferences (settings)
```

It is a **separate process from AIShot.app**, which matters in a few ways:

- It reads the app's settings from the `com.aishot.app` preference domain, so the
  **Enable MCP server** and **Confirm before clicks/typing** switches genuinely govern it.
  Both are re-read per tool call, so flipping one takes effect without reconnecting.
- It reads the same history and OCR index files the app writes, so `get_history` and
  `search_captures` see your real captures.
- It captures using its **own** ScreenCaptureKit session and therefore needs its own
  Screen Recording grant the first time an agent uses it.
- Agent captures do **not** flow through the running app's post-capture pipeline
  (notification, notes/tags prompt).

Why not host it in-process in the GUI app? That would unify permissions and the
post-capture pipeline, and it's the more natural design — but it requires a transport the
agent can reach (loopback HTTP or a UDS) plus its own authentication, and MCP clients
overwhelmingly speak stdio today. The current split is the honest, working arrangement;
see [ARCHITECTURE.md](ARCHITECTURE.md).

SDK: `modelcontextprotocol/swift-sdk` (v0.12.x, pre-1.0 — isolated behind
`ScreenshotMCPService` so churn stays contained).

## Setup

**1.** Turn the server on in **AIShot → Settings → AI Agents → Enable MCP server**.
With it off, every tool is refused with a message telling the agent to enable it.

**2.** Register it:

```bash
claude mcp add aishot -- /Applications/AIShot.app/Contents/Helpers/aishot-mcp-server
```

or, for a client with a JSON config (Claude Desktop:
`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "aishot": {
      "command": "/Applications/AIShot.app/Contents/Helpers/aishot-mcp-server"
    }
  }
}
```

**3.** Restart the agent so it picks up the tools.

In a dev checkout the binary is at `.build/release/aishot-mcp-server` after
`swift build -c release --product aishot-mcp-server`.

## Tool catalog

Source of truth: `Sources/AIShotMCP/MCPToolCatalog.swift`. "Priv." marks tools that
synthesize input or control apps.

| Tool | Key args | Returns | Priv. |
|---|---|---|:--:|
| `list_displays` | — | displays: id, frame, scale, isMain | |
| `list_windows` | `onScreenOnly?` | windows: id, title, app, bundleID, frame | |
| `list_apps` | — | running apps | |
| `get_history` | `limit?` | recent captures (path, time, mode, size, kind) | |
| `search_captures` | `query`, `limit?` | captures matching OCR text, note, tag, or file name — with the matching excerpt and which field matched | |
| `capture_region` | `displayID`, `rect`, `format?`, `includeCursor?` | image content + saved path | |
| `capture_window` | `windowID`, `format?` | image content + saved path | |
| `capture_display` | `displayID`, `format?` | image content + saved path | |
| `annotate` | `imageRef`, `annotations[]`, `format?` | rendered image | |
| `beautify` | `imageRef` | image framed on a gradient background | |
| `redact` | `imageRef` | image with sensitive text blurred | |
| `locate` | `text?` / `templateRef?`, `region?` | matches: rect + confidence | |
| `ocr` | `displayID?`, `rect?` | recognized text | |
| `switch_app` | `bundleID` | ok | ✅ |
| `click` | `x`, `y`, `button?` | ok | ✅ |
| `type_text` | `text` | ok | ✅ |

`search_captures` is the one worth knowing about: because AIShot OCRs your captures in
the background, an agent can find *"the screenshot with the stack trace"* rather than
guessing from the most recent few.

### Resources

Recent captures are also exposed as MCP resources at `aishot://history/<uuid>`, with a
MIME type derived per file (so recordings report `video/mp4`, not `image/png`).

## Safety model

1. **Master switch.** With **Enable MCP server** off, *every* tool — including plain
   captures — is refused.
2. **Read and capture tools** run immediately when the server is on.
3. **Privileged tools** (`switch_app`, `click`, `type_text`) are refused while
   **Confirm before clicks/typing** is on, because the helper is headless and has no UI
   in which to ask you. Turning that setting **off** is the deliberate opt-in that lets
   agents click and type. It defaults to **on**.
4. **No network exposure.** stdio only; no socket is opened.
5. **OS-level gate.** Synthetic input additionally requires the Accessibility permission.

Not yet implemented, and listed here so the gap is explicit: a per-call confirmation UI,
a session allowlist, and an audit log of tool calls. Until those exist, the honest
posture is that enabling input access is a standing grant, not a per-action one.

See [SECURITY.md](SECURITY.md).

## Testing

Contract tests run the service over `InMemoryTransport` — no ports, no permissions:
they assert the advertised tool list, validate argument schemas, check error mapping
(`AIShotError` → MCP error), and cover the policy gates (server disabled, confirmation
required, confirmation opted out). See [TESTING.md](TESTING.md).

To exercise the real binary end to end, drive it over stdio — note it exits when stdin
closes, so keep the pipe open while you wait for responses:

```bash
/Applications/AIShot.app/Contents/Helpers/aishot-mcp-server
# then write JSON-RPC lines: initialize → notifications/initialized → tools/call
```
