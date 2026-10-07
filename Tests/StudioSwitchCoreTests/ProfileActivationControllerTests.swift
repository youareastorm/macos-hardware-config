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

private final class MockUADConsole: UADConsoleSessionEnsuring {
    var error: Error?
    private(set) var ensuredPaths: [String] = []
    func ensureSessionOpen(atPath path: String) throws {
        ensuredPaths.append(path)
        if let error { throw error }
    }
}

/// Shared call log so tests can check the order of the UAD steps.
private final class StepLog { var steps: [String] = [] }

private final class OrderedUADConsole: UADConsoleSessionEnsuring {
    let log: StepLog
    init(log: StepLog) { self.log = log }
    func ensureSessionOpen(atPath path: String) throws { log.steps.append("session") }
}

private final class MockUADMixer: UAMixerControlling {
    var error: Error?
    var log: StepLog?
    private(set) var applyCalls: [(clockSource: String?, monitorLevel: Double?)] = []
    func currentState() throws -> UAMixerState { UAMixerState(clockSource: "Internal", monitorLevel: 0) }
    func apply(clockSource: String?, monitorLevel: Double?) throws {
        applyCalls.append((clockSource, monitorLevel))
        log?.steps.append("mixer")
        if let error { throw error }
    }
}

private final class MockOfflineDevices: UADConsoleOfflineDevicesControlling {
    var error: Error?
    var log: StepLog?
    private(set) var hideCalls = 0
    func isShowingOfflineDevices() throws -> Bool { false }
    func hideOfflineDevices() throws {
        hideCalls += 1
        log?.steps.append("offline")
        if let error { throw error }
    }
}

private final class RecordingLogger: ActivationLogging {
    private(set) var lines: [String] = []
    func log(_ message: String) { lines.append(message) }
}

/// Reports a different active pair before and after the UAD steps, the way a UA Mixer Engine
/// restart could reset it.
private final class ChangingChannelStatus: AudioDeviceStatusProviding {
    var pairs: [ChannelPair] = []
    var current: [String] = ["MON L", "MON R"]
    func isDeviceOnline(named deviceName: String) -> Bool { true }
    func nominalSampleRate(forDeviceNamed deviceName: String) -> Double? { nil }
    func defaultOutputDeviceName() -> String? { nil }
    func defaultInputDeviceName() -> String? { nil }
    func builtInOutputDeviceName() -> String? { nil }
    func outputChannelNames(forDeviceNamed deviceName: String) -> [String]? { current }
    func availableOutputChannelPairs(forDeviceNamed deviceName: String) -> [ChannelPair] { pairs }
}

private final class PairApplyingConfigurator: AudioMIDIConfiguring {
    let status: ChangingChannelStatus
    init(status: ChangingChannelStatus) { self.status = status }
    func setDefaultDevice(named deviceName: String) throws {}
    func setDefaultInputDevice(named deviceName: String) throws {}
    func setDefaultOutputDevice(named deviceName: String) throws {}
    func enableIACDriverIfPresent() throws {}
    func setPreferredOutputChannelPair(_ pair: ChannelPair, forDeviceNamed deviceName: String) throws {
        status.current = [pair.firstName, pair.secondName]
    }
    func enableMIDIDevice(named deviceName: String) throws {}
}

private final class PairResettingConsole: UADConsoleSessionEnsuring {
    let status: ChangingChannelStatus
    init(status: ChangingChannelStatus) { self.status = status }
    func ensureSessionOpen(atPath path: String) throws { status.current = ["MON L", "MON R"] }
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

    func test_activate_ensuresTheProfilesUADConsoleSessionWhenDeviceDetected() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let uadConsole = MockUADConsole()
        let controller = ProfileActivationController(detector: detector, configurator: MockConfigurator(), uadConsole: uadConsole)

        let result = controller.activate(profile)

