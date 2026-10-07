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
    private let logger: ActivationLogging

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
        debounce: TimeInterval = 2,
        logger: ActivationLogging = NoActivationLogger()
    ) {
        self.loadProfiles = loadProfiles
        self.detector = detector
        self.isAudioDeviceOnline = isAudioDeviceOnline
        self.activator = activator
        self.isEnabled = isEnabled
        self.watcher = watcher
        self.debounce = debounce
        self.logger = logger
    }

    public func start() {
        watcher.start { [weak self] in self?.scheduleEvaluation() }
        queue.async { [weak self] in self?.evaluate(trigger: "lancement") }
    }

    /// Collapses a burst of device-list events into one evaluation, once things settle.
    private func scheduleEvaluation() {
        queue.async { [weak self] in
            guard let self else { return }
            self.logger.log("Changement de périphériques signalé")
            self.pendingEvaluation?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.evaluate(trigger: "changement de périphériques") }
            self.pendingEvaluation = work
            self.queue.asyncAfter(deadline: .now() + self.debounce, execute: work)
        }
    }

    /// Lets queued (not debounced) work finish (for tests).
    func waitForPendingWork() {
        queue.sync {}
    }

    func evaluate(trigger: String = "manuel") {
        logger.log("Évaluation (\(trigger))")
        guard isEnabled() else {
            logger.log("  bascule auto désactivée, rien à faire")
            return
        }

        let profiles: [Profile]
        do {
            profiles = try loadProfiles()
        } catch {
            logger.log("  lecture des profils impossible : \(error)")
            profiles = []
        }

        var matched: Profile?
        for profile in profiles {
            let hardware = detector.matchingDeviceName(for: profile) != nil
            let audioOnline = isAudioDeviceOnline(profile.audioDeviceName)
            logger.log("  \(profile.name) : carte \(hardware ? "détectée" : "non détectée"), périphérique audio \(audioOnline ? "en ligne" : "hors ligne")")
            if matched == nil && hardware && audioOnline { matched = profile }
        }

        guard matched?.name != lastActivatedProfileName else {
            logger.log(matched.map { "  \($0.name) déjà actif, rien à faire" } ?? "  aucun profil prêt")
            return
        }
        guard let matched else {
            logger.log("  aucun profil prêt")
            lastActivatedProfileName = nil
            return
        }

        let result = activator.activate(matched)
        if result.deviceDetected && result.deviceConfigError == nil {
            lastActivatedProfileName = matched.name
        } else {
            logger.log("  \(matched.name) n'a pas pu être configuré, nouvel essai au prochain changement")
        }
    }
}
