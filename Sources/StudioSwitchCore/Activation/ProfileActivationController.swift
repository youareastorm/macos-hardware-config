public struct ProfileActivationResult: Equatable {
    public let profile: Profile
    public let deviceDetected: Bool
    public let deviceConfigError: String?
    public let outputRoutingError: String?
    public let channelPairError: String?
    public let uadConsoleError: String?
}

public final class ProfileActivationController {
    private let detector: DeviceDetecting
    private let configurator: AudioMIDIConfiguring
    private let multiOutputProvider: MultiOutputDeviceProviding
    private let channelStatus: AudioDeviceStatusProviding
    private let uadConsoleLauncher: UADConsoleLaunching?

    public init(
        detector: DeviceDetecting,
        configurator: AudioMIDIConfiguring,
        multiOutputProvider: MultiOutputDeviceProviding = CoreAudioMultiOutputDeviceProvider(),
        channelStatus: AudioDeviceStatusProviding = CoreAudioStatusProvider(),
        uadConsoleLauncher: UADConsoleLaunching? = nil
    ) {
        self.detector = detector
        self.configurator = configurator
        self.multiOutputProvider = multiOutputProvider
        self.channelStatus = channelStatus
        self.uadConsoleLauncher = uadConsoleLauncher
    }

    public func activate(_ profile: Profile) -> ProfileActivationResult {
        guard detector.matchingDeviceName(for: profile) != nil else {
            return ProfileActivationResult(profile: profile, deviceDetected: false, deviceConfigError: nil, outputRoutingError: nil, channelPairError: nil, uadConsoleError: nil)
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

        let channelPairError = applyOutputChannelPair(for: profile)

        var uadConsoleError: String?
        do {
            try uadConsoleLauncher?.launchIfNotRunning()
        } catch {
            uadConsoleError = "\(error)"
        }

        return ProfileActivationResult(profile: profile, deviceDetected: true, deviceConfigError: deviceConfigError, outputRoutingError: outputRoutingError, channelPairError: channelPairError, uadConsoleError: uadConsoleError)
    }

    /// Writes the profile's expected output channel pair (e.g. an Apollo's software-return
    /// channels) as the device's active stereo pair, when the profile cares which one is active.
    private func applyOutputChannelPair(for profile: Profile) -> String? {
        guard profile.expectedOutputChannelNames.count == 2 else { return nil }
        let expectedFirst = profile.expectedOutputChannelNames[0]
        let expectedSecond = profile.expectedOutputChannelNames[1]

        let availablePairs = channelStatus.availableOutputChannelPairs(forDeviceNamed: profile.audioDeviceName)
        guard let matchingPair = availablePairs.first(where: {
            $0.firstName.caseInsensitiveCompare(expectedFirst) == .orderedSame
                && $0.secondName.caseInsensitiveCompare(expectedSecond) == .orderedSame
        }) else {
            return "Aucune paire de canaux ne correspond à \(expectedFirst) / \(expectedSecond)"
        }

        do {
            try configurator.setPreferredOutputChannelPair(matchingPair, forDeviceNamed: profile.audioDeviceName)
            return nil
        } catch {
            return "\(error)"
        }
    }
}
