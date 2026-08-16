import Testing
import Foundation
@testable import AIShotService

struct SmartTagTests {
    @Test func usesTheAppNameForOrdinaryApps() {
        #expect(SmartTag.suggest(appName: "Xcode", windowTitle: "AIShot.xcodeproj") == "Xcode")
        #expect(SmartTag.suggest(appName: "Slack", windowTitle: "#general") == "Slack")
    }

    /// Tagging every web screenshot "Safari" would be useless.
    @Test func prefersTheSiteOverTheBrowser() {
        #expect(SmartTag.suggest(appName: "Safari",
                                 windowTitle: "alexey-a-abramov/AIShot · GitHub") == "GitHub")
        #expect(SmartTag.suggest(appName: "Google Chrome",
                                 windowTitle: "Swift Forums — Concurrency") == "Concurrency")
    }

    @Test func stripsATrailingBrowserName() {
        #expect(SmartTag.suggest(appName: "Firefox",
                                 windowTitle: "Some Page — Wikipedia — Mozilla Firefox") == "Wikipedia")
    }

    @Test func reducesABareDomainToItsName() {
        #expect(SmartTag.site(from: "github.com", browser: "Safari") == "github")
        #expect(SmartTag.site(from: "www.example.com", browser: "Safari") == "example")
    }

    /// A long page title is not a tag — better to fall back to the app.
    @Test func fallsBackToTheBrowserWhenTheTitleIsProse() {
        let prose = "How to configure a really long thing in seventeen easy steps today"
        #expect(SmartTag.suggest(appName: "Safari", windowTitle: prose) == "Safari")
    }

    @Test func handlesMissingInformation() {
        #expect(SmartTag.suggest(appName: nil) == nil)
        #expect(SmartTag.suggest(appName: "  ") == nil)
        #expect(SmartTag.suggest(appName: "Safari", windowTitle: nil) == "Safari")
        #expect(SmartTag.suggest(appName: "Safari", windowTitle: "") == "Safari")
    }
}
