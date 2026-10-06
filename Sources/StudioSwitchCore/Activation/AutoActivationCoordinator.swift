import Foundation

public protocol ProfileActivating {
    func activate(_ profile: Profile) -> ProfileActivationResult
}

extension ProfileActivationController: ProfileActivating {}

/// Activates the profile matching the connected hardware by itself — when an interface is
/// plugged in or powered on, and once at launch — instead of waiting for a click on the profile.
///
/// It only acts when the *matched profile changes* (including from "none" to one), never on every
/// device-list event: CoreAudio also reports unrelated changes (headphones, and the Multi-Output
/// Device this app creates itself), and re-applying the profile each time would undo manual
/// changes and risk feedback loops. A match requires both the hardware model (Thunderbolt) and
/// the profile's CoreAudio device to be online: the Thunderbolt listing can lag behind the audio
/// device in both directions, and activating before the audio device exists just fails.
public final class AutoActivationCoordinator {
    private let loadProfiles: () throws -> [Profile]
    private let detector: DeviceDetecting
    private let isAudioDeviceOnline: (String) -> Bool
    private let activator: ProfileActivating
    private let isEnabled: () -> Bool
    private let watcher: AudioDeviceListWatching
    private let debounce: TimeInterval

    private let queue = DispatchQueue(label: "com.simonrenard.studioswitch.autoactivation")
    private var lastActivatedProfileName: String?
    private var pendingEvaluation: DispatchWorkItem?

    public init(
        loadProfiles: @escaping () throws -> [Profile],
        detector: DeviceDetecting,
        isAudioDeviceOnline: @escaping (String) -> Bool,
        activator: ProfileActivating,
        isEnabled: @escaping () -> Bool,
        watcher: AudioDeviceListWatching,
        debounce: TimeInterval = 2
    ) {
        self.loadProfiles = loadProfiles
        self.detector = detector
        self.isAudioDeviceOnline = isAudioDeviceOnline
        self.activator = activator
        self.isEnabled = isEnabled
        self.watcher = watcher
        self.debounce = debounce
    }

    public func start() {
        watcher.start { [weak self] in self?.scheduleEvaluation() }
        queue.async { [weak self] in self?.evaluate() }
    }

    /// Collapses a burst of device-list events into one evaluation, once things settle.
    private func scheduleEvaluation() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingEvaluation?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.evaluate() }
            self.pendingEvaluation = work
            self.queue.asyncAfter(deadline: .now() + self.debounce, execute: work)
        }
    }

    func evaluate() {
        guard isEnabled() else { return }

        let profiles = (try? loadProfiles()) ?? []
        let matched = profiles.first {
            detector.matchingDeviceName(for: $0) != nil && isAudioDeviceOnline($0.audioDeviceName)
        }
        guard matched?.name != lastActivatedProfileName else { return }
        guard let matched else {
            lastActivatedProfileName = nil
            return
        }

        let result = activator.activate(matched)
        if result.deviceDetected && result.deviceConfigError == nil {
            lastActivatedProfileName = matched.name
        }
    }
}
