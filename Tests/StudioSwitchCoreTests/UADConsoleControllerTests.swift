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
    private(set) var discardFlags: [Bool] = []
    func loadSession(atPath path: String, discardingUnsavedChanges: Bool) throws {
        loadedPaths.append(path)
        discardFlags.append(discardingUnsavedChanges)
        if let error { throw error }
    }
}

private final class MockSessionInspector: UADConsoleSessionInspecting {
    var title: String?
    func currentSessionName() -> String? { title }
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

    // MARK: - ensureSessionOpen

    private func makeEnsureFixture(running: Bool, windowTitle: String?) throws -> (controller: UADConsoleController, launcher: MockAppLauncher, loader: MockSessionLoader, sessionURL: URL) {
        let sessionURL = tempDirectory.appendingPathComponent("OCTO EMPTY.uadmix")
        try Data().write(to: sessionURL)
        let consoleAppURL = tempDirectory.appendingPathComponent("UAD Console.app")
        try FileManager.default.createDirectory(at: consoleAppURL, withIntermediateDirectories: true)
        let launcher = MockAppLauncher()
        let runningChecker = MockRunningApplicationChecker()
        if running { runningChecker.runningBundleIDs = [UADConsoleController.defaultConsoleBundleID] }
        let loader = MockSessionLoader()
        let inspector = MockSessionInspector()
        inspector.title = windowTitle
        let controller = UADConsoleController(
            appLauncher: launcher,
            consoleAppPath: consoleAppURL.path,
            runningChecker: runningChecker,
            sessionLoader: loader,
            sessionInspector: inspector,
            sleep: { _ in },
            launchTimeout: 1
        )
        return (controller, launcher, loader, sessionURL)
    }

    func test_ensureSessionOpen_coldStart_launchesConsoleThenLoadsTheSessionThroughItsMenu() throws {
        let f = try makeEnsureFixture(running: false, windowTitle: "UAD Console: empty home")

        try f.controller.ensureSessionOpen(atPath: f.sessionURL.path)

        XCTAssertEqual(f.launcher.launchedAppURLs.count, 1)
        XCTAssertNil(f.launcher.openedFileURL)
        XCTAssertEqual(f.loader.loadedPaths, [f.sessionURL.path])
    }

    func test_ensureSessionOpen_coldStart_skipsTheLoadWhenConsoleStartsOnTheRightSession() throws {
        let f = try makeEnsureFixture(running: false, windowTitle: "UAD Console: OCTO EMPTY")

        try f.controller.ensureSessionOpen(atPath: f.sessionURL.path)

        XCTAssertEqual(f.launcher.launchedAppURLs.count, 1)
        XCTAssertTrue(f.loader.loadedPaths.isEmpty)
    }

    func test_ensureSessionOpen_coldStart_throwsWhenTheConsoleWindowNeverAppears() throws {
        let f = try makeEnsureFixture(running: false, windowTitle: nil)

        XCTAssertThrowsError(try f.controller.ensureSessionOpen(atPath: f.sessionURL.path)) { error in
            XCTAssertEqual(error as? UADConsoleControllerError, .consoleWindowNeverAppeared)
        }
        XCTAssertTrue(f.loader.loadedPaths.isEmpty)
    }

    func test_ensureSessionOpen_doesNothingWhenTheSessionIsAlreadyOpen() throws {
        let f = try makeEnsureFixture(running: true, windowTitle: "UAD Console: OCTO EMPTY")

        try f.controller.ensureSessionOpen(atPath: f.sessionURL.path)

        XCTAssertTrue(f.loader.loadedPaths.isEmpty)
        XCTAssertNil(f.launcher.openedFileURL)
    }

    func test_ensureSessionOpen_ignoresCaseAndTheUnsavedChangesAsterisk() throws {
        let f = try makeEnsureFixture(running: true, windowTitle: "UAD Console: octo empty*")

        try f.controller.ensureSessionOpen(atPath: f.sessionURL.path)

        XCTAssertTrue(f.loader.loadedPaths.isEmpty)
    }

