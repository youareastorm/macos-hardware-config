import XCTest
@testable import StudioSwitchCore

private final class MockDetector: DeviceDetecting {
    var connectedProfileName: String?
    func matchingDeviceName(for profile: Profile) -> String? {
        profile.name == connectedProfileName ? profile.deviceNameMatch : nil
    }
}

private final class MockActivator: ProfileActivating {
    private(set) var activated: [String] = []
    var deviceConfigError: String?
    func activate(_ profile: Profile) -> ProfileActivationResult {
        activated.append(profile.name)
        return ProfileActivationResult(profile: profile, deviceDetected: true, deviceConfigError: deviceConfigError, outputRoutingError: nil, channelPairError: nil, uadConsoleError: nil)
    }
}

private final class RecordingLogger: ActivationLogging {
    private(set) var lines: [String] = []
    func log(_ message: String) { lines.append(message) }
}

private final class TriggerableWatcher: AudioDeviceListWatching {
    var onChange: (() -> Void)?
    func start(onChange: @escaping () -> Void) { self.onChange = onChange }
}

private final class MockWatcher: AudioDeviceListWatching {
    private(set) var started = false
    func start(onChange: @escaping () -> Void) { started = true }
}

final class AutoActivationCoordinatorTests: XCTestCase {
    private let home = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", useIACDriver: false, daws: [])
    private let studio = Profile(name: "Studio", deviceNameMatch: "Thunderbolt 3 Option Card", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", useIACDriver: false, daws: [])

    private var detector: MockDetector!
    private var activator: MockActivator!
    private var enabled = true
    private var audioOnline = true

    override func setUp() {
        detector = MockDetector()
        activator = MockActivator()
        enabled = true
        audioOnline = true
    }

    private func makeCoordinator(watcher: AudioDeviceListWatching = MockWatcher()) -> AutoActivationCoordinator {
        AutoActivationCoordinator(
            loadProfiles: { [self.home, self.studio] },
            detector: detector,
            isAudioDeviceOnline: { _ in self.audioOnline },
            activator: activator,
            isEnabled: { self.enabled },
            watcher: watcher
        )
    }

    func test_evaluate_activatesTheProfileWhoseHardwareIsConnected() {
        detector.connectedProfileName = "Studio"

        makeCoordinator().evaluate()

        XCTAssertEqual(activator.activated, ["Studio"])
    }

    func test_evaluate_doesNothingWhenNoProfileMatches() {
        makeCoordinator().evaluate()

        XCTAssertTrue(activator.activated.isEmpty)
    }

    func test_evaluate_doesNotReactivateTheSameProfileOnRepeatedChanges() {
        detector.connectedProfileName = "Home"
        let coordinator = makeCoordinator()

        coordinator.evaluate()
        coordinator.evaluate()

        XCTAssertEqual(activator.activated, ["Home"])
    }

    func test_evaluate_reactivatesAfterTheHardwareWentAwayAndCameBack() {
        detector.connectedProfileName = "Studio"
        let coordinator = makeCoordinator()

        coordinator.evaluate()
        detector.connectedProfileName = nil
        coordinator.evaluate()
        detector.connectedProfileName = "Studio"
        coordinator.evaluate()

        XCTAssertEqual(activator.activated, ["Studio", "Studio"])
    }

    func test_evaluate_switchesWhenADifferentProfileMatchesLater() {
        let coordinator = makeCoordinator()

        detector.connectedProfileName = "Home"
        coordinator.evaluate()
        detector.connectedProfileName = "Studio"
        coordinator.evaluate()

        XCTAssertEqual(activator.activated, ["Home", "Studio"])
    }

    func test_evaluate_doesNothingWhileDisabledThenActivatesOnceEnabled() {
        detector.connectedProfileName = "Studio"
        let coordinator = makeCoordinator()
        enabled = false

        coordinator.evaluate()
        XCTAssertTrue(activator.activated.isEmpty)

        enabled = true
        coordinator.evaluate()
        XCTAssertEqual(activator.activated, ["Studio"])
    }

    func test_evaluate_ignoresAThunderboltMatchWhoseAudioDeviceIsNotOnlineYet() {
        detector.connectedProfileName = "Studio"
        audioOnline = false

        makeCoordinator().evaluate()

        XCTAssertTrue(activator.activated.isEmpty)
    }

    func test_evaluate_retriesWhenTheActivationCouldNotConfigureTheDevice() {
        detector.connectedProfileName = "Studio"
        activator.deviceConfigError = "boom"
        let coordinator = makeCoordinator()

        coordinator.evaluate()
        activator.deviceConfigError = nil
        coordinator.evaluate()

        XCTAssertEqual(activator.activated, ["Studio", "Studio"])
    }

    func test_start_beginsWatchingTheDeviceList() {
        let watcher = MockWatcher()

        makeCoordinator(watcher: watcher).start()

        XCTAssertTrue(watcher.started)
    }

    func test_evaluate_logsWhyItActsOrNot() {
        let logger = RecordingLogger()
        detector.connectedProfileName = "Home"
        audioOnline = false
        let coordinator = AutoActivationCoordinator(
            loadProfiles: { [self.home, self.studio] }, detector: detector, isAudioDeviceOnline: { _ in self.audioOnline },
            activator: activator, isEnabled: { self.enabled }, watcher: MockWatcher(), logger: logger
        )

        coordinator.evaluate(trigger: "lancement")
        audioOnline = true
        coordinator.evaluate(trigger: "changement de périphériques")
        coordinator.evaluate(trigger: "changement de périphériques")

        let joined = logger.lines.joined(separator: "\n")
        XCTAssertTrue(joined.contains("Évaluation (lancement)"), joined)
        XCTAssertTrue(joined.contains("Home : carte détectée, périphérique audio hors ligne"), joined)
        XCTAssertTrue(joined.contains("aucun profil prêt"), joined)
        XCTAssertTrue(joined.contains("Home : carte détectée, périphérique audio en ligne"), joined)
        XCTAssertTrue(joined.contains("Home déjà actif, rien à faire"), joined)
    }

    func test_deviceListChanges_areLoggedWhenSignalled() {
        let logger = RecordingLogger()
        let watcher = TriggerableWatcher()
        let coordinator = AutoActivationCoordinator(
            loadProfiles: { [] }, detector: detector, isAudioDeviceOnline: { _ in true },
            activator: activator, isEnabled: { true }, watcher: watcher, debounce: 60, logger: logger
        )
        coordinator.start()

        watcher.onChange?()
        coordinator.waitForPendingWork()

        XCTAssertTrue(logger.lines.contains("Changement de périphériques signalé"), "\(logger.lines)")
    }

    func test_evaluate_reportsEachActivationResult() {
        detector.connectedProfileName = "Home"
        var reported: [String] = []
        let coordinator = AutoActivationCoordinator(
            loadProfiles: { [self.home, self.studio] }, detector: detector, isAudioDeviceOnline: { _ in true },
            activator: activator, isEnabled: { true }, watcher: MockWatcher(), onActivation: { reported.append($0.profile.name) }
        )

        coordinator.evaluate()

        XCTAssertEqual(reported, ["Home"])
    }
}
