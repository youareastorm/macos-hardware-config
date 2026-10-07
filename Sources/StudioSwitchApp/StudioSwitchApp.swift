import SwiftUI
import AppKit
import StudioSwitchCore

enum AutoActivationSetting {
    static let key = "autoActivationEnabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

@main
struct StudioSwitchApp: App {
    private let autoActivation: AutoActivationCoordinator
    @ObservedObject private var status = StatusMonitor.shared

    init() {
        FileActivationLogger.shared.log("StudioSwitch démarré")
        NSApplication.shared.setActivationPolicy(.accessory)

        let coordinator = AutoActivationCoordinator(
            loadProfiles: { try ProfileStore().loadProfiles() },
            detector: AudioInterfaceDetector(),
            isAudioDeviceOnline: { CoreAudioStatusProvider().isDeviceOnline(named: $0) },
            activator: ProfileActivationController(
                detector: AudioInterfaceDetector(),
                configurator: AudioMIDIConfigurator(),
                uadConsole: UADConsoleController(),
                uadMixer: UAMixerEngineController(),
                uadOfflineDevices: AppleScriptUADConsoleOfflineDevicesController(),
                logger: FileActivationLogger.shared
            ),
            isEnabled: { AutoActivationSetting.isEnabled },
            watcher: CoreAudioDeviceListWatcher(),
            logger: FileActivationLogger.shared,
            onActivation: { StatusMonitor.shared.recordActivation($0) }
        )
        coordinator.start()
        StatusMonitor.shared.start()
        autoActivation = coordinator
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            // A triangle as soon as a check isn't green or the last activation had an error.
            Image(systemName: status.needsAttention ? "exclamationmark.triangle.fill" : "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}
