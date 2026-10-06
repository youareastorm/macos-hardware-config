import XCTest
@testable import StudioSwitchCore

private final class MockDetector: DeviceDetecting {
    var matchedName: String?
    func matchingDeviceName(for profile: Profile) -> String? { matchedName }
}

private final class MockConfigurator: AudioMIDIConfiguring {
    var setDefaultDeviceError: Error?
    var setDefaultInputDeviceError: Error?
    var setDefaultOutputDeviceError: Error?
    var enableIACDriverError: Error?
    var setPreferredOutputChannelPairError: Error?
    private(set) var setDefaultDeviceCallCount = 0
    private(set) var enableIACDriverCallCount = 0
    private(set) var setDefaultDeviceNames: [String] = []
    private(set) var setDefaultInputDeviceNames: [String] = []
    private(set) var setDefaultOutputDeviceNames: [String] = []
    private(set) var setPreferredOutputChannelPairCalls: [(pair: ChannelPair, deviceName: String)] = []

    func setDefaultDevice(named deviceName: String) throws {
        setDefaultDeviceCallCount += 1
        setDefaultDeviceNames.append(deviceName)
        if let error = setDefaultDeviceError { throw error }
    }

    func setDefaultInputDevice(named deviceName: String) throws {
        setDefaultInputDeviceNames.append(deviceName)
        if let error = setDefaultInputDeviceError { throw error }
    }

    func setDefaultOutputDevice(named deviceName: String) throws {
        setDefaultOutputDeviceNames.append(deviceName)
        if let error = setDefaultOutputDeviceError { throw error }
    }

    func enableIACDriverIfPresent() throws {
        enableIACDriverCallCount += 1
        if let error = enableIACDriverError { throw error }
    }

    func setPreferredOutputChannelPair(_ pair: ChannelPair, forDeviceNamed deviceName: String) throws {
        setPreferredOutputChannelPairCalls.append((pair, deviceName))
        if let error = setPreferredOutputChannelPairError { throw error }
    }

    func enableMIDIDevice(named deviceName: String) throws {}
}

private final class MockChannelStatus: AudioDeviceStatusProviding {
    var pairs: [String: [ChannelPair]] = [:]

    func isDeviceOnline(named deviceName: String) -> Bool { false }
    func nominalSampleRate(forDeviceNamed deviceName: String) -> Double? { nil }
    func defaultOutputDeviceName() -> String? { nil }
    func defaultInputDeviceName() -> String? { nil }
    func builtInOutputDeviceName() -> String? { nil }
    func outputChannelNames(forDeviceNamed deviceName: String) -> [String]? { nil }
    func availableOutputChannelPairs(forDeviceNamed deviceName: String) -> [ChannelPair] { pairs[deviceName] ?? [] }
}

private final class MockMultiOutputDeviceProvider: MultiOutputDeviceProviding {
    var error: Error?
    private(set) var ensureCalls: [(name: String, subDeviceNames: [String])] = []

    func ensureMultiOutputDevice(named deviceName: String, subDeviceNames: [String]) throws -> String {
        ensureCalls.append((deviceName, subDeviceNames))
        if let error { throw error }
        return deviceName
    }
}

private enum TestError: Error { case boom }

final class ProfileActivationControllerTests: XCTestCase {
    private let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", useIACDriver: false, daws: [])

    func test_activate_shortCircuitsWhenDeviceNotDetected() {
        let configurator = MockConfigurator()
        let controller = ProfileActivationController(detector: MockDetector(), configurator: configurator)

        let result = controller.activate(profile)

        XCTAssertFalse(result.deviceDetected)
        XCTAssertEqual(configurator.setDefaultDeviceCallCount, 0)
    }

    func test_activate_configuresAudioWhenDeviceDetected() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let controller = ProfileActivationController(detector: detector, configurator: configurator)

        let result = controller.activate(profile)

