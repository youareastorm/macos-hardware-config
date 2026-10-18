import CoreAudio

public protocol AudioMIDIConfiguring {
    func setDefaultDevice(named deviceName: String) throws
    func setDefaultInputDevice(named deviceName: String) throws
    func setDefaultOutputDevice(named deviceName: String) throws
    func setPreferredOutputChannelPair(_ pair: ChannelPair, forDeviceNamed deviceName: String) throws
}

public enum AudioMIDIConfiguratorError: Error, Equatable {
    case deviceNotFound(String)
    case channelPairWriteFailed(OSStatus)
}

public final class AudioMIDIConfigurator: AudioMIDIConfiguring {
    private let deviceProvider: AudioDeviceProviding

    public init(deviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider()) {
        self.deviceProvider = deviceProvider
    }

    public func setDefaultDevice(named deviceName: String) throws {
        try setDefaultInputDevice(named: deviceName)
        try setDefaultOutputDevice(named: deviceName)
    }

    public func setDefaultInputDevice(named deviceName: String) throws {
        let deviceID = try resolvedDeviceID(named: deviceName, direction: .input)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    public func setDefaultOutputDevice(named deviceName: String) throws {
        let deviceID = try resolvedDeviceID(named: deviceName, direction: .output)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    public func setPreferredOutputChannelPair(_ pair: ChannelPair, forDeviceNamed deviceName: String) throws {
        let deviceID = try resolvedDeviceID(named: deviceName, direction: .output)
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

    private func resolvedDeviceID(named deviceName: String, direction: AudioDirection) throws -> AudioDeviceID {
        guard let deviceID = deviceProvider.deviceID(named: deviceName, direction: direction) else {
            throw AudioMIDIConfiguratorError.deviceNotFound(deviceName)
        }
        return deviceID
    }
}
