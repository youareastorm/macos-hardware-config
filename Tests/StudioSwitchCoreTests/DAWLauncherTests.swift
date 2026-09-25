import XCTest
@testable import StudioSwitchCore

private final class MockAppLocator: AppLocating {
    var urlsByBundleID: [String: URL] = [:]
    func applicationURL(forBundleID bundleID: String) -> URL? { urlsByBundleID[bundleID] }
}

private final class MockAppLauncher: AppLaunching {
    private(set) var launchedAppURL: URL?
    private(set) var openedFileURL: URL?
    private(set) var openedAppURL: URL?
    func launchApplication(at appURL: URL) throws { launchedAppURL = appURL }
    func open(fileURL: URL, withApplicationAt appURL: URL) throws {
        openedFileURL = fileURL
        openedAppURL = appURL
    }
}

final class DAWLauncherTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func test_launch_throwsWhenApplicationNotFound() {
        let launcher = DAWLauncher(appLocator: MockAppLocator(), appLauncher: MockAppLauncher())
        let daw = DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: nil)

        XCTAssertThrowsError(try launcher.launch(daw)) { error in
            XCTAssertEqual(error as? DAWLauncherError, .applicationNotFound("com.apple.logic10"))
        }
    }

    func test_launch_launchesAppDirectlyWhenNoTemplate() throws {
        let appURL = tempDirectory.appendingPathComponent("Logic Pro.app")
        let locator = MockAppLocator()
        locator.urlsByBundleID["com.apple.logic10"] = appURL
        let appLauncher = MockAppLauncher()
        let launcher = DAWLauncher(appLocator: locator, appLauncher: appLauncher)

        try launcher.launch(DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: nil))

        XCTAssertEqual(appLauncher.launchedAppURL, appURL)
        XCTAssertNil(appLauncher.openedFileURL)
    }

    func test_launch_opensTemplateWhenPresent() throws {
        let appURL = tempDirectory.appendingPathComponent("Logic Pro.app")
        let templateURL = tempDirectory.appendingPathComponent("template.logicx")
        try Data().write(to: templateURL)
        let locator = MockAppLocator()
        locator.urlsByBundleID["com.apple.logic10"] = appURL
        let appLauncher = MockAppLauncher()
        let launcher = DAWLauncher(appLocator: locator, appLauncher: appLauncher)

        try launcher.launch(DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: templateURL.path))

        XCTAssertEqual(appLauncher.openedFileURL, templateURL)
        XCTAssertEqual(appLauncher.openedAppURL, appURL)
        XCTAssertNil(appLauncher.launchedAppURL)
    }

    func test_launch_fallsBackToPlainLaunchWhenTemplateMissing() throws {
        let appURL = tempDirectory.appendingPathComponent("Logic Pro.app")
        let locator = MockAppLocator()
        locator.urlsByBundleID["com.apple.logic10"] = appURL
        let appLauncher = MockAppLauncher()
        let launcher = DAWLauncher(appLocator: locator, appLauncher: appLauncher)
        let missingTemplatePath = tempDirectory.appendingPathComponent("missing.logicx").path

        let outcome = try launcher.launch(DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: missingTemplatePath))

        XCTAssertEqual(appLauncher.launchedAppURL, appURL)
        XCTAssertNil(appLauncher.openedFileURL)
        XCTAssertEqual(outcome, .launchedWithoutTemplate(missingTemplatePath))
    }

    func test_launch_returnsLaunchedWhenNoTemplateConfigured() throws {
        let appURL = tempDirectory.appendingPathComponent("Logic Pro.app")
        let locator = MockAppLocator()
        locator.urlsByBundleID["com.apple.logic10"] = appURL
        let launcher = DAWLauncher(appLocator: locator, appLauncher: MockAppLauncher())

        let outcome = try launcher.launch(DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: nil))

        XCTAssertEqual(outcome, .launched)
    }

    func test_launch_prefersExplicitAppPathOverAmbiguousBundleIDLookup() throws {
        let standardURL = tempDirectory.appendingPathComponent("Ableton Live 12 Standard.app")
        let suiteURL = tempDirectory.appendingPathComponent("Ableton Live 12 Suite.app")
        let locator = MockAppLocator()
        locator.urlsByBundleID["com.ableton.live"] = standardURL
        let appLauncher = MockAppLauncher()
        let launcher = DAWLauncher(appLocator: locator, appLauncher: appLauncher)

        try launcher.launch(DAWEntry(name: "Ableton Live 12 Suite", bundleID: "com.ableton.live", appPath: suiteURL.path, templatePath: nil))

        XCTAssertEqual(appLauncher.launchedAppURL, suiteURL)
    }
}
