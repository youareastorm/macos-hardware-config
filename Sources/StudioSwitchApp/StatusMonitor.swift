import Foundation
import StudioSwitchCore

/// Keeps the menu-bar icon honest without opening the menu: re-runs the health checks for the
/// connected profile every minute (in the background — no UAD Console UI involved, one UA Mixer
/// Engine connection per pass) and remembers the last automatic activation's result.
final class StatusMonitor: ObservableObject {
    static let shared = StatusMonitor()

    @Published private(set) var needsAttention = false
    @Published private(set) var lastActivation: ProfileActivationResult?

    private var latestHealth: [HealthCheckResult] = []
    private let queue = DispatchQueue(label: "com.simonrenard.studioswitch.status")
    private var timer: DispatchSourceTimer?
    private let healthChecker = SystemHealthChecker(
        uadMixer: UAMixerEngineController(),
        uadOfflineDevices: AppleScriptUADConsoleOfflineDevicesController()
    )

    func start(interval: TimeInterval = 60) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.refreshHealth() }
        timer.resume()
        self.timer = timer
    }

    func recordActivation(_ result: ProfileActivationResult) {
        DispatchQueue.main.async {
            self.lastActivation = result
            self.update()
        }
        queue.async { [weak self] in self?.refreshHealth() }
    }

    func recordHealth(_ health: [HealthCheckResult]) {
        DispatchQueue.main.async {
            self.latestHealth = health
            self.update()
        }
    }

    private func refreshHealth() {
        let profiles = (try? ProfileStore().loadProfiles()) ?? []
        let detector = AudioInterfaceDetector()
        let audio = CoreAudioStatusProvider()
        guard let profile = profiles.first(where: { detector.matchingDeviceName(for: $0) != nil && audio.isDeviceOnline(named: $0.audioDeviceName) }) else {
            recordHealth([])
            return
        }
        recordHealth(healthChecker.check(for: profile))
    }

    private func update() {
        needsAttention = StatusEvaluation.needsAttention(health: latestHealth, lastActivation: lastActivation)
    }
}
