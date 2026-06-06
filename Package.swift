// swift-tools-version: 6.0
import PackageDescription

// AIShotKit — the testable, UI-independent core of AIShot.
//
// The GUI/menu-bar application target lives outside SPM (generated from
// `project.yml` via XcodeGen) and links this package. Keeping the engine here
// means `swift build` / `swift test` cover all logic in CI without an app
// bundle, code signing, or TCC permissions.
//
// External dependencies (MCP swift-sdk, KeyboardShortcuts, Defaults, Sparkle,
// …) are intentionally NOT added yet — they arrive with the phase that needs
// them so the initial scaffold builds fully offline. See ROADMAP.md.
let package = Package(
    name: "AIShotKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "AIShotKit",
            targets: [
                "AIShotShared",
                "AIShotCore",
                "AIShotCapture",
                "AIShotAnnotation",
                "AIShotAutomation",
                "AIShotPersistence",
                "AIShotService",
                "AIShotMCP",
            ]
        )
    ],
    dependencies: [
        // Official Model Context Protocol Swift SDK (pre-1.0).
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.0"),
    ],
    targets: [
        // Cross-cutting utilities: logging, geometry, permission model.
        .target(name: "AIShotShared"),

        // Pure domain models (capture requests/results, displays, windows).
        .target(name: "AIShotCore", dependencies: ["AIShotShared"]),

        // ScreenCaptureKit-backed capture engine.
        .target(name: "AIShotCapture", dependencies: ["AIShotCore", "AIShotShared"]),

        // Annotation model + rendering (arrows, shapes, text, redaction).
        .target(name: "AIShotAnnotation", dependencies: ["AIShotCore", "AIShotShared"]),

        // App switching + synthetic input + Vision-based element location.
        .target(name: "AIShotAutomation", dependencies: ["AIShotCore", "AIShotShared"]),

        // Settings, save locations, history, clipboard, notifications.
        .target(name: "AIShotPersistence", dependencies: ["AIShotCore", "AIShotShared"]),

        // Application service layer: orchestrates capture → save → clipboard →
        // notify → history, and surfaces system permission status.
        .target(
            name: "AIShotService",
            dependencies: [
                "AIShotCore", "AIShotCapture", "AIShotAnnotation",
                "AIShotAutomation", "AIShotPersistence", "AIShotShared",
            ]
        ),

        // Embedded MCP server: maps MCP tool calls onto the service/engines.
        .target(
            name: "AIShotMCP",
            dependencies: [
                "AIShotCore", "AIShotCapture", "AIShotAnnotation",
                "AIShotAutomation", "AIShotPersistence", "AIShotService", "AIShotShared",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),

        // Standalone stdio MCP server binary that local agents spawn.
        .executableTarget(
            name: "aishot-mcp-server",
            dependencies: [
                "AIShotMCP", "AIShotService", "AIShotCapture", "AIShotPersistence",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),

        // ─── Tests ───
        .testTarget(name: "AIShotCoreTests", dependencies: ["AIShotCore"]),
        .testTarget(name: "AIShotCaptureTests", dependencies: ["AIShotCapture", "AIShotCore"]),
        .testTarget(name: "AIShotSharedTests", dependencies: ["AIShotShared"]),
        .testTarget(name: "AIShotAnnotationTests", dependencies: ["AIShotAnnotation"]),
        .testTarget(
            name: "AIShotMCPTests",
            dependencies: [
                "AIShotMCP", "AIShotService", "AIShotCapture", "AIShotCore", "AIShotPersistence",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(name: "AIShotServiceTests", dependencies: ["AIShotService", "AIShotCore", "AIShotCapture", "AIShotPersistence"]),
        .testTarget(name: "AIShotPersistenceTests", dependencies: ["AIShotPersistence", "AIShotCore"]),
    ]
)
