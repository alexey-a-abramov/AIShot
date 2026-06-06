# AIShot Roadmap

This roadmap turns the vision — a native macOS capture tool for humans **and** local AI agents — into shippable increments. Every phase ends with a build that runs and tests that pass.

**Decisions locked in:** native Swift (SwiftUI + AppKit) · macOS 15+ · embedded MCP server · Developer ID / notarized / non-sandboxed distribution.

Legend: ✅ done · 🟡 in progress · ⬜ planned.

---

## Implementation status (live)

- ✅ **Phase 0** — scaffold, CI, 7 modules, tests.
- ✅ **Phase 1 (MVP)** — P1a capture core + outputs + hotkeys + overlay; P1b embedded MCP (capture/enumeration tools + stdio server); P1c annotation renderer + editor; P1d app switching + synthetic input + Vision locator; P1e launch-at-login + settings + permissions UI.
- ✅ **i18n** — English/French/Spanish via String Catalog (extensible).
- ✅ **Phase 2** — OCR text-grab, color picker, pin-to-screen (+ `ocr` MCP tool).
- ✅ **Phase 3** — beautify, auto-redact, screen recording (+ `beautify`/`redact` MCP tools).
- ✅ **Phase 4** — MCP resources (history), scrolling capture, Sparkle auto-update, release scripts + CI.
- ✅ **Website** — localized Astro site (en/fr/es) under `website/`.
- 🟡 **Phase 5** — App Intents/Shortcuts, plugin surface, extras (in progress).

70+ unit/contract/snapshot tests pass via `swift test`; the app builds via `xcodebuild`. Runtime permission-gated behavior (live capture, synthetic input) and notarization require a real machine/Apple account and are gated/documented.

---

## Guiding principles

1. **Local-first & private.** No network egress except an optional, explicit update check. Screenshots never leave the machine.
2. **One path in.** UI, hotkeys, and MCP all build the same `CaptureRequest` and call the same engine — no divergent behavior between humans and agents.
3. **Safe by default for agents.** Capture/read tools are free; input/app-control tools are confirmation-gated.
4. **Always shippable.** Each sub-milestone is independently runnable and tested.
5. **Steal the best UX.** Match or beat CleanShot X / Shottr / Flameshot on the features that matter (see the feature table).

---

## Phase 0 — Foundations ✅

The scaffold in this commit.

- ✅ Git repo, `.gitignore`, CI (`swift build` + `swift test` on `macos-15`).
- ✅ SwiftPM package `AIShotKit` split into 7 modules with clear boundaries.
- ✅ Domain models, protocols, and stubbed engines that compile under Swift 6 strict concurrency.
- ✅ 18 unit tests (swift-testing) across models, geometry, annotation, MCP catalog, settings.
- ✅ App shell (menu-bar agent + Dashboard + Settings), XcodeGen spec, entitlements, Info.plist.
- ✅ Architecture / MCP / Permissions / Testing / Security docs.

**Exit criteria:** met — `swift test` green, app sources type-check against the 15 SDK.

---

## Phase 1 — MVP for users *and* agents

All four capability buckets you asked for, delivered as five independently shippable sub-milestones.

### P1a — Capture core + outputs ⬜
The foundation everything else builds on.

- Enumerate displays/windows via `SCShareableContent`.
- Region / window / display / all-displays capture via `SCScreenshotManager.captureImage(contentFilter:configuration:)`.
- Retina correctness: multiply `SCStreamConfiguration` size by `backingScaleFactor`; record `scale` in metadata.
- Exclude AIShot's own overlay/toolbar windows via `SCContentFilter(excludingWindows:)`.
- Selection overlay window (crosshair, dimensions, snap-to-window, magnifier loupe).
- Encode (PNG/JPEG/HEIC/TIFF) via ImageIO; save to the configured folder with the filename template.
- Copy to clipboard (`NSPasteboard`), notification with thumbnail + actions (`UserNotifications`).
- Global hotkeys (KeyboardShortcuts), self-timer, cursor toggle.
- **Tests:** coordinate/scale math, filename templating, format encoding round-trips, content-filter exclusion logic (integration tests gated behind Screen-Recording permission).
- **Exit:** press a hotkey → region capture → file on disk + clipboard + notification.

### P1b — Embedded MCP server (capture/read tools) ⬜
The "for agents" core.

