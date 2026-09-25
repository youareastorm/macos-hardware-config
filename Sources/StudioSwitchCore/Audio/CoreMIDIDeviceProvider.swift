import CoreMIDI

public enum CoreMIDIError: Error, Equatable {
    case iacDriverNotFound
    case propertyWriteFailed(OSStatus)
}

public final class CoreMIDIDeviceProvider: MIDIDeviceProviding {
    public init() {}

    public func iacDriverIsPresent() -> Bool {
        iacDriverDevice() != nil
    }

    public func enableIACDriver() throws {
        guard let device = iacDriverDevice() else { throw CoreMIDIError.iacDriverNotFound }
        let status = MIDIObjectSetIntegerProperty(device, kMIDIPropertyOffline, 0)
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
}
