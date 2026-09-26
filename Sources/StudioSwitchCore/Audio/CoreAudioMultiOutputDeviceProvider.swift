import CoreAudio
import Foundation

/// Creates and reuses macOS Multi-Output Devices via CoreAudio's aggregate device API, so a
/// profile can route its output to several devices at once (e.g. two virtual outputs) without
/// requiring the user to have pre-built one in Audio MIDI Setup.
public final class CoreAudioMultiOutputDeviceProvider: MultiOutputDeviceProviding {
    private let deviceProvider: AudioDeviceProviding

    public init(deviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider()) {
        self.deviceProvider = deviceProvider
    }

    @discardableResult
    public func ensureMultiOutputDevice(named deviceName: String, subDeviceNames: [String]) throws -> String {
        if deviceProvider.deviceID(named: deviceName) != nil {
            return deviceName
        }

        let subDeviceUIDs = try subDeviceNames.map { name -> String in
            guard let deviceID = deviceProvider.deviceID(named: name) else {
                throw MultiOutputDeviceError.subDeviceNotFound(name)
            }
            guard let uid = deviceUID(for: deviceID) else {
                throw MultiOutputDeviceError.missingUID(name)
            }
            return uid
        }

        guard let mainUID = subDeviceUIDs.first else {
            throw MultiOutputDeviceError.subDeviceNotFound(deviceName)
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: deviceName,
            kAudioAggregateDeviceUIDKey: "com.simonrenard.studioswitch.multioutput.\(deviceName)",
            kAudioAggregateDeviceMainSubDeviceKey: mainUID,
            kAudioAggregateDeviceIsPrivateKey: false,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subDeviceUIDs.map { uid in
                [kAudioSubDeviceUIDKey: uid, kAudioSubDeviceDriftCompensationKey: true]
            }
        ]

        var aggregateDeviceID: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            throw MultiOutputDeviceError.creationFailed(status)
        }

        return deviceName
    }

    private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? (uid as String) : nil
    }
}
