# Architecture

## Process model

AIShot is **two processes**:

1. **`AIShot.app`** — a long-running, menu-bar GUI app (no Dock icon). It holds the
   Screen-Recording / Accessibility / Notifications grants and owns the capture,
   annotation, automation, and persistence engines.
2. **`aishot-mcp-server`** — a small executable bundled at `Contents/Helpers/`, spawned
   by an agent and spoken to over **stdio**. It opens no network socket.

```
   hotkeys ─┐        ┌─ MenuBarExtra · Dashboard · Settings · Editor · Overlay (SwiftUI/AppKit)
            ▼        ▼
   ┌──────────────────────────── AIShot.app ─────────────────────────────┐
   │  AppDelegate / AppModel  — wiring, hotkeys, permissions, windows     │
   │            │                                                         │
   │            ▼                                                         │
   │  ┌───────────────────────── AIShotKit ──────────────────────────┐    │
   │  │ Capture · Annotation · Automation · Persistence · Service ·  │    │
   │  │ MCP · Core (models) · Shared (logging/geometry/perms)        │    │
   │  └──────────────────────────────────────────────────────────────┘    │
   └───────────────────────────────┬──────────────────────────────────────┘
                                   │  shared files + preference domain
                                   ▼
   agent ──stdio──►  aishot-mcp-server   (same AIShotKit engines, own SCK session)
```

The two processes share state **through the filesystem**, not IPC:

| Shared via | What |
|---|---|
| `~/Library/Application Support/AIShot/history.json` | capture history |
| `~/Library/Application Support/AIShot/text-index.json` | OCR search index |
| `com.aishot.app` preferences | settings, incl. the two MCP switches |

Those locations are defined once in `AIShotPersistence.DataPaths` precisely because two
processes must agree on them — an earlier version had the helper build its own in-memory
history, so agents saw an empty world while the app worked fine.

### Why the MCP server isn't hosted in-process

Hosting it inside the GUI app would be tidier: one permission grant, one capture
authority, and agent captures could flow through the same post-capture pipeline
(notification, notes/tags prompt) as manual ones. It isn't done today because MCP clients
overwhelmingly speak **stdio**, and a stdio server must be a process the client can
spawn. Bridging stdio → the running app needs a local transport (loopback HTTP or a Unix
socket) plus its own authentication, which is real surface area to get right.

The current arrangement is the working, honest one. Consequences to know:

- The helper needs its **own** Screen Recording grant.
- Agent captures don't trigger the app's notification or notes/tags prompt.
- `AppSettings.mcpPort` exists but is **unused** — there is no HTTP transport.

## Module boundaries (`AIShotKit`)

| Module | Responsibility | Notable types |
|---|---|---|
| `AIShotShared` | Cross-cutting utilities | `Logger.aishot`, `Permission`, `Geometry` |
| `AIShotCore` | Pure domain models | `CaptureRequest/Result`, `DisplayInfo`, `WindowInfo`, `ImageFormat`, `AIShotError` |
| `AIShotCapture` | ScreenCaptureKit engine | `ScreenCapturing`, `ScreenCaptureKitEngine`, `CapturedImage` |
| `AIShotAnnotation` | Annotation model + render | `Annotation`, `AnnotationDocument`, `AnnotationRendering`, `ArrowGeometry` |
| `AIShotAutomation` | App control + input + CV | `AppSwitching`, `InputAutomating`, `ElementLocating` |
| `AIShotPersistence` | Settings, history, notes/tags, OCR index, paths | `AppSettings`, `HistoryStore`, `CaptureMetadataStore`, `CaptureTextIndexStore`, `DataPaths` |
| `AIShotService` | Orchestration across engines | `CaptureService`, `AutoRedactor`, `TextIndexer` |
| `AIShotMCP` | MCP surface | `MCPTool`, `ToolSchemas`, `ScreenshotMCPService`, `MCPServerHost` |

Dependencies flow one way: `Shared ← Core ← {Capture, Annotation, Automation, Persistence} ← Service ← MCP`. The **app** is the only consumer that imports AppKit/SwiftUI; engines stay UI-free so they're testable from `swift test` without an app bundle.

## Why SwiftPM + XcodeGen

All logic lives in the SwiftPM package so CI runs `swift build && swift test` with no signing, bundle, or TCC. The app target (bundle, Info.plist, entitlements, SwiftUI scenes) is described by `project.yml` and generated with XcodeGen — the `.xcodeproj` is disposable and git-ignored, eliminating merge conflicts.

