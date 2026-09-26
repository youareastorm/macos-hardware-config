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
    public let expectedSampleRate: Double?
    public let expectedExternalDiskNames: [String]

    public init(
        name: String,
        deviceNameMatch: String,
        audioDeviceName: String,
        uadConsoleSession: String,
        useIACDriver: Bool,
        daws: [DAWEntry],
        expectedSampleRate: Double? = nil,
        expectedExternalDiskNames: [String] = []
    ) {
        self.name = name
        self.deviceNameMatch = deviceNameMatch
        self.audioDeviceName = audioDeviceName
        self.uadConsoleSession = uadConsoleSession
        self.useIACDriver = useIACDriver
        self.daws = daws
        self.expectedSampleRate = expectedSampleRate
        self.expectedExternalDiskNames = expectedExternalDiskNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        deviceNameMatch = try container.decode(String.self, forKey: .deviceNameMatch)
        audioDeviceName = try container.decode(String.self, forKey: .audioDeviceName)
        uadConsoleSession = try container.decode(String.self, forKey: .uadConsoleSession)
        useIACDriver = try container.decode(Bool.self, forKey: .useIACDriver)
        daws = try container.decode([DAWEntry].self, forKey: .daws)
        expectedSampleRate = try container.decodeIfPresent(Double.self, forKey: .expectedSampleRate)
        expectedExternalDiskNames = try container.decodeIfPresent([String].self, forKey: .expectedExternalDiskNames) ?? []
    }
}

public struct ProfilesFile: Codable, Equatable {
    public let profiles: [Profile]

    public init(profiles: [Profile]) {
        self.profiles = profiles
    }
}
