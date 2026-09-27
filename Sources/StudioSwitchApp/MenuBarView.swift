import SwiftUI
import AppKit
import StudioSwitchCore

struct MenuBarView: View {
    @State private var profiles: [Profile] = []
    @State private var activeProfile: Profile?
    @State private var lastResult: ProfileActivationResult?
    @State private var loadError: String?
    @State private var dawLaunchMessage: String?
    @State private var showingNewProfileForm = false
    @State private var saveError: String?
    @State private var healthResults: [HealthCheckResult] = []
    @State private var healthProfile: Profile?
    @State private var rowOptions: [String: [String]] = [:]
    @State private var selections: [String: String] = [:]
    @State private var uadSessions: [UADSessionFile] = []
    @State private var channelPairs: [ChannelPair] = []
    @State private var actionMessage: String?

    private let profileStore = ProfileStore()
    private let detector: DeviceDetecting = AudioInterfaceDetector()
    private let activationController = ProfileActivationController(
        detector: AudioInterfaceDetector(),
        configurator: AudioMIDIConfigurator(),
        uadConsole: UADConsoleController()
    )
    private let dawLauncher = DAWLauncher()
    private let healthChecker = SystemHealthChecker()

    private let audioDeviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider()
    private let audioStatus: AudioDeviceStatusProviding = CoreAudioStatusProvider()
    private let audioConfigurator: AudioMIDIConfiguring = AudioMIDIConfigurator()
    private let uadConsoleSessionInspector: UADConsoleSessionInspecting = AppleScriptUADConsoleSessionInspector()
    private let uadSessionLister: UADSessionListing = FileManagerUADSessionLister()
    private let uadConsole: UADSessionOpening = UADConsoleController()
    private let appLocator: AppLocating = WorkspaceAppLocator()
    private let appLauncher: AppLaunching = WorkspaceAppLauncher()

    private static let pickerWidth: CGFloat = 150
    private static let audioMIDISetupBundleID = "com.apple.audio.AudioMIDISetup"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let loadError {
                Text("Erreur de config : \(loadError)").foregroundStyle(.red)
            }

            ForEach(Array(profiles.enumerated()), id: \.offset) { _, profile in
                Button(profile.name) {
                    dawLaunchMessage = nil
                    lastResult = activationController.activate(profile)
                    activeProfile = lastResult?.deviceDetected == true ? profile : nil
                    refreshHealth(for: profile)
                }
            }

            if let result = lastResult {
                Divider()
                statusText(for: result)
            }

            if !healthResults.isEmpty {
                Divider()
                healthIndicators
            }

            if let activeProfile {
                Divider()
                ForEach(Array(activeProfile.daws.enumerated()), id: \.offset) { _, daw in
                    Button(daw.name) {
                        launchDAW(daw)
                    }
                }
                if let dawLaunchMessage {
                    Text(dawLaunchMessage).foregroundStyle(.orange)
                }
            }

            Divider()

            if showingNewProfileForm {
                NewProfileFormView(
                    onCancel: { showingNewProfileForm = false },
                    onSave: { profile in
                        saveNewProfile(profile)
                    }
                )
                if let saveError {
                    Text("Erreur d'enregistrement : \(saveError)").foregroundStyle(.red)
                }
            } else {
                Button("Nouveau profil…") {
                    saveError = nil
                    showingNewProfileForm = true
                }
            }