## Capture data flow

```
hotkey / menu bar / App Intent / MCP call
   └─► CaptureRequest (AIShotCore)
        └─► self-timer countdown, if configured
             └─► (region) freeze-frame: snapshot every display, then select against it
                  └─► ScreenCaptureKitEngine.capture()  →  SCScreenshotManager.captureImage
                       └─► CapturedImage (encoded bytes + pixelSize + scale)
                            └─► CaptureService.deliver
                                 ├─► save to disk (CaptureSaver)          → fileURL
                                 ├─► copy to clipboard  (post-capture action)
                                 ├─► notify (UserNotifications: Copy / Reveal)
                                 ├─► record HistoryEntry
                                 └─► AppModel.handleOutcome
                                      ├─► sound + HUD
                                      ├─► open editor (if that's the default action)
                                      ├─► note/tag prompt, or silently apply the last tag
                                      └─► kick off background OCR indexing
```

Two paths deliberately bypass `deliver` because their output is already written and
re-running the post-capture action would double-notify — screen recordings and editor
exports. Both call `CaptureService.recordExisting` so they still appear in the Dashboard.

Note that AIShot's **own** windows are no longer excluded from captures, so you can
screenshot its menu and windows. Ephemeral capture chrome (the selection overlay, the
countdown, the post-capture HUD, the notes prompt) is torn down or dismissed before the
pixel grab — see `AppModel.dismissEphemeralCaptureUI()`.

## Search index

`TextIndexer` walks recent history in the background, OCRs anything not yet indexed
(fingerprinted by size + mtime, read through `FileManager` because `URL.resourceValues`
caches per instance), and stores the text in `CaptureTextIndexStore`.

It is deliberately **separate from the notes/tags index**: that one is loaded wholesale
and rewritten atomically on every tag edit, so putting megabytes of recognized text
there would make tagging progressively slower. The OCR index is derived data — delete it
and it rebuilds.

## Concurrency

Swift 6 language mode with **complete** strict-concurrency. Engines are `actor`s (`ScreenCaptureKitEngine`, `AutomationEngine`, `ScreenshotMCPService`) so state is isolated; models are `Sendable` value types. UI runs on `@MainActor`. This makes the capture→encode→deliver pipeline safe to drive from both UI and MCP concurrently.

## Coordinate spaces

A persistent source of bugs on macOS. AppKit/`NSScreen` use a **bottom-left, global** origin; Quartz / ScreenCaptureKit / `CGEvent` use **top-left, per-display**. All conversions go through `Geometry.flipToTopLeft` (and its tests). The rect handed to ScreenCaptureKit is in display space, not global AppKit space.

## Key Apple APIs by area

- **Capture:** `SCShareableContent`, `SCContentFilter`, `SCStreamConfiguration`, `SCScreenshotManager.captureImage`; `SCStream` for recording (P3). ([docs](https://developer.apple.com/documentation/screencapturekit/))
- **OCR/CV:** `RecognizeTextRequest` / `RecognizeDocumentsRequest` (fallback `VNRecognizeTextRequest`). ([docs](https://developer.apple.com/documentation/vision/recognizetextrequest))
- **Automation:** `NSWorkspace`/`NSRunningApplication`; `AXUIElement*`; `CGEvent` + `CGEvent.post(tap:)`.
- **Outputs:** `NSPasteboard`; `UNUserNotificationCenter` + `UNNotificationAttachment`/`UNNotificationAction`; ImageIO + `UTType`.
- **MCP:** `modelcontextprotocol/swift-sdk` (`Server`, `StdioTransport`, `StatefulHTTPServerTransport`, `InMemoryTransport`).

## External dependencies

Three, all small and all pinned in `Package.swift` / `project.yml`:

| Dependency | Used for |
|---|---|
| [`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk) | the MCP server (pre-1.0; isolated behind `ScreenshotMCPService`) |
| [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) | user-remappable global hotkeys |
| [`LaunchAtLogin-Modern`](https://github.com/sindresorhus/LaunchAtLogin-Modern) | the launch-at-login toggle |

Everything else — capture, OCR, annotation rendering, GIF export, thumbnails, the update
checker — is built on system frameworks. Sparkle was evaluated for auto-update and
deliberately **not** adopted: its binary artifact broke offline/CI builds, so AIShot ships
a dependency-free `UpdateChecker` (appcast parse + version compare) instead. See
[RELEASING.md](RELEASING.md).
