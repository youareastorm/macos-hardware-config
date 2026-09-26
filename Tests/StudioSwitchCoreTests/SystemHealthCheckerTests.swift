import XCTest
@testable import StudioSwitchCore

private final class MockAudioDeviceStatusProvider: AudioDeviceStatusProviding {
    var onlineDeviceNames: Set<String> = []
    var sampleRates: [String: Double] = [:]
    var defaultOutput: String?
    var defaultInput: String?
    var builtInOutput: String?

    func isDeviceOnline(named deviceName: String) -> Bool { onlineDeviceNames.contains(deviceName) }
    func nominalSampleRate(forDeviceNamed deviceName: String) -> Double? { sampleRates[deviceName] }
    func defaultOutputDeviceName() -> String? { defaultOutput }
    func defaultInputDeviceName() -> String? { defaultInput }
    func builtInOutputDeviceName() -> String? { builtInOutput }
}

private final class MockMIDIStatusProvider: MIDIStatusProviding {
    var names: [String] = []
    func onlineDeviceNames() -> [String] { names }
}

private final class MockExternalStorageProvider: ExternalStorageProviding {
    var names: [String] = []
    func mountedExternalVolumeNames() -> [String] { names }
}

final class SystemHealthCheckerTests: XCTestCase {
    private let profile = Profile(
        name: "Home",
        deviceNameMatch: "Apollo Solo",
        audioDeviceName: "Universal Audio Thunderbolt",
        uadConsoleSession: "s",
        useIACDriver: false,
        daws: []
    )

    private func makeChecker(
        audioStatus: MockAudioDeviceStatusProvider = MockAudioDeviceStatusProvider(),
        midiStatus: MockMIDIStatusProvider = MockMIDIStatusProvider(),
        storageProvider: MockExternalStorageProvider = MockExternalStorageProvider()
    ) -> SystemHealthChecker {
        SystemHealthChecker(audioStatus: audioStatus, midiStatus: midiStatus, storageProvider: storageProvider)
    }

    func test_audioInterface_errorsWhenDeviceOffline() {
        let checker = makeChecker()

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Interface audio" })?.status, .error("Universal Audio Thunderbolt non détectée"))
    }

    func test_audioInterface_okWhenOnlineAndDefault() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.onlineDeviceNames = ["Universal Audio Thunderbolt"]
        audioStatus.defaultOutput = "Universal Audio Thunderbolt"
        audioStatus.defaultInput = "universal audio thunderbolt"
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Interface audio" })?.status, .ok)
    }

    func test_audioInterface_warnsWhenNotDefaultDevice() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.onlineDeviceNames = ["Universal Audio Thunderbolt"]
        audioStatus.defaultOutput = "MacBook Pro Speakers"
        audioStatus.defaultInput = "MacBook Pro Microphone"
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Interface audio" })?.status, .warning("N'est pas le device par défaut"))
    }

    func test_audioInterface_warnsWhenSampleRateMismatched() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.onlineDeviceNames = ["Universal Audio Thunderbolt"]
        audioStatus.sampleRates["Universal Audio Thunderbolt"] = 44100
        audioStatus.defaultOutput = "Universal Audio Thunderbolt"
        audioStatus.defaultInput = "Universal Audio Thunderbolt"
        let profileWithRate = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedSampleRate: 96000
        )
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profileWithRate)

        XCTAssertEqual(results.first(where: { $0.label == "Interface audio" })?.status, .warning("44100 Hz au lieu de 96000 Hz"))
    }

    func test_speakers_errorsWhenNoBuiltInDeviceDetected() {
        let checker = makeChecker()

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Haut-parleurs Mac" })?.status, .error("Non détectés"))
    }

    func test_speakers_okWhenBuiltInDeviceDetected() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.builtInOutput = "MacBook Pro Speakers"
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Haut-parleurs Mac" })?.status, .ok)
    }

    func test_midi_warnsWhenNoDeviceOnline() {
        let checker = makeChecker()

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "MIDI" })?.status, .warning("Aucun périphérique en ligne"))
    }

    func test_midi_okWhenDeviceOnline() {
        let midiStatus = MockMIDIStatusProvider()
        midiStatus.names = ["IAC Driver Bus 1"]
        let checker = makeChecker(midiStatus: midiStatus)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "MIDI" })?.status, .ok)
    }

    func test_externalDisks_okWhenProfileExpectsNone() {
        let checker = makeChecker()

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Disques externes" })?.status, .ok)
    }

    func test_externalDisks_errorsWhenExpectedDiskMissing() {
        let storageProvider = MockExternalStorageProvider()
        storageProvider.names = ["Backup"]
        let profileWithDisks = Profile(
            name: "Studio", deviceNameMatch: "Apollo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedExternalDiskNames: ["Backup", "Samples"]
        )
        let checker = makeChecker(storageProvider: storageProvider)

        let results = checker.check(for: profileWithDisks)

        XCTAssertEqual(results.first(where: { $0.label == "Disques externes" })?.status, .error("Manquants : Samples"))
    }

    func test_externalDisks_okWhenAllExpectedDisksMounted() {
        let storageProvider = MockExternalStorageProvider()
        storageProvider.names = ["Backup", "Samples"]
        let profileWithDisks = Profile(
            name: "Studio", deviceNameMatch: "Apollo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedExternalDiskNames: ["Backup", "Samples"]
        )
        let checker = makeChecker(storageProvider: storageProvider)

        let results = checker.check(for: profileWithDisks)

        XCTAssertEqual(results.first(where: { $0.label == "Disques externes" })?.status, .ok)
    }
}
