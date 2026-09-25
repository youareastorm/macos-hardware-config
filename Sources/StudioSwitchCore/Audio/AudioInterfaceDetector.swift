public protocol DeviceDetecting {
    func matchingDeviceName(for profile: Profile) -> String?
}

public final class AudioInterfaceDetector: DeviceDetecting {
    private let provider: HardwareModelProviding

    public init(provider: HardwareModelProviding = ThunderboltHardwareModelProvider()) {
        self.provider = provider
    }

    public func matchingDeviceName(for profile: Profile) -> String? {
        provider.connectedModelNames().first {
            $0.caseInsensitiveCompare(profile.deviceNameMatch) == .orderedSame
        }
    }
}
