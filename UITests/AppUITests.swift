import XCTest

final class AppUITests: XCTestCase {
    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let tag = ProcessInfo.processInfo.environment["SNAPSHOT_TAG"].map { "-" + $0 } ?? ""
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(device)\(tag)-\(name).png"))
    }
    /// A thin sample of what is on screen, to tell whether the picture itself changed.
    private func screenSample() -> [UInt8] {
        guard let data = XCUIScreen.main.screenshot().image.cgImage?.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        return stride(from: 0, to: CFDataGetLength(data), by: 97).map { bytes[$0] }
    }
    /// Waits until the screen really shows something new: more than a moving drawing or the clock would change.
    private func waitForNewScreen(since before: [UInt8], _ what: String) {
        let deadline = Date().addingTimeInterval(40)
        var share = 0.0
        repeat {
            let now = screenSample()
            if now.count != before.count || now.isEmpty { return }
            share = Double(zip(before, now).filter { $0 != $1 }.count) / Double(now.count)
            if share > 0.02 { return }
            usleep(500_000)
        } while Date() < deadline
        XCTFail("The screen did not visibly change after opening \(what) (changed share \(share))")
    }
    private func type(_ text: String, into field: XCUIElement, app: XCUIApplication) {
        // The first tap on a web field can land before the keyboard is ready on a busy simulator.
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 5) { break }
        }
        field.typeText(text)
    }

    /// First run to daily use: a blank app, the person's own numbers, every tab, and the data coming back after
    /// the web view's storage is wiped and after a plain relaunch.
    func testFirstRunEveryTabAndDataSafety() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-resetData"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Set up your plan"].waitForExistence(timeout: 60), "A new install starts with setup")
        sleep(1)
        save("1-first-run")

        // Body for the drawings: both choices are offered, pick one.
        XCTAssertTrue(web.staticTexts["Man"].exists && web.staticTexts["Woman"].exists, "Setup offers a man's and a woman's body")
        web.staticTexts["Woman"].tap()

        // Web fields carry their label; fall back to their position in the form (age, weight, feet, inches come first).
        func field(_ label: String, position: Int) -> XCUIElement {
            let named = web.textFields[label]
            return named.exists ? named : web.textFields.element(boundBy: position)
        }
        XCTAssertGreaterThanOrEqual(web.textFields.count, 6)
        type("2600", into: field("Calories per day", position: 4), app: app)
        type("150", into: field("Protein per day (g)", position: 5), app: app)
        save("2-setup-filled")
        let start = web.buttons["Start"]
        if !start.isHittable { web.swipeUp() }
        start.tap()
        XCTAssertTrue(web.staticTexts["Food today"].waitForExistence(timeout: 20), "Setup leads to the Today screen")
        XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS '2,600'")).firstMatch.waitForExistence(timeout: 10), "The entered calorie goal is used")
        sleep(1)
        save("3-today")

        for (tab, expected) in [("Food", "What did you eat?"), ("Gym", "Four-week cycle"), ("Coach", "What do you want to know?")] {
            let before = screenSample()
            web.buttons[tab].tap()
            XCTAssertTrue(web.staticTexts[expected].waitForExistence(timeout: 15), "\(tab) tab opens")
            waitForNewScreen(since: before, tab)
            sleep(1)
            save("4-" + tab.lowercased())
        }
        // More is a list of buttons; open Pills from it and add nothing: a blank app has no supplements.
        web.buttons["More"].tap()
        let pills = web.buttons.matching(NSPredicate(format: "label CONTAINS 'Your supplements and daily checklist'")).firstMatch
        XCTAssertTrue(pills.waitForExistence(timeout: 15), "More tab opens")
        save("4-more")
        pills.tap()
        XCTAssertTrue(web.staticTexts["Your supplements"].waitForExistence(timeout: 15), "Pills screen opens")
        XCTAssertTrue(web.staticTexts["None yet"].exists, "No supplements are pre-filled")
        sleep(1)
        save("5-pills")

        app.terminate()
        let afterLoss = XCUIApplication()
        afterLoss.launchArguments = ["-forgetWebsiteData"]
        afterLoss.launch()
        let restored = afterLoss.webViews.firstMatch
        XCTAssertTrue(restored.staticTexts["Food today"].waitForExistence(timeout: 60), "Data comes back after the web view's storage is wiped")
        XCTAssertTrue(restored.staticTexts.matching(NSPredicate(format: "label CONTAINS '2,600'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(restored.staticTexts["Set up your plan"].exists)

        afterLoss.terminate()
        let again = XCUIApplication()
        again.launch()
        XCTAssertTrue(again.webViews.firstMatch.staticTexts["Food today"].waitForExistence(timeout: 60), "Data is still there on a normal relaunch")
    }
}
