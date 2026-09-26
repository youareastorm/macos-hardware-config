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
    public let expectedOutputDeviceNames: [String]
    /// Names of the two channels `audioDeviceName` should have as its default output pair, e.g.
    /// `["VIRTUAL 1", "VIRTUAL 2"]` on a UA Apollo routed to its software-return channels instead
    /// of its main outs. Distinct from `expectedOutputDeviceNames`, which combines separate
    /// CoreAudio devices — this checks a channel pair *within* a single device. Empty means the
    /// profile doesn't care which channel pair is active.
    public let expectedOutputChannelNames: [String]

    public init(
        name: String,
        deviceNameMatch: String,
        audioDeviceName: String,
        uadConsoleSession: String,
        useIACDriver: Bool,
        daws: [DAWEntry],
        expectedSampleRate: Double? = nil,
        expectedExternalDiskNames: [String] = [],
        expectedOutputDeviceNames: [String] = [],
        expectedOutputChannelNames: [String] = []
    ) {
        self.name = name
        self.deviceNameMatch = deviceNameMatch
        self.audioDeviceName = audioDeviceName
        self.uadConsoleSession = uadConsoleSession
        self.useIACDriver = useIACDriver
        self.daws = daws
        self.expectedSampleRate = expectedSampleRate
        self.expectedExternalDiskNames = expectedExternalDiskNames
        self.expectedOutputDeviceNames = expectedOutputDeviceNames
        self.expectedOutputChannelNames = expectedOutputChannelNames
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
        expectedOutputDeviceNames = try container.decodeIfPresent([String].self, forKey: .expectedOutputDeviceNames) ?? []
        expectedOutputChannelNames = try container.decodeIfPresent([String].self, forKey: .expectedOutputChannelNames) ?? []
    }
}

extension Profile {
    /// The single device StudioSwitch should set as default output for this profile: the lone
    /// entry when there's one, or the name of the combined Multi-Output Device it creates/reuses
    /// when there are several. Nil when the profile doesn't route output separately from its
    /// interface (audioDeviceName then serves as both input and output).
    public var outputDeviceTargetName: String? {
        switch expectedOutputDeviceNames.count {
        case 0: return nil
        case 1: return expectedOutputDeviceNames[0]
        default: return expectedOutputDeviceNames.joined(separator: " + ")
        }
    }
}

public struct ProfilesFile: Codable, Equatable {
    public let profiles: [Profile]

    public init(profiles: [Profile]) {
        self.profiles = profiles
    }
}
