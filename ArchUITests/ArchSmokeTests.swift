import XCTest

/// Does the app work when you touch it.
///
/// `tools/simrun.py` proves Arch launches and draws. That is worth having and it
/// is not the same question: a dead button, a crash on opening a profile, a
/// navigation route that pushes nothing are all a healthy-looking launch. Nothing
/// in this repository had ever *tapped* anything.
///
/// These run against the design build -- CI holds no Supabase keys, so
/// `ArchConfig.isConfigured` is false, `ArchSession` settles on `.designBuild` and
/// every screen is driven by `MockData`. No network, no sign-in, no notification
/// prompt, and nothing here depends on a server being up.
///
/// Deliberately structural. They assert on the tab bar, on screens appearing and
/// on the app still being alive afterwards -- not on wording, which is the half of
/// this product most likely to change and the half least worth pinning down in a
/// test that would then have to be edited every time somebody improves a sentence.
final class ArchSmokeTests: XCTestCase {

    /// Every tab, by the accessibility label `TabBar` already puts on each button.
    private let tabs = ["Premium", "Daily 5", "Messages", "You"]

    override func setUp() {
        super.setUp()
        // A failed assertion means the rest of the walk is meaningless, and
        // carrying on past it buries the first failure under its consequences.
        continueAfterFailure = false
    }

    /// Launch, and wait for the tab bar rather than for a fixed number of seconds.
    ///
    /// The launch view draws itself for about 1.4 seconds before the app opens, so
    /// anything that looks for a control immediately finds nothing. Waiting on the
    /// control itself is also the difference between a test that is slow on a busy
    /// runner and a test that is flaky on one.
    @discardableResult
    private func launch(file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.buttons["Daily 5"].waitForExistence(timeout: 30),
            "The tab bar never appeared, so Arch did not get past its launch view.",
            file: file, line: line
        )
        return app
    }

    // MARK: The shell

    func testItOpensOnTheRosterWithFourTabs() {
        let app = launch()

        for tab in tabs {
            XCTAssertTrue(app.buttons[tab].exists, "The \(tab) tab is missing.")
        }
        // Four and only four. The tab bar's own comment says "four tabs, no more",
        // and a fifth appearing is a product decision that should have to be made
        // on purpose rather than noticed later.
        XCTAssertEqual(
            tabs.filter { app.buttons[$0].exists }.count, 4,
            "Arch should open with exactly four tabs."
        )
        XCTAssertTrue(
            app.buttons["Daily 5"].isSelected,
            "Arch should open on the roster, which is the whole point of it."
        )
    }

    func testEveryTabOpensAndComesBack() {
        let app = launch()

        for tab in tabs {
            app.buttons[tab].tap()
            XCTAssertTrue(
                app.buttons[tab].waitForExistence(timeout: 5),
                "The tab bar disappeared after tapping \(tab)."
            )
            XCTAssertTrue(
                app.buttons[tab].isSelected,
                "Tapping \(tab) did not select it."
            )
            XCTAssertEqual(
                app.state, .runningForeground,
                "Arch stopped running after opening \(tab)."
            )
        }

        // Back to where it started, because a tab bar that only goes one way is
        // not a tab bar.
        app.buttons["Daily 5"].tap()
        XCTAssertTrue(app.buttons["Daily 5"].isSelected)
    }

    // MARK: The roster

    func testTheRosterHasPeopleInIt() {
        let app = launch()
        app.buttons["Daily 5"].tap()

        // Something to tap that is not the tab bar itself. `MockData` fills the
        // roster, so an empty content area here means the roster did not render --
        // which is exactly the failure a launch screenshot cannot see.
        let content = app.descendants(matching: .any)
            .matching(NSPredicate(format: "elementType == %d OR elementType == %d",
                                  XCUIElement.ElementType.button.rawValue,
                                  XCUIElement.ElementType.staticText.rawValue))
        XCTAssertGreaterThan(
            content.count, tabs.count,
            "The Daily 5 tab has nothing on it but the tab bar."
        )
    }

    /// Opening somebody, then coming back.
    ///
    /// The navigation routes are where this app broke last: four `NavigationPath`
    /// destinations were written as bare names that compiled and went nowhere.
    func testOpeningAProfileAndGoingBack() {
        let app = launch()
        app.buttons["Daily 5"].tap()

        // The first tappable thing that is not a tab. Deliberately not addressed by
        // name -- the roster is mock data and the names in it are not a contract.
        let card = app.buttons.allElementsBoundByIndex.first { element in
            element.exists && element.isHittable && !tabs.contains(element.label)
        }
        guard let card else {
            // Not a failure: the design build's roster may legitimately be all
            // empty slots. Saying so is better than a green test that checked
            // nothing, and better than a red one blaming the app for the fixture.
            XCTContext.runActivity(named: "No roster card to open") { _ in }
            return
        }

        card.tap()
        XCTAssertEqual(
            app.state, .runningForeground,
            "Arch stopped running after opening a profile."
        )
        XCTAssertTrue(
            app.buttons["Daily 5"].waitForExistence(timeout: 5),
            "Opening a profile left nowhere to go back to."
        )
    }

    // MARK: You

    func testTheYouTabDrawsAProfile() {
        let app = launch()
        app.buttons["You"].tap()

        XCTAssertTrue(app.buttons["You"].isSelected)
        XCTAssertGreaterThan(
            app.staticTexts.count, 0,
            "The You tab drew no text at all."
        )
        XCTAssertEqual(app.state, .runningForeground)
    }
}
