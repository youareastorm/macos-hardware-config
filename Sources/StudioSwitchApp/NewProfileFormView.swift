import Foundation
import SwiftUI
import StudioSwitchCore

struct NewProfileFormView: View {
    static let knownDAWs: [DAWEntry] = [
        DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: nil),
        DAWEntry(name: "Ableton Live 12 Suite", bundleID: "com.ableton.live", appPath: "/Applications/Ableton Live 12 Suite.app", templatePath: nil),
        DAWEntry(name: "Ableton Live 12 Standard", bundleID: "com.ableton.live", appPath: "/Applications/Ableton Live 12 Standard.app", templatePath: nil),
        DAWEntry(name: "Pro Tools", bundleID: "com.avid.ProTools", templatePath: nil),
        DAWEntry(name: "Cubase 15", bundleID: "com.steinberg.cubase15", templatePath: nil),
        DAWEntry(name: "Cubase 14", bundleID: "com.steinberg.cubase14", templatePath: nil),
        DAWEntry(name: "Cubase 13", bundleID: "com.steinberg.cubase13", templatePath: nil),
        DAWEntry(name: "Bitwig Studio", bundleID: "com.bitwig.studio", templatePath: nil)
    ]

    let hardwareModelProvider: HardwareModelProviding
    let onCancel: () -> Void
    let onSave: (Profile) -> Void

    @State private var name = ""
    @State private var deviceNameMatch = ""
    @State private var audioDeviceName = "Universal Audio Thunderbolt"
    @State private var uadConsoleSession = "~/Documents/Universal Audio/Sessions/"
    @State private var useIACDriver = false
    @State private var selectedDAWNames: Set<String> = []
    @State private var detectedModels: [String] = []
    @State private var expectedSampleRate = ""
    @State private var expectedExternalDiskNames = ""

    init(hardwareModelProvider: HardwareModelProviding = ThunderboltHardwareModelProvider(), onCancel: @escaping () -> Void, onSave: @escaping (Profile) -> Void) {
        self.hardwareModelProvider = hardwareModelProvider
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nouveau profil").font(.headline)

            TextField("Nom du profil", text: $name)
            TextField("Nom de l'appareil (détection)", text: $deviceNameMatch)

            if !detectedModels.isEmpty {
                Text("Détecté : \(detectedModels.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    ForEach(detectedModels, id: \.self) { model in
                        Button(model) { deviceNameMatch = model }
                            .font(.caption)
                    }
                }
            }

            TextField("Nom du device audio (routage)", text: $audioDeviceName)
            TextField("Session UAD Console (.uadmix)", text: $uadConsoleSession)
            Toggle("Activer IAC Driver", isOn: $useIACDriver)
            TextField("Fréquence attendue en Hz (optionnel)", text: $expectedSampleRate)
            TextField("Disques externes attendus (séparés par des virgules)", text: $expectedExternalDiskNames)

            Text("DAWs").font(.subheadline)
            ForEach(Self.knownDAWs, id: \.name) { daw in
                Toggle(daw.name, isOn: Binding(
                    get: { selectedDAWNames.contains(daw.name) },
                    set: { isOn in
                        if isOn {
                            selectedDAWNames.insert(daw.name)
                        } else {
                            selectedDAWNames.remove(daw.name)
                        }
                    }
                ))
            }

            HStack {
                Button("Annuler", action: onCancel)
                Spacer()
                Button("Enregistrer", action: save)
                    .disabled(name.isEmpty || deviceNameMatch.isEmpty)
            }
        }
        .onAppear { detectedModels = hardwareModelProvider.connectedModelNames() }
    }

    private func save() {
        let daws = Self.knownDAWs.filter { selectedDAWNames.contains($0.name) }
        let diskNames = expectedExternalDiskNames
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onSave(Profile(
            name: name,
            deviceNameMatch: deviceNameMatch,
            audioDeviceName: audioDeviceName,
            uadConsoleSession: uadConsoleSession,
            useIACDriver: useIACDriver,
            daws: daws,
            expectedSampleRate: Double(expectedSampleRate),
            expectedExternalDiskNames: diskNames
        ))
    }
}
