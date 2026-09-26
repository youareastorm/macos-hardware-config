public struct ProfileActivationResult: Equatable {
    public let profile: Profile
    public let deviceDetected: Bool
    public let deviceConfigError: String?
    public let outputRoutingError: String?
    public let uadConsoleError: String?
}

public final class ProfileActivationController {
    private let detector: DeviceDetecting
    private let configurator: AudioMIDIConfiguring
    private let multiOutputProvider: MultiOutputDeviceProviding
    private let uadConsole: UADSessionOpening

    public init(
        detector: DeviceDetecting,
        configurator: AudioMIDIConfiguring,
        uadConsole: UADSessionOpening,
        multiOutputProvider: MultiOutputDeviceProviding = CoreAudioMultiOutputDeviceProvider()
    ) {
        self.detector = detector
        self.configurator = configurator
        self.uadConsole = uadConsole
        self.multiOutputProvider = multiOutputProvider
    }

    public func activate(_ profile: Profile) -> ProfileActivationResult {
        guard detector.matchingDeviceName(for: profile) != nil else {
            return ProfileActivationResult(profile: profile, deviceDetected: false, deviceConfigError: nil, outputRoutingError: nil, uadConsoleError: nil)
        }

        var deviceConfigError: String?
        do {
            if profile.outputDeviceTargetName != nil {
                try configurator.setDefaultInputDevice(named: profile.audioDeviceName)
            } else {
                try configurator.setDefaultDevice(named: profile.audioDeviceName)
            }
            if profile.useIACDriver {
                try configurator.enableIACDriverIfPresent()
            }
        } catch {
            deviceConfigError = "\(error)"
        }

        var outputRoutingError: String?
        if let target = profile.outputDeviceTargetName {
            do {
                if profile.expectedOutputDeviceNames.count > 1 {
                    try multiOutputProvider.ensureMultiOutputDevice(named: target, subDeviceNames: profile.expectedOutputDeviceNames)
                }
                try configurator.setDefaultOutputDevice(named: target)
            } catch {
                outputRoutingError = "\(error)"
            }
        }

        var uadConsoleError: String?
        do {
            try uadConsole.openSession(atPath: profile.uadConsoleSession)
        } catch {
            uadConsoleError = "\(error)"
        }

        return ProfileActivationResult(profile: profile, deviceDetected: true, deviceConfigError: deviceConfigError, outputRoutingError: outputRoutingError, uadConsoleError: uadConsoleError)
    }
}
