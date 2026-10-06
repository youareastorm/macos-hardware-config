import Foundation

public final class SystemHealthChecker {
    private let audioStatus: AudioDeviceStatusProviding
    private let uadMixer: UAMixerControlling?
    private let uadOfflineDevices: UADConsoleOfflineDevicesControlling?

    public init(
        audioStatus: AudioDeviceStatusProviding = CoreAudioStatusProvider(),
        uadMixer: UAMixerControlling? = nil,
        uadOfflineDevices: UADConsoleOfflineDevicesControlling? = nil
    ) {
        self.audioStatus = audioStatus
        self.uadMixer = uadMixer
        self.uadOfflineDevices = uadOfflineDevices
    }

    /// Audio checks, plus the UAD Console clock, monitor level and offline-units setting when the
    /// profile asks for them. MIDI, USB power, external disks and the UAD session row were dropped
    /// from the menu bar; their providers remain in the codebase but nothing here calls them.
    public func check(for profile: Profile) -> [HealthCheckResult] {
        var results = [
            audioInterfaceResult(for: profile),
            outputRoutingResult(for: profile)
        ]
        if let channelsResult = outputChannelsResult(for: profile) {
            results.append(channelsResult)
        }
        results += uadMixerResults(for: profile)
        if let offlineResult = offlineDevicesResult(for: profile) {
            results.append(offlineResult)
        }
        return results
    }

    /// One engine read for both rows (see `UAMixerEngineController` on why connections are kept few).
    private func uadMixerResults(for profile: Profile) -> [HealthCheckResult] {
        guard let uadMixer, profile.expectedClockSource != nil || profile.expectedMonitorLevel != nil else { return [] }

        let state: UAMixerState
        do {
            state = try uadMixer.currentState()
        } catch {
            let unreadable = HealthStatus.error("Moteur UA illisible : \(error)")
            return [
                profile.expectedClockSource.map { _ in HealthCheckResult(label: "Clock", status: unreadable) },
                profile.expectedMonitorLevel.map { _ in HealthCheckResult(label: "Volume moniteur", status: unreadable) }
            ].compactMap { $0 }
        }

        var results: [HealthCheckResult] = []
        if let expected = profile.expectedClockSource {
            let matches = state.clockSource.caseInsensitiveCompare(expected) == .orderedSame
            results.append(HealthCheckResult(label: "Clock", status: matches ? .ok : .error("Actuellement : \(state.clockSource)")))
        }
        if let expected = profile.expectedMonitorLevel {
            let matches = abs(state.monitorLevel - expected) < 0.25
            results.append(HealthCheckResult(
                label: "Volume moniteur",
                status: matches ? .ok : .warning("\(Self.decibels(state.monitorLevel)) au lieu de \(Self.decibels(expected))")
            ))
        }
        return results
    }

    private func offlineDevicesResult(for profile: Profile) -> HealthCheckResult? {
        guard let uadOfflineDevices, profile.hideUADOfflineDevices else { return nil }
        guard let showing = try? uadOfflineDevices.isShowingOfflineDevices() else {
            return HealthCheckResult(label: "Cartes hors ligne", status: .warning("Préférence de UAD Console illisible"))
        }
        return HealthCheckResult(label: "Cartes hors ligne", status: showing ? .error("Affichées (View > Offline Devices coché)") : .ok)
    }

    private static func decibels(_ value: Double) -> String {
        String(format: "%g dB", value)
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
}