        XCTAssertEqual(uadConsole.ensuredPaths, ["s"])
        XCTAssertNil(result.uadConsoleError)
    }

    func test_activate_doesNotTouchUADConsoleWhenDeviceNotDetected() {
        let uadConsole = MockUADConsole()
        let controller = ProfileActivationController(detector: MockDetector(), configurator: MockConfigurator(), uadConsole: uadConsole)

        _ = controller.activate(profile)

        XCTAssertTrue(uadConsole.ensuredPaths.isEmpty)
    }

    func test_activate_reportsUADConsoleErrorWithoutFailingActivation() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let uadConsole = MockUADConsole()
        uadConsole.error = TestError.boom
        let controller = ProfileActivationController(detector: detector, configurator: MockConfigurator(), uadConsole: uadConsole)

        let result = controller.activate(profile)

        XCTAssertTrue(result.deviceDetected)
        XCTAssertNil(result.deviceConfigError)
        XCTAssertNotNil(result.uadConsoleError)
    }

    private let studioProfile = Profile(
        name: "Studio", deviceNameMatch: "Thunderbolt 3 Option Card", audioDeviceName: "Universal Audio Thunderbolt",
        uadConsoleSession: "s", useIACDriver: false, daws: [],
        expectedClockSource: "Internal", expectedMonitorLevel: 0, hideUADOfflineDevices: true
    )

    private func detectedController(mixer: UAMixerControlling? = nil, offline: UADConsoleOfflineDevicesControlling? = nil, console: UADConsoleSessionEnsuring? = nil) -> ProfileActivationController {
        let detector = MockDetector()
        detector.matchedName = "Thunderbolt 3 Option Card"
        return ProfileActivationController(detector: detector, configurator: MockConfigurator(), uadConsole: console, uadMixer: mixer, uadOfflineDevices: offline)
    }

    func test_activate_appliesTheProfilesClockAndMonitorLevel() {
        let mixer = MockUADMixer()

        let result = detectedController(mixer: mixer).activate(studioProfile)

        XCTAssertEqual(mixer.applyCalls.count, 1)
        XCTAssertEqual(mixer.applyCalls.first?.clockSource, "Internal")
        XCTAssertEqual(mixer.applyCalls.first?.monitorLevel, 0)
        XCTAssertNil(result.uadMixerError)
    }

    func test_activate_leavesTheMixerAloneWhenTheProfileSetsNeither() {
        let mixer = MockUADMixer()

        _ = detectedController(mixer: mixer).activate(profile)

        XCTAssertTrue(mixer.applyCalls.isEmpty)
    }

    func test_activate_reportsMixerErrorWithoutFailingActivation() {
        let mixer = MockUADMixer()
        mixer.error = TestError.boom

        let result = detectedController(mixer: mixer).activate(studioProfile)

        XCTAssertTrue(result.deviceDetected)
        XCTAssertNotNil(result.uadMixerError)
    }

    func test_activate_hidesOfflineDevicesWhenTheProfileAsks() {
        let offline = MockOfflineDevices()

        let result = detectedController(offline: offline).activate(studioProfile)

        XCTAssertEqual(offline.hideCalls, 1)
        XCTAssertNil(result.uadOfflineDevicesError)
    }

    func test_activate_leavesOfflineDevicesAloneWhenTheProfileDoesNotAsk() {
        let offline = MockOfflineDevices()

        _ = detectedController(offline: offline).activate(profile)

        XCTAssertEqual(offline.hideCalls, 0)
    }

    func test_activate_reportsOfflineDevicesErrorWithoutFailingActivation() {
        let offline = MockOfflineDevices()
        offline.error = TestError.boom

        let result = detectedController(offline: offline).activate(studioProfile)

        XCTAssertNotNil(result.uadOfflineDevicesError)
    }

    func test_activate_setsTheMixerAndOfflineDevicesAfterOpeningTheSession() {
        let log = StepLog()
        let mixer = MockUADMixer()
        mixer.log = log
        let offline = MockOfflineDevices()
        offline.log = log

        _ = detectedController(mixer: mixer, offline: offline, console: OrderedUADConsole(log: log)).activate(studioProfile)

        XCTAssertEqual(log.steps, ["session", "offline", "mixer"])
    }

    func test_activate_doesNotTouchTheMixerWhenDeviceNotDetected() {
        let mixer = MockUADMixer()
        let offline = MockOfflineDevices()
        let controller = ProfileActivationController(detector: MockDetector(), configurator: MockConfigurator(), uadMixer: mixer, uadOfflineDevices: offline)

        _ = controller.activate(studioProfile)

        XCTAssertTrue(mixer.applyCalls.isEmpty)
        XCTAssertEqual(offline.hideCalls, 0)
    }

    func test_activate_logsTheChannelPairBeforeAfterAndOnceTheUADStepsAreDone() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let status = ChangingChannelStatus()
        status.pairs = [ChannelPair(firstChannel: 3, secondChannel: 4, firstName: "VIRTUAL 1", secondName: "VIRTUAL 2")]
        let configurator = PairApplyingConfigurator(status: status)
        let logger = RecordingLogger()
        let pairProfile = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedOutputChannelNames: ["VIRTUAL 1", "VIRTUAL 2"]
        )
        let controller = ProfileActivationController(
            detector: detector, configurator: configurator, channelStatus: status,
            uadConsole: PairResettingConsole(status: status), logger: logger
        )

        _ = controller.activate(pairProfile)

        let joined = logger.lines.joined(separator: "\n")
        XCTAssertTrue(joined.contains("paire avant : MON L / MON R"), joined)
        XCTAssertTrue(joined.contains("paire après : VIRTUAL 1 / VIRTUAL 2"), joined)
        XCTAssertTrue(joined.contains("paire à la fin : MON L / MON R"), joined)
    }

    func test_activate_logsEachStepAndItsError() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let uadConsole = MockUADConsole()
        uadConsole.error = TestError.boom
        let logger = RecordingLogger()
        let controller = ProfileActivationController(detector: detector, configurator: MockConfigurator(), uadConsole: uadConsole, logger: logger)

        _ = controller.activate(profile)

        XCTAssertTrue(logger.lines.contains { $0.hasPrefix("Activation de Home") }, "\(logger.lines)")
        XCTAssertTrue(logger.lines.contains { $0.contains("Session UAD Console") && $0.contains("ÉCHEC") && $0.contains("boom") }, "\(logger.lines)")
    }

    func test_activate_logsWhenTheDeviceIsNotDetected() {
        let logger = RecordingLogger()
        let controller = ProfileActivationController(detector: MockDetector(), configurator: MockConfigurator(), logger: logger)

        _ = controller.activate(profile)

        XCTAssertTrue(logger.lines.contains { $0.contains("non détecté") }, "\(logger.lines)")
    }
}
