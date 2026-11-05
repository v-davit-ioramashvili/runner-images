import XCTest

// One tap, one typeText, then measure how long until the full value lands.
// Mirrors the #15252 reporter: unchanged 10 s exact-value window, no retries.
// The test does not fail on a slow insertion so every run reports its timings.
final class KbdProbeUITests: XCTestCase {
    private func ts(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    func testTypeOnce() {
        let app = XCUIApplication()
        let launchStart = Date()
        app.launch()
        let field = app.textFields["field"]
        XCTAssertTrue(field.waitForExistence(timeout: 60))
        let tapAt = Date()
        field.tap()
        let kbShown = app.keyboards.firstMatch.waitForExistence(timeout: 60)
        let kbAt = Date()
        field.typeText("Table Test")
        let typedAt = Date()

        let mirror = app.staticTexts["mirror"]
        let full = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Table Test"), object: mirror)
        let result = XCTWaiter().wait(for: [full], timeout: 90)
        let doneAt = Date()

        let insertSec = doneAt.timeIntervalSince(typedAt)
        print("KBDPROBE launchStart=\(ts(launchStart)) tap=\(ts(tapAt)) kbShown=\(kbShown) kbAt=\(ts(kbAt)) typedAt=\(ts(typedAt)) doneAt=\(ts(doneAt)) result=\(result.rawValue) tapToKb=\(String(format: "%.3f", kbAt.timeIntervalSince(tapAt))) typeTextSec=\(String(format: "%.3f", typedAt.timeIntervalSince(kbAt))) insertAfterTypeSec=\(String(format: "%.3f", insertSec)) within10=\(result == .completed && insertSec <= 10) value=\(mirror.label)")
    }
}
