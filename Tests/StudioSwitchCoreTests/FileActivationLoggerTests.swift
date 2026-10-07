import XCTest
@testable import StudioSwitchCore

final class FileActivationLoggerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func test_log_appendsTimestampedLinesCreatingTheFolder() throws {
        let file = directory.appendingPathComponent("activation.log")
        let logger = FileActivationLogger(fileURL: file, now: { Date(timeIntervalSince1970: 0) }, timeZone: TimeZone(identifier: "UTC")!)

        logger.log("premier")
        logger.log("second")
        logger.flush()

        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(content, "1970-01-01 00:00:00.000  premier\n1970-01-01 00:00:00.000  second\n")
    }

    func test_log_startsAFreshFileWhenTheCurrentOneIsTooBig() throws {
        let file = directory.appendingPathComponent("activation.log")
        let logger = FileActivationLogger(fileURL: file, maxBytes: 40, now: { Date(timeIntervalSince1970: 0) }, timeZone: TimeZone(identifier: "UTC")!)

        logger.log("une ligne assez longue pour dépasser")
        logger.log("suivante")
        logger.flush()

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "1970-01-01 00:00:00.000  suivante\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path + ".1"))
    }
}
