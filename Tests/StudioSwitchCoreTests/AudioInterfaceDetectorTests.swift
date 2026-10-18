import XCTest
import CoreAudio
@testable import StudioSwitchCore

private final class MockHardwareModelProvider: HardwareModelProviding {
    var names: [String]
    init(names: [String]) { self.names = names }
    func connectedModelNames() -> [String] { names }
}

private final class MockAudioDevices: AudioDeviceProviding {
    var names: [String]
    init(names: [String]) { self.names = names }
    func connectedDeviceNames() -> [String] { names }
    func deviceID(named exactName: String) -> AudioDeviceID? { nil }
    func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws {}
}

final class AudioInterfaceDetectorTests: XCTestCase {
    private let headset = Profile(name: "Casque", deviceNameMatch: "", audioDeviceName: "WH-CH720N", uadConsoleSession: nil, daws: [], detectByAudioDevice: true)

    func test_matchesExactCaseInsensitiveDeviceName() {
        let detector = AudioInterfaceDetector(provider: MockHardwareModelProvider(names: ["MacBook Pro Speakers", "apollo solo"]))
        let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", daws: [])

        XCTAssertEqual(detector.matchingDeviceName(for: profile), "apollo solo")
    }

    func test_doesNotCrossMatchSimilarProfileNames() {
        let detector = AudioInterfaceDetector(provider: MockHardwareModelProvider(names: ["Apollo Solo"]))
        let studioProfile = Profile(name: "Studio", deviceNameMatch: "Apollo x8p", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", daws: [])

        XCTAssertNil(detector.matchingDeviceName(for: studioProfile))
    }

    func test_returnsNilWhenNoDevicesConnected() {
        let detector = AudioInterfaceDetector(provider: MockHardwareModelProvider(names: []))
        let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", daws: [])

        XCTAssertNil(detector.matchingDeviceName(for: profile))
    }

    func test_audioDeviceProfile_matchesWhenItsAudioDeviceIsPresent() {
        let detector = AudioInterfaceDetector(provider: MockHardwareModelProvider(names: []), audioDevices: MockAudioDevices(names: ["Haut-parleurs MacBook Pro", "wh-ch720n"]))

        XCTAssertEqual(detector.matchingDeviceName(for: headset), "wh-ch720n")
    }

    func test_audioDeviceProfile_doesNotMatchWhenItsAudioDeviceIsAbsent() {
        let detector = AudioInterfaceDetector(provider: MockHardwareModelProvider(names: ["Apollo Solo"]), audioDevices: MockAudioDevices(names: ["Universal Audio Thunderbolt"]))

        XCTAssertNil(detector.matchingDeviceName(for: headset))
    }

    func test_thunderboltProfile_ignoresTheAudioDeviceList() {
        let detector = AudioInterfaceDetector(provider: MockHardwareModelProvider(names: []), audioDevices: MockAudioDevices(names: ["Apollo Solo"]))
        let home = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", daws: [])

        XCTAssertNil(detector.matchingDeviceName(for: home))
    }
}
