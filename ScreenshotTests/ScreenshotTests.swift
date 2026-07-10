import XCTest

/// Captures App Store screenshots by launching the app and navigating to key screens.
/// Each screenshot is saved to the DERIVED_FILE_DIR so CI can collect them.
///
/// Run with: xcodebuild test -project Trace.xcodeproj -scheme Trace \
///   -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
///   -testPlan Screenshots ONLY
final class ScreenshotTests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = true
        app.launchArguments = ["-ScreenshotMode"]
        app.launch()
        // Dismiss the "How to Play" sheet that appears on first launch.
        let done = app.buttons["Done"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        sleep(1)
    }

    func test01LevelSelect() throws {
        // The level-select grid — 21 themed cards with stars and progress.
        capture("01-LevelSelect")
    }

    func test02LevelOneGameplay() throws {
        // Tap level 1 card (the first card in the grid, showing "Tutorial Grove").
        let card = app.staticTexts["Tutorial Grove"]
        XCTAssertTrue(card.waitForExistence(timeout: 3), "level 1 card not found")
        card.tap()
        sleep(2)
        // The maze is visible with "start" label and the drag prompt.
        capture("02-Gameplay-Level1")
    }

    func test03HowToPlay() throws {
        // Open the "?" help button (present on both level-select and game screens).
        let help = app.buttons.firstMatch
        // Navigate back to level select if we're in a game.
        let back = app.buttons["chevron.left"]
        if back.exists { back.tap(); sleep(1) }
        // Tap the question-mark button.
        let qButton = app.buttons["questionmark.circle"]
        if qButton.waitForExistence(timeout: 3) { qButton.tap() }
        sleep(1)
        capture("03-HowToPlay")
    }

    func test04Leaderboard() throws {
        // Dismiss any sheet and go back to level select.
        let done = app.buttons["Done"]
        if done.exists { done.tap(); sleep(1) }
        let back = app.buttons["chevron.left"]
        if back.exists { back.tap(); sleep(1) }
        // Tap the trophy button.
        let trophy = app.buttons["trophy"]
        if trophy.waitForExistence(timeout: 3) { trophy.tap() }
        sleep(2)
        capture("04-Leaderboard")
    }

    // MARK: - helpers

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("[SCREENSHOT] saved \(url.path)")
    }
}
