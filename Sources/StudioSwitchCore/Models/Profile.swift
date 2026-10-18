import Foundation

public struct DAWEntry: Codable, Equatable {
    public let name: String
    public let bundleID: String
    public let appPath: String?
    public let templatePath: String?
    /// Name of the icon shipped in the app bundle (`Contents/Resources/DAWIcons/daw-<icon>.png`),
    /// e.g. `"cubase"`. Without it the menu falls back to the application's own icon.
    public let icon: String?

    public init(name: String, bundleID: String, appPath: String? = nil, templatePath: String?, icon: String? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.appPath = appPath
        self.templatePath = templatePath
        self.icon = icon
    }
}

public struct Profile: Codable, Equatable {
    public let name: String
    public let deviceNameMatch: String
    public let audioDeviceName: String
    /// The `.uadmix` session UAD Console should have open. `nil` (e.g. a Bluetooth headset) skips
    /// every UAD Console step.
    public let uadConsoleSession: String?
    public let daws: [DAWEntry]
    public let expectedSampleRate: Double?
    /// Names of the two channels `audioDeviceName` should have as its default output pair, e.g.
    /// `["VIRTUAL 1", "VIRTUAL 2"]` on a UA Apollo routed to its software-return channels instead
    /// of its main outs. Empty means the profile doesn't care which channel pair is active.
    public let expectedOutputChannelNames: [String]
    /// Clock source the UA Mixer Engine should be on (e.g. `"Internal"`), as listed in its
    /// `ClockSource` values. `nil` leaves the clock alone.
    public let expectedClockSource: String?
    /// UAD Console's MONITOR level in dB (-96…0), set once on activation. `nil` leaves it alone.
    public let expectedMonitorLevel: Double?
    /// Uncheck UAD Console's View > Offline Devices so units that aren't connected aren't shown.
    public let hideUADOfflineDevices: Bool
    /// Detect this profile by its CoreAudio device (`audioDeviceName`) being present, instead of a
    /// Thunderbolt device named `deviceNameMatch` — for devices that aren't Thunderbolt, such as a
    /// Bluetooth headset.
    public let detectByAudioDevice: Bool

    public init(
        name: String,
        deviceNameMatch: String,
        audioDeviceName: String,
        uadConsoleSession: String?,
        daws: [DAWEntry],
        expectedSampleRate: Double? = nil,
        expectedOutputChannelNames: [String] = [],
        expectedClockSource: String? = nil,
        expectedMonitorLevel: Double? = nil,
        hideUADOfflineDevices: Bool = false,
        detectByAudioDevice: Bool = false
    ) {
        self.name = name
        self.deviceNameMatch = deviceNameMatch
        self.audioDeviceName = audioDeviceName
        self.uadConsoleSession = uadConsoleSession
        self.daws = daws
        self.expectedSampleRate = expectedSampleRate
        self.expectedOutputChannelNames = expectedOutputChannelNames
        self.expectedClockSource = expectedClockSource
        self.expectedMonitorLevel = expectedMonitorLevel
        self.hideUADOfflineDevices = hideUADOfflineDevices
        self.detectByAudioDevice = detectByAudioDevice
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        deviceNameMatch = try container.decode(String.self, forKey: .deviceNameMatch)
        audioDeviceName = try container.decode(String.self, forKey: .audioDeviceName)
        uadConsoleSession = try container.decodeIfPresent(String.self, forKey: .uadConsoleSession)
        daws = try container.decode([DAWEntry].self, forKey: .daws)
        expectedSampleRate = try container.decodeIfPresent(Double.self, forKey: .expectedSampleRate)
        expectedOutputChannelNames = try container.decodeIfPresent([String].self, forKey: .expectedOutputChannelNames) ?? []
        expectedClockSource = try container.decodeIfPresent(String.self, forKey: .expectedClockSource)
        expectedMonitorLevel = try container.decodeIfPresent(Double.self, forKey: .expectedMonitorLevel)
        hideUADOfflineDevices = try container.decodeIfPresent(Bool.self, forKey: .hideUADOfflineDevices) ?? false
        detectByAudioDevice = try container.decodeIfPresent(Bool.self, forKey: .detectByAudioDevice) ?? false
    }
}


public struct ProfilesFile: Codable, Equatable {
    public let profiles: [Profile]

    public init(profiles: [Profile]) {
        self.profiles = profiles
    }
}
