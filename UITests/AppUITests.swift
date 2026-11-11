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

        let fields = web.textFields
        XCTAssertGreaterThanOrEqual(fields.count, 2)
        type("2600", into: fields.element(boundBy: 0), app: app)
        type("150", into: fields.element(boundBy: 1), app: app)
        save("2-setup-filled")
        web.buttons["Start"].tap()
        XCTAssertTrue(web.staticTexts["Food today"].waitForExistence(timeout: 20), "Setup leads to the Today screen")
        XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS '2,600'")).firstMatch.waitForExistence(timeout: 10), "The entered calorie goal is used")
        sleep(1)
        save("3-today")

        for (tab, expected) in [("Food", "What did you eat?"), ("Gym", "Four-week cycle"), ("Coach", "What do you want to know?"), ("More", "Settings")] {
            web.buttons[tab].tap()
            XCTAssertTrue(web.staticTexts[expected].waitForExistence(timeout: 15), "\(tab) tab opens")
            sleep(1)
            save("4-" + tab.lowercased())
        }

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
