import XCTest
@testable import StudioSwitchCore

private final class MockAudioDeviceStatusProvider: AudioDeviceStatusProviding {
    var onlineDeviceNames: Set<String> = []
    var sampleRates: [String: Double] = [:]
    var defaultOutput: String?
    var defaultInput: String?
    var builtInOutput: String?
    var outputChannels: [String: [String]] = [:]

    func isDeviceOnline(named deviceName: String) -> Bool { onlineDeviceNames.contains(deviceName) }
    func nominalSampleRate(forDeviceNamed deviceName: String) -> Double? { sampleRates[deviceName] }
    func defaultOutputDeviceName() -> String? { defaultOutput }
    func defaultInputDeviceName() -> String? { defaultInput }
    func builtInOutputDeviceName() -> String? { builtInOutput }
    func outputChannelNames(forDeviceNamed deviceName: String) -> [String]? { outputChannels[deviceName] }
}

private final class MockMIDIStatusProvider: MIDIStatusProviding {
    var names: [String] = []
    func onlineDeviceNames() -> [String] { names }
}

private final class MockExternalStorageProvider: ExternalStorageProviding {
    var names: [String] = []
    func mountedExternalVolumeNames() -> [String] { names }
}

private final class MockUADConsoleSessionInspector: UADConsoleSessionInspecting {
    var sessionName: String?
    func currentSessionName() -> String? { sessionName }
}

private final class MockUSBPowerInspector: USBPowerInspecting {
    var outcome: USBPowerCheckOutcome = .ok
    func checkPower() -> USBPowerCheckOutcome { outcome }
}

final class SystemHealthCheckerTests: XCTestCase {
    private let profile = Profile(
        name: "Home",
        deviceNameMatch: "Apollo Solo",
        audioDeviceName: "Universal Audio Thunderbolt",
        uadConsoleSession: "~/Documents/Universal Audio/Sessions/home guit vox.uadmix",
        useIACDriver: false,
        daws: []
    )

    private func makeChecker(
        audioStatus: MockAudioDeviceStatusProvider = MockAudioDeviceStatusProvider(),
        midiStatus: MockMIDIStatusProvider = MockMIDIStatusProvider(),
        storageProvider: MockExternalStorageProvider = MockExternalStorageProvider(),
        uadConsoleSession: MockUADConsoleSessionInspector = MockUADConsoleSessionInspector(),
        usbPower: MockUSBPowerInspector = MockUSBPowerInspector()
    ) -> SystemHealthChecker {
        SystemHealthChecker(
            audioStatus: audioStatus,
            midiStatus: midiStatus,
            storageProvider: storageProvider,
            uadConsoleSession: uadConsoleSession,
            usbPower: usbPower
        )
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

    func test_audioInterface_warnsWhenNotDefaultInput() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.onlineDeviceNames = ["Universal Audio Thunderbolt"]
        audioStatus.defaultOutput = "Universal Audio Thunderbolt"
        audioStatus.defaultInput = "MacBook Pro Microphone"
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Interface audio" })?.status, .warning("N'est pas l'entrée par défaut"))
    }

