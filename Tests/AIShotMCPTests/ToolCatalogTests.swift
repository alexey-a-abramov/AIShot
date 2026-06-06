import Testing
@testable import AIShotMCP

struct ToolCatalogTests {
    @Test func rawValuesAreUniqueAndSnakeCase() {
        let raw = MCPTool.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        #expect(raw.allSatisfy { $0 == $0.lowercased() })
        #expect(raw.allSatisfy { !$0.contains(" ") })
    }

    @Test func everyToolHasASummary() {
        #expect(MCPTool.allCases.allSatisfy { !$0.summary.isEmpty })
    }

    @Test func onlyInputAndAppControlToolsArePrivileged() {
        let privileged = Set(MCPTool.allCases.filter(\.isPrivileged))
        #expect(privileged == [.switchApp, .click, .typeText])
        #expect(!MCPTool.captureRegion.isPrivileged)
        #expect(!MCPTool.listDisplays.isPrivileged)
    }
}
