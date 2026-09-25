import Foundation

public struct DAWEntry: Codable, Equatable {
    public let name: String
    public let bundleID: String
    public let appPath: String?
    public let templatePath: String?

    public init(name: String, bundleID: String, appPath: String? = nil, templatePath: String?) {
        self.name = name
        self.bundleID = bundleID
        self.appPath = appPath
        self.templatePath = templatePath
    }
}

public struct Profile: Codable, Equatable {
    public let name: String
    public let deviceNameMatch: String
    public let audioDeviceName: String
    public let uadConsoleSession: String
    public let useIACDriver: Bool
    public let daws: [DAWEntry]

    public init(name: String, deviceNameMatch: String, audioDeviceName: String, uadConsoleSession: String, useIACDriver: Bool, daws: [DAWEntry]) {
        self.name = name
        self.deviceNameMatch = deviceNameMatch
        self.audioDeviceName = audioDeviceName
        self.uadConsoleSession = uadConsoleSession
        self.useIACDriver = useIACDriver
        self.daws = daws
    }
}

public struct ProfilesFile: Codable, Equatable {
    public let profiles: [Profile]

    public init(profiles: [Profile]) {
        self.profiles = profiles
    }
}
