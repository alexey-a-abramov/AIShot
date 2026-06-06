# AIShot

A modern, native macOS screen-capture tool built for **both humans and local AI agents**. Capture a region, window, or display; annotate it; save / copy / get notified — and let local agents (Claude Code, Claude Desktop, …) drive the same capabilities over an **embedded MCP server**, entirely on-device.

> **Status:** Phase 0 — foundation scaffold. The engine modules compile and are unit-tested; capture, MCP, editing, and automation are stubbed with a clear roadmap. See [ROADMAP.md](ROADMAP.md).

---

## Why

Existing screenshot apps are built for people clicking a shutter. AIShot is built for the workflow where an **AI agent** also needs to *see* the screen, *act* on it, and *hand images back* — without anything leaving the machine. It pairs a best-in-class human capture/annotation UX with a first-class local MCP surface.

## Highlights (target)

- **Capture:** region / window / full-display / all-displays via [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/), Retina-correct, with our own overlay excluded from the shot.
- **Outputs:** save to a configurable folder, copy to clipboard, rich notification with quick actions (Copy / Annotate / Reveal).
- **Annotate:** arrows, rectangles, ellipses, lines, text, highlighter, blur/pixelate redaction, numbered steps.
- **For agents:** an embedded **MCP server** exposing capture, enumeration, annotation, app-switching, and vision-targeted click tools — bound to loopback, confirmation-gated for risky actions.
- **Surfaces:** menu-bar agent, a **Dashboard** ("admin") window, and a **Settings** window (save location, format, shortcuts, MCP, permissions).
- **Later phases:** OCR/text-grab, scrolling capture, pin-to-screen, color picker/magnifier, beautify/device frames, auto-redact, screen recording (video/GIF), Sparkle auto-update.

## Architecture at a glance

```
        Global hotkeys ─┐        ┌─ Menu bar / Dashboard / Settings (SwiftUI)
                        ▼        ▼
                 ┌──────────────────────┐        ┌──────────────────────────┐
   local agent ─►│  Embedded MCP server │◄──────►│   AIShotKit (engines)    │
  (stdio bridge) │  loopback HTTP+stdio │        │  Capture · Annotation ·  │
                 └──────────────────────┘        │  Automation · Persistence│
                                                 └──────────────────────────┘
```

The long-running GUI app is the single holder of Screen-Recording / Accessibility permissions and hosts the MCP server in-process. Agents that speak stdio connect through a thin bridge that forwards to the app over loopback. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/MCP.md](docs/MCP.md).

## Repository layout

```
AIShot/
├── Package.swift            # SwiftPM: the testable engine (AIShotKit)
├── project.yml              # XcodeGen spec for the app target (generated .xcodeproj is gitignored)
├── Sources/
│   ├── AIShotShared/        # logging, geometry, permission model
│   ├── AIShotCore/          # domain models (CaptureRequest/Result, Display/Window)
│   ├── AIShotCapture/       # ScreenCaptureKit engine
│   ├── AIShotAnnotation/    # annotation model + renderer
│   ├── AIShotAutomation/    # app switching, synthetic input, Vision locator
│   ├── AIShotPersistence/   # settings, history, clipboard, notifications
│   └── AIShotMCP/           # embedded MCP server: tool catalog + service facade
├── Tests/                   # swift-testing unit suites (run via `swift test`)
├── App/                     # SwiftUI app shell (menu bar, Dashboard, Settings)
│   ├── Sources/
│   └── Resources/           # Info.plist, AIShot.entitlements
├── docs/                    # ARCHITECTURE, MCP, PERMISSIONS, TESTING, SECURITY
└── ROADMAP.md
```

## Requirements

- macOS **15 Sequoia** or later
- **Xcode 26** / Swift 6.2 (Swift 6 language mode)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for the app target: `brew install xcodegen`

## Build & test

```bash
# Engine: builds and tests with no app bundle, signing, or permissions needed
swift build
swift test

# App: generate the Xcode project, then build/run from Xcode
brew install xcodegen
xcodegen generate
open AIShot.xcodeproj
```

## Permissions

AIShot needs **Screen Recording** (capture) and, for the automation tools, **Accessibility** (synthetic input). These are granted in System Settings at runtime — there are no Info.plist usage strings for them. Because the App Sandbox blocks cross-app synthetic input, AIShot ships **Developer ID, notarized, non-sandboxed** (not via the Mac App Store). Details: [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

## A note on this folder

This directory already contained `data/mcp.db` and a `logs/…-audit.json` from a prior process. They are **not** part of AIShot, are left untouched, and are git-ignored.

## License

License **TBD** — not yet an open-source release. Treat as all-rights-reserved until a `LICENSE` file is added.
