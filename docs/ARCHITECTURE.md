# Architecture

## Process model

AIShot is a **single long-running, menu-bar GUI application**. That process:

- holds the Screen-Recording / Accessibility / Notifications TCC grants,
- owns the capture, annotation, automation, and persistence engines,
- **hosts the MCP server in-process** over loopback HTTP.

Local agents that speak stdio (Claude Code, Claude Desktop) connect through a small **stdio bridge** executable they spawn; it forwards JSON-RPC to the app. This avoids every agent invocation needing its own permission grants and keeps one capture authority. Advanced clients that support HTTP MCP can point straight at the loopback endpoint.

```
┌─────────────────────────── AIShot.app (GUI process) ────────────────────────────┐
│                                                                                  │
│  SwiftUI surfaces            AppDelegate / AppModel            Embedded MCP       │
│  ┌───────────────┐          ┌────────────────────┐          ┌─────────────────┐  │
│  │ MenuBarExtra  │          │ wiring & lifecycle │          │ swift-sdk Server│  │
│  │ Dashboard     │◄────────►│  global hotkeys    │◄────────►│ HTTP @127.0.0.1 │◄─┼─ stdio bridge ◄─ agent
│  │ Settings      │          │  permissions       │          │ tool handlers   │  │
│  │ Capture overlay│         └─────────┬──────────┘          └────────┬────────┘  │
│  │ Editor        │                    │                              │           │
│  └───────────────┘                    ▼                              ▼           │
│                          ┌──────────────────────── AIShotKit ───────────────────┐│
│                          │ Capture · Annotation · Automation · Persistence · MCP ││
│                          │ Core (models) · Shared (logging/geometry/perms)       ││
│                          └───────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Module boundaries (`AIShotKit`)

| Module | Responsibility | Notable types |
|---|---|---|
| `AIShotShared` | Cross-cutting utilities | `Logger.aishot`, `Permission`, `Geometry` |
| `AIShotCore` | Pure domain models | `CaptureRequest/Result`, `DisplayInfo`, `WindowInfo`, `ImageFormat`, `AIShotError` |
| `AIShotCapture` | ScreenCaptureKit engine | `ScreenCapturing`, `ScreenCaptureKitEngine`, `CapturedImage` |
| `AIShotAnnotation` | Annotation model + render | `Annotation`, `AnnotationDocument`, `AnnotationRendering`, `ArrowGeometry` |
| `AIShotAutomation` | App control + input + CV | `AppSwitching`, `InputAutomating`, `ElementLocating` |
| `AIShotPersistence` | Settings/history/outputs | `AppSettings`, `SettingsStore`, `HistoryStore`, `ClipboardWriting`, `NotificationPresenting` |
| `AIShotMCP` | Embedded MCP surface | `MCPTool`, `ScreenshotMCPService` |

Dependencies flow one way: `Shared ← Core ← {Capture, Annotation, Automation, Persistence} ← MCP`. The **app** is the only consumer that imports AppKit/SwiftUI; engines stay UI-free so they're testable from `swift test` without an app bundle.

## Why SwiftPM + XcodeGen

All logic lives in the SwiftPM package so CI runs `swift build && swift test` with no signing, bundle, or TCC. The app target (bundle, Info.plist, entitlements, SwiftUI scenes) is described by `project.yml` and generated with XcodeGen — the `.xcodeproj` is disposable and git-ignored, eliminating merge conflicts.

## Capture data flow (target, P1a/P1b)

```
hotkey / menu / MCP call
      └─► build CaptureRequest (AIShotCore)
            └─► (region) show selection overlay, exclude own windows
                  └─► ScreenCaptureKitEngine.capture()  →  SCScreenshotManager.captureImage
                        └─► CapturedImage (PNG + pixelSize + scale)
                              ├─► encode + save (AIShotPersistence)        → fileURL
                              ├─► copy to clipboard (NSPasteboard)
                              ├─► notify (UserNotifications, thumbnail+actions)
                              ├─► record HistoryEntry
                              └─► (MCP) return image content + path to agent
```

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

## External dependencies (added per-phase)

`swift-sdk` (MCP, P1b) · `KeyboardShortcuts` (P1a) · `Defaults` (P1) · `Settings` (P1e) · `LaunchAtLogin-Modern` (P1e) · `Sparkle` (P4). Each is introduced only when its phase needs it, keeping the scaffold buildable offline.
