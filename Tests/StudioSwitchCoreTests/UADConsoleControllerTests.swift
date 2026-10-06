import XCTest
@testable import StudioSwitchCore

private final class MockAppLauncher: AppLaunching {
    private(set) var openedFileURL: URL?
    private(set) var openedAppURL: URL?
    private(set) var launchedAppURLs: [URL] = []
    func launchApplication(at appURL: URL) throws { launchedAppURLs.append(appURL) }
    func open(fileURL: URL, withApplicationAt appURL: URL) throws {
        openedFileURL = fileURL
        openedAppURL = appURL
    }
}

private final class MockRunningApplicationChecker: RunningApplicationChecking {
    var runningBundleIDs: Set<String> = []
    func isRunning(bundleID: String) -> Bool { runningBundleIDs.contains(bundleID) }
}

private final class MockSessionLoader: UADConsoleSessionLoading {
    var error: Error?
    private(set) var loadedPaths: [String] = []
    func loadSession(atPath path: String) throws {
        loadedPaths.append(path)
        if let error { throw error }
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
        let controller = UADConsoleController(appLauncher: launcher, consoleAppPath: consoleAppURL.path, runningChecker: MockRunningApplicationChecker())

        try controller.openSession(atPath: sessionURL.path)

        XCTAssertEqual(launcher.openedFileURL, sessionURL)
        XCTAssertEqual(launcher.openedAppURL?.path, consoleAppURL.path)
    }

    func test_openSession_throwsWhenSessionFileMissing() {
        let controller = UADConsoleController(appLauncher: MockAppLauncher(), consoleAppPath: tempDirectory.path, runningChecker: MockRunningApplicationChecker())

        XCTAssertThrowsError(try controller.openSession(atPath: tempDirectory.appendingPathComponent("missing.uadmix").path)) { error in
            guard case UADConsoleControllerError.sessionFileNotFound = error else {
                return XCTFail("expected sessionFileNotFound, got \(error)")
            }
        }
    }

    func test_openSession_throwsWhenConsoleAppMissing() throws {
        let sessionURL = tempDirectory.appendingPathComponent("session.uadmix")
        try Data().write(to: sessionURL)
        let controller = UADConsoleController(appLauncher: MockAppLauncher(), consoleAppPath: tempDirectory.appendingPathComponent("NoConsole.app").path, runningChecker: MockRunningApplicationChecker())

        XCTAssertThrowsError(try controller.openSession(atPath: sessionURL.path)) { error in
            guard case UADConsoleControllerError.consoleAppNotFound = error else {
                return XCTFail("expected consoleAppNotFound, got \(error)")
            }
        }
    }

    func test_openSession_expandsTildeInPath() throws {
        let controller = UADConsoleController(appLauncher: MockAppLauncher(), consoleAppPath: tempDirectory.path, runningChecker: MockRunningApplicationChecker())

        XCTAssertThrowsError(try controller.openSession(atPath: "~/StudioSwitchTests-does-not-exist.uadmix")) { error in
            guard case UADConsoleControllerError.sessionFileNotFound(let path) = error else {
                return XCTFail("expected sessionFileNotFound, got \(error)")
            }
            XCTAssertFalse(path.hasPrefix("~"))
        }
    }

    func test_openSession_loadsSessionThroughAppleScriptWhenConsoleAlreadyRunning() throws {
        let sessionURL = tempDirectory.appendingPathComponent("session.uadmix")
        try Data().write(to: sessionURL)
        let consoleAppURL = tempDirectory.appendingPathComponent("UAD Console.app")
        try FileManager.default.createDirectory(at: consoleAppURL, withIntermediateDirectories: true)
        let launcher = MockAppLauncher()
        let runningChecker = MockRunningApplicationChecker()
        runningChecker.runningBundleIDs = [UADConsoleController.defaultConsoleBundleID]
        let sessionLoader = MockSessionLoader()
        let controller = UADConsoleController(
            appLauncher: launcher,
            consoleAppPath: consoleAppURL.path,
            runningChecker: runningChecker,
            sessionLoader: sessionLoader
        )

        try controller.openSession(atPath: sessionURL.path)

        XCTAssertEqual(sessionLoader.loadedPaths, [sessionURL.path])
        XCTAssertNil(launcher.openedFileURL)
    }

    func test_openSession_propagatesSessionLoaderErrorWhenConsoleAlreadyRunning() throws {
        let sessionURL = tempDirectory.appendingPathComponent("session.uadmix")
        try Data().write(to: sessionURL)
        let consoleAppURL = tempDirectory.appendingPathComponent("UAD Console.app")
        try FileManager.default.createDirectory(at: consoleAppURL, withIntermediateDirectories: true)
        let runningChecker = MockRunningApplicationChecker()
        runningChecker.runningBundleIDs = [UADConsoleController.defaultConsoleBundleID]
        let sessionLoader = MockSessionLoader()
        sessionLoader.error = UADConsoleSessionLoaderError.appleScriptFailed("boom")
        let controller = UADConsoleController(
            appLauncher: MockAppLauncher(),
            consoleAppPath: consoleAppURL.path,
            runningChecker: runningChecker,
            sessionLoader: sessionLoader
        )

        XCTAssertThrowsError(try controller.openSession(atPath: sessionURL.path)) { error in
            XCTAssertEqual(error as? UADConsoleSessionLoaderError, .appleScriptFailed("boom"))
        }
    }

    func test_launchIfNotRunning_launchesTheConsoleAppWhenItIsNotRunning() throws {
        let consoleAppURL = tempDirectory.appendingPathComponent("UAD Console.app")
        try FileManager.default.createDirectory(at: consoleAppURL, withIntermediateDirectories: true)
        let launcher = MockAppLauncher()
        let controller = UADConsoleController(appLauncher: launcher, consoleAppPath: consoleAppURL.path, runningChecker: MockRunningApplicationChecker())

        try controller.launchIfNotRunning()

        XCTAssertEqual(launcher.launchedAppURLs.map(\.path), [consoleAppURL.path])
    }

    func test_launchIfNotRunning_doesNothingWhenTheConsoleIsAlreadyRunning() throws {
        let consoleAppURL = tempDirectory.appendingPathComponent("UAD Console.app")
        try FileManager.default.createDirectory(at: consoleAppURL, withIntermediateDirectories: true)
        let launcher = MockAppLauncher()
        let runningChecker = MockRunningApplicationChecker()
        runningChecker.runningBundleIDs = [UADConsoleController.defaultConsoleBundleID]
        let controller = UADConsoleController(appLauncher: launcher, consoleAppPath: consoleAppURL.path, runningChecker: runningChecker)

        try controller.launchIfNotRunning()

        XCTAssertTrue(launcher.launchedAppURLs.isEmpty)
    }

    func test_launchIfNotRunning_throwsWhenTheConsoleAppIsMissing() {
        let controller = UADConsoleController(
            appLauncher: MockAppLauncher(),
            consoleAppPath: tempDirectory.appendingPathComponent("NoConsole.app").path,
            runningChecker: MockRunningApplicationChecker()
        )

        XCTAssertThrowsError(try controller.launchIfNotRunning()) { error in
            guard case UADConsoleControllerError.consoleAppNotFound = error else {
                return XCTFail("expected consoleAppNotFound, got \(error)")
            }
        }
    }
}
