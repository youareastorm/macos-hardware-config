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
        NSApplication.shared.setActivationPolicy(.accessory)

        let coordinator = AutoActivationCoordinator(
            loadProfiles: { try ProfileStore().loadProfiles() },
            detector: AudioInterfaceDetector(),
            isAudioDeviceOnline: { CoreAudioStatusProvider().isDeviceOnline(named: $0) },
            activator: ProfileActivationController(detector: AudioInterfaceDetector(), configurator: AudioMIDIConfigurator(), uadConsole: UADConsoleController()),
            isEnabled: { AutoActivationSetting.isEnabled },
            watcher: CoreAudioDeviceListWatcher()
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
