import XCTest
import CoreAudio
@testable import StudioSwitchCore

final class CoreAudioMultiOutputDeviceProviderTests: XCTestCase {
    func test_aggregateDeviceDescription_setsNameAndAStableUID() {
        let description = CoreAudioMultiOutputDeviceProvider.aggregateDeviceDescription(
            name: "Virtuel 1 + Virtuel 2",
            subDeviceUIDs: ["uid-1", "uid-2"]
        )

        XCTAssertEqual(description[kAudioAggregateDeviceNameKey] as? String, "Virtuel 1 + Virtuel 2")
        XCTAssertEqual(description[kAudioAggregateDeviceUIDKey] as? String, "com.simonrenard.studioswitch.multioutput.Virtuel 1 + Virtuel 2")
    }

    func test_aggregateDeviceDescription_isMarkedAsAPublicStackedMultiOutputDevice() {
        let description = CoreAudioMultiOutputDeviceProvider.aggregateDeviceDescription(name: "Combo", subDeviceUIDs: ["uid-1", "uid-2"])

        XCTAssertEqual(description[kAudioAggregateDeviceIsStackedKey] as? Bool, true)
        XCTAssertEqual(description[kAudioAggregateDeviceIsPrivateKey] as? Bool, false)
    }

    func test_aggregateDeviceDescription_usesFirstSubDeviceAsClockMaster() {
        let description = CoreAudioMultiOutputDeviceProvider.aggregateDeviceDescription(name: "Combo", subDeviceUIDs: ["uid-1", "uid-2", "uid-3"])

        XCTAssertEqual(description[kAudioAggregateDeviceMainSubDeviceKey] as? String, "uid-1")
    }

    func test_aggregateDeviceDescription_listsEverySubDeviceWithDriftCompensationEnabled() {
        let description = CoreAudioMultiOutputDeviceProvider.aggregateDeviceDescription(name: "Combo", subDeviceUIDs: ["uid-1", "uid-2"])

        let subDevices = description[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]]
        XCTAssertEqual(subDevices?.count, 2)
        XCTAssertEqual(subDevices?[0][kAudioSubDeviceUIDKey] as? String, "uid-1")
        XCTAssertEqual(subDevices?[0][kAudioSubDeviceDriftCompensationKey] as? Bool, true)
        XCTAssertEqual(subDevices?[1][kAudioSubDeviceUIDKey] as? String, "uid-2")
        XCTAssertEqual(subDevices?[1][kAudioSubDeviceDriftCompensationKey] as? Bool, true)
    }
}
