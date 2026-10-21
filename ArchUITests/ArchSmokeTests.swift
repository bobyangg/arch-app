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
    /// an activity, something to eat, and another activity -- three, and no more.
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

        // An activity, given three hours. A stop opens to its length and its
        // actions; closed, it is two lines.
        app.buttons["planner.choose.activity"].tap()
        XCTAssertTrue(stops.firstMatch.waitForExistence(timeout: 5), "Choosing an activity planned nothing.")
        XCTAssertEqual(stops.count, 1)
        XCTAssertFalse(app.buttons["planner.hours.0.3"].exists, "A stop should open closed.")
        tapClearOfTheBar(app.buttons["planner.open.0"], in: app)
        XCTAssertTrue(app.buttons["planner.hours.0.3"].waitForExistence(timeout: 5), "Opening a stop showed no length.")
        tapClearOfTheBar(app.buttons["planner.hours.0.3"], in: app)
        XCTAssertTrue(app.buttons["planner.hours.0.3"].isSelected, "The three-hour block did not stick.")

        // Something to eat, then whatever the planner suggests. A new item
        // lands at the end of the list, which can be under Share.
        tapClearOfTheBar(app.buttons["planner.addItem"], in: app)
        tapClearOfTheBar(app.buttons["planner.choose.food"], in: app)
        XCTAssertEqual(stops.count, 2, "Adding food did not add a stop.")
        tapClearOfTheBar(app.buttons["planner.addItem"], in: app)
        tapClearOfTheBar(app.buttons["planner.choose.activity"], in: app)
        XCTAssertEqual(stops.count, 3, "A second activity did not add a stop.")
        XCTAssertFalse(app.buttons["planner.addItem"].exists, "A plan holds three items at most.")

        // The date opens a calendar, and closing it still leaves the whole
        // plan. Which day is tapped is left alone: a calendar shows the month
        // of the date it opens on, and tomorrow may be its last day.
        app.buttons["planner.date"].tap()
        XCTAssertTrue(app.datePickers["planner.calendar"].waitForExistence(timeout: 5),
                      "The date did not open a calendar.")
        app.buttons["planner.dateDone"].tap()
        XCTAssertTrue(app.buttons["planner.date"].waitForExistence(timeout: 5),
                      "Done did not close the calendar.")
        XCTAssertEqual(stops.count, 3, "Opening the calendar lost the plan.")

        // Swapping a stop has to leave a plan behind, not an empty screen. The
        // anchor always has a Swap here: more than one place can anchor it.
        let swaps = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Swap'"))
        XCTAssertGreaterThan(swaps.count, 0, "No stop on this plan can be swapped.")
        swaps.firstMatch.tap()
        XCTAssertEqual(stops.count, 3, "Swapping a stop lost the plan.")

        // A Swap tapped by accident is one tap back.
        let undo = app.buttons["planner.undoSwap"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "A swap offered no Undo.")
        tapClearOfTheBar(undo, in: app)
        XCTAssertFalse(undo.waitForExistence(timeout: 1), "Undo stayed after undoing.")
        XCTAssertEqual(stops.count, 3, "Undoing a swap lost the plan.")

        // Every stop can be looked up in Apple Maps. Not tapped: that would
        // leave the app.
        XCTAssertTrue(app.buttons["planner.maps.0"].exists, "A stop has no way to open it in Maps.")

        // "Not for us": the place goes, another takes the item, and the
        // planner offers to undo it.
        tapClearOfTheBar(app.buttons["planner.hide.0"], in: app)
        XCTAssertTrue(app.buttons["planner.undoHide"].waitForExistence(timeout: 5),
                      "Hiding a place did not offer to undo it.")
        XCTAssertEqual(stops.count, 3, "Hiding a place lost the stop instead of replacing it.")
        tapClearOfTheBar(app.buttons["planner.undoHide"], in: app)

        // Removing one leaves room to add again.
        tapClearOfTheBar(app.buttons["planner.open.2"], in: app)
        XCTAssertTrue(app.buttons["planner.remove.2"].waitForExistence(timeout: 5), "Opening the third stop showed no Remove.")
        tapClearOfTheBar(app.buttons["planner.remove.2"], in: app)
        XCTAssertEqual(stops.count, 2, "Remove did not take the stop off.")
        XCTAssertTrue(app.buttons["planner.addItem"].exists, "With two items there is room for a third.")
        XCTAssertEqual(app.state, .runningForeground, "Arch stopped running on the Date planner.")
    }

    /// Taps a control in the planner after scrolling it clear of the bar pinned
    /// at the bottom. Share stays put while the plan scrolls under it, so a
    /// control that is on screen can still be behind it -- and a tap there is
    /// a tap on Share.
    private func tapClearOfTheBar(
        _ element: XCUIElement, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5),
                      "\(element) never appeared.", file: file, line: line)
        let bar = app.otherElements["planner.bottomBar"]
        var tries = 0
        while tries < 4, bar.exists, element.frame.maxY > bar.frame.minY - 4 {
            app.swipeUp()
            tries += 1
        }
        element.tap()
    }

    /// "Custom spot" adds a place you name: searched for, tapped, and on the
    /// plan as your pick.
    func testACustomSpotGoesOnThePlan() {
        let app = launch()
        app.buttons["tab.planner"].tap()
        answerDatePreferences(app)

        let custom = app.buttons["planner.choose.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5), "A blank item has no Custom spot.")
        custom.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Custom spot opened no search.")
        search.tap()
        // The design build searches its own places; "park" is in several.
        search.typeText("park")
        let result = app.buttons["planner.custom.result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Searching found nothing to add.")
        result.tap()

        let stops = app.descendants(matching: .any).matching(identifier: "planner.stop")
        XCTAssertTrue(stops.firstMatch.waitForExistence(timeout: 5), "The custom spot is not on the plan.")
        let yours = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Your pick'"))
        XCTAssertGreaterThan(yours.count, 0, "The custom spot does not say it is your pick.")
    }

    /// A plan in progress stays with its person: switch to somebody else and
    /// back, and it is as you left it.
    func testAPlanStaysWithItsPersonWhenYouSwitch() {
        let app = launch()
        app.buttons["tab.planner"].tap()
        answerDatePreferences(app)

        app.buttons["planner.choose.activity"].tap()
        let stops = app.descendants(matching: .any).matching(identifier: "planner.stop")
        XCTAssertTrue(stops.firstMatch.waitForExistence(timeout: 5), "Choosing an activity planned nothing.")
        tapClearOfTheBar(app.buttons["planner.addItem"], in: app)
        tapClearOfTheBar(app.buttons["planner.choose.food"], in: app)
        XCTAssertEqual(stops.count, 2, "Adding food did not add a stop.")

        // Somebody else starts blank.
        let me = app.buttons["planner.with.self"]
        var tries = 0
        while !me.isHittable && tries < 4 { app.scrollViews["planner.picker"].swipeLeft(); tries += 1 }
        me.tap()
        XCTAssertTrue(app.buttons["planner.choose.activity"].waitForExistence(timeout: 5),
                      "Somebody new did not start on a blank plan.")
        XCTAssertEqual(stops.count, 0, "The last person's plan followed you to somebody else.")

        // And back: the two stops are still there.
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'planner.with.'")).firstMatch
        tries = 0
        while !first.isHittable && tries < 4 { app.scrollViews["planner.picker"].swipeRight(); tries += 1 }
        first.tap()
        XCTAssertTrue(stops.firstMatch.waitForExistence(timeout: 5), "Going back lost the plan.")
        XCTAssertEqual(stops.count, 2, "Going back did not bring the plan back as it was.")
    }

    /// Sharing the very same plan to the same person again asks first, and
    /// "Send it again" sends it -- the earlier copy is removed.
    ///
    /// On Hana's plan opened with Change it, so the places are held: a plan
    /// the planner made itself moves on to new places once it has been sent,
    /// and is not the same plan the second time.
    func testSendingTheSamePlanTwiceAsksFirst() {
        let app = launch()
        app.buttons["tab.planner"].tap()
        answerDatePreferences(app)

        app.buttons["tab.messages"].tap()
        let hana = app.buttons["messages.thread.hana"]
        XCTAssertTrue(hana.waitForExistence(timeout: 5), "No conversation with Hana in Messages.")
        hana.tap()
        let change = app.buttons["thread.plan.change"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), "Hana's plan has no Change it.")
        var tries = 0
        while !change.isHittable && tries < 4 { app.swipeUp(); tries += 1 }
        change.tap()

        let share = app.buttons["Share this plan"]
        let toHana = app.buttons["Share with Hana"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "Change it did not open a plan to share.")
        share.tap()
        XCTAssertTrue(toHana.waitForExistence(timeout: 5), "Share this plan did not offer Hana.")
        toHana.tap()

        share.tap()
        XCTAssertTrue(toHana.waitForExistence(timeout: 5), "Share this plan did not offer Hana the second time.")
        toHana.tap()

        let again = app.buttons["Send it again"]
        XCTAssertTrue(again.waitForExistence(timeout: 5), "Sharing the same plan twice did not ask first.")
        again.tap()
        XCTAssertFalse(again.waitForExistence(timeout: 1), "The question stayed after Send it again.")
        XCTAssertEqual(app.state, .runningForeground, "Arch stopped running after resending a plan.")
    }

    /// A plan saved for later is in Saved, and opens back in the planner with
    /// its places kept.
    func testAPlanCanBeSavedAndOpened() {
        let app = launch()
        app.buttons["tab.planner"].tap()
        answerDatePreferences(app)

        app.buttons["planner.choose.activity"].tap()
        let stops = app.descendants(matching: .any).matching(identifier: "planner.stop")
        XCTAssertTrue(stops.firstMatch.waitForExistence(timeout: 5), "Choosing an activity planned nothing.")

        let save = app.buttons["planner.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "The plan has no Save for later.")
        // A phone's saved plans outlive a launch; start from this plan unsaved.
        if save.isSelected { save.tap() }
        save.tap()
        XCTAssertTrue(save.isSelected, "Save for later did not save.")

        app.buttons["planner.saved"].tap()
        let open = app.buttons["planner.savedOpen"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "The saved plan is not in Saved.")
        open.tap()
        XCTAssertTrue(stops.firstMatch.waitForExistence(timeout: 5), "Opening a saved plan planned nothing.")
        let kept = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'From your saved plan'"))
        XCTAssertGreaterThan(kept.count, 0, "The saved plan did not open on its places.")

        // Tidy up, so the next launch starts with nothing saved from here.
        if save.isSelected { save.tap() }
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

    /// Straight after onboarding, the tour: a welcome, then a tab at a time --
    /// the app moving to each tab as the tour reaches it -- and on the Date
    /// planner's step, the five questions the planner's popup used to offer.
    ///
    /// The design build has no onboarding to finish, so `-introducePlanner`
    /// stands in for having just finished it -- the same flag finishing sets.
    func testTheTourFollowsOnboarding() {
        let app = launch(arguments: ["-introducePlanner"])

        let next = app.buttons["tour.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "No tour after onboarding.")
        next.tap()  // Show me
        XCTAssertTrue(app.buttons["tour.back"].waitForExistence(timeout: 5), "The tour did not move on.")
        XCTAssertTrue(app.buttons["tab.daily"].isSelected, "The tour's first step is not the Daily 5.")
        next.tap()
        XCTAssertTrue(app.buttons["tab.messages"].isSelected, "The tour did not move the app to Messages.")
        app.buttons["tour.back"].tap()
        XCTAssertTrue(app.buttons["tab.daily"].isSelected, "Back did not go back to the Daily 5.")
        next.tap()
        next.tap()
        XCTAssertTrue(app.buttons["tab.planner"].isSelected, "The tour did not move the app to the Date planner.")

        let questions = app.buttons["tour.questions"]
        XCTAssertTrue(questions.waitForExistence(timeout: 5),
                      "The planner's step does not offer the questions.")
        questions.tap()
        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 5),
                      "The questions did not open from the tour.")
        XCTAssertFalse(app.buttons["tour.next"].exists, "The tour stayed up over the questions.")
    }

    /// Skip leaves at once, back on the roster -- and the questions wait
    /// where they belong, on the planner tab's Get started screen.
    func testTheTourCanBeSkipped() {
        let app = launch(arguments: ["-introducePlanner"])

        let skip = app.buttons["tour.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "No tour after onboarding.")
        app.buttons["tour.next"].tap()
        app.buttons["tour.next"].tap()
        skip.tap()
        XCTAssertFalse(app.buttons["tour.next"].waitForExistence(timeout: 2), "Skip did not end the tour.")
        XCTAssertTrue(app.buttons["tab.daily"].isSelected, "Skip should leave you on the roster.")

        app.buttons["tab.planner"].tap()
        XCTAssertTrue(app.buttons["planner.getStarted"].waitForExistence(timeout: 5),
                      "After the tour, the planner tab should still ask first.")
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
        // In the line under the settings: "... · you both wrote “Street trees” · ..."
        let bothWrote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'you both wrote'"))
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

    /// "Self plan", last in the row of faces, plans a date for you alone: the
    /// same items, from your own interests and answers, with nothing to share.
    func testASelfPlanIsLastAndPlansForYou() {
        let app = launch()
        app.buttons["tab.planner"].tap()
        answerDatePreferences(app)

        let me = app.buttons["planner.with.self"]
        XCTAssertTrue(me.waitForExistence(timeout: 5), "There is no Self plan in the row of faces.")
        // Last in the row: further right than every match.
        let faces = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'planner.with.'"))
        let rightmost = faces.allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(rightmost?.identifier, "planner.with.self", "Self plan is not the last in the row.")

        var tries = 0
        while !me.isHittable && tries < 4 { app.scrollViews["planner.picker"].swipeLeft(); tries += 1 }
        me.tap()
        XCTAssertTrue(me.isSelected, "Tapping Self plan did not choose it.")

        app.buttons["planner.choose.activity"].tap()
        let stops = app.descendants(matching: .any).matching(identifier: "planner.stop")
        XCTAssertTrue(stops.firstMatch.waitForExistence(timeout: 5), "A self plan planned nothing.")
        XCTAssertTrue(app.buttons["planner.save"].exists, "A self plan cannot be saved for later.")

        // Confirmed, it is settled like an agreed date: calendar, export,
        // change and cancel. Neither sheet is opened -- both are the system's.
        let confirm = app.buttons["planner.self.confirm"]
        var scrolls = 0
        while !confirm.isHittable && scrolls < 6 { app.swipeUp(); scrolls += 1 }
        confirm.tap()
        XCTAssertTrue(app.buttons["planner.agreed.edit"].waitForExistence(timeout: 5),
                      "Confirming a self plan did not settle it.")
        XCTAssertTrue(app.buttons["planner.agreed.calendar"].exists, "A confirmed plan has no Add to calendar.")
        XCTAssertTrue(app.buttons["planner.agreed.export"].exists, "A confirmed plan has no Export.")

        // Cancelled, it is gone -- and kept on no phone, for the next launch.
        let cancel = app.buttons["planner.agreed.cancel"]
        scrolls = 0
        while !cancel.isHittable && scrolls < 6 { app.swipeUp(); scrolls += 1 }
        cancel.tap()
        let yes = app.buttons["Yes, cancel it"]
        XCTAssertTrue(yes.waitForExistence(timeout: 5), "Cancelling a self plan did not ask first.")
        yes.tap()
        XCTAssertTrue(app.staticTexts["planner.cancelled"].waitForExistence(timeout: 5),
                      "The planner did not say the self plan was cancelled.")
        XCTAssertFalse(app.buttons["planner.agreed.edit"].exists, "A cancelled self plan is still settled.")
        XCTAssertEqual(app.state, .runningForeground, "Arch stopped running on a self plan.")
    }

    /// "Change it" on a plan somebody sent opens your planner on *their*
    /// plan: the same places, not ones like them, each saying where it came
    /// from. Hana's plan in the design build carries its places.
    func testChangeItOpensTheirPlan() {
        let app = launch()
        app.buttons["tab.planner"].tap()
        answerDatePreferences(app)

        app.buttons["tab.messages"].tap()
        let hana = app.buttons["messages.thread.hana"]
        XCTAssertTrue(hana.waitForExistence(timeout: 5), "No conversation with Hana in Messages.")
        hana.tap()

        let change = app.buttons["thread.plan.change"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), "Hana's plan has no Change it.")
        var tries = 0
        while !change.isHittable && tries < 4 { app.swipeUp(); tries += 1 }
        change.tap()

        XCTAssertTrue(app.buttons["tab.planner"].waitForExistence(timeout: 5),
                      "Change it did not come back to the tab bar.")
        XCTAssertTrue(app.buttons["tab.planner"].isSelected, "Change it did not open the planner.")
        for place in ["Short Fuse Coffee", "Domino Park", "Wide Bowl Noodles"] {
            XCTAssertTrue(app.staticTexts[place].waitForExistence(timeout: 5),
                          "The planner did not open on Hana's \(place).")
        }
        let fromHana = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'From Hana'"))
        XCTAssertGreaterThan(fromHana.count, 0, "The kept places do not say they came from Hana's plan.")
    }

    /// "I'm in" opens the Date planner on the plan just agreed, as it was
    /// agreed; "Make changes" opens the planner on its places, and the way
    /// back returns to it.
    func testImInOpensTheAgreedPlan() {
        let app = launch()
        app.buttons["tab.planner"].tap()
        answerDatePreferences(app)

        app.buttons["tab.messages"].tap()
        let hana = app.buttons["messages.thread.hana"]
        XCTAssertTrue(hana.waitForExistence(timeout: 5), "No conversation with Hana in Messages.")
        hana.tap()

        let yes = app.buttons["thread.plan.yes"]
        XCTAssertTrue(yes.waitForExistence(timeout: 5), "Hana's plan has no I'm in.")
        var tries = 0
        while !yes.isHittable && tries < 4 { app.swipeUp(); tries += 1 }
        yes.tap()

        XCTAssertTrue(app.buttons["tab.planner"].waitForExistence(timeout: 5),
                      "I'm in did not come back to the tab bar.")
        XCTAssertTrue(app.buttons["tab.planner"].isSelected, "I'm in did not open the planner.")
        let edit = app.buttons["planner.agreed.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "The planner did not open on the agreed plan.")
        for place in ["Short Fuse Coffee", "Domino Park", "Wide Bowl Noodles"] {
            XCTAssertTrue(app.staticTexts[place].exists, "The agreed plan does not show \(place).")
        }
        XCTAssertTrue(app.buttons["planner.agreed.maps.0"].exists, "An agreed stop has no way to open it in Maps.")

        edit.tap()
        let back = app.buttons["planner.agreed.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Make changes did not open the planner.")
        let fromAgreed = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'From your agreed plan'"))
        XCTAssertGreaterThan(fromAgreed.count, 0, "The planner did not open on the agreed plan's places.")

        back.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Back did not return to the agreed plan.")

        // "Cancel the date" asks first, then calls it off on both phones: the
        // planner says so, and the card in the thread says who cancelled it.
        app.buttons["planner.agreed.cancel"].tap()
        let confirm = app.buttons["Yes, cancel it"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Cancel the date did not ask first.")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["planner.cancelled"].waitForExistence(timeout: 5),
                      "The planner did not say the date was cancelled.")
        XCTAssertFalse(edit.exists, "A cancelled plan is still shown as agreed.")

        app.buttons["tab.messages"].tap()
        XCTAssertTrue(app.staticTexts["thread.plan.cancelled"].waitForExistence(timeout: 5),
                      "The plan in the thread does not say it was cancelled.")
        XCTAssertEqual(app.state, .runningForeground, "Arch stopped running on the agreed plan.")
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
