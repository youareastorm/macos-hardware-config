import Foundation

/// Swift port of `Scripts/usb-topology.py`'s correlation logic (verified against real hardware):
/// `diskutil` and `system_profiler` don't share a common key, so the USB device's display name —
/// truncated differently on each side (diskutil's "MobileDataStar" vs system_profiler's "Netac
/// MobileDataStar") — is matched by substring in either direction, not exact equality.
public final class DiskUtilMountedDiskInspector: MountedDiskInspecting {
    public init() {}

    public func mountedDisks(matching expectedNames: [String]) -> [MountedDiskInfo] {
        let expected = Set(expectedNames)
        let usbEntries = usbDeviceEntries()

        return mountedVolumeMediaNames()
            .filter { expected.contains($0.key) }
            .map { volumeName, mediaName in
                MountedDiskInfo(volumeName: volumeName, wattage: Self.wattage(forMediaName: mediaName, in: usbEntries))
            }
            .sorted { $0.volumeName.localizedCaseInsensitiveCompare($1.volumeName) == .orderedAscending }
    }

    /// Exposed for testing the substring correlation without shelling out.
    static func wattage(forMediaName mediaName: String, in entries: [(name: String, power: String?)]) -> String? {
        entries.first { entry in
            mediaName.localizedCaseInsensitiveContains(entry.name) || entry.name.localizedCaseInsensitiveContains(mediaName)
        }?.power
    }

    private func mountedVolumeMediaNames() -> [String: String] {
        guard let disks = diskutilExternalDisks() else { return [:] }

        var result: [String: String] = [:]
        for disk in disks {
            guard let deviceIdentifier = disk["DeviceIdentifier"] as? String,
                  let mediaName = diskutilInfo(deviceIdentifier: deviceIdentifier),
                  mediaName != "Disk Image" else { continue }
            for volumeName in Self.mountedVolumeNames(in: disk) {
                result[volumeName] = mediaName
            }
        }
        return result
    }

    private static func mountedVolumeNames(in disk: [String: Any]) -> [String] {
        var names: [String] = []
        if let volumeName = disk["VolumeName"] as? String {
            names.append(volumeName)
        }
        if let partitions = disk["Partitions"] as? [[String: Any]] {
            for partition in partitions {
                names.append(contentsOf: mountedVolumeNames(in: partition))
            }
        }
        return names
    }

    private func usbDeviceEntries() -> [(name: String, power: String?)] {
        guard let root = runProcessJSON(executable: "/usr/sbin/system_profiler", arguments: ["-json", "SPUSBHostDataType"]),
              let buses = root["SPUSBHostDataType"] as? [[String: Any]] else {
            return []
        }
        var entries: [(name: String, power: String?)] = []
        for bus in buses {
            Self.collectUSBEntries(from: bus, into: &entries)
        }
        return entries
    }

    private static func collectUSBEntries(from node: [String: Any], into entries: inout [(name: String, power: String?)]) {
        let name = (node["_name"] as? String) ?? "Appareil sans nom"
        let isHub = name.localizedCaseInsensitiveContains("hub") || name.localizedCaseInsensitiveContains("bus")
        if !isHub {
            entries.append((name, node["USBDeviceKeyPowerAllocation"] as? String))
        }
        if let children = node["_items"] as? [[String: Any]] {
            for child in children {
                collectUSBEntries(from: child, into: &entries)
            }
        }
    }

    private func diskutilExternalDisks() -> [[String: Any]]? {
        guard let plist = runProcessPlist(executable: "/usr/sbin/diskutil", arguments: ["list", "-plist", "external"]) else { return nil }
        return plist["AllDisksAndPartitions"] as? [[String: Any]]
    }

    private func diskutilInfo(deviceIdentifier: String) -> String? {
        guard let plist = runProcessPlist(executable: "/usr/sbin/diskutil", arguments: ["info", "-plist", deviceIdentifier]) else { return nil }
        return plist["MediaName"] as? String
    }

    private func runProcessJSON(executable: String, arguments: [String]) -> [String: Any]? {
        guard let data = runProcess(executable: executable, arguments: arguments) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func runProcessPlist(executable: String, arguments: [String]) -> [String: Any]? {
        guard let data = runProcess(executable: executable, arguments: arguments) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    private func runProcess(executable: String, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}
