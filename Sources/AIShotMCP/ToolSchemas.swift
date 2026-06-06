import MCP

/// JSON Schemas (as MCP `Value`) describing each tool's arguments.
enum ToolSchemas {
    static func schema(for tool: MCPTool) -> Value {
        switch tool {
        case .listDisplays, .listApps:
            return object([:])
        case .listWindows:
            return object(["onScreenOnly": prop("boolean", "Only on-screen windows")])
        case .getHistory:
            return object(["limit": prop("integer", "Maximum number of entries")])
        case .captureRegion:
            return object([
                "displayID": prop("integer", "Target display id"),
                "rect": [
                    "type": "object",
                    "description": "Region in display-local, top-left points",
                    "properties": ["x": number, "y": number, "width": number, "height": number],
                    "required": ["x", "y", "width", "height"],
                ],
                "format": format,
                "includeCursor": prop("boolean", "Render the mouse cursor"),
            ], required: ["displayID", "rect"])
        case .captureWindow:
            return object([
                "windowID": prop("integer", "Target window id"),
                "includeWindowShadow": prop("boolean", "Include the window's drop shadow"),
                "format": format,
            ], required: ["windowID"])
        case .captureDisplay:
            return object([
                "displayID": prop("integer", "Target display id"),
                "format": format,
            ], required: ["displayID"])
        case .annotate:
            return object([
                "imagePath": prop("string", "Path to a base image (or use imageBase64)"),
                "imageBase64": prop("string", "Base64-encoded base image bytes"),
                "annotations": [
                    "type": "array",
                    "description": "Annotations to draw",
                    "items": ["type": "object"],
                ],
                "format": format,
            ], required: ["annotations"])
        case .locate:
            return object([
                "text": prop("string", "Text to find on screen"),
                "displayID": prop("integer", "Display to search (defaults to main)"),
            ])
        case .switchApp:
            return object(["bundleID": prop("string", "Bundle identifier to activate")], required: ["bundleID"])
        case .click:
            return object([
                "x": number, "y": number,
                "button": prop("string", "left | right | center"),
            ], required: ["x", "y"])
        case .typeText:
            return object(["text": prop("string", "Text to type into the focused app")], required: ["text"])
        }
    }

    private static func object(_ properties: [String: Value], required: [Value] = []) -> Value {
        var dict: [String: Value] = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty { dict["required"] = .array(required) }
        return .object(dict)
    }

    private static func prop(_ type: String, _ description: String) -> Value {
        ["type": .string(type), "description": .string(description)]
    }

    private static let number: Value = ["type": "number"]
    private static let format: Value = [
        "type": "string",
        "enum": ["png", "jpeg", "heic", "tiff"],
        "description": "Image format",
    ]
}
