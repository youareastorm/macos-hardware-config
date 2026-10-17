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

final class AudioMIDIConfiguratorTests: XCTestCase {
    func test_setDefaultDevice_setsInputOutputAndSystemOutput() throws {
        let deviceProvider = MockAudioDeviceProvider()
        deviceProvider.idsByName["Apollo Solo"] = 42
        let configurator = AudioMIDIConfigurator(deviceProvider: deviceProvider)

        try configurator.setDefaultDevice(named: "Apollo Solo")

        XCTAssertEqual(deviceProvider.setDefaultCalls.map(\.0), [42, 42, 42])
        XCTAssertEqual(deviceProvider.setDefaultCalls.map(\.1), [
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice
        ])
    }

    func test_setDefaultInputDevice_setsOnlyInput() throws {
        let deviceProvider = MockAudioDeviceProvider()
        deviceProvider.idsByName["Apollo Solo"] = 42
        let configurator = AudioMIDIConfigurator(deviceProvider: deviceProvider)

        try configurator.setDefaultInputDevice(named: "Apollo Solo")

        XCTAssertEqual(deviceProvider.setDefaultCalls.map(\.0), [42])
        XCTAssertEqual(deviceProvider.setDefaultCalls.map(\.1), [kAudioHardwarePropertyDefaultInputDevice])
    }

    func test_setDefaultOutputDevice_setsOutputAndSystemOutput() throws {
        let deviceProvider = MockAudioDeviceProvider()
        deviceProvider.idsByName["Virtuel 1 + Virtuel 2"] = 7
        let configurator = AudioMIDIConfigurator(deviceProvider: deviceProvider)

        try configurator.setDefaultOutputDevice(named: "Virtuel 1 + Virtuel 2")

        XCTAssertEqual(deviceProvider.setDefaultCalls.map(\.0), [7, 7])
        XCTAssertEqual(deviceProvider.setDefaultCalls.map(\.1), [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice
        ])
    }

    func test_setDefaultInputDevice_throwsWhenDeviceNotFound() {
        let configurator = AudioMIDIConfigurator(deviceProvider: MockAudioDeviceProvider())

        XCTAssertThrowsError(try configurator.setDefaultInputDevice(named: "Missing")) { error in
            XCTAssertEqual(error as? AudioMIDIConfiguratorError, .deviceNotFound("Missing"))
        }
    }

    func test_setDefaultDevice_throwsWhenDeviceNotFound() {
        let configurator = AudioMIDIConfigurator(deviceProvider: MockAudioDeviceProvider())

        XCTAssertThrowsError(try configurator.setDefaultDevice(named: "Missing")) { error in
            XCTAssertEqual(error as? AudioMIDIConfiguratorError, .deviceNotFound("Missing"))
        }
    }

    func test_setPreferredOutputChannelPair_throwsWhenDeviceNotFound() {
        let configurator = AudioMIDIConfigurator(deviceProvider: MockAudioDeviceProvider())
        let pair = ChannelPair(firstChannel: 1, secondChannel: 2, firstName: "Virtual 1", secondName: "Virtual 2")

        XCTAssertThrowsError(try configurator.setPreferredOutputChannelPair(pair, forDeviceNamed: "Missing")) { error in
            XCTAssertEqual(error as? AudioMIDIConfiguratorError, .deviceNotFound("Missing"))
        }
    }
}
