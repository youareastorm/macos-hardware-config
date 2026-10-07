import XCTest
@testable import StudioSwitchCore

private final class FakeLogWatcher: UADConsoleLogWatching {
    var loadLogged = true
    private(set) var marks = 0
    private(set) var waitedFor: [String] = []
    func mark() -> UADConsoleLogMark {
        marks += 1
        return UADConsoleLogMark(file: nil, offset: 0)
    }
    func waitForLine(containing text: String, after mark: UADConsoleLogMark, timeout: TimeInterval) -> Bool {
        waitedFor.append(text)
        return loadLogged
    }
}

final class AppleScriptUADConsoleSessionLoaderTests: XCTestCase {
    private let path = "/Users/me/Documents/Universal Audio/Sessions/empty home.uadmix"

    func test_loadSession_succeedsWhenConsoleLogsTheLoad() throws {
        let watcher = FakeLogWatcher()
        let loader = AppleScriptUADConsoleSessionLoader(runScript: { _ in nil }, logWatcher: watcher)

        try loader.loadSession(atPath: path, discardingUnsavedChanges: false)

        XCTAssertEqual(watcher.marks, 1)
        XCTAssertEqual(watcher.waitedFor, ["Hide Progress Dialog"])
    }

    func test_loadSession_failsWhenConsoleNeverLogsTheLoad() {
        let watcher = FakeLogWatcher()
        watcher.loadLogged = false
        let loader = AppleScriptUADConsoleSessionLoader(runScript: { _ in nil }, logWatcher: watcher)

        XCTAssertThrowsError(try loader.loadSession(atPath: path, discardingUnsavedChanges: false)) { error in
            XCTAssertEqual(error as? UADConsoleSessionLoaderError, .sessionNotLoaded("empty home"))
        }
    }

    func test_loadSession_doesNotWaitForTheLoadWhenTheScriptFailed() {
        let watcher = FakeLogWatcher()
        let loader = AppleScriptUADConsoleSessionLoader(runScript: { _ in "le panneau d'ouverture ne s'est pas affiché" }, logWatcher: watcher)

        XCTAssertThrowsError(try loader.loadSession(atPath: path, discardingUnsavedChanges: false)) { error in
            XCTAssertEqual(error as? UADConsoleSessionLoaderError, .appleScriptFailed("le panneau d'ouverture ne s'est pas affiché"))
        }
        XCTAssertTrue(watcher.waitedFor.isEmpty)
    }

    func test_script_noLongerWaitsForTheWindowTitle() {
        var script = ""
        let loader = AppleScriptUADConsoleSessionLoader(runScript: { script = $0; return nil }, logWatcher: FakeLogWatcher())

        try? loader.loadSession(atPath: path, discardingUnsavedChanges: true)

        XCTAssertFalse(script.contains("name begins with \"UAD Console:\""))
        XCTAssertTrue(script.contains("key code 53"))
    }
}
