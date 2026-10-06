import Foundation
import XCTest
@testable import StudioSwitchCore

private final class MockAudioDeviceStatusProvider: AudioDeviceStatusProviding {
    var onlineDeviceNames: Set<String> = []
    var sampleRates: [String: Double] = [:]
    var defaultOutput: String?
    var defaultInput: String?
    var builtInOutput: String?
    var outputChannels: [String: [String]] = [:]
    var availableChannelPairs: [String: [ChannelPair]] = [:]

    func isDeviceOnline(named deviceName: String) -> Bool { onlineDeviceNames.contains(deviceName) }
    func nominalSampleRate(forDeviceNamed deviceName: String) -> Double? { sampleRates[deviceName] }
    func defaultOutputDeviceName() -> String? { defaultOutput }
    func defaultInputDeviceName() -> String? { defaultInput }
    func builtInOutputDeviceName() -> String? { builtInOutput }
    func outputChannelNames(forDeviceNamed deviceName: String) -> [String]? { outputChannels[deviceName] }
    func availableOutputChannelPairs(forDeviceNamed deviceName: String) -> [ChannelPair] { availableChannelPairs[deviceName] ?? [] }
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
        audioStatus: MockAudioDeviceStatusProvider = MockAudioDeviceStatusProvider()
    ) -> SystemHealthChecker {
        SystemHealthChecker(audioStatus: audioStatus)
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

        XCTAssertEqual(results.first(where: { $0.label == "Sortie HP" })?.status, .error("Haut-parleurs Mac non détectés"))
    }

    func test_outputRouting_okWhenBuiltInDeviceDetectedAndNoTargetConfigured() {
        let audioStatus = MockAudioDeviceStatusProvider()
        audioStatus.builtInOutput = "MacBook Pro Speakers"
        let checker = makeChecker(audioStatus: audioStatus)

        let results = checker.check(for: profile)

        XCTAssertEqual(results.first(where: { $0.label == "Sortie HP" })?.status, .ok)
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

        XCTAssertEqual(results.first(where: { $0.label == "Sortie HP" })?.status, .error("Sortie actuelle : MacBook Pro Speakers"))
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

        XCTAssertEqual(results.first(where: { $0.label == "Sortie HP" })?.status, .ok)
    }

    func test_check_doesNotIncludeMIDIOrUSBPowerRows() {
        let checker = makeChecker()

        let results = checker.check(for: profile)

        XCTAssertNil(results.first(where: { $0.label == "MIDI" }))
        XCTAssertNil(results.first(where: { $0.label == "Alimentation USB" }))
    }

    func test_check_doesNotIncludeUADConsoleRow() {
        let checker = makeChecker()

        let results = checker.check(for: profile)

        XCTAssertNil(results.first(where: { $0.label == "UAD Console" }))
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
