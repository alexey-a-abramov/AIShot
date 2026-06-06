# MCP Surface

AIShot embeds a [Model Context Protocol](https://modelcontextprotocol.io) server so local agents can capture, enumerate, annotate, and (gated) drive the screen. Everything runs **on-device**.

## Transport architecture

The real server runs **inside the GUI app** (the only process holding capture/automation permissions) over **loopback HTTP** (`StatefulHTTPServerTransport`, `127.0.0.1:<port>`). Because most agents (Claude Code, Claude Desktop) speak **stdio**, AIShot ships a thin **stdio bridge** binary that an agent spawns; it relays JSON-RPC to the app.

```
agent ──stdio──► aishot-mcp-bridge ──loopback HTTP/UDS──► AIShot.app (Server)
```

- **Loopback only.** Never binds a routable interface.
- **Per-launch token** + `Origin` check on the HTTP transport.
- **Unix-domain-socket** option for zero open TCP ports.

SDK: `modelcontextprotocol/swift-sdk` (v0.12.x, pre-1.0 — isolated behind `ScreenshotMCPService` so churn stays contained).

## Tool catalog

Matches `Sources/AIShotMCP/MCPToolCatalog.swift`. "Priv." = privileged (synthetic input / app control), confirmation-gated by `mcpRequireConfirmationForInput` (default **on**).

| Tool | Args (planned) | Returns | Priv. |
|---|---|---|:--:|
| `list_displays` | — | displays: id, frame, scale, isMain | |
| `list_windows` | `onScreenOnly?` | windows: id, title, app, bundleID, frame | |
| `list_apps` | — | apps: bundleID, name, pid, isActive | |
| `get_history` | `limit?` | recent captures (path, time, mode, size) | |
| `capture_region` | `displayID`, `rect`, `format?`, `includeCursor?` | image content + file path + size/scale | |
| `capture_window` | `windowID`, `format?`, `includeShadow?` | image content + file path + size/scale | |
| `capture_display` | `displayID`, `format?` | image content + file path + size/scale | |
| `annotate` | `imageRef`, `annotations[]`, `format?` | rendered image content + path | |
| `locate` | `text?` / `templateRef?`, `region?` | matches: rect + confidence | |
| `switch_app` | `bundleID` | ok / new frontmost | ✅ |
| `click` | `point` (screen), `button?` | ok | ✅ |
| `type_text` | `text` | ok | ✅ |

**Image results** are returned both as MCP image content (base64) and as a saved file path, so an agent can either read pixels inline or reference the file. Coordinates in args are documented per-tool as display-space (top-left).

Planned later: MCP **resources** (browse capture history) and **prompts** (e.g. "capture & describe") — Phase 4.

## Safety model

1. **Read/capture tools are unprivileged** — always available when MCP is enabled.
2. **Privileged tools** (`switch_app`, `click`, `type_text`) require confirmation by default; users can session-approve or allowlist.
3. **Audit log** of every tool call (tool, args summary, result) in the Dashboard.
4. **Kill switch** — disable MCP from the menu bar or Settings instantly.

See [docs/SECURITY.md](SECURITY.md).

## Client configuration (planned, P1b)

Once the bridge ships, registering with Claude Code will look like:

```bash
claude mcp add aishot -- /Applications/AIShot.app/Contents/MacOS/aishot-mcp-bridge
```

Or for clients using a JSON config:

```json
{
  "mcpServers": {
    "aishot": {
      "command": "/Applications/AIShot.app/Contents/MacOS/aishot-mcp-bridge"
    }
  }
}
```

The Settings → MCP pane will show the exact, copyable snippet with the active token/port.

## Testing the MCP surface

Contract tests run the server over `InMemoryTransport` (no ports, no permissions): assert the advertised tool list, validate argument schemas, and check error mapping (`AIShotError` → MCP error). See [docs/TESTING.md](TESTING.md).
