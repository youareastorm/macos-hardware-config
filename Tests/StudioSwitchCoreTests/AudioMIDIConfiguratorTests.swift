import XCTest
import CoreAudio
@testable import StudioSwitchCore

private final class MockAudioDeviceProvider: AudioDeviceProviding {
    var idsByName: [String: AudioDeviceID] = [:]
    private(set) var setDefaultCalls: [(AudioDeviceID, AudioObjectPropertySelector)] = []
    func connectedDeviceNames() -> [String] { Array(idsByName.keys) }
    func deviceID(named exactName: String) -> AudioDeviceID? { idsByName[exactName] }
    func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws {
        setDefaultCalls.append((deviceID, selector))
    }
}

private final class MockMIDIDeviceProvider: MIDIDeviceProviding {
    var present: Bool
    var enableError: Error?
    private(set) var enableCallCount = 0
    init(present: Bool) { self.present = present }
    func iacDriverIsPresent() -> Bool { present }
    func enableIACDriver() throws {
        enableCallCount += 1
        if let enableError { throw enableError }
    }
}

final class AudioMIDIConfiguratorTests: XCTestCase {
    func test_setDefaultDevice_setsInputOutputAndSystemOutput() throws {
        let deviceProvider = MockAudioDeviceProvider()
        deviceProvider.idsByName["Apollo Solo"] = 42
        let configurator = AudioMIDIConfigurator(deviceProvider: deviceProvider, midiProvider: MockMIDIDeviceProvider(present: false))

        try configurator.setDefaultDevice(named: "Apollo Solo")

        XCTAssertEqual(deviceProvider.setDefaultCalls.map(\.0), [42, 42, 42])
        XCTAssertEqual(deviceProvider.setDefaultCalls.map(\.1), [
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice
        ])
    }

    func test_setDefaultDevice_throwsWhenDeviceNotFound() {
        let configurator = AudioMIDIConfigurator(deviceProvider: MockAudioDeviceProvider(), midiProvider: MockMIDIDeviceProvider(present: false))

        XCTAssertThrowsError(try configurator.setDefaultDevice(named: "Missing")) { error in
            XCTAssertEqual(error as? AudioMIDIConfiguratorError, .deviceNotFound("Missing"))
        }
    }

    func test_enableIACDriverIfPresent_enablesDriver() throws {
        let midiProvider = MockMIDIDeviceProvider(present: true)
        let configurator = AudioMIDIConfigurator(deviceProvider: MockAudioDeviceProvider(), midiProvider: midiProvider)

        try configurator.enableIACDriverIfPresent()

        XCTAssertEqual(midiProvider.enableCallCount, 1)
    }

    func test_enableIACDriverIfPresent_throwsWhenDriverAbsent() {
        let midiProvider = MockMIDIDeviceProvider(present: false)
        midiProvider.enableError = CoreMIDIError.iacDriverNotFound
        let configurator = AudioMIDIConfigurator(deviceProvider: MockAudioDeviceProvider(), midiProvider: midiProvider)

        XCTAssertThrowsError(try configurator.enableIACDriverIfPresent()) { error in
            XCTAssertEqual(error as? CoreMIDIError, .iacDriverNotFound)
        }
    }
}
