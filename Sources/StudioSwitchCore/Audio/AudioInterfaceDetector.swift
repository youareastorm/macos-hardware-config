public protocol DeviceDetecting {
    func matchingDeviceName(for profile: Profile) -> String?
}

public final class AudioInterfaceDetector: DeviceDetecting {
    private let provider: AudioDeviceProviding

    public init(provider: AudioDeviceProviding = CoreAudioDeviceProvider()) {
        self.provider = provider
    }

    public func matchingDeviceName(for profile: Profile) -> String? {
        provider.connectedDeviceNames().first {
            $0.caseInsensitiveCompare(profile.deviceNameMatch) == .orderedSame
        }
    }
}
