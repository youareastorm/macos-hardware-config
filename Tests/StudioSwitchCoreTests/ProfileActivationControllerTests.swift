import XCTest
@testable import StudioSwitchCore

private final class MockDetector: DeviceDetecting {
    var matchedName: String?
    func matchingDeviceName(for profile: Profile) -> String? { matchedName }
}

private final class MockConfigurator: AudioMIDIConfiguring {
    var setDefaultDeviceError: Error?
    var enableIACDriverError: Error?
    private(set) var setDefaultDeviceCallCount = 0
    private(set) var enableIACDriverCallCount = 0
    private(set) var setDefaultDeviceNames: [String] = []

    func setDefaultDevice(named deviceName: String) throws {
        setDefaultDeviceCallCount += 1
        setDefaultDeviceNames.append(deviceName)
        if let error = setDefaultDeviceError { throw error }
    }

    func enableIACDriverIfPresent() throws {
        enableIACDriverCallCount += 1
        if let error = enableIACDriverError { throw error }
    }
}

private final class MockUADConsole: UADSessionOpening {
    var openSessionError: Error?
    private(set) var openSessionCallCount = 0

    func openSession(atPath path: String) throws {
        openSessionCallCount += 1
        if let error = openSessionError { throw error }
    }
}

private enum TestError: Error { case boom }

final class ProfileActivationControllerTests: XCTestCase {
    private let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", useIACDriver: false, daws: [])

    func test_activate_shortCircuitsWhenDeviceNotDetected() {
        let configurator = MockConfigurator()
        let uadConsole = MockUADConsole()
        let controller = ProfileActivationController(detector: MockDetector(), configurator: configurator, uadConsole: uadConsole)

        let result = controller.activate(profile)

        XCTAssertFalse(result.deviceDetected)
        XCTAssertEqual(configurator.setDefaultDeviceCallCount, 0)
        XCTAssertEqual(uadConsole.openSessionCallCount, 0)
    }

    func test_activate_configuresAudioAndOpensSessionWhenDeviceDetected() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let uadConsole = MockUADConsole()
        let controller = ProfileActivationController(detector: detector, configurator: configurator, uadConsole: uadConsole)

        let result = controller.activate(profile)

        XCTAssertTrue(result.deviceDetected)
        XCTAssertNil(result.deviceConfigError)
        XCTAssertNil(result.uadConsoleError)
        XCTAssertEqual(configurator.setDefaultDeviceCallCount, 1)
        XCTAssertEqual(uadConsole.openSessionCallCount, 1)
    }

    func test_activate_stillOpensSessionWhenDeviceConfigFails() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        configurator.setDefaultDeviceError = TestError.boom
        let uadConsole = MockUADConsole()
        let controller = ProfileActivationController(detector: detector, configurator: configurator, uadConsole: uadConsole)

        let result = controller.activate(profile)

        XCTAssertNotNil(result.deviceConfigError)
        XCTAssertEqual(uadConsole.openSessionCallCount, 1)
        XCTAssertNil(result.uadConsoleError)
    }

    func test_activate_reportsUADConsoleErrorWithoutFailingActivation() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let uadConsole = MockUADConsole()
        uadConsole.openSessionError = TestError.boom
        let controller = ProfileActivationController(detector: detector, configurator: MockConfigurator(), uadConsole: uadConsole)

        let result = controller.activate(profile)

        XCTAssertTrue(result.deviceDetected)
        XCTAssertNil(result.deviceConfigError)
        XCTAssertNotNil(result.uadConsoleError)
    }

    func test_activate_routesAudioByProfileAudioDeviceNameNotDetectionMatch() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let controller = ProfileActivationController(detector: detector, configurator: configurator, uadConsole: MockUADConsole())

        _ = controller.activate(profile)

        XCTAssertEqual(configurator.setDefaultDeviceNames, ["Universal Audio Thunderbolt"])
    }

    func test_activate_enablesIACDriverOnlyWhenProfileRequestsIt() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let profileWithIAC = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", useIACDriver: true, daws: [])
        let controller = ProfileActivationController(detector: detector, configurator: configurator, uadConsole: MockUADConsole())

        _ = controller.activate(profileWithIAC)

        XCTAssertEqual(configurator.enableIACDriverCallCount, 1)
    }
}
