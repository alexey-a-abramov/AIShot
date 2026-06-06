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

### Unit — `swift test` (CI, every push)
Pure logic, no platform permissions. Already present (18 tests):
- **Core:** `ImageFormat` mapping, `CaptureRequest` `Codable`/defaults, `CaptureMode` cases.
- **Shared:** `Geometry` clamp/scale/union, **coordinate flip** (multi-display correctness).
- **Annotation:** arrowhead symmetry, bounding boxes, document `Codable`.
- **MCP:** tool catalog uniqueness, snake_case wire names, **privileged-tool gating**.
- **Persistence:** settings defaults (safe MCP default), `Codable`, in-memory history ordering.

Add per phase: filename templating, content-filter exclusion logic, locator scoring, settings migrations.

### Contract (MCP) — added P1b
Run the embedded server over `InMemoryTransport`: assert advertised tools, validate argument JSON schemas, and verify `AIShotError` → MCP error mapping. No network, no permissions → runs in CI.

### Render snapshots — added P1c
Flatten an `AnnotationDocument` onto a fixed base image and assert a **pixel hash** per tool (arrow, rect, text, blur). Deterministic and CI-safe (Core Image render is reproducible for fixed inputs).

### Integration (gated) — local
Real ScreenCaptureKit capture and real `CGEvent` clicks need Screen-Recording / Accessibility. Guard with an env flag (e.g. `AISHOT_INTEGRATION=1`) so they're **skipped in CI** and run on a developer machine that has granted permissions. Assert: a capture returns non-empty pixels of expected size/scale; a click lands at the expected point in a test harness window.

### UI smoke — optional
XCUITest: app launches as an agent, Dashboard/Settings open, menu items exist. Kept minimal and opt-in.

## What runs where

| Tier | CI (`macos-15`) | Local dev |
|---|:--:|:--:|
| Unit | ✅ | ✅ |
| MCP contract | ✅ | ✅ |
| Render snapshots | ✅ | ✅ |
| Integration (capture/input) | ⬜ skipped (no TCC) | ✅ with permissions |
| UI smoke | optional | ✅ |

## Conventions

- Framework: **swift-testing** (`import Testing`, `@Test`, `#expect`). XCTest only where required (XCUITest).
- One behavior per test; deterministic inputs (no wall-clock/random in assertions).
- New engine code lands with its unit tests in the same PR (see CONTRIBUTING).
- Coverage target: ≥80% of `AIShotKit` non-UI logic.

## Running

```bash
swift test                       # unit + contract + snapshots
AISHOT_INTEGRATION=1 swift test  # also run gated integration (needs permissions)
```
