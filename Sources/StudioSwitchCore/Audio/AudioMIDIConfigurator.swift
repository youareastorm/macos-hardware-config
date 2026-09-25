import CoreAudio

public protocol AudioMIDIConfiguring {
    func setDefaultDevice(named deviceName: String) throws
    func enableIACDriverIfPresent() throws
}

public enum AudioMIDIConfiguratorError: Error, Equatable {
    case deviceNotFound(String)
}

public final class AudioMIDIConfigurator: AudioMIDIConfiguring {
    private let deviceProvider: AudioDeviceProviding
    private let midiProvider: MIDIDeviceProviding

    public init(deviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider(), midiProvider: MIDIDeviceProviding = CoreMIDIDeviceProvider()) {
        self.deviceProvider = deviceProvider
        self.midiProvider = midiProvider
    }

    public func setDefaultDevice(named deviceName: String) throws {
        guard let deviceID = deviceProvider.deviceID(named: deviceName) else {
            throw AudioMIDIConfiguratorError.deviceNotFound(deviceName)
        }
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    public func enableIACDriverIfPresent() throws {
        try midiProvider.enableIACDriver()
    }
}
