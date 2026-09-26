import XCTest
@testable import StudioSwitchCore

final class FileManagerUADSessionListerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func test_listSessions_returnsOnlyUadmixFilesSortedByName() throws {
        try "".write(to: tempDirectory.appendingPathComponent("home guit vox.uadmix"), atomically: true, encoding: .utf8)
        try "".write(to: tempDirectory.appendingPathComponent("Backup Notes.txt"), atomically: true, encoding: .utf8)
        try "".write(to: tempDirectory.appendingPathComponent("Ambient Mix.uadmix"), atomically: true, encoding: .utf8)
        let lister = FileManagerUADSessionLister(sessionsDirectory: tempDirectory.path)

        let sessions = lister.listSessions()

        XCTAssertEqual(sessions.map(\.name), ["Ambient Mix", "home guit vox"])
        XCTAssertEqual(sessions.map(\.path), [
            tempDirectory.appendingPathComponent("Ambient Mix.uadmix").path,
            tempDirectory.appendingPathComponent("home guit vox.uadmix").path
        ])
    }

    func test_listSessions_returnsEmptyWhenDirectoryMissing() {
        let lister = FileManagerUADSessionLister(sessionsDirectory: tempDirectory.appendingPathComponent("missing").path)

        XCTAssertEqual(lister.listSessions(), [])
    }
}
