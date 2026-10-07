import XCTest
@testable import StudioSwitchCore

final class UADConsoleLogWatcherTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, _ text: String, modified: Date = Date()) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private func watcher() -> FileUADConsoleLogWatcher {
        FileUADConsoleLogWatcher(directory: directory, sleep: { _ in })
    }

    func test_waitForLine_findsALineWrittenAfterTheMark() throws {
        let log = try write("UAD Console_10_07_26_12_52_59.txt", "12.53.08 ReloadEngine@info Main Hide Progress Dialog\n")
        let watcher = watcher()
        let mark = watcher.mark()
        try append("12.53.19 ReloadEngine@info Main Hide Progress Dialog\n", to: log)

        XCTAssertTrue(watcher.waitForLine(containing: "Hide Progress Dialog", after: mark, timeout: 1))
    }

    func test_waitForLine_ignoresLinesFromBeforeTheMark() throws {
        _ = try write("UAD Console_10_07_26_12_52_59.txt", "12.53.08 ReloadEngine@info Main Hide Progress Dialog\n")
        let watcher = watcher()
        let mark = watcher.mark()

        XCTAssertFalse(watcher.waitForLine(containing: "Hide Progress Dialog", after: mark, timeout: 1))
    }

    func test_mark_followsTheMostRecentConsoleLog() throws {
        _ = try write("UAD Console_10_07_26_12_32_21.txt", "old\n", modified: Date(timeIntervalSinceNow: -600))
        let current = try write("UAD Console_10_07_26_12_52_59.txt", "new\n")
        _ = try write("UA Mixer Engine_2.log", "Hide Progress Dialog\n")
        let watcher = watcher()
        let mark = watcher.mark()
        try append("Hide Progress Dialog\n", to: current)

        XCTAssertTrue(watcher.waitForLine(containing: "Hide Progress Dialog", after: mark, timeout: 1))
    }

    func test_waitForLine_readsANewLogStartedAfterTheMark() throws {
        _ = try write("UAD Console_10_07_26_12_32_21.txt", "old\n", modified: Date(timeIntervalSinceNow: -600))
        let watcher = watcher()
        let mark = watcher.mark()
        _ = try write("UAD Console_10_07_26_13_00_00.txt", "Hide Progress Dialog\n")

        XCTAssertTrue(watcher.waitForLine(containing: "Hide Progress Dialog", after: mark, timeout: 1))
    }
}
