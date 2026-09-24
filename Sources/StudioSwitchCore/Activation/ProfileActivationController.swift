public struct ProfileActivationResult: Equatable {
    public let profile: Profile
    public let deviceDetected: Bool
    public let deviceConfigError: String?
    public let uadConsoleError: String?
}

public final class ProfileActivationController {
    private let detector: DeviceDetecting
    private let configurator: AudioMIDIConfiguring
    private let uadConsole: UADSessionOpening

    public init(detector: DeviceDetecting, configurator: AudioMIDIConfiguring, uadConsole: UADSessionOpening) {
        self.detector = detector
        self.configurator = configurator
        self.uadConsole = uadConsole
    }

    public func activate(_ profile: Profile) -> ProfileActivationResult {
        guard let matchedName = detector.matchingDeviceName(for: profile) else {
            return ProfileActivationResult(profile: profile, deviceDetected: false, deviceConfigError: nil, uadConsoleError: nil)
        }

        var deviceConfigError: String?
        do {
            try configurator.setDefaultDevice(named: matchedName)
            if profile.useIACDriver {
                try configurator.enableIACDriverIfPresent()
            }
        } catch {
            deviceConfigError = "\(error)"
        }

        var uadConsoleError: String?
        do {
            try uadConsole.openSession(atPath: profile.uadConsoleSession)
        } catch {
            uadConsoleError = "\(error)"
        }

        return ProfileActivationResult(profile: profile, deviceDetected: true, deviceConfigError: deviceConfigError, uadConsoleError: uadConsoleError)
    }
}
