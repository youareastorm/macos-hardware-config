public struct MountedDiskInfo: Equatable, Identifiable {
    public var id: String { volumeName }
    public let volumeName: String
    /// e.g. "4.48 W (896 mA)", nil when macOS doesn't report power for this device.
    public let wattage: String?

    public init(volumeName: String, wattage: String?) {
        self.volumeName = volumeName
        self.wattage = wattage
    }
}

public protocol MountedDiskInspecting {
    /// Of `expectedNames`, only the ones currently mounted — absent ones are simply left out,
    /// each with its USB device's wattage when macOS reports it.
    func mountedDisks(matching expectedNames: [String]) -> [MountedDiskInfo]
}
