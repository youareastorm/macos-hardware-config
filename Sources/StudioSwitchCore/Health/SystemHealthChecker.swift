import Foundation

public final class SystemHealthChecker {
    private let audioStatus: AudioDeviceStatusProviding
    private let midiStatus: MIDIStatusProviding
    private let uadConsoleSession: UADConsoleSessionInspecting
    private let usbPower: USBPowerInspecting
    private let usbPowerFaultDetector: USBPowerFaultDetecting

    /// How far back the "Alimentation USB" check looks in the kernel log for power-fault signs.
    private static let usbLogWindow: TimeInterval = 15 * 60

    public init(
        audioStatus: AudioDeviceStatusProviding = CoreAudioStatusProvider(),
        midiStatus: MIDIStatusProviding = CoreMIDIStatusProvider(),
        uadConsoleSession: UADConsoleSessionInspecting = AppleScriptUADConsoleSessionInspector(),
        usbPower: USBPowerInspecting = SystemProfilerUSBPowerProvider(),
        usbPowerFaultDetector: USBPowerFaultDetecting = KernelLogUSBPowerFaultDetector()
    ) {
        self.audioStatus = audioStatus
        self.midiStatus = midiStatus
        self.uadConsoleSession = uadConsoleSession
        self.usbPower = usbPower
        self.usbPowerFaultDetector = usbPowerFaultDetector
    }

    /// Every check except external disks, which the menu bar renders as its own expandable
    /// button (see `MountedDiskInspecting`) rather than a colored-dot row.
    public func check(for profile: Profile) -> [HealthCheckResult] {
        var results = [
            audioInterfaceResult(for: profile),
            outputRoutingResult(for: profile),
            midiResult(),
            uadConsoleResult(for: profile),
            usbPowerResult()
        ]
        if let channelsResult = outputChannelsResult(for: profile) {
            results.append(channelsResult)
        }
        return results
    }

    private func outputChannelsResult(for profile: Profile) -> HealthCheckResult? {
        guard !profile.expectedOutputChannelNames.isEmpty else { return nil }

        guard let current = audioStatus.outputChannelNames(forDeviceNamed: profile.audioDeviceName) else {
            return HealthCheckResult(label: "Canaux de sortie", status: .error("Impossible de lire les canaux de \(profile.audioDeviceName)"))
        }

        let matches = current.count == profile.expectedOutputChannelNames.count
            && zip(current, profile.expectedOutputChannelNames).allSatisfy { $0.caseInsensitiveCompare($1) == .orderedSame }
        guard matches else {
            return HealthCheckResult(label: "Canaux de sortie", status: .error("Actuellement : \(current.joined(separator: ", "))"))
        }

        return HealthCheckResult(label: "Canaux de sortie", status: .ok)
    }

    private func audioInterfaceResult(for profile: Profile) -> HealthCheckResult {
        guard audioStatus.isDeviceOnline(named: profile.audioDeviceName) else {
            return HealthCheckResult(label: "Interface audio", status: .error("\(profile.audioDeviceName) non détectée"))
        }

        if let expectedRate = profile.expectedSampleRate,
           let actualRate = audioStatus.nominalSampleRate(forDeviceNamed: profile.audioDeviceName),
           actualRate != expectedRate {
            return HealthCheckResult(label: "Interface audio", status: .warning("\(Int(actualRate)) Hz au lieu de \(Int(expectedRate)) Hz"))
        }

        let isDefaultInput = audioStatus.defaultInputDeviceName()?.caseInsensitiveCompare(profile.audioDeviceName) == .orderedSame
        guard isDefaultInput else {
            return HealthCheckResult(label: "Interface audio", status: .warning("N'est pas l'entrée par défaut"))
        }

        if profile.outputDeviceTargetName == nil {
            let isDefaultOutput = audioStatus.defaultOutputDeviceName()?.caseInsensitiveCompare(profile.audioDeviceName) == .orderedSame
            guard isDefaultOutput else {
                return HealthCheckResult(label: "Interface audio", status: .warning("N'est pas la sortie par défaut"))
            }
        }

        return HealthCheckResult(label: "Interface audio", status: .ok)
    }

    private func outputRoutingResult(for profile: Profile) -> HealthCheckResult {
        guard let target = profile.outputDeviceTargetName else {
            guard audioStatus.builtInOutputDeviceName() != nil else {
                return HealthCheckResult(label: "Sorties audio", status: .error("Haut-parleurs Mac non détectés"))
            }
            return HealthCheckResult(label: "Sorties audio", status: .ok)
        }

        guard let currentOutput = audioStatus.defaultOutputDeviceName() else {
            return HealthCheckResult(label: "Sorties audio", status: .error("Aucune sortie par défaut détectée"))
        }

        guard currentOutput.caseInsensitiveCompare(target) == .orderedSame else {
            return HealthCheckResult(label: "Sorties audio", status: .error("Sortie actuelle : \(currentOutput)"))
        }

        return HealthCheckResult(label: "Sorties audio", status: .ok)
    }

    private func midiResult() -> HealthCheckResult {
        guard !midiStatus.onlineDeviceNames().isEmpty else {
            return HealthCheckResult(label: "MIDI", status: .warning("Aucun périphérique en ligne"))
        }
        return HealthCheckResult(label: "MIDI", status: .ok)
    }

    private func uadConsoleResult(for profile: Profile) -> HealthCheckResult {
        guard let currentSession = uadConsoleSession.currentSessionName() else {
            return HealthCheckResult(label: "UAD Console", status: .error("UAD Console non lancé ou aucune session ouverte"))
        }

        let expectedName = expectedSessionName(fromPath: profile.uadConsoleSession)
        guard currentSession.localizedCaseInsensitiveContains(expectedName) else {
            return HealthCheckResult(label: "UAD Console", status: .error("Session ouverte : \(currentSession)"))
        }

        return HealthCheckResult(label: "UAD Console", status: .ok)
    }

    private func expectedSessionName(fromPath path: String) -> String {
        (path as NSString).lastPathComponent.replacingOccurrences(of: ".uadmix", with: "")
    }

    private func usbPowerResult() -> HealthCheckResult {
        let incidents = usbPowerFaultDetector.recentPowerIncidents(within: Self.usbLogWindow)
        if !incidents.isEmpty {
            let preview = incidents.suffix(3).map(\.line).joined(separator: " | ")
            return HealthCheckResult(
                label: "Alimentation USB",
                status: .error("\(incidents.count) évènement(s) suspect(s) dans les 15 dernières minutes"),
                info: preview
            )
        }

        switch usbPower.checkPower() {
        case .ok(let details):
            return HealthCheckResult(label: "Alimentation USB", status: .ok, info: details.isEmpty ? nil : details.joined(separator: ", "))
        case .unavailable:
            return HealthCheckResult(label: "Alimentation USB", status: .warning("Impossible de vérifier (system_profiler n'a rien renvoyé)"))
        }
    }
}
