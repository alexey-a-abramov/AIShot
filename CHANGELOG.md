# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project aims to
adopt [Semantic Versioning](https://semver.org/) from its first tagged release.

## [Unreleased]

### Added — Phase 0 (foundation scaffold)
- SwiftPM package `AIShotKit` with 7 modules: `AIShotShared`, `AIShotCore`,
  `AIShotCapture`, `AIShotAnnotation`, `AIShotAutomation`, `AIShotPersistence`,
  `AIShotMCP`.
- Domain models, engine protocols, and stubbed `actor` engines (Swift 6 strict
  concurrency).
- MCP tool catalog (`MCPTool`) and transport-agnostic `ScreenshotMCPService`
  facade.
- 18 unit tests (swift-testing) across models, geometry, annotation, MCP
  catalog, and settings.
- SwiftUI app shell: menu-bar agent, Dashboard window, Settings window.
- XcodeGen `project.yml`, `Info.plist`, non-sandboxed `AIShot.entitlements`.
- GitHub Actions CI (`swift build` + `swift test` on `macos-15`).
- Documentation: README, ROADMAP, ARCHITECTURE, MCP, PERMISSIONS, TESTING,
  SECURITY, CONTRIBUTING.

### Added — Phase 1 (MVP)
- ScreenCaptureKit engine: region/window/display/all-displays capture, ImageIO
  encoding, save with filename templating, clipboard, notifications, global
  hotkeys, region-selection overlay.
- Embedded MCP server (swift-sdk): capture/enumeration/history tools, plus a
  standalone `aishot-mcp-server` stdio binary; privileged input tools gated.
- Annotation renderer (arrows/shapes/text/redaction) and an interactive editor.
- Automation: NSWorkspace app switching, CGEvent synthetic input, Vision locator.
- Onboarding/permissions UI, settings, launch-at-login.

### Added — Internationalization
- English/French/Spanish via a String Catalog; extensible to more locales.

### Added — Phase 2/3/4
- OCR text-grab, color picker, pin-to-screen.
- Beautify, auto-redact, screen recording; `ocr`/`beautify`/`redact` MCP tools.
- MCP resources for capture history; scrolling capture; Sparkle auto-update;
  release scripts (`scripts/`) and a release CI workflow.

### Added — Website
- Localized Astro marketing/docs site (`website/`, en/fr/es).

[Unreleased]: https://example.com/aishot/commits
