import XCTest
@testable import StudioSwitchCore

private final class MockHardwareModelProvider: HardwareModelProviding {
    var names: [String]
    init(names: [String]) { self.names = names }
    func connectedModelNames() -> [String] { names }
}

final class AudioInterfaceDetectorTests: XCTestCase {
    func test_matchesExactCaseInsensitiveDeviceName() {
        let detector = AudioInterfaceDetector(provider: MockHardwareModelProvider(names: ["MacBook Pro Speakers", "apollo solo"]))
        let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", useIACDriver: false, daws: [])

        XCTAssertEqual(detector.matchingDeviceName(for: profile), "apollo solo")
    }

    func test_doesNotCrossMatchSimilarProfileNames() {
        let detector = AudioInterfaceDetector(provider: MockHardwareModelProvider(names: ["Apollo Solo"]))
        let studioProfile = Profile(name: "Studio", deviceNameMatch: "Apollo x8p", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", useIACDriver: false, daws: [])

        XCTAssertNil(detector.matchingDeviceName(for: studioProfile))
    }

    func test_returnsNilWhenNoDevicesConnected() {
        let detector = AudioInterfaceDetector(provider: MockHardwareModelProvider(names: []))
        let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", useIACDriver: false, daws: [])

        XCTAssertNil(detector.matchingDeviceName(for: profile))
    }
}
