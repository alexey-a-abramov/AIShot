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

[Unreleased]: https://example.com/aishot/commits