            Divider()
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .onAppear(perform: loadProfiles)
    }

    private func loadProfiles() {
        do {
            profiles = try profileStore.loadProfiles()
            refreshHealthForConnectedProfile()
        } catch {
            loadError = "\(error)"
        }
    }

    /// Shows health indicators as soon as the app opens, for whichever profile matches the
    /// currently connected hardware — read-only (no device switching, no UAD Console opening),
    /// unlike clicking a profile button.
    private func refreshHealthForConnectedProfile() {
        guard let matched = profiles.first(where: { detector.matchingDeviceName(for: $0) != nil }) else { return }
        refreshHealth(for: matched)
    }

    private func refreshHealth(for profile: Profile) {
        healthResults = healthChecker.check(for: profile)
        healthProfile = profile
        actionMessage = nil
        refreshRowOptions(for: profile)
    }

    private func refreshRowOptions(for profile: Profile) {
        let connectedDevices = audioDeviceProvider.connectedDeviceNames().sorted()

        rowOptions["Interface audio"] = connectedDevices
        selections["Interface audio"] = audioStatus.defaultInputDeviceName() ?? profile.audioDeviceName

        rowOptions["Sortie HP"] = connectedDevices
        selections["Sortie HP"] = audioStatus.defaultOutputDeviceName() ?? profile.audioDeviceName

        uadSessions = uadSessionLister.listSessions()
        let currentSessionTitle = uadConsoleSessionInspector.currentSessionName()
        rowOptions["UAD Console"] = uadSessions.map(\.name)
        selections["UAD Console"] = uadSessions.first { currentSessionTitle?.localizedCaseInsensitiveContains($0.name) == true }?.name
            ?? uadSessions.first?.name ?? ""

        if profile.expectedOutputChannelNames.isEmpty {
            channelPairs = []
        } else {
            channelPairs = audioStatus.availableOutputChannelPairs(forDeviceNamed: profile.audioDeviceName)
            rowOptions["Canaux de sortie"] = channelPairs.map(\.displayName)
            if let current = audioStatus.outputChannelNames(forDeviceNamed: profile.audioDeviceName), current.count == 2 {
                selections["Canaux de sortie"] = "\(current[0]) / \(current[1])"
            } else {
                selections["Canaux de sortie"] = channelPairs.first?.displayName ?? ""
            }
        }
    }

    private func binding(forLabel label: String, profile: Profile) -> Binding<String> {
        Binding(
            get: { selections[label] ?? "" },
            set: { newValue in
                selections[label] = newValue
                applySelection(label: label, value: newValue, profile: profile)
            }
        )
    }

    private func applySelection(label: String, value: String, profile: Profile) {
        actionMessage = nil
        do {
            switch label {
            case "Interface audio":
                try audioConfigurator.setDefaultInputDevice(named: value)
                if profile.outputDeviceTargetName == nil {
                    try audioConfigurator.setDefaultOutputDevice(named: value)
                }
            case "Sortie HP":
                try audioConfigurator.setDefaultOutputDevice(named: value)
            case "UAD Console":
                if let session = uadSessions.first(where: { $0.name == value }) {
                    try uadConsole.openSession(atPath: session.path)
                }
            case "Canaux de sortie":
                if let pair = channelPairs.first(where: { $0.displayName == value }) {
                    try audioConfigurator.setPreferredOutputChannelPair(pair, forDeviceNamed: profile.audioDeviceName)
                }
            default:
                break
            }
        } catch {
            actionMessage = "Échec de l'action sur \(label) : \(error)"
        }
        refreshHealth(for: profile)
    }

    private func openUADConsole(profile: Profile) {
        actionMessage = nil
        do {
            try uadConsole.openSession(atPath: profile.uadConsoleSession)
        } catch {
            actionMessage = "Échec de l'ouverture d'UAD Console : \(error)"
        }
        refreshHealth(for: profile)
    }

    private func openAudioMIDISetup() {
        actionMessage = nil
        guard let appURL = appLocator.applicationURL(forBundleID: Self.audioMIDISetupBundleID) else {
            actionMessage = "Configuration audio et MIDI introuvable"
            return
        }
        do {
            try appLauncher.launchApplication(at: appURL)
        } catch {
            actionMessage = "Échec de l'ouverture de Configuration audio et MIDI : \(error)"
        }
    }

    private func saveNewProfile(_ profile: Profile) {
        do {
            try profileStore.save(profile)
            saveError = nil
            showingNewProfileForm = false
            loadProfiles()
        } catch {
            saveError = "\(error)"
        }
    }

    private func launchDAW(_ daw: DAWEntry) {
        do {
            switch try dawLauncher.launch(daw) {
            case .launched:
                dawLaunchMessage = nil
            case .launchedWithoutTemplate(let path):
                dawLaunchMessage = "\(daw.name) lancé sans le template (introuvable : \(path))"
            }
        } catch {
            dawLaunchMessage = "Échec du lancement de \(daw.name) : \(error)"
        }
    }

    private var healthIndicators: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let healthProfile {
                ForEach(healthResults) { result in
                    healthRow(result, profile: healthProfile)
                }
            }
            if let actionMessage {
                Text(actionMessage).font(.caption).foregroundStyle(.orange)
            }
            if let activeProfile {
                Button("Actualiser") {
                    refreshHealth(for: activeProfile)
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func healthRow(_ result: HealthCheckResult, profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                rowLabel(result, profile: profile)
                Spacer()
                Picker("", selection: binding(forLabel: result.label, profile: profile)) {
                    ForEach(rowOptions[result.label] ?? [], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: Self.pickerWidth, alignment: .trailing)
            }
            if let detail = result.info ?? detail(for: result.status) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }
        }
    }

    /// The dot + name is plain text for most rows, but for "UAD Console" and "Sortie HP" it's
    /// also a button: clicking the name opens the matching native macOS tool directly, while the
    /// picker on the right still lets you pick a value the way every other row does.
    @ViewBuilder
    private func rowLabel(_ result: HealthCheckResult, profile: Profile) -> some View {
        switch result.label {
        case "UAD Console":
            Button { openUADConsole(profile: profile) } label: { rowLabelContent(result) }
                .buttonStyle(.plain)
        case "Sortie HP":
            Button { openAudioMIDISetup() } label: { rowLabelContent(result) }
                .buttonStyle(.plain)
        default:
            rowLabelContent(result)
        }
    }

    private func rowLabelContent(_ result: HealthCheckResult) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: result.status))
                .frame(width: 8, height: 8)
            Text(result.label)
        }
    }

    private func color(for status: HealthStatus) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }

    private func detail(for status: HealthStatus) -> String? {
        switch status {
        case .ok: return nil
        case .warning(let message), .error(let message): return message
        }
    }

    @ViewBuilder
    private func statusText(for result: ProfileActivationResult) -> some View {
        if !result.deviceDetected {
            Text("\(result.profile.deviceNameMatch) non détecté").foregroundStyle(.red)
        } else {
            if let error = result.deviceConfigError {
                Text("Erreur audio : \(error)").foregroundStyle(.orange)
            }
            if let error = result.outputRoutingError {
                Text("Erreur sortie audio : \(error)").foregroundStyle(.orange)
            }
            if let error = result.uadConsoleError {
                Text("Erreur UAD Console : \(error)").foregroundStyle(.orange)
            }
            if result.deviceConfigError == nil && result.outputRoutingError == nil && result.uadConsoleError == nil {
                Text("\(result.profile.name) activé").foregroundStyle(.green)
            }
        }
    }
}