    func test_audioInterface_warnsWhenNotDefaultOutputAndProfileHasNoOutputTarget() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.onlineDeviceNames = ["Universal Audio Thunderbolt"]
        audioStatus.defaultOutput = "MacBook Pro Speakers"
        audioStatus.defaultInput = "Universal Audio Thunderbolt"
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Interface audio" })?.status, .warning("N'est pas la sortie par défaut"))
    }

    func test_audioInterface_ignoresOutputMismatchWhenProfileHasOutputTarget() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.onlineDeviceNames = ["Universal Audio Thunderbolt"]
        audioStatus.defaultOutput = "Virtuel 1"
        audioStatus.defaultInput = "Universal Audio Thunderbolt"
        let profileWithOutput = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedOutputDeviceNames: ["Virtuel 1"]
        )
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profileWithOutput)

        XCTAssertEqual(results.first(where: { $0.label == "Interface audio" })?.status, .ok)
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

    func test_outputRouting_errorsWhenNoBuiltInDeviceDetectedAndNoTargetConfigured() {
        let checker = makeChecker()

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Sorties audio" })?.status, .error("Haut-parleurs Mac non détectés"))
    }

    func test_outputRouting_okWhenBuiltInDeviceDetectedAndNoTargetConfigured() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.builtInOutput = "MacBook Pro Speakers"
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Sorties audio" })?.status, .ok)
    }

    func test_outputRouting_errorsWhenCurrentOutputDoesNotMatchTarget() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.defaultOutput = "MacBook Pro Speakers"
        let profileWithOutput = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedOutputDeviceNames: ["Virtuel 1", "Virtuel 2"]
        )
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profileWithOutput)

        XCTAssertEqual(results.first(where: { $0.label == "Sorties audio" })?.status, .error("Sortie actuelle : MacBook Pro Speakers"))
    }

    func test_outputRouting_okWhenCurrentOutputMatchesCombinedTarget() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.defaultOutput = "Virtuel 1 + Virtuel 2"
        let profileWithOutput = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [], expectedOutputDeviceNames: ["Virtuel 1", "Virtuel 2"]
        )
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profileWithOutput)

        XCTAssertEqual(results.first(where: { $0.label == "Sorties audio" })?.status, .ok)
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

    func test_uadConsole_errorsWhenNotRunning() {
        let checker = makeChecker()

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "UAD Console" })?.status, .error("UAD Console non lancé ou aucune session ouverte"))
    }

    func test_uadConsole_errorsWhenWrongSessionOpen() {
        let uadConsoleSession = MockUADConsoleSessionInspector()
        uadConsoleSession.sessionName = "session_mix_v3.uadmix — UAD Console"
        let checker = makeChecker(uadConsoleSession: uadConsoleSession)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "UAD Console" })?.status, .error("Session ouverte : session_mix_v3.uadmix — UAD Console"))
    }

    func test_uadConsole_okWhenExpectedSessionOpen() {
        let uadConsoleSession = MockUADConsoleSessionInspector()
        uadConsoleSession.sessionName = "home guit vox — UAD Console"
        let checker = makeChecker(uadConsoleSession: uadConsoleSession)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "UAD Console" })?.status, .ok)
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

    func test_usbPower_okWhenEnumerationWorks() {
        let checker = makeChecker()

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Alimentation USB" })?.status, .ok)
    }

    func test_usbPower_warnsWhenCheckUnavailable() {
        let usbPower = MockUSBPowerInspector()
        usbPower.outcome = .unavailable
        let checker = makeChecker(usbPower: usbPower)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Alimentation USB" })?.status, .warning("Impossible de vérifier (system_profiler n'a rien renvoyé)"))
    }

    func test_outputChannels_absentWhenProfileHasNoExpectedChannels() {
        let checker = makeChecker()

        let results = checker.check(for: profile)

        XCTAssertNil(results.first(where: { $0.label == "Canaux de sortie" }))
    }

    func test_outputChannels_okWhenCurrentPairMatchesExpectedCaseInsensitively() {
        let profileWithChannels = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [],
            expectedOutputChannelNames: ["Virtual 1", "Virtual 2"]
        )
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.outputChannels["Universal Audio Thunderbolt"] = ["VIRTUAL 1", "VIRTUAL 2"]
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profileWithChannels)

        XCTAssertEqual(results.first(where: { $0.label == "Canaux de sortie" })?.status, .ok)
    }

    func test_outputChannels_errorsWhenCurrentPairDoesNotMatchExpected() {
        let profileWithChannels = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [],
            expectedOutputChannelNames: ["VIRTUAL 1", "VIRTUAL 2"]
        )
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.outputChannels["Universal Audio Thunderbolt"] = ["Main 1", "Main 2"]
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profileWithChannels)

        XCTAssertEqual(results.first(where: { $0.label == "Canaux de sortie" })?.status, .error("Actuellement : Main 1, Main 2"))
    }

    func test_outputChannels_errorsWhenChannelsCannotBeRead() {
        let profileWithChannels = Profile(
            name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s", useIACDriver: false, daws: [],
            expectedOutputChannelNames: ["VIRTUAL 1", "VIRTUAL 2"]
        )
        let checker = makeChecker()

        let results = checker.check(for: profileWithChannels)

        XCTAssertEqual(results.first(where: { $0.label == "Canaux de sortie" })?.status, .error("Impossible de lire les canaux de Universal Audio Thunderbolt"))
    }
}
