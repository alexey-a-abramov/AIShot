# Contributing

## Prerequisites

- macOS 15+, Xcode 26 / Swift 6.2
- `brew install xcodegen` (for the app target)

## Build & test

```bash
swift build          # engine
swift test           # unit + contract + snapshot suites
xcodegen generate    # (re)create AIShot.xcodeproj from project.yml
open AIShot.xcodeproj
```

The `.xcodeproj` is generated and **git-ignored** — never commit it; edit `project.yml` instead.

## Project shape

- All testable logic lives in the SwiftPM package (`Sources/`, `Tests/`). Keep it **UI-free** so `swift test` covers it without an app bundle.
- The app (`App/`) is the only place that imports SwiftUI/AppKit.
- Add an external dependency only in the phase that needs it (see [ROADMAP.md](ROADMAP.md)); keep the package buildable offline otherwise.

## Code style

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Swift 6 language mode, **complete** strict concurrency. Engines are `actor`s; models are `Sendable` value types.
- Public API gets doc comments. Stubs are marked `notImplemented("… (Pxx)")` referencing their phase.
- SwiftFormat/SwiftLint configs land in P1e; until then, match surrounding style.

## Commits & branches

- **Conventional Commits**: `feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `test:`, `refactor:` (optionally scoped, e.g. `feat(capture):`).
- **Atomic commits** — one logical change each; keep code separate from config/tooling changes.
- Branches: work on `dev`, release-merge to `main`. Never force-push shared branches.

## Pull request checklist

- [ ] `swift build` and `swift test` pass.
- [ ] New/changed engine logic has unit tests in the same PR.
- [ ] Touched only files in scope (no drive-by edits).
- [ ] Docs updated if behavior/architecture changed.
- [ ] No secrets, `.env`, or generated `.xcodeproj` committed.
