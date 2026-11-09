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
    /// locale-independent navigation hooks. Runs on full Xcode (see 08-04-SUMMARY.md).
    @MainActor
    func testReadOnlySafetyNavigationFlow() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        for identifier in Self.readOnlyNavigationIdentifiers {
            // Scope to firstMatch: the identifier can resolve to more than one node in the
            // split-view hierarchy, and .click() requires a single matching element.
            let destination = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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

        // Scope to firstMatch: the identifier can resolve to more than one node in the
        // split-view hierarchy, and .click() requires a single matching element.
        let destination = app.descendants(matching: .any)
            .matching(identifier: "navigation.adaptive-experience").firstMatch
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

    /// The permission-help sheet must close with Escape (WCAG 2.1.2). It opens from a
    /// coverage-gap button, which only exists when this Mac reports a permission gap.
    @MainActor
    func testPermissionHelpSheetClosesWithEscape() throws {
        let app = launchAdaptiveExperience()

        let gapButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'adaptive.coverage.'")
        ).firstMatch
        guard gapButton.waitForExistence(timeout: 60) else {
            throw XCTSkip("No permission gap on this Mac, so the help sheet cannot be opened")
        }
        gapButton.click()

        let close = app.buttons["adaptive.permission.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }

    /// The receipts sheet always opens from the history card; its Close button must keep its
    /// own identifier and the sheet must close with Escape.
    @MainActor
    func testReceiptsSheetClosesWithEscape() throws {
        let app = launchAdaptiveExperience()

        let history = app.buttons["adaptive.history.open"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.click()

        let close = app.buttons["adaptive.receipts.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }

    /// Home asks for Full Disk Access in a sheet before a scan without it; Escape must close
    /// the sheet without starting the scan.
    @MainActor
    func testHomePermissionSheetClosesWithEscape() throws {
        let app = launch(at: "navigation.home")

        let start = app.descendants(matching: .any).matching(identifier: "home.scan.start").firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.click()

        let later = app.buttons["home.permission.later"]
        guard later.waitForExistence(timeout: 5) else {
            throw XCTSkip("This Mac grants Full Disk Access, so Home scans without the prompt")
        }
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        XCTAssertTrue(later.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["home.scan.cancel"].exists, "Escape must not start a scan")
    }

    /// The Disk Cleaner category sheet opens from "View all" on a category with more than five
    /// items, so it needs a finished scan; Escape must close it.
    @MainActor
    func testCategoryDetailSheetClosesWithEscape() throws {
        let app = launch(at: "navigation.disk-cleaner")

        let start = app.descendants(matching: .any).matching(identifier: "diskCleaner.scan.start").firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.click()

        let categories = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'diskCleaner.category.'")
        )
        guard categories.firstMatch.waitForExistence(timeout: 120) else {
            throw XCTSkip("The scan found no categories, or a macOS folder prompt is waiting for an answer")
        }
        // A macOS folder prompt during the scan can leave another app's window in front.
        app.activate()

        let viewAll = app.buttons["diskCleaner.viewAll"]
        for index in 0..<categories.count where !viewAll.exists {
            categories.element(boundBy: index).click()
            _ = viewAll.waitForExistence(timeout: 2)
        }
        guard viewAll.exists else {
            throw XCTSkip("No category has more than five items, so the detail sheet cannot be opened")
        }
        // XCUITest reports this plain button as not hittable, so click its centre directly.
        viewAll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let close = app.buttons["diskCleaner.detail.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }

    /// The review sheet opens from an opportunity card, which only exists when this Mac has an
    /// eligible cache; Escape must close it.
    @MainActor
    func testReviewSheetClosesWithEscape() throws {
        let app = launchAdaptiveExperience()

        let card = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'adaptive.card.'")
        ).firstMatch
        guard card.waitForExistence(timeout: 60) else {
            throw XCTSkip("No cleanup opportunity on this Mac, so the review sheet cannot be opened")
        }
        card.click()

        let close = app.buttons["adaptive.review.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }

    /// Keyboard only, no clicks: Shift-Tab back through the key view loop into the sidebar
    /// list, where Down Arrow moves from Home to the next row, Adaptive Experience, the only
    /// path that can move files to the Trash.
    @MainActor
    func testKeyboardReachesAdaptiveExperienceFromTheSidebar() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        let home = app.descendants(matching: .any).matching(identifier: "navigation.home").firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10), "Sidebar navigation should load")

        let continueButton = app.buttons["adaptive.onboarding.continue"]
        let dashboard = app.descendants(matching: .any)["adaptive.dashboard"]
        var reached = false
        for _ in 0..<Self.keyViewSteps where !reached {
            app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [.shift])
            app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
            reached = continueButton.waitForExistence(timeout: 1) || dashboard.exists
        }
        XCTAssertTrue(reached, "Shift-Tab and Down Arrow should reach Adaptive Experience")

        if continueButton.exists {
            // Continue is the onboarding sheet's default action.
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        }
        XCTAssertTrue(dashboard.waitForExistence(timeout: 8))
    }

    /// More than the controls between Home's first control and the sidebar.
    private static let keyViewSteps = 8

    @MainActor
    private func launch(at navigationIdentifier: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        // The row's identifier also lands on its icon, which can report a zero frame, so click
        // the first match that can take the click.
        let matches = app.descendants(matching: .any).matching(identifier: navigationIdentifier)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5), "Missing \(navigationIdentifier)")
        let destination = (0..<matches.count).lazy
            .map { matches.element(boundBy: $0) }
            .first { $0.isHittable } ?? matches.firstMatch
        destination.click()
        return app
    }

    @MainActor
    private func launchAdaptiveExperience() -> XCUIApplication {
        let app = launch(at: "navigation.adaptive-experience")
        let continueButton = app.buttons["adaptive.onboarding.continue"]
        if continueButton.waitForExistence(timeout: 3) {
            continueButton.click()
        }
        return app
    }
}
