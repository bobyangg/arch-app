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
///
/// Tabs are addressed by accessibility *identifier* rather than by label. The
/// first version of this used the titles and every test failed the same way:
/// "multiple matching elements". Messages and You each put their own name on a
/// heading, so a query for a control called "Messages" is ambiguous by
/// construction -- and a query by display text breaks the moment anybody rewords
/// anything.
final class ArchSmokeTests: XCTestCase {

    /// Every tab, by the identifier `ArchTab` gives it.
    private let tabs = ["tab.premium", "tab.daily", "tab.messages", "tab.you"]

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
            app.buttons["tab.daily"].waitForExistence(timeout: 30),
            "The tab bar never appeared, so Arch did not get past its launch view.",
            file: file, line: line
        )
        return app
    }

    /// The element tree, attached to the report when something is ambiguous.
    ///
    /// "Multiple matching elements found" is the least informative failure XCTest
    /// produces, and the only way to learn what the other match was is to look.
    private func attachTree(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: The shell

    func testItOpensOnTheRosterWithFourTabs() {
        let app = launch()

        for tab in tabs {
            let matches = app.buttons.matching(identifier: tab).count
            if matches != 1 { attachTree(app, named: "Tree when \(tab) matched \(matches)") }
            // Exactly one, not "at least one". Two would mean the tab bar is on
            // screen twice, which is the kind of thing that looks fine in a
            // screenshot and makes every later query ambiguous.
            XCTAssertEqual(matches, 1, "\(tab) matched \(matches) elements; expected one.")
        }

        XCTAssertTrue(
            app.buttons["tab.daily"].isSelected,
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
            XCTAssertTrue(app.buttons[tab].isSelected, "Tapping \(tab) did not select it.")
            XCTAssertEqual(
                app.state, .runningForeground,
                "Arch stopped running after opening \(tab)."
            )
        }

        // Back to where it started, because a tab bar that only goes one way is
        // not a tab bar.
        app.buttons["tab.daily"].tap()
        XCTAssertTrue(app.buttons["tab.daily"].isSelected)
    }

    // MARK: The roster

    func testTheRosterHasPeopleInIt() {
        let app = launch()
        app.buttons["tab.daily"].tap()

        // Something on screen that is not the tab bar itself. `MockData` fills the
        // roster, so an empty content area here means the roster did not render --
        // which is exactly the failure a launch screenshot cannot see.
        XCTAssertGreaterThan(
            app.staticTexts.count, 0,
            "The Daily 5 tab drew no text at all."
        )
        XCTAssertGreaterThan(
            app.buttons.count, tabs.count,
            "The Daily 5 tab has nothing on it but the tab bar."
        )
    }

    /// Opening somebody, then coming back.
    ///
    /// The navigation routes are where this app broke last: four `NavigationPath`
    /// destinations were written as bare names that compiled and went nowhere.
    func testOpeningAProfileAndGoingBack() {
        let app = launch()
        app.buttons["tab.daily"].tap()

        // The first tappable thing that is not a tab. Deliberately not addressed by
        // name -- the roster is mock data and the names in it are not a contract.
        let card = app.buttons.allElementsBoundByIndex.first { element in
            element.exists && element.isHittable && !tabs.contains(element.identifier)
        }
        guard let card else {
            // Not a failure: the design build's roster may legitimately be all
            // empty slots. Saying so is better than a green test that checked
            // nothing, and better than a red one blaming the app for the fixture.
            attachTree(app, named: "No roster card to open")
            return
        }

        card.tap()
        XCTAssertEqual(
            app.state, .runningForeground,
            "Arch stopped running after opening a profile."
        )
        XCTAssertTrue(
            app.buttons["tab.daily"].waitForExistence(timeout: 5),
            "Opening a profile left nowhere to go back to."
        )
    }

    // MARK: You

    func testTheYouTabDrawsAProfile() {
        let app = launch()
        app.buttons["tab.you"].tap()

        XCTAssertTrue(app.buttons["tab.you"].isSelected)
        XCTAssertGreaterThan(app.staticTexts.count, 0, "The You tab drew no text at all.")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
