public final class SystemHealthChecker {
    private let audioStatus: AudioDeviceStatusProviding
    private let midiStatus: MIDIStatusProviding
    private let storageProvider: ExternalStorageProviding

    public init(
        audioStatus: AudioDeviceStatusProviding = CoreAudioStatusProvider(),
        midiStatus: MIDIStatusProviding = CoreMIDIStatusProvider(),
        storageProvider: ExternalStorageProviding = FileManagerExternalStorageProvider()
    ) {
        self.audioStatus = audioStatus
        self.midiStatus = midiStatus
        self.storageProvider = storageProvider
    }

    public func check(for profile: Profile) -> [HealthCheckResult] {
        [
            audioInterfaceResult(for: profile),
            speakersResult(),
            midiResult(),
            externalDisksResult(for: profile)
        ]
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

        let isDefaultOutput = audioStatus.defaultOutputDeviceName()?.caseInsensitiveCompare(profile.audioDeviceName) == .orderedSame
        let isDefaultInput = audioStatus.defaultInputDeviceName()?.caseInsensitiveCompare(profile.audioDeviceName) == .orderedSame
        guard isDefaultOutput, isDefaultInput else {
            return HealthCheckResult(label: "Interface audio", status: .warning("N'est pas le device par défaut"))
        }

        return HealthCheckResult(label: "Interface audio", status: .ok)
    }

    private func speakersResult() -> HealthCheckResult {
        guard audioStatus.builtInOutputDeviceName() != nil else {
            return HealthCheckResult(label: "Haut-parleurs Mac", status: .error("Non détectés"))
        }
        return HealthCheckResult(label: "Haut-parleurs Mac", status: .ok)
    }

    private func midiResult() -> HealthCheckResult {
        guard !midiStatus.onlineDeviceNames().isEmpty else {
            return HealthCheckResult(label: "MIDI", status: .warning("Aucun périphérique en ligne"))
        }
        return HealthCheckResult(label: "MIDI", status: .ok)
    }

    private func externalDisksResult(for profile: Profile) -> HealthCheckResult {
        guard !profile.expectedExternalDiskNames.isEmpty else {
            return HealthCheckResult(label: "Disques externes", status: .ok)
        }

        let mounted = Set(storageProvider.mountedExternalVolumeNames())
        let missing = profile.expectedExternalDiskNames.filter { !mounted.contains($0) }
        guard missing.isEmpty else {
            return HealthCheckResult(label: "Disques externes", status: .error("Manquants : \(missing.joined(separator: ", "))"))
        }

        return HealthCheckResult(label: "Disques externes", status: .ok)
    }
}
