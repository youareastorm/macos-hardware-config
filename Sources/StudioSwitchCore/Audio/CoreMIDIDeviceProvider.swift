import CoreMIDI

public enum CoreMIDIError: Error, Equatable {
    case iacDriverNotFound
    case deviceNotFound(String)
    case propertyWriteFailed(OSStatus)
}

public final class CoreMIDIDeviceProvider: MIDIDeviceProviding {
    public init() {}

    public func iacDriverIsPresent() -> Bool {
        iacDriverDevice() != nil
    }

    public func enableIACDriver() throws {
        guard let device = iacDriverDevice() else { throw CoreMIDIError.iacDriverNotFound }
        try setOffline(false, for: device)
    }

    public func enableDevice(named deviceName: String) throws {
        guard let device = device(named: deviceName) else {
            throw CoreMIDIError.deviceNotFound(deviceName)
        }
        try setOffline(false, for: device)
    }

    private func setOffline(_ offline: Bool, for device: MIDIDeviceRef) throws {
        let status = MIDIObjectSetIntegerProperty(device, kMIDIPropertyOffline, offline ? 1 : 0)
        guard status == noErr else { throw CoreMIDIError.propertyWriteFailed(status) }
    }

    private func iacDriverDevice() -> MIDIDeviceRef? {
        for index in 0..<MIDIGetNumberOfDevices() {
            let device = MIDIGetDevice(index)
            var ownerRef: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(device, kMIDIPropertyDriverOwner, &ownerRef) == noErr,
                  let owner = ownerRef?.takeRetainedValue() as String?,
                  owner == "com.apple.AppleMIDIIACDriver" else { continue }
            return device
        }
        return nil
    }

    private func device(named deviceName: String) -> MIDIDeviceRef? {
        for index in 0..<MIDIGetNumberOfDevices() {
            let device = MIDIGetDevice(index)
            var nameRef: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(device, kMIDIPropertyName, &nameRef) == noErr,
                  let name = nameRef?.takeRetainedValue() as String?,
                  name.caseInsensitiveCompare(deviceName) == .orderedSame else { continue }
            return device
        }
        return nil
    }
}