    func test_ensureSessionOpen_loadsTheSessionWhenADifferentOneIsOpen() throws {
        let f = try makeEnsureFixture(running: true, windowTitle: "UAD Console: empty home*")

        try f.controller.ensureSessionOpen(atPath: f.sessionURL.path)

        XCTAssertEqual(f.loader.loadedPaths, [f.sessionURL.path])
    }

    func test_ensureSessionOpen_doesNotConfuseASessionWhoseNameContainsTheExpectedOne() throws {
        let sessionURL = tempDirectory.appendingPathComponent("EMPTY.uadmix")
        try Data().write(to: sessionURL)
        let consoleAppURL = tempDirectory.appendingPathComponent("UAD Console.app")
        try FileManager.default.createDirectory(at: consoleAppURL, withIntermediateDirectories: true)
        let runningChecker = MockRunningApplicationChecker()
        runningChecker.runningBundleIDs = [UADConsoleController.defaultConsoleBundleID]
        let loader = MockSessionLoader()
        let inspector = MockSessionInspector()
        inspector.title = "UAD Console: OCTO EMPTY"
        let controller = UADConsoleController(appLauncher: MockAppLauncher(), consoleAppPath: consoleAppURL.path, runningChecker: runningChecker, sessionLoader: loader, sessionInspector: inspector)

        try controller.ensureSessionOpen(atPath: sessionURL.path)

        XCTAssertEqual(loader.loadedPaths, [sessionURL.path])
    }

    func test_ensureSessionOpen_loadsTheSessionWhenTheCurrentOneCannotBeRead() throws {
        let f = try makeEnsureFixture(running: true, windowTitle: nil)

        try f.controller.ensureSessionOpen(atPath: f.sessionURL.path)

        XCTAssertEqual(f.loader.loadedPaths, [f.sessionURL.path])
    }

    private func runningController(title: String, dirty: Bool, loader: MockSessionLoader) throws -> (UADConsoleController, String) {
        let sessionURL = tempDirectory.appendingPathComponent("empty home.uadmix")
        try Data().write(to: sessionURL)
        let running = MockRunningApplicationChecker()
        running.runningBundleIDs = [UADConsoleController.defaultConsoleBundleID]
        let inspector = MockSessionInspector()
        inspector.title = title
        let controller = UADConsoleController(
            appLauncher: MockAppLauncher(), consoleAppPath: tempDirectory.path, runningChecker: running,
            sessionLoader: loader, sessionInspector: inspector, sleep: { _ in }, hasUnsavedChanges: { dirty }
        )
        return (controller, sessionURL.path)
    }

    func test_ensureSessionOpen_discardsUnsavedChangesWhenTheEngineSaysDirty() throws {
        let loader = MockSessionLoader()
        let (controller, path) = try runningController(title: "UAD Console: OCTO EMPTY", dirty: true, loader: loader)

        try controller.ensureSessionOpen(atPath: path)

        XCTAssertEqual(loader.discardFlags, [true])
    }

    func test_ensureSessionOpen_discardsUnsavedChangesWhenTheTitleHasAnAsterisk() throws {
        let loader = MockSessionLoader()
        let (controller, path) = try runningController(title: "UAD Console: OCTO EMPTY*", dirty: false, loader: loader)

        try controller.ensureSessionOpen(atPath: path)

        XCTAssertEqual(loader.discardFlags, [true])
    }

    func test_ensureSessionOpen_doesNotDiscardWhenTheSessionIsClean() throws {
        let loader = MockSessionLoader()
        let (controller, path) = try runningController(title: "UAD Console: OCTO EMPTY", dirty: false, loader: loader)

        try controller.ensureSessionOpen(atPath: path)

        XCTAssertEqual(loader.discardFlags, [false])
    }
}
