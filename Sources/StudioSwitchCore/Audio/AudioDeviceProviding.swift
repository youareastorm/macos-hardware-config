import CoreAudio

public protocol AudioDeviceProviding {
    func connectedDeviceNames() -> [String]
    func deviceID(named exactName: String) -> AudioDeviceID?
    func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws
}
