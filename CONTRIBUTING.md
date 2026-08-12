# Contributing

## Prerequisites

- macOS 15+, Xcode 26 / Swift 6.2
- `brew install xcodegen` (for the app target)

## Build & test

```bash
swift build          # engine
swift test           # 89 unit + contract suites
xcodegen generate    # (re)create AIShot.xcodeproj from project.yml
xcodebuild -project AIShot.xcodeproj -scheme AIShot -configuration Debug build
open AIShot.xcodeproj
```

If `swift test` reports `no such module 'Testing'`, your `xcode-select` is pointing at
the Command Line Tools, which don't ship swift-testing. Either repoint it, or override
per-command without changing system state:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

**Working on permission-gated behavior?** Install to `/Applications` and run
`scripts/dev-sign.sh` — macOS ties TCC grants to the exact code signature, so an
ad-hoc-signed rebuild silently loses Screen Recording every time. The script creates a
stable self-signed identity so you grant once. See [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

The `.xcodeproj` is generated and **git-ignored** — never commit it; edit `project.yml` instead.

## Project shape

- All testable logic lives in the SwiftPM package (`Sources/`, `Tests/`). Keep it **UI-free** so `swift test` covers it without an app bundle.
- The app (`App/`) is the only place that imports SwiftUI/AppKit.
- Adding a dependency is a real decision — there are only three today, and the package must stay buildable offline. Prefer system frameworks; say why in the PR if you add one.

## Code style

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Swift 6 language mode, **complete** strict concurrency. Engines are `actor`s; models are `Sendable` value types.
- Public API gets doc comments.
- Comments explain **why**, not what. If a line looks odd but is deliberate, say what
  breaks without it — much of this codebase's trickiness (TCC signature pinning,
  `URL.resourceValues` caching, `AsyncImage` refusing `file://`) is invisible otherwise.
- User-facing strings go in `App/Resources/Localizable.xcstrings` with **fr and es**
  translations. Dynamic values (file names, tags, numbers) use `Text(verbatim:)` — a
  localized `Text("\(someInt)")` will insert the locale's thousands separator.
- No SwiftFormat/SwiftLint config yet; match surrounding style.

## Commits & branches

- **Conventional Commits**: `feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `test:`, `refactor:` (optionally scoped, e.g. `feat(capture):`).
- **Atomic commits** — one logical change each; keep code separate from config/tooling changes.
- Branches: feature branches off `main`; never force-push shared branches.

## Pull request checklist

- [ ] `swift build` and `swift test` pass.
- [ ] New/changed engine logic has unit tests in the same PR.
- [ ] Touched only files in scope (no drive-by edits).
- [ ] Docs updated if behavior/architecture changed — including the in-app help page
      (`App/Resources/Help/index.html`) if it's user-visible.
- [ ] New user-facing strings have fr + es translations.
- [ ] No secrets, `.env`, or generated `.xcodeproj` committed.

## Reporting security issues

Don't open a public issue — see [docs/SECURITY.md](docs/SECURITY.md).

## License

By contributing you agree your contributions are licensed under the
[Apache License 2.0](LICENSE).
