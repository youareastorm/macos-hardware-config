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
            logger: FileActivationLogger.shared
        )
        coordinator.start()
        autoActivation = coordinator
    }

    var body: some Scene {
        MenuBarExtra("StudioSwitch", systemImage: "waveform") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