- Add the official [`swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk) (v0.12.x); create `Server`, register `ListTools` / `CallTool`.
- Host in-app over **loopback HTTP** (`StatefulHTTPServerTransport`, `127.0.0.1`) with a per-launch token + `Origin` check.
- Ship a thin **stdio bridge** executable that agents spawn; it forwards JSON-RPC to the running app (Unix-domain-socket option for zero open ports).
- Wire tools: `list_displays`, `list_windows`, `list_apps`, `capture_region`, `capture_window`, `capture_display`, `get_history`. Images returned as MCP image content **and** a file path.
- Settings → MCP pane: enable/disable, port, token, copyable client config.
- **Tests:** MCP contract tests over `InMemoryTransport` (tool list, schema validation, error mapping); golden tests for argument decode/encode.
- **Exit:** Claude Code/Desktop lists AIShot tools and captures a screenshot via MCP.

### P1c — Annotation editor ⬜
Post-capture editing + the `annotate` MCP tool.

- Floating editor window: arrow, line, rectangle, ellipse, text, highlighter, blur, pixelate, numbered counter.
- Flatten via `CGContext` + Core Image (`CIFilter.gaussianBlur`/`pixellate`) → new image bytes.
- Undo/redo, color/width pickers, drag/resize/reorder, copy/save annotated result.
- `annotate` MCP tool: accept an image + declarative annotations, return the rendered image.
- **Tests:** geometry (arrowheads, bounding boxes — already started), document `Codable` round-trips, deterministic render snapshots (pixel hash) for each tool.
- **Exit:** capture → draw arrow + redact a region → save; an agent annotates an image headlessly.

### P1d — App switching + vision-targeted clicks ⬜
The automation/debugging surface (heaviest; needs Accessibility).

- `NSWorkspace` app switching first (low risk): `list_apps`, `switch_app`, `frontmostApp`.
- Accessibility detection/onboarding (`AXIsProcessTrusted`, prompt + deep link).
- Synthetic input via `CGEvent.post`: `click`, `type_text`, with correct per-display coordinate conversion.
- Vision locator: `locate` finds UI by recognized text (`RecognizeTextRequest`) or template match → rects to click.
- **Safety:** all privileged tools honor `mcpRequireConfirmationForInput` (default on) — a confirmation UI before each action, with an allowlist/session-approve option.
- **Tests:** coordinate conversion across multi-display layouts, privileged-tool gating logic, locator scoring on fixture images.
- **Exit:** an agent switches to an app, locates a button by label, and clicks it (after confirmation).

### P1e — Permissions, onboarding & polish ⬜
- First-run onboarding for Screen Recording / Accessibility / Notifications with live status (`CGPreflightScreenCaptureAccess`, etc.) and "Open System Settings" deep links.
- Dashboard: capture history (persisted), MCP status/log, permission health.
- Settings fully bound to `AppSettings` (save location picker, format, filename template, shortcuts, MCP, launch-at-login via `LaunchAtLogin-Modern`).
- **Exit:** clean install → guided permissions → all P1 features usable; **Phase 1 = a daily-driver capture app with a working local agent surface.**

---

## Phase 2 — Power capture features ⬜
High value-to-effort wins that differentiate from the system tool.

- **OCR / text-grab** (`RecognizeTextRequest`) — region → text on clipboard; also an MCP `ocr` tool.
- **Pin / float** a screenshot above all windows for reference.
- **Color picker + pixel magnifier** with HEX/RGB readout (Shottr-style).
- **Pixel ruler / measure** with sub-pixel arrow-key nudging.
- **Capture history** with search, re-copy, re-open in editor.
- **Hide desktop icons** mode; remember-last-selection.

## Phase 3 — Beautify, redaction & recording ⬜
- **Beautify**: gradient/image backgrounds, padding, rounded corners, shadow, device/window frames, social-size presets (Xnapper-style).
- **Auto-redact** sensitive data (emails, cards, keys) via Vision + Core Image blur.
- **Screen recording** (`SCStream`): region/window/display to video + **GIF**, optional mic/system audio.
- **Step capture**: auto-numbered click-through guide (synergizes with automation).

## Phase 4 — Advanced agent platform & distribution ⬜
- MCP **resources** (browse history) and **prompts** (capture-and-describe workflows).
- Scriptable automation flows / macros; richer CV (element-tree-aware targeting via `AXUIElement`).
- **Scrolling capture** (synthetic scroll + frame stitching with Vision feature matching — high effort).
- **Distribution**: Developer ID signing + notarization pipeline, **Sparkle 2** auto-update, DMG, release CI.

## Phase 5 — Optional & exploratory ⬜
- Optional, explicitly-opt-in share/upload providers.
- Plugin/extension surface for custom MCP tools.
- Localization, accessibility audit, App Intents / Shortcuts.

---

## Feature → phase matrix (best-in-class targets)

| Feature | Source of inspiration | Phase |
|---|---|---|
| Region/window/display capture, Retina-correct | macOS native, all | P1a |
| Save / clipboard / notification w/ actions | CleanShot X | P1a |
| Global hotkeys, self-timer | macOS native | P1a |
| MCP capture/enumeration tools | (AIShot) | P1b |
| Annotation (arrows/shapes/text/redact/steps) | Flameshot, Skitch | P1c |
| App switching + vision-targeted clicks (gated) | (AIShot) | P1d |
| Onboarding, history, full settings | CleanShot X | P1e |
| OCR / text-grab | Shottr, Snagit | P2 |
| Pin/float, color picker, pixel ruler | CleanShot X, Shottr | P2 |
| Beautify / device frames | Xnapper | P3 |
| Auto-redact sensitive info | Xnapper | P3 |
| Screen + region recording, GIF | CleanShot X | P3 |
| Scrolling capture | Snagit, Shottr | P4 |
| Auto-update (Sparkle), notarized DMG | — | P4 |

---

## Cross-cutting risks & mitigations

| Risk | Mitigation |
|---|---|
| MCP `swift-sdk` is pre-1.0 (API churn) | Isolate behind `ScreenshotMCPService`; pin a version; contract tests. |
| Sandbox blocks synthetic input | Ship Developer ID non-sandboxed (decided); documented in PERMISSIONS. |
| TCC re-prompts on unstable signing | Stable signing identity; detect status and guide to Settings. |
| Multi-display coordinate bugs | Central converter (`Geometry.flipToTopLeft`) + dedicated tests. |
| Agent misuse of click/type | Confirmation gate on by default; loopback + token; audit log. |
| Scrolling capture complexity | Deferred to P4; scoped as its own spike. |

See [docs/TESTING.md](docs/TESTING.md) for the per-phase test strategy and what runs in CI vs. locally.
