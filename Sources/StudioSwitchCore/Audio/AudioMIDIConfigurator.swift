import CoreAudio

public protocol AudioMIDIConfiguring {
    func setDefaultDevice(named deviceName: String) throws
    func setDefaultInputDevice(named deviceName: String) throws
    func setDefaultOutputDevice(named deviceName: String) throws
    func setPreferredOutputChannelPair(_ pair: ChannelPair, forDeviceNamed deviceName: String) throws
    func enableIACDriverIfPresent() throws
    func enableMIDIDevice(named deviceName: String) throws
}

public enum AudioMIDIConfiguratorError: Error, Equatable {
    case deviceNotFound(String)
    case channelPairWriteFailed(OSStatus)
}

public final class AudioMIDIConfigurator: AudioMIDIConfiguring {
    private let deviceProvider: AudioDeviceProviding
    private let midiProvider: MIDIDeviceProviding

    public init(deviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider(), midiProvider: MIDIDeviceProviding = CoreMIDIDeviceProvider()) {
        self.deviceProvider = deviceProvider
        self.midiProvider = midiProvider
    }

    public func setDefaultDevice(named deviceName: String) throws {
        let deviceID = try resolvedDeviceID(named: deviceName)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    public func setDefaultInputDevice(named deviceName: String) throws {
        let deviceID = try resolvedDeviceID(named: deviceName)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    public func setDefaultOutputDevice(named deviceName: String) throws {
        let deviceID = try resolvedDeviceID(named: deviceName)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    public func setPreferredOutputChannelPair(_ pair: ChannelPair, forDeviceNamed deviceName: String) throws {
        let deviceID = try resolvedDeviceID(named: deviceName)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var channels: [UInt32] = [pair.firstChannel, pair.secondChannel]
        let size = UInt32(MemoryLayout<UInt32>.size * 2)
        let status = channels.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, buffer.baseAddress!)
        }
        guard status == noErr else {
            throw AudioMIDIConfiguratorError.channelPairWriteFailed(status)
        }
    }

    public func enableIACDriverIfPresent() throws {
        try midiProvider.enableIACDriver()
    }

    public func enableMIDIDevice(named deviceName: String) throws {
        try midiProvider.enableDevice(named: deviceName)
    }

    private func resolvedDeviceID(named deviceName: String) throws -> AudioDeviceID {
        guard let deviceID = deviceProvider.deviceID(named: deviceName) else {
            throw AudioMIDIConfiguratorError.deviceNotFound(deviceName)
        }
        return deviceID
    }
}
