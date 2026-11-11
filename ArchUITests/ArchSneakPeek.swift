import XCTest

/// A walk through the Daily 5, paced for a screen recording.
///
/// **Not a test of anything, and not part of the normal run.** The Build workflow
/// skips this class; `.github/workflows/sneak-peek.yml` runs it alone while the
/// simulator records, and uploads the video. The pauses are for a viewer, not for
/// the app, which is why the smoke tests do not carry them.
///
/// It is the design build, so everybody in it is a `MockData` person -- with a
/// face if `Arch/Resources/MockPhotos` has one for them, a colour if not.
///
/// It only fails when it could not record the one thing it is for: the app
/// opening on the roster. Anything after that which is not where it expected is
/// skipped rather than failed, so a renamed button costs a shot, not the video.
final class ArchSneakPeek: XCTestCase {

    private let tabs = ["tab.premium", "tab.daily", "tab.messages", "tab.planner", "tab.you"]

    /// Who is written to. The first person in the mock roster, and the fallback
    /// is whoever is first on screen.
    private let person = "Priya"
    private let message = "Okay, I need the story behind this photo."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTheDailyFive() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab.daily"].waitForExistence(timeout: 30),
                      "Arch never got past its launch view, so there is nothing to record.")

        // The launch view has gone; let the roster sit on screen.
        hold(3)

        // The five, top to bottom and back.
        app.swipeUp(velocity: .slow)
        hold(1.5)
        app.swipeUp(velocity: .slow)
        hold(1.5)
        app.swipeDown(velocity: .slow)
        app.swipeDown(velocity: .slow)
        hold(1.5)

        // Somebody's profile.
        guard let card = rosterCard(in: app) else { return }
        card.tap()
        hold(2.5)

        // Their photos and answers.
        app.swipeUp(velocity: .slow)
        hold(1.5)
        app.swipeUp(velocity: .slow)
        hold(1.5)
        app.swipeDown(velocity: .fast)
        hold(1)

        // No like button: the photo is what you write about.
        let photo = app.buttons["Photo 1"].firstMatch
        if photo.waitForExistence(timeout: 3), photo.isHittable {
            photo.tap()
            hold(1.5)
        }

        let write = app.buttons.matching(
            NSPredicate(format: "label == 'Write about this' OR label == 'Send a message'")
        ).firstMatch
        guard write.waitForExistence(timeout: 3) else { return }
        write.tap()
        hold(1.5)

        // The composer focuses itself. Typed slowly enough to read.
        if app.keyboards.count == 0 { app.textViews.firstMatch.tap() }
        guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else { return }
        for word in message.split(separator: " ") {
            app.typeText(String(word) + " ")
            usleep(180_000)
        }
        hold(2)

        let send = app.buttons["Send"].firstMatch
        guard send.waitForExistence(timeout: 3), send.isEnabled else { return }
        send.tap()
        hold(2.5)

        // Where the conversation lives now.
        let messages = app.buttons["tab.messages"]
        if messages.waitForExistence(timeout: 5), messages.isHittable {
            messages.tap()
            hold(2.5)
        }
        let thread = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'messages.thread.'")
        ).firstMatch
        if thread.waitForExistence(timeout: 3), thread.isHittable {
            thread.tap()
            hold(3)
        }
    }

    /// The card for `person`, or else the first thing on the roster that opens a
    /// profile. The mock names are not a contract, so neither is this.
    private func rosterCard(in app: XCUIApplication) -> XCUIElement? {
        let named = app.buttons[person].firstMatch
        if named.waitForExistence(timeout: 3), named.isHittable { return named }
        return app.buttons.allElementsBoundByIndex.first { element in
            element.exists && element.isHittable && !tabs.contains(element.identifier)
        }
    }

    /// A pause a viewer can see.
    private func hold(_ seconds: Double) {
        usleep(useconds_t(seconds * 1_000_000))
    }
}
