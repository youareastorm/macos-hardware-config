import Foundation

public enum ProfileStoreError: Error, Equatable {
    case decodingFailed(String)
}

public final class ProfileStore {
    public static var defaultConfigURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/StudioSwitch/profiles.json")
    }

    public static let defaultProfilesFile = ProfilesFile(profiles: [
        Profile(
            name: "Home",
            deviceNameMatch: "Apollo Solo",
            uadConsoleSession: "~/Documents/Universal Audio/Sessions/home guit vox.uadmix",
            useIACDriver: false,
            daws: [
                DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: nil),
                DAWEntry(name: "Ableton Live 12 Suite", bundleID: "com.ableton.live", templatePath: nil)
            ]
        ),
        Profile(
            name: "Studio",
            deviceNameMatch: "Apollo",
            uadConsoleSession: "~/Documents/Universal Audio/Sessions/octo.uadmix",
            useIACDriver: false,
            daws: [
                DAWEntry(name: "Pro Tools", bundleID: "com.avid.ProTools", templatePath: nil),
                DAWEntry(name: "Cubase 15", bundleID: "com.steinberg.cubase15", templatePath: nil)
            ]
        )
    ])

    private let configURL: URL
    private let fileManager: FileManager

    public init(configURL: URL = ProfileStore.defaultConfigURL, fileManager: FileManager = .default) {
        self.configURL = configURL
        self.fileManager = fileManager
    }

    public func loadProfiles() throws -> [Profile] {
        if !fileManager.fileExists(atPath: configURL.path) {
            try ensureDefaultConfigExists()
        }
        let data = try Data(contentsOf: configURL)
        do {
            return try JSONDecoder().decode(ProfilesFile.self, from: data).profiles
        } catch {
            throw ProfileStoreError.decodingFailed("\(error)")
        }
    }

    public func ensureDefaultConfigExists() throws {
        guard !fileManager.fileExists(atPath: configURL.path) else { return }
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ProfileStore.defaultProfilesFile)
        try data.write(to: configURL)
    }
}
