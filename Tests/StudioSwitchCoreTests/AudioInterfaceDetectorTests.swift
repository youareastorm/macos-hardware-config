import XCTest
import CoreAudio
@testable import StudioSwitchCore

private final class MockAudioDeviceProvider: AudioDeviceProviding {
    var names: [String]
    init(names: [String]) { self.names = names }
    func connectedDeviceNames() -> [String] { names }
    func deviceID(named exactName: String) -> AudioDeviceID? { nil }
    func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws {}
}

final class AudioInterfaceDetectorTests: XCTestCase {
    func test_matchesExactCaseInsensitiveDeviceName() {
        let detector = AudioInterfaceDetector(provider: MockAudioDeviceProvider(names: ["MacBook Pro Speakers", "apollo solo"]))
        let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", uadConsoleSession: "s", useIACDriver: false, daws: [])

        XCTAssertEqual(detector.matchingDeviceName(for: profile), "apollo solo")
    }

    func test_doesNotCrossMatchSimilarProfileNames() {
        let detector = AudioInterfaceDetector(provider: MockAudioDeviceProvider(names: ["Apollo Solo"]))
        let studioProfile = Profile(name: "Studio", deviceNameMatch: "Apollo x8p", uadConsoleSession: "s", useIACDriver: false, daws: [])

        XCTAssertNil(detector.matchingDeviceName(for: studioProfile))
    }

    func test_returnsNilWhenNoDevicesConnected() {
        let detector = AudioInterfaceDetector(provider: MockAudioDeviceProvider(names: []))
        let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", uadConsoleSession: "s", useIACDriver: false, daws: [])

        XCTAssertNil(detector.matchingDeviceName(for: profile))
    }
}
