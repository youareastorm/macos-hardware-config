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
            var nameRef: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(device, kMIDIPropertyName, &nameRef) == noErr,
                  let name = nameRef?.takeRetainedValue() as String?,
                  name == "IAC Driver" else { continue }
            return device
        }
        return nil
    }
}
