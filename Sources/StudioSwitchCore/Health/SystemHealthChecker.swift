import Foundation

public final class SystemHealthChecker {
    private let audioStatus: AudioDeviceStatusProviding
    private let uadConsoleSession: UADConsoleSessionInspecting

    public init(
        audioStatus: AudioDeviceStatusProviding = CoreAudioStatusProvider(),
        uadConsoleSession: UADConsoleSessionInspecting = AppleScriptUADConsoleSessionInspector()
    ) {
        self.audioStatus = audioStatus
        self.uadConsoleSession = uadConsoleSession
    }

    /// Every check except external disks, which the menu bar renders as its own expandable
    /// button (see `MountedDiskInspecting`) rather than a colored-dot row. MIDI and USB power
    /// checks were dropped from the menu bar entirely; their providers remain available for
    /// future use but nothing here calls them anymore.
    public func check(for profile: Profile) -> [HealthCheckResult] {
        var results = [
            audioInterfaceResult(for: profile),
            outputRoutingResult(for: profile),
            uadConsoleResult(for: profile)
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
                return HealthCheckResult(label: "Sortie HP", status: .error("Haut-parleurs Mac non détectés"))
            }
            return HealthCheckResult(label: "Sortie HP", status: .ok)
        }

        guard let currentOutput = audioStatus.defaultOutputDeviceName() else {
            return HealthCheckResult(label: "Sortie HP", status: .error("Aucune sortie par défaut détectée"))
        }

        guard currentOutput.caseInsensitiveCompare(target) == .orderedSame else {
            return HealthCheckResult(label: "Sortie HP", status: .error("Sortie actuelle : \(currentOutput)"))
        }

        return HealthCheckResult(label: "Sortie HP", status: .ok)
    }

    private func uadConsoleResult(for profile: Profile) -> HealthCheckResult {
        guard let currentSession = uadConsoleSession.currentSessionName() else {
            return HealthCheckResult(label: "UAD Console", status: .error("UAD Console non lancé ou aucune session ouverte"))
        }

        let acceptedNames = profile.expectedUADConsoleSessionNames.isEmpty
            ? [expectedSessionName(fromPath: profile.uadConsoleSession)]
            : profile.expectedUADConsoleSessionNames
        guard acceptedNames.contains(where: { currentSession.localizedCaseInsensitiveContains($0) }) else {
            return HealthCheckResult(label: "UAD Console", status: .error("Session ouverte : \(currentSession)"))
        }

        return HealthCheckResult(label: "UAD Console", status: .ok)
    }

    private func expectedSessionName(fromPath path: String) -> String {
        (path as NSString).lastPathComponent.replacingOccurrences(of: ".uadmix", with: "")
    }
}
