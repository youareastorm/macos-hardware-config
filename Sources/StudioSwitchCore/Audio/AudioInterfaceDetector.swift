public protocol DeviceDetecting {
    func matchingDeviceName(for profile: Profile) -> String?
}

public final class AudioInterfaceDetector: DeviceDetecting {
    private let provider: HardwareModelProviding
    private let audioDevices: AudioDeviceProviding

    public init(provider: HardwareModelProviding = ThunderboltHardwareModelProvider(), audioDevices: AudioDeviceProviding = CoreAudioDeviceProvider()) {
        self.provider = provider
        self.audioDevices = audioDevices
    }

    public func matchingDeviceName(for profile: Profile) -> String? {
        let names = profile.detectByAudioDevice ? audioDevices.connectedDeviceNames() : provider.connectedModelNames()
        let wanted = profile.detectByAudioDevice ? profile.audioDeviceName : profile.deviceNameMatch
        return names.first { $0.caseInsensitiveCompare(wanted) == .orderedSame }
    }
}