        XCTAssertTrue(result.deviceDetected)
        XCTAssertNil(result.deviceConfigError)
        XCTAssertEqual(configurator.setDefaultDeviceCallCount, 1)
    }

    func test_activate_routesAudioByProfileAudioDeviceNameNotDetectionMatch() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let controller = ProfileActivationController(detector: detector, configurator: configurator)

        _ = controller.activate(profile)

        XCTAssertEqual(configurator.setDefaultDeviceNames, ["Universal Audio Thunderbolt"])
    }

    func test_activate_enablesIACDriverOnlyWhenProfileRequestsIt() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let profileWithIAC = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", useIACDriver: true, daws: [])
        let controller = ProfileActivationController(detector: detector, configurator: configurator)

        _ = controller.activate(profileWithIAC)

        XCTAssertEqual(configurator.enableIACDriverCallCount, 1)
    }

    func test_activate_routesOutputSeparatelyWhenProfileHasSingleOutputTarget() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let multiOutput = MockMultiOutputDeviceProvider()
        let profileWithOutput = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedOutputDeviceNames: ["Virtuel 1"]
        )
        let controller = ProfileActivationController(detector: detector, configurator: configurator, multiOutputProvider: multiOutput)

        let result = controller.activate(profileWithOutput)

        XCTAssertEqual(configurator.setDefaultInputDeviceNames, ["Universal Audio Thunderbolt"])
        XCTAssertEqual(configurator.setDefaultOutputDeviceNames, ["Virtuel 1"])
        XCTAssertEqual(configurator.setDefaultDeviceCallCount, 0)
        XCTAssertTrue(multiOutput.ensureCalls.isEmpty)
        XCTAssertNil(result.outputRoutingError)
    }

    func test_activate_createsMultiOutputDeviceWhenProfileHasSeveralOutputTargets() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let multiOutput = MockMultiOutputDeviceProvider()
        let profileWithOutputs = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedOutputDeviceNames: ["Virtuel 1", "Virtuel 2"]
        )
        let controller = ProfileActivationController(detector: detector, configurator: configurator, multiOutputProvider: multiOutput)

        let result = controller.activate(profileWithOutputs)

        XCTAssertEqual(multiOutput.ensureCalls.count, 1)
        XCTAssertEqual(multiOutput.ensureCalls.first?.name, "Virtuel 1 + Virtuel 2")
        XCTAssertEqual(multiOutput.ensureCalls.first?.subDeviceNames, ["Virtuel 1", "Virtuel 2"])
        XCTAssertEqual(configurator.setDefaultOutputDeviceNames, ["Virtuel 1 + Virtuel 2"])
        XCTAssertNil(result.outputRoutingError)
    }

    func test_activate_reportsOutputRoutingErrorWithoutFailingActivation() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let multiOutput = MockMultiOutputDeviceProvider()
        multiOutput.error = MultiOutputDeviceError.subDeviceNotFound("Virtuel 2")
        let profileWithOutputs = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedOutputDeviceNames: ["Virtuel 1", "Virtuel 2"]
        )
        let controller = ProfileActivationController(detector: detector, configurator: MockConfigurator(), multiOutputProvider: multiOutput)

        let result = controller.activate(profileWithOutputs)

        XCTAssertTrue(result.deviceDetected)
        XCTAssertNotNil(result.outputRoutingError)
    }

    func test_activate_appliesMatchingOutputChannelPair() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let channelStatus = MockChannelStatus()
        let virtualPair = ChannelPair(firstChannel: 3, secondChannel: 4, firstName: "VIRTUAL 1", secondName: "VIRTUAL 2")
        channelStatus.pairs["Universal Audio Thunderbolt"] = [
            ChannelPair(firstChannel: 1, secondChannel: 2, firstName: "Main 1", secondName: "Main 2"),
            virtualPair
        ]
        let profileWithChannels = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedOutputChannelNames: ["VIRTUAL 1", "VIRTUAL 2"]
        )
        let controller = ProfileActivationController(detector: detector, configurator: configurator, channelStatus: channelStatus)

        let result = controller.activate(profileWithChannels)

        XCTAssertNil(result.channelPairError)
        XCTAssertEqual(configurator.setPreferredOutputChannelPairCalls.count, 1)
        XCTAssertEqual(configurator.setPreferredOutputChannelPairCalls.first?.pair, virtualPair)
        XCTAssertEqual(configurator.setPreferredOutputChannelPairCalls.first?.deviceName, "Universal Audio Thunderbolt")
    }

    func test_activate_skipsChannelPairWhenProfileHasNoExpectedChannels() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let channelStatus = MockChannelStatus()
        let controller = ProfileActivationController(detector: detector, configurator: configurator, channelStatus: channelStatus)

        let result = controller.activate(profile)

        XCTAssertNil(result.channelPairError)
        XCTAssertTrue(configurator.setPreferredOutputChannelPairCalls.isEmpty)
    }

    func test_activate_reportsChannelPairErrorWhenNoPairMatches() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let channelStatus = MockChannelStatus()
        channelStatus.pairs["Universal Audio Thunderbolt"] = [
            ChannelPair(firstChannel: 1, secondChannel: 2, firstName: "Main 1", secondName: "Main 2")
        ]
        let profileWithChannels = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedOutputChannelNames: ["VIRTUAL 1", "VIRTUAL 2"]
        )
        let controller = ProfileActivationController(detector: detector, configurator: configurator, channelStatus: channelStatus)

        let result = controller.activate(profileWithChannels)

        XCTAssertNotNil(result.channelPairError)
        XCTAssertTrue(configurator.setPreferredOutputChannelPairCalls.isEmpty)
    }

    func test_activate_reportsChannelPairErrorWithoutFailingActivation() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        configurator.setPreferredOutputChannelPairError = TestError.boom
        let channelStatus = MockChannelStatus()
        channelStatus.pairs["Universal Audio Thunderbolt"] = [
            ChannelPair(firstChannel: 3, secondChannel: 4, firstName: "VIRTUAL 1", secondName: "VIRTUAL 2")
        ]
        let profileWithChannels = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedOutputChannelNames: ["VIRTUAL 1", "VIRTUAL 2"]
        )
        let controller = ProfileActivationController(detector: detector, configurator: configurator, channelStatus: channelStatus)

        let result = controller.activate(profileWithChannels)

        XCTAssertTrue(result.deviceDetected)
        XCTAssertNotNil(result.channelPairError)
    }
}
