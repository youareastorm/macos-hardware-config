import CoreAudio

public enum AudioDirection: Hashable {
    case input
    case output
}

public protocol AudioDeviceProviding {
    func connectedDeviceNames() -> [String]
    func deviceID(named exactName: String) -> AudioDeviceID?
    /// The device with that name that has channels in `direction`. A Bluetooth headset shows up as
    /// two devices with the same name — one with only an input (its mic), one with only an output.
    func deviceID(named exactName: String, direction: AudioDirection) -> AudioDeviceID?
    func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws
}

extension AudioDeviceProviding {
    public func deviceID(named exactName: String, direction: AudioDirection) -> AudioDeviceID? {
        deviceID(named: exactName)
    }
}
