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
    private let tabs = ["tab.premium", "tab.daily", "tab.messages", "tab.planner", "tab.you"]

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
    private func launch(
        arguments: [String] = [],
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
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

    func testItOpensOnTheRosterWithFiveTabs() {
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

    // MARK: The top bar

    /// The lock-up goes away as you read down, and comes back the moment you
    /// scroll up.
    ///
    /// Shipped once to TestFlight without this, and the bar never moved on a
    /// phone. The build had compiled and launched in the simulator, and nothing
    /// in the simulator had ever scrolled it.
    ///
    /// Measured, not counted. All five tabs stay in the tree and XCUITest sees
    /// all four lock-ups whatever their accessibility says, and it will not call
    /// a plain strip over a scroll view "hittable" either. What it does report
    /// faithfully is a frame: the bar on the tab in front is the one that moves,
    /// so the lowest top edge among the bars drops by the bar's height when it
    /// slides away and comes back when it returns.
    func testTheTopBarHidesOnScrollDownAndComesBackOnScrollUp() {
        let app = launch()
        app.buttons["tab.daily"].tap()

        // By identifier or by label. A content shape on the bar once cost it its
        // identifier in the tree while the label stayed, and the label is a
        // brand name that no other element carries on its own.
        let bars = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'topbar.arch' OR label == 'Arch'")
        )
        if !bars.firstMatch.waitForExistence(timeout: 5) {
            // The tree, in the message, because a log is all CI keeps.
            let tree = app.debugDescription.split(separator: "\n")
                .filter { $0.contains("Arch") || $0.contains("topbar") || $0.contains("ScrollView") || $0.contains("Header") }
                .prefix(30).joined(separator: "\n")
            XCTFail("The roster has no lock-up above it. Related elements:\n\(tree)")
        }
        func top() -> CGFloat { bars.allElementsBoundByIndex.map(\.frame.minY).min() ?? .nan }
        func wait(until settled: @escaping (CGFloat) -> Bool, _ message: String) {
            let deadline = Date().addingTimeInterval(5)
            while !settled(top()) && Date() < deadline { usleep(200_000) }
            let tops = bars.allElementsBoundByIndex.map { $0.frame.minY }
            XCTAssertTrue(settled(top()), "\(message) Bar tops: \(tops)")
        }

        let shown = top()
        XCTAssertFalse(shown.isNaN, "No lock-up has a frame.")

        // Two swipes, so a slow one on a busy runner still gets well past the
        // bar's own height. Reading down is the gesture; the bar should go.
        app.swipeUp()
        app.swipeUp()
        wait(until: { $0 < shown - 30 }, "Scrolling down did not hide the lock-up.")

        // One swipe up the page. Not necessarily back to the top, and it should
        // not need to be: any scroll towards the top brings the bar back.
        app.swipeDown()
        wait(until: { abs($0 - shown) < 2 }, "Scrolling back up did not bring the lock-up back.")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: You

    func testTheYouTabDrawsAProfile() {
        let app = launch()
        app.buttons["tab.you"].tap()

        XCTAssertTrue(app.buttons["tab.you"].isSelected)
        XCTAssertGreaterThan(app.staticTexts.count, 0, "The You tab drew no text at all.")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Settings

    /// The two rows added with the profile controls go somewhere.
    ///
    /// A settings row is routed by its string id, and a mistyped id is not a
    /// compile error -- it is a screen that says "This setting is not built
    /// yet". Both new rows are opened and asked for the one control each has.
    func testWhereYouAreAndYourAnswersOpen() {
        let app = launch()
        app.buttons["tab.you"].tap()
        app.buttons["Settings"].tap()

        func open(_ title: String, expecting control: String) {
            let row = app.staticTexts[title]
            // Settings is one scroll; the later rows start below the fold.
            var tries = 0
            while !row.isHittable && tries < 4 { app.swipeUp(); tries += 1 }
            XCTAssertTrue(row.isHittable, "No settings row called \(title).")
            row.tap()
            XCTAssertTrue(
                app.buttons[control].waitForExistence(timeout: 5),
                "\(title) opened without its \(control) button."
            )
            app.buttons["Back to settings"].tap()
        }

        open("Where you are", expecting: "Change")
        open("Your answers", expecting: "Answer again")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: The profile editor

    /// Into Arrange and back.
    ///
    /// The first test that leaves the tab bar. Everything above this walks four
    /// root screens; a push that went nowhere would pass all of them.
    func testArrangeOpensAndComesBack() {
        let app = launch()
        app.buttons["tab.you"].tap()

        let arrange = app.buttons["profile.arrange"]
        XCTAssertTrue(arrange.waitForExistence(timeout: 5), "No way into Arrange from the You tab.")
        arrange.tap()

        // Not the add slot. That was the first version of this test and it failed
        // for a reason that had nothing to do with Arrange: `MockData.you` holds
        // exactly `photoLimit` photographs, so `canAdd` is false and there is
        // correctly no add button to find. The test was wrong, the screen was
        // fine, and the assertion message blamed the screen.
        //
        // "Done" is on the header whatever the grid contains, and it is also the
        // way back — so one control proves both halves of what this test is named
        // after.
        let done = app.buttons["arrange.done"]
        XCTAssertTrue(
            done.waitForExistence(timeout: 5),
            "Arrange did not open — its header never appeared."
        )
        XCTAssertEqual(app.state, .runningForeground)

        done.tap()
        XCTAssertTrue(
            app.buttons["profile.arrange"].waitForExistence(timeout: 5),
            "Done did not come back to the profile."
        )
    }

    /// The refused photograph, opened and read.
    ///
    /// This is the test that would have caught `PhotoRejectedView` being dead
    /// code. It was written, previewed, and wired to nothing — the chain from the
    /// moderation tables to the screen was broken in four separate places, and
    /// every check in this repository passed the whole time, because nothing ever
    /// tapped anything inside the profile editor.
    ///
    /// `MockData` seeds one refusal on the first photo, so the design build can
    /// reach this at all.
    func testARefusedPhotoOpensTheScreenThatSaysWhy() {
        let app = launch()
        app.buttons["tab.you"].tap()
        app.buttons["profile.arrange"].tap()

        let tile = app.buttons["photo.rejected"]
        XCTAssertTrue(
            tile.waitForExistence(timeout: 5),
            "No refused photo in the grid, so nothing here tested the rejection screen. "
                + "MockData is meant to seed one."
        )
        tile.tap()

        XCTAssertTrue(
            app.staticTexts["photo.rejected.title"].waitForExistence(timeout: 5),
            "Tapping a refused photo opened nothing."
        )
        XCTAssertEqual(app.state, .runningForeground, "Arch stopped running on the rejection screen.")
    }

    // MARK: The Date planner

    /// The planner opens on one blank item, and a date is built from there:
    /// an activity, something to eat, and a surprise -- three, and no more.
    ///
    /// No stop on screen means the engine found nowhere to go, or the tab drew
    /// nothing -- either way the tab bar would still look fine in a screenshot.
    /// Stops are counted by their cards, not their Swap buttons: a stop that is
    /// the only place that fits has no Swap, because one would change nothing.
    func testTheDatePlannerLaysOutADate() {
        let app = launch()
        app.buttons["tab.planner"].tap()
        XCTAssertTrue(app.buttons["tab.planner"].isSelected)
        answerDatePreferences(app)

        let stops = app.descendants(matching: .any).matching(identifier: "planner.stop")
        XCTAssertTrue(app.buttons["planner.choose.activity"].waitForExistence(timeout: 5),
                      "The planner should open on a blank item.")
        XCTAssertEqual(stops.count, 0, "Nothing is planned before anything is chosen.")

        // An activity, given three hours.
        app.buttons["planner.choose.activity"].tap()
        XCTAssertTrue(stops.firstMatch.waitForExistence(timeout: 5), "Choosing an activity planned nothing.")
        XCTAssertEqual(stops.count, 1)
        app.buttons["planner.hours.0.3"].tap()
        XCTAssertTrue(app.buttons["planner.hours.0.3"].isSelected, "The three-hour block did not stick.")

        // Something to eat, then whatever the planner suggests.
        app.buttons["planner.addItem"].tap()
        app.buttons["planner.choose.food"].tap()
        XCTAssertEqual(stops.count, 2, "Adding food did not add a stop.")
        app.buttons["planner.addItem"].tap()
        app.buttons["planner.choose.surprise"].tap()
        XCTAssertEqual(stops.count, 3, "Surprise me did not add a stop.")
        XCTAssertFalse(app.buttons["planner.addItem"].exists, "A plan holds three items at most.")

        // A week of days, and picking one still leaves the whole plan.
        XCTAssertTrue(app.buttons["planner.day.6"].exists, "The planner should offer seven days.")
        app.buttons["planner.day.6"].tap()
        XCTAssertTrue(app.buttons["planner.day.6"].isSelected, "Tapping a day did not pick it.")
        XCTAssertEqual(stops.count, 3, "Picking a day lost the plan.")

        // Swapping a stop has to leave a plan behind, not an empty screen. The
        // anchor always has a Swap here: more than one place can anchor it.
        let swaps = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Swap'"))
        XCTAssertGreaterThan(swaps.count, 0, "No stop on this plan can be swapped.")
        swaps.firstMatch.tap()
        XCTAssertEqual(stops.count, 3, "Swapping a stop lost the plan.")

        // Removing one leaves room to add again.
        app.buttons["planner.remove.2"].tap()
        XCTAssertEqual(stops.count, 2, "Remove did not take the stop off.")
        XCTAssertTrue(app.buttons["planner.addItem"].exists, "With two items there is room for a third.")
        XCTAssertEqual(app.state, .runningForeground, "Arch stopped running on the Date planner.")
    }

    /// Through "Get started" and the five questions, taking the first option
    /// each time. Waits for each question by its "N of 5" line, because the
    /// questions move on by themselves a beat after a tap, and a tap that lands
    /// before the move is a tap on the question just answered.
    private func answerDatePreferences(
        _ app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let start = app.buttons["planner.getStarted"]
        XCTAssertTrue(start.waitForExistence(timeout: 5),
                      "The Date planner did not open on its Get started screen.",
                      file: file, line: line)
        start.tap()
        for question in 1...5 {
            XCTAssertTrue(app.staticTexts["\(question) of 5"].waitForExistence(timeout: 5),
                          "Question \(question) of the date preferences never appeared.",
                          file: file, line: line)
            app.buttons["planner.option.0"].tap()
        }
        XCTAssertTrue(app.buttons["planner.editPreferences"].waitForExistence(timeout: 5),
                      "Answering all five did not take the planner to a plan.",
                      file: file, line: line)
    }

    /// Straight after onboarding the planner is introduced in a popup, and its
    /// "Get started" goes to the first question in the planner tab.
    ///
    /// The design build has no onboarding to finish, so `-introducePlanner`
    /// stands in for having just finished it -- the same flag finishing sets.
    func testThePlannerIsIntroducedAfterOnboarding() {
        let app = launch(arguments: ["-introducePlanner"])

        let start = app.buttons["planner.getStarted"]
        XCTAssertTrue(start.waitForExistence(timeout: 10),
                      "No Date planner popup after onboarding.")
        start.tap()

        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 5),
                      "Get started in the popup did not open the first question.")
        XCTAssertTrue(app.buttons["tab.planner"].isSelected,
                      "Get started in the popup did not go to the Date planner tab.")
    }

    /// "Not now" leaves the questions waiting where they belong: on the
    /// planner tab's Get started screen.
    func testThePlannerPopupCanWait() {
        let app = launch(arguments: ["-introducePlanner"])

        let later = app.buttons["plannerIntro.later"]
        XCTAssertTrue(later.waitForExistence(timeout: 10),
                      "No Date planner popup after onboarding.")
        later.tap()
        XCTAssertTrue(app.buttons["tab.daily"].isSelected,
                      "Not now should leave you where you were.")

        app.buttons["tab.planner"].tap()
        XCTAssertTrue(app.buttons["planner.getStarted"].waitForExistence(timeout: 5),
                      "After Not now, the planner tab should still ask first.")
    }

    /// Editing your interests changes the plan.
    ///
    /// The plan is computed from your profile every time it is drawn, so this
    /// should be true by construction -- which is exactly the kind of thing
    /// that stops being true quietly. Hana wrote "Street trees" and you did
    /// not; once you have, the planner says you both wrote it.
    func testEditingYourInterestsChangesThePlan() {
        let app = launch()
        app.buttons["tab.planner"].tap()
        answerDatePreferences(app)

        // By identifier: "Hana" is also the label of her row in Messages, and
        // the first run of this test failed on exactly that ambiguity.
        app.buttons["planner.with.hana"].tap()
        let bothWrote = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You both wrote'"))
        XCTAssertEqual(bothWrote.count, 0, "Nothing you wrote matches Hana's words yet.")

        app.buttons["tab.you"].tap()
        let edit = app.buttons["Edit your interests"]
        var tries = 0
        while !edit.isHittable && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(edit.isHittable, "No way to edit your interests on the You tab.")
        edit.tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The interests editor has no fields.")
        // Tapped at its far end, so the deletes take the whole of what is there.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 45))
        field.typeText("Street trees")
        app.buttons["interests.save"].tap()

        app.buttons["tab.planner"].tap()
        XCTAssertTrue(bothWrote.firstMatch.waitForExistence(timeout: 5),
                      "The plan did not change after your interests did.")
        // And the planner says it planned again, so a rerun that lands on the
        // same places is not mistaken for nothing happening.
        XCTAssertTrue(app.staticTexts["planner.replanned"].waitForExistence(timeout: 5),
                      "The planner did not say it replanned after your interests changed.")
    }

    // MARK: App Review

    /// The Premium screen, photographed for App Store Connect.
    ///
    /// Every subscription needs a review screenshot before Apple will serve it --
    /// even to TestFlight -- and the real build cannot take one: until a
    /// subscription is ready, the Premium tab truthfully says there is nothing to
    /// buy. The design build draws the same view with `MockData`'s prices, so the
    /// picture is the shipping screen, not a mock-up of it.
    ///
    /// **The prices are checked before the picture is kept.** Each plan row reads
    /// out as one label, so these are exact matches on what is drawn. A
    /// screenshot showing the wrong prices would fail this test rather than be
    /// uploaded to Apple.
    func testPremiumScreenForAppReview() {
        let app = launch()
        app.buttons["tab.premium"].tap()

        for plan in [
            "One month, $14.99, $14.99 a month",
            "Three months, $38.97, $12.99 a month",
            "Twelve months, $119.88, $9.99 a month",
        ] {
            XCTAssertTrue(
                app.buttons[plan].waitForExistence(timeout: 10),
                "The Premium screen does not show \"\(plan)\"."
            )
        }
        // Let the rail and the button finish settling before the picture.
        XCTAssertTrue(app.buttons["Subscribe for $38.97"].waitForExistence(timeout: 5),
                      "The subscribe button is not offering the recommended plan.")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "premium-for-app-review"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
