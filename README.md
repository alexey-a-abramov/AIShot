# AIShot

A native macOS screen-capture tool built for **both humans and local AI agents**.
Capture a region, window, or display; annotate it; organise captures with notes and
project tags; search them by the text *inside* the image — and let local agents
(Claude Code, Claude Desktop, …) drive the same capabilities over a bundled **MCP
server**, entirely on-device.

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/swift-6.2-orange.svg)

---

## Why

Most screenshot tools are built for a person clicking a shutter. AIShot is built for
the workflow where an **AI assistant also needs to see your screen**, act on it, and
hand images back — while still being a first-class capture tool for you. Nothing is
uploaded: no account, no telemetry, no cloud.

The differentiating piece is **search**. AIShot OCRs your captures in the background,
so you can find a screenshot by the words it contains — and so can an agent, via the
`search_captures` tool. Searching `connection refused` finds that error screenshot
from three weeks ago that you never named or tagged.

## Features

**Capture**
- Region, window, full display, all displays (stitched), via [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/) — Retina-correct.
- **Freeze-frame region select**: the screen is snapshotted the instant you press the
  shortcut, so menus and tooltips stay put while you drag. Cancel and nothing is saved.
- Self-timer (3/5/10s) with an on-screen countdown.
- Text grab (OCR to clipboard), scrolling capture, colour picker.
- Screen recording to `.mp4` or animated GIF.

**Organise**
- A free-text **note** and a single **project tag** per capture, in a combo box that
  autocompletes existing tags.
- "Apply this tag to the next captures" for tagging a run of related screenshots
  without re-prompting.
- Metadata is a small JSON file — hidden beside your screenshots by default, or
  visible, or in a folder you choose.

**Dashboard**
- Date-grouped grid with real thumbnails (downsampled, cached, decoded off the main thread).
- **Full-text search over the words inside your screenshots**, plus notes, tags, and file names.
- Browse by tag, multi-select (⌘/⇧-click, ⌘A), bulk tag/copy/trash.
- Quick Look (space), drag-out to any app, open in editor, pin, reveal, move to Trash.

**Annotate**
- Arrows, lines, rectangles, ellipses, text, highlighter, blur/pixelate, auto-numbered
  step counters. Objects stay editable until you save.
- Beautify (gradient frame) and auto-redact (emails, card numbers, IPs).
- Everything is undoable, including Beautify and Redact.

**For agents**
- A bundled **MCP server** exposing capture, enumeration, OCR, annotation, search, and
  (opt-in) synthetic input. See [docs/MCP.md](docs/MCP.md).

**Also:** menu-bar app (no Dock icon), global hotkeys, App Intents/Shortcuts, an offline
help page, and English/French/Spanish localization.

## Architecture at a glance

```
   Global hotkeys ─┐          ┌─ Menu bar · Dashboard · Settings · Editor (SwiftUI)
                   ▼          ▼
                ┌────────────────────┐         ┌───────────────────────────────┐
                │    AIShot.app      │────────►│  AIShotKit (SwiftPM engines)  │
                │  (permission       │         │  Capture · Annotation ·       │
                │   holder, GUI)     │         │  Automation · Persistence ·   │
                └────────────────────┘         │  Service · MCP                │
                          │                    └───────────────────────────────┘
                          │ shares files (history, OCR index, settings)
                          ▼
   local agent ──────►  aishot-mcp-server  (bundled helper, stdio)
   (Claude Code…)       Contents/Helpers/
```

The GUI app holds the Screen-Recording / Accessibility grants. The MCP server is a
**separate, short-lived process** that the agent spawns and talks to over **stdio** — it
opens no network socket. It reads the app's settings and shares its history and search
index on disk. Details, including why it isn't hosted in-process, in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Repository layout

