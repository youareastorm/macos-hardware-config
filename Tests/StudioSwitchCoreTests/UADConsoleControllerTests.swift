import XCTest
@testable import StudioSwitchCore

private final class MockAppLauncher: AppLaunching {
    private(set) var openedFileURL: URL?
    private(set) var openedAppURL: URL?
    func launchApplication(at appURL: URL) throws {}
    func open(fileURL: URL, withApplicationAt appURL: URL) throws {
        openedFileURL = fileURL
        openedAppURL = appURL
    }
}

final class UADConsoleControllerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func test_openSession_opensExistingFileWithConsoleApp() throws {
        let sessionURL = tempDirectory.appendingPathComponent("session.uadmix")
        try Data().write(to: sessionURL)
        let consoleAppURL = tempDirectory.appendingPathComponent("UAD Console.app")
        try FileManager.default.createDirectory(at: consoleAppURL, withIntermediateDirectories: true)
        let launcher = MockAppLauncher()
        let controller = UADConsoleController(appLauncher: launcher, consoleAppPath: consoleAppURL.path)

        try controller.openSession(atPath: sessionURL.path)

        XCTAssertEqual(launcher.openedFileURL, sessionURL)
        XCTAssertEqual(launcher.openedAppURL?.path, consoleAppURL.path)
    }

    func test_openSession_throwsWhenSessionFileMissing() {
        let controller = UADConsoleController(appLauncher: MockAppLauncher(), consoleAppPath: tempDirectory.path)

        XCTAssertThrowsError(try controller.openSession(atPath: tempDirectory.appendingPathComponent("missing.uadmix").path)) { error in
            guard case UADConsoleControllerError.sessionFileNotFound = error else {
                return XCTFail("expected sessionFileNotFound, got \(error)")
            }
        }
    }

    func test_openSession_throwsWhenConsoleAppMissing() throws {
        let sessionURL = tempDirectory.appendingPathComponent("session.uadmix")
        try Data().write(to: sessionURL)
        let controller = UADConsoleController(appLauncher: MockAppLauncher(), consoleAppPath: tempDirectory.appendingPathComponent("NoConsole.app").path)

        XCTAssertThrowsError(try controller.openSession(atPath: sessionURL.path)) { error in
            guard case UADConsoleControllerError.consoleAppNotFound = error else {
                return XCTFail("expected consoleAppNotFound, got \(error)")
            }
        }
    }

    func test_openSession_expandsTildeInPath() throws {
        let controller = UADConsoleController(appLauncher: MockAppLauncher(), consoleAppPath: tempDirectory.path)

        XCTAssertThrowsError(try controller.openSession(atPath: "~/StudioSwitchTests-does-not-exist.uadmix")) { error in
            guard case UADConsoleControllerError.sessionFileNotFound(let path) = error else {
                return XCTFail("expected sessionFileNotFound, got \(error)")
            }
            XCTAssertFalse(path.hasPrefix("~"))
        }
    }
}
