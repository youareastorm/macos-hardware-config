import CoreMIDI

public final class CoreMIDIStatusProvider: MIDIStatusProviding {
    public init() {}

    public func onlineDeviceNames() -> [String] {
        var names: [String] = []
        for index in 0..<MIDIGetNumberOfDevices() {
            let device = MIDIGetDevice(index)

            var isOffline: Int32 = 0
            guard MIDIObjectGetIntegerProperty(device, kMIDIPropertyOffline, &isOffline) == noErr,
                  isOffline == 0 else { continue }

            var nameRef: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(device, kMIDIPropertyName, &nameRef) == noErr,
                  let name = nameRef?.takeRetainedValue() as String? else { continue }

            names.append(name)
        }
        return names
    }
}