```
AIShot/
├── Package.swift            # SwiftPM: the testable engine (AIShotKit)
├── project.yml              # XcodeGen spec for the app target (.xcodeproj is gitignored)
├── Sources/
│   ├── AIShotShared/        # logging, geometry, permission model
│   ├── AIShotCore/          # domain models (CaptureRequest/Result, Display/Window)
│   ├── AIShotCapture/       # ScreenCaptureKit engine, image/GIF/thumbnail codecs
│   ├── AIShotAnnotation/    # annotation model, renderer, beautifier
│   ├── AIShotAutomation/    # app switching, synthetic input, OCR, Vision locator
│   ├── AIShotPersistence/   # settings, history, notes/tags, OCR index, paths
│   ├── AIShotService/       # capture orchestration, auto-redaction, text indexer
│   ├── AIShotMCP/           # MCP tool catalog, schemas, service facade, host
│   └── aishot-mcp-server/   # the standalone stdio helper agents spawn
├── Tests/                   # swift-testing suites (`swift test`)
├── App/
│   ├── Sources/             # SwiftUI/AppKit shell: menu bar, Dashboard, Settings, editor
│   └── Resources/           # Info.plist, entitlements, String Catalog, offline help page
├── docs/                    # ARCHITECTURE · MCP · PERMISSIONS · TESTING · SECURITY · RELEASING
├── website/                 # Astro marketing/help site (en/fr/es)
└── scripts/                 # dev-sign, build-release, notarize, dmg
```

## Requirements

- macOS **15 Sequoia** or later
- **Xcode 26** / Swift 6.2 (Swift 6 language mode, strict concurrency)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build & test

```bash
# Engine — no app bundle, signing, or permissions needed
swift build
swift test

# App — gen-project.sh runs xcodegen and stamps the build number from git
./scripts/gen-project.sh
xcodebuild -project AIShot.xcodeproj -scheme AIShot -configuration Debug build

# Run it from Xcode, or install + sign so permissions persist across rebuilds:
open AIShot.xcodeproj
```

> **Development builds:** macOS ties permission grants to an app's exact code signature,
> so an ad-hoc-signed rebuild loses Screen Recording every time. `scripts/dev-sign.sh`
> creates a stable self-signed identity and signs with it, so you grant once.
> See [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

## Permissions

| Permission | Needed for |
|---|---|
| **Screen Recording** | Required — any capture or recording. |
| **Accessibility** | Only for agent-driven clicking/typing via MCP. |
| **Notifications** | Optional — the post-capture banner. |

Granted in System Settings at runtime; there are no Info.plist usage strings for them.
Because the App Sandbox blocks cross-app synthetic input, AIShot ships **Developer ID,
notarized, non-sandboxed** (not via the Mac App Store).

## Using it with an AI agent

```bash
claude mcp add aishot -- /Applications/AIShot.app/Contents/Helpers/aishot-mcp-server
```

Then enable it in **Settings → AI Agents → Enable MCP server** — with that off, every
tool is refused. Full setup, the tool list, and the safety model: [docs/MCP.md](docs/MCP.md).

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — module boundaries, capture pipeline, why the MCP helper is a separate process
- [docs/MCP.md](docs/MCP.md) — tools, setup, and the safety model
- [docs/PERMISSIONS.md](docs/PERMISSIONS.md) — TCC, signing, and why dev builds lose grants
- [docs/TESTING.md](docs/TESTING.md) — what's unit-tested vs. needs a real machine
- [docs/SECURITY.md](docs/SECURITY.md) — threat model and reporting
- [docs/RELEASING.md](docs/RELEASING.md) — signing, notarizing, shipping
- [CONTRIBUTING.md](CONTRIBUTING.md) — conventions and how to propose changes
- In-app: **⌘?** opens an offline help page covering the whole feature set.

## Status & limitations

Implemented and covered by **89 tests** (`swift test`). Known gaps, stated plainly:

- **The MCP server runs as a spawned helper, not in-process.** Agent-initiated captures
  therefore don't currently flow through the running app's post-capture pipeline
  (notification, notes prompt), though they do share history and the search index.
- **`mcpPort` is unused.** There is no HTTP transport today — stdio only.
- **No app icon yet**, so macOS shows the generic placeholder.
- Notarization requires an Apple Developer account; the release scripts are written but
  can only be exercised with real credentials.

## License

[Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for third-party attributions.
