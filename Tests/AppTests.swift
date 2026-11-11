import XCTest
import WebKit
@testable import GymPlanner

final class AppTests: XCTestCase {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("saved-" + UUID().uuidString + ".json")
    }

    func testSavedDataSurvivesARestart() {
        let file = temporaryFile()
        let first = SavedData(file: file)
        first.set("a", "1"); first.set("b", "two \"quoted\" </script>"); first.remove("a"); first.set("c", "3")
        first.flush()
        let second = SavedData(file: file)
        XCTAssertNil(second.value(for: "a"))
        XCTAssertEqual(second.value(for: "b"), "two \"quoted\" </script>")
        XCTAssertEqual(second.count, 2)
        second.replaceAll(["only": "this"]); second.flush()
        XCTAssertEqual(SavedData(file: file).json, "{\"only\":\"this\"}")
    }

    func testSavedDataFallsBackToThePreviousCopy() throws {
        let file = temporaryFile()
        let store = SavedData(file: file)
        store.set("k", "v1"); store.flush()          // first write
        store.set("k", "v2"); store.flush()          // keeps v1 as the previous copy, writes v2
        try Data("not json".utf8).write(to: file)    // the main file gets damaged
        XCTAssertEqual(SavedData(file: file).value(for: "k"), "v1", "A damaged file falls back to the copy kept from before")
    }

    func testStartScriptCarriesSavedValuesSafely() {
        let script = WebHost.startScript(saved: "{\"k\":\"v\"}")
        XCTAssertTrue(script.contains("var saved = {\"k\":\"v\"};"))
    }

    /// The real page in the real web view: it starts, its storage is mirrored natively, and copy works.
    @MainActor
    func testPageRunsAndItsStorageIsMirrored() async throws {
        let host = WebHost()
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first
        host.webView.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        window?.addSubview(host.webView)
        defer { host.webView.removeFromSuperview() }

        func js(_ source: String) async -> Any? { try? await host.webView.evaluateJavaScript(source) }
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, (await js("typeof state === 'object' && document.getElementById('js-check').style.display === 'none'")) as? Bool != true {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        let checkBox = await js("document.getElementById('js-check').style.display") as? String
        XCTAssertEqual(checkBox, "none", "The page's script ran to the end")
        let scheme = await js("location.protocol") as? String
        XCTAssertEqual(scheme, "gymplanner:")

        let key = "test-" + UUID().uuidString
        _ = await js("localStorage.setItem('\(key)', 'kept')")
        var mirrored: String?
        for _ in 0..<50 where mirrored == nil { try await Task.sleep(nanoseconds: 100_000_000); mirrored = SavedData.shared.value(for: key) }
        XCTAssertEqual(mirrored, "kept", "What the page saves is copied outside the web view")
        _ = await js("localStorage.removeItem('\(key)')")
        for _ in 0..<50 where SavedData.shared.value(for: key) != nil { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertNil(SavedData.shared.value(for: key), "Deletions are copied too")

        let clipboard = await js("typeof navigator.clipboard.writeText") as? String
        XCTAssertEqual(clipboard, "function")
        let fixedZoom = await js("document.querySelector('meta[name=viewport]').content.includes('user-scalable=no')") as? Bool
        XCTAssertEqual(fixedZoom, true)
    }
}
