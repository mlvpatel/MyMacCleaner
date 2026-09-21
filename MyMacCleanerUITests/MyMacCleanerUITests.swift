import XCTest

final class MyMacCleanerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for main window to appear with timeout
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10), "Main window should appear")
    }

    @MainActor
    func testSidebarNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for main window to appear
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10), "Main window should appear")

        // Wait on a concrete sidebar hook instead of a fixed delay.
        let homeEntry = app.descendants(matching: .any)["navigation.home"]
        XCTAssertTrue(homeEntry.waitForExistence(timeout: 10), "Sidebar navigation should load")
    }

    /// Full-Xcode gate: each formerly actionable family remains reachable through
    /// locale-independent navigation hooks. This test is checked in but not run on CLT.
    @MainActor
    func testReadOnlySafetyNavigationFlow() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        for identifier in Self.readOnlyNavigationIdentifiers {
            let destination = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(destination.waitForExistence(timeout: 5), "Missing \(identifier)")
            destination.click()
        }
    }

    private static let readOnlyNavigationIdentifiers = [
        "navigation.home",
        "navigation.disk-cleaner",
        "navigation.space-lens",
        "navigation.orphaned-files",
        "navigation.duplicates",
        "navigation.performance",
        "navigation.applications",
        "navigation.startup-items",
        "navigation.port-management",
        "navigation.system-health",
        "navigation.permissions"
    ]

    @MainActor
    func testAdaptiveExperienceDashboardIdentifiers() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        let destination = app.descendants(matching: .any)["navigation.adaptive-experience"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "Missing navigation.adaptive-experience")
        destination.click()

        let continueButton = app.buttons["adaptive.onboarding.continue"]
        if continueButton.waitForExistence(timeout: 3) {
            continueButton.click()
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["adaptive.dashboard"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["adaptive.mode.picker"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.descendants(matching: .any)["adaptive.approval.button"].exists)
    }
}
