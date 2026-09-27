import XCTest
import CoreAudio
@testable import StudioSwitchCore

private final class MockAudioDeviceProviding: AudioDeviceProviding {
    /// Queued per-name results, consumed one per call — lets a test simulate a device that isn't
    /// enumerable yet on the first few lookups and then appears, without a real delay.
    var lookupResults: [String: [AudioDeviceID?]] = [:]

    func connectedDeviceNames() -> [String] { [] }

    func deviceID(named exactName: String) -> AudioDeviceID? {
        guard var queue = lookupResults[exactName], !queue.isEmpty else { return nil }
        let result = queue.removeFirst()
        lookupResults[exactName] = queue
        return result
    }

    func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws {}
}

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

    // MARK: - waitForNewlyVisibleDevice
    //
    // Verified on real hardware: right after AudioHardwareCreateAggregateDevice succeeds, calling
    // ensureMultiOutputDevice again immediately (same process, no deliberate wait) found the new
    // device NOT YET enumerable via kAudioHardwarePropertyDevices, retried creation, and got back
    // kAudioHardwareIllegalOperationError ('nope') because the UID already existed. A later call —
    // a few seconds on — found it fine. These tests cover the retry/backoff recovery for that race
    // with a mock device list instead of a real timing-dependent aggregate device.

    func test_waitForNewlyVisibleDevice_returnsNameOnceDeviceBecomesVisible() throws {
        let deviceProvider = MockAudioDeviceProviding()
        deviceProvider.lookupResults["Combo"] = [nil, nil, 42]
        var delays: [TimeInterval] = []
        let provider = CoreAudioMultiOutputDeviceProvider(deviceProvider: deviceProvider, retryDelay: { delays.append($0) })

        let result = try provider.waitForNewlyVisibleDevice(named: "Combo", expectedSubDeviceNames: ["Sub 1"], fallbackStatus: kAudioHardwareIllegalOperationError)

        XCTAssertEqual(result, "Combo")
        XCTAssertEqual(delays.count, 2)
    }

    func test_waitForNewlyVisibleDevice_throwsOriginalErrorWhenDeviceNeverAppears() {
        let deviceProvider = MockAudioDeviceProviding()
        deviceProvider.lookupResults["Combo"] = [nil, nil, nil, nil, nil]
        let provider = CoreAudioMultiOutputDeviceProvider(deviceProvider: deviceProvider, retryDelay: { _ in })

        XCTAssertThrowsError(try provider.waitForNewlyVisibleDevice(named: "Combo", expectedSubDeviceNames: [], fallbackStatus: kAudioHardwareIllegalOperationError)) { error in
            guard case MultiOutputDeviceError.creationFailed(let status) = error else {
                return XCTFail("expected creationFailed, got \(error)")
            }
            XCTAssertEqual(status, kAudioHardwareIllegalOperationError)
        }
    }
}
