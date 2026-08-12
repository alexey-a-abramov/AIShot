# Testing Strategy

Goal: keep as much logic as possible in pure, fast, deterministic unit tests that run in CI without an app bundle, code signing, or TCC permissions — and clearly separate the slice that genuinely needs a real screen.

## The pyramid

```
        ┌───────────────────────────┐
        │  Manual / exploratory     │  permissions, real multi-display, agents
        ├───────────────────────────┤
        │  UI smoke (XCUITest)      │  app launches, windows open, hotkeys (local/CI-opt)
        ├───────────────────────────┤
        │  Integration (gated)      │  real ScreenCaptureKit / CGEvent — needs TCC, run locally
        ├───────────────────────────┤
        │  Contract (MCP)           │  server over InMemoryTransport, no ports/permissions
        ├───────────────────────────┤
        │  Unit (swift-testing) ◄── majority; runs everywhere, <1s total
        └───────────────────────────┘
```

## Tiers

### Unit — `swift test` (every push)
Pure logic, no platform permissions. **89 tests** today:

- **Core:** `ImageFormat` mapping, `CaptureRequest` `Codable`/defaults, `CaptureMode` cases.
- **Shared:** `Geometry` clamp/scale/union, coordinate flip (multi-display correctness).
- **Annotation:** arrowhead symmetry, bounding boxes, document `Codable`, contrasting
  label colour, counter badges actually rendering their number.
- **Capture:** image round-trips per format, stitching overlap, and **thumbnail
  downsampling** (longest-edge bound, aspect preserved, never upscales, missing/garbage
  input throws).
- **Persistence:** settings defaults and resilient decoding; history ordering, removal,
  and **decoding rows written before a field existed**; notes/tags upsert, tag
  normalisation, index relocation and merge-on-conflict; **OCR index** store/reload,
  change detection, search, snippet elision, prune.
- **MCP:** tool-catalog uniqueness, snake_case wire names, and the **policy gates** —
  server disabled, confirmation required, confirmation opted out.

### Contract (MCP)
Runs the service over `InMemoryTransport`: asserts the advertised tool list, validates
argument schemas, and verifies `AIShotError` → MCP error mapping. No ports, no
permissions.

### Integration (gated) — local only
Real ScreenCaptureKit capture and real `CGEvent` input need Screen-Recording /
Accessibility, so they're guarded by `AISHOT_INTEGRATION=1` and skipped by default.

### Manual — what tests can't reach
Some behaviour only exists against a real windowserver and real TCC, and is verified by
hand before release:

- Permission grants surviving a rebuild (the signing-identity trap — see PERMISSIONS.md).
- Global hotkeys, the selection overlay, Esc-cancel, freeze-frame.
- Quick Look, drag-out to another app, Trash + Put Back.
- The MCP helper end to end over stdio (keep stdin open — it exits when the pipe closes).
- Locale-sensitive formatting: launch with `-AppleLanguages "(fr)"` and confirm a
  1254×512 capture still reads `1254×512`, not `1 254×512`.

## What runs where

| Tier | CI (`macos-15`) | Local dev |
|---|:--:|:--:|
| Unit | ✅ | ✅ |
| MCP contract | ✅ | ✅ |
| Integration (capture/input) | ⬜ skipped (no TCC) | ✅ with permissions |
| Manual | ⬜ | ✅ before release |

## Conventions

- Framework: **swift-testing** (`import Testing`, `@Test`, `#expect`). XCTest only where required (XCUITest).
- One behavior per test; deterministic inputs (no wall-clock/random in assertions).
- New engine code lands with its unit tests in the same PR (see CONTRIBUTING).
- Coverage target: ≥80% of `AIShotKit` non-UI logic.
- `EditorModel` and the SwiftUI views live in the **app** target and aren't covered by
  `swift test`. That's the biggest coverage gap; extracting `EditorModel` into a library
  target would close most of it.

## Running

```bash
swift test                       # unit + contract
AISHOT_INTEGRATION=1 swift test  # also run gated integration (needs permissions)
swift test --filter CaptureTextIndexStoreTests   # one suite
```

If you see `no such module 'Testing'`, `xcode-select` is pointing at the Command Line
Tools, which don't ship swift-testing:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```
