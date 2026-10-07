import Foundation

public struct ProfileActivationResult: Equatable {
    public let profile: Profile
    public let deviceDetected: Bool
    public let deviceConfigError: String?
    public let outputRoutingError: String?
    public let channelPairError: String?
    public let uadConsoleError: String?
    public var uadOfflineDevicesError: String? = nil
    public var uadMixerError: String? = nil
}

public final class ProfileActivationController {
    private let detector: DeviceDetecting
    private let configurator: AudioMIDIConfiguring
    private let multiOutputProvider: MultiOutputDeviceProviding
    private let channelStatus: AudioDeviceStatusProviding
    private let uadConsole: UADConsoleSessionEnsuring?
    private let uadMixer: UAMixerControlling?
    private let uadOfflineDevices: UADConsoleOfflineDevicesControlling?
    private let logger: ActivationLogging

    public init(
        detector: DeviceDetecting,
        configurator: AudioMIDIConfiguring,
        multiOutputProvider: MultiOutputDeviceProviding = CoreAudioMultiOutputDeviceProvider(),
        channelStatus: AudioDeviceStatusProviding = CoreAudioStatusProvider(),
        uadConsole: UADConsoleSessionEnsuring? = nil,
        uadMixer: UAMixerControlling? = nil,
        uadOfflineDevices: UADConsoleOfflineDevicesControlling? = nil,
        logger: ActivationLogging = NoActivationLogger()
    ) {
        self.detector = detector
        self.configurator = configurator
        self.multiOutputProvider = multiOutputProvider
        self.channelStatus = channelStatus
        self.uadConsole = uadConsole
        self.uadMixer = uadMixer
        self.uadOfflineDevices = uadOfflineDevices
        self.logger = logger
    }

    public func activate(_ profile: Profile) -> ProfileActivationResult {
        guard let hardwareName = detector.matchingDeviceName(for: profile) else {
            logger.log("Activation de \(profile.name) : \(profile.deviceNameMatch) non détecté")
            return ProfileActivationResult(profile: profile, deviceDetected: false, deviceConfigError: nil, outputRoutingError: nil, channelPairError: nil, uadConsoleError: nil)
        }
        let started = Date()
        logger.log("Activation de \(profile.name) (carte : \(hardwareName))")

        let deviceConfigError = step("Entrée/sortie par défaut → \(profile.audioDeviceName)") {
            if profile.outputDeviceTargetName != nil {
                try configurator.setDefaultInputDevice(named: profile.audioDeviceName)
            } else {
                try configurator.setDefaultDevice(named: profile.audioDeviceName)
            }
            if profile.useIACDriver {
                try configurator.enableIACDriverIfPresent()
            }
        }

        var outputRoutingError: String?
        if let target = profile.outputDeviceTargetName {
            outputRoutingError = step("Sortie → \(target)") {
                if profile.expectedOutputDeviceNames.count > 1 {
                    try multiOutputProvider.ensureMultiOutputDevice(named: target, subDeviceNames: profile.expectedOutputDeviceNames)
                }
                try configurator.setDefaultOutputDevice(named: target)
            }
        }

        var channelPairError: String?
        if profile.expectedOutputChannelNames.count == 2 {
            logPair("avant", profile)
            channelPairError = step("Paire de sortie → \(profile.expectedOutputChannelNames.joined(separator: " / "))") {
                if let error = applyOutputChannelPair(for: profile) { throw ActivationStepError(message: error) }
            }
            logPair("après", profile)
        }

        let uadConsoleError = step("Session UAD Console → \((profile.uadConsoleSession as NSString).lastPathComponent)") {
            try uadConsole?.ensureSessionOpen(atPath: profile.uadConsoleSession)
        }

        // After the session: hiding offline units needs UAD Console running, and the mixer
        // settings go last so a freshly loaded session can't override them.
        var uadOfflineDevicesError: String?
        if profile.hideUADOfflineDevices, let uadOfflineDevices {
            logger.log("  Offline Devices avant : \(describe { try uadOfflineDevices.isShowingOfflineDevices() ? "coché" : "décoché" })")
            uadOfflineDevicesError = step("Masquer les cartes hors ligne") {
                try uadOfflineDevices.hideOfflineDevices()
            }
        }

        var uadMixerError: String?
        if profile.expectedClockSource != nil || profile.expectedMonitorLevel != nil, let uadMixer {
            logger.log("  moteur UA avant : \(describe { Self.describe(try uadMixer.currentState()) })")
            uadMixerError = step("Clock → \(profile.expectedClockSource ?? "inchangée"), moniteur → \(profile.expectedMonitorLevel.map { "\($0) dB" } ?? "inchangé")") {
                try uadMixer.apply(clockSource: profile.expectedClockSource, monitorLevel: profile.expectedMonitorLevel)
            }
            logger.log("  moteur UA après : \(describe { Self.describe(try uadMixer.currentState()) })")
        }

        // Seen on real hardware (2026-10-07, after a reboot): the pair set above was back to
        // MON L / MON R once UAD Console had started — its launch restarts the UA Mixer Engine.
        // So it's checked again after the UAD steps and put back if it moved.
        if profile.expectedOutputChannelNames.count == 2, channelPairError == nil {
            let current = channelStatus.outputChannelNames(forDeviceNamed: profile.audioDeviceName)
            logger.log("  paire après UAD : \(current.map { $0.joined(separator: " / ") } ?? "illisible")")
            let moved = current.map { names in
                names.count != 2 || !zip(names, profile.expectedOutputChannelNames).allSatisfy {
                    $0.caseInsensitiveCompare($1) == .orderedSame
                }
            } ?? false
            if moved {
                channelPairError = step("Paire de sortie remise après UAD Console") {
                    if let error = applyOutputChannelPair(for: profile) { throw ActivationStepError(message: error) }
                }
            }
            logPair("à la fin", profile)
        }
        logger.log("Activation de \(profile.name) terminée en \(Self.seconds(since: started))")

        return ProfileActivationResult(profile: profile, deviceDetected: true, deviceConfigError: deviceConfigError, outputRoutingError: outputRoutingError, channelPairError: channelPairError, uadConsoleError: uadConsoleError, uadOfflineDevicesError: uadOfflineDevicesError, uadMixerError: uadMixerError)
    }

    /// Runs one activation step, logs its outcome and duration, and returns its error message.
    private func step(_ name: String, _ body: () throws -> Void) -> String? {
        let started = Date()
        do {
            try body()
            logger.log("  \(name) : ok (\(Self.seconds(since: started)))")
            return nil
        } catch {
            let message = (error as? ActivationStepError)?.message ?? "\(error)"
            logger.log("  \(name) : ÉCHEC (\(Self.seconds(since: started))) \(message)")
            return message
        }
    }

    private func logPair(_ moment: String, _ profile: Profile) {
        let current = channelStatus.outputChannelNames(forDeviceNamed: profile.audioDeviceName)
        logger.log("  paire \(moment) : \(current.map { $0.joined(separator: " / ") } ?? "illisible")")
    }

    private func describe(_ read: () throws -> String) -> String {
        do { return try read() } catch { return "illisible (\(error))" }
    }

    private static func describe(_ state: UAMixerState) -> String {
        "clock \(state.clockSource), moniteur \(String(format: "%g", state.monitorLevel)) dB"
    }

    private static func seconds(since date: Date) -> String {
        String(format: "%.1f s", Date().timeIntervalSince(date))
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

private struct ActivationStepError: Error {
    let message: String
}
