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

    private let profileStore = ProfileStore()
    private let activationController = ProfileActivationController(
        detector: AudioInterfaceDetector(),
        configurator: AudioMIDIConfigurator(),
        uadConsole: UADConsoleController()
    )
    private let dawLauncher = DAWLauncher()

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
                }
            }

            if let result = lastResult {
                Divider()
                statusText(for: result)
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
        } catch {
            loadError = "\(error)"
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

    @ViewBuilder
    private func statusText(for result: ProfileActivationResult) -> some View {
        if !result.deviceDetected {
            Text("\(result.profile.deviceNameMatch) non détecté").foregroundStyle(.red)
        } else {
            if let error = result.deviceConfigError {
                Text("Erreur audio : \(error)").foregroundStyle(.orange)
            }
            if let error = result.uadConsoleError {
                Text("Erreur UAD Console : \(error)").foregroundStyle(.orange)
            }
            if result.deviceConfigError == nil && result.uadConsoleError == nil {
                Text("\(result.profile.name) activé").foregroundStyle(.green)
            }
        }
    }
}
