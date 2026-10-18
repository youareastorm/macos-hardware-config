import CoreAudio
import Foundation

public enum CoreAudioError: Error, Equatable {
    case propertyWriteFailed(OSStatus)
}

public final class CoreAudioDeviceProvider: AudioDeviceProviding {
    public init() {}

    public func connectedDeviceNames() -> [String] {
        deviceIDsAndNames().map(\.name)
    }

    public func deviceID(named exactName: String) -> AudioDeviceID? {
        deviceIDsAndNames().first { $0.name.caseInsensitiveCompare(exactName) == .orderedSame }?.id
    }

    public func deviceID(named exactName: String, direction: AudioDirection) -> AudioDeviceID? {
        let candidates = deviceIDsAndNames().filter { $0.name.caseInsensitiveCompare(exactName) == .orderedSame }.map(\.id)
        let scope = direction == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        return candidates.first { channelCount(of: $0, scope: scope) > 0 } ?? candidates.first
    }

    private func channelCount(of deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    public func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
        guard status == noErr else { throw CoreAudioError.propertyWriteFailed(status) }
    }

    private func deviceIDsAndNames() -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs.compactMap { id in
            guard let name = deviceName(for: id) else { return nil }
            return (id, name)
        }
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? (name as String) : nil
    }
}
